# Architecture

Godot 4.7, GL Compatibility, Android landscape. Base viewport 640×360,
`viewport` stretch, integer scaling, nearest filtering.

## Principles
- **Two autoloads only:** `SaveService` (persistent progress, JSON in `user://`) and
  `SceneRouter` (menu ↔ run transitions). Run state lives in the Run scene.
- **Data-driven:** balance lives in `.tres` files under `data/`, typed by the
  Resource scripts in `resources/`. Never mutate shared defs at runtime.
- **Signals up, calls down.** Systems never reference siblings; `run.gd` wires them.
- **Crowds are data, not nodes.** `ZombieManager` simulates all zombies over packed
  arrays; zombie nodes are pooled display-only sprites. No physics for zombies or
  projectiles — queries go through `SpatialGrid`.

## Layout
| Path | Contents |
|---|---|
| `autoload/` | `SaveService`, `SceneRouter` |
| `resources/` | `ZombieDef`, `WeaponDef`, `WaveTable`, `SpawnEntry`, `UpgradeDef`, `ShopCatalog`, `ItemDef` |
| `data/` | Balance `.tres` (zombies, weapons, waves, upgrades, items) |
| `systems/` | Engine-agnostic helpers: `SpatialGrid`, `SaveData`, `Inventory` |
| `scenes/run/` | Gameplay root, `RunState` |
| `scenes/main_menu/` | Main menu, `ShopPanel` + `ShopRow`, `PreparePanel`, `SettingsPanel` |
| `scenes/player/` | Player body + `components/` |
| `scenes/zombies/` | `ZombieManager`, `ZombieSpawner` |
| `scenes/waves/` | `WaveDirector` |
| `scenes/projectiles/` | `ProjectileManager`, `GrenadeManager` |
| `scenes/pickups/` | `CoinManager`, `SupplyManager`, `PickupManager` |
| `scenes/world/` | `Arena` (fixed bounded map) |
| `scenes/ui/` | HUD (native `VirtualJoystick` → `move_*` actions, quick buttons, `AimButton`), `InventoryPanel` + `InventorySlotButton`, game-over screen, debug overlay |
| `tests/` | Headless scripts, e.g. `zombie_stress_test.gd` |

## Game rules decided
- Fixed, bounded arena.
- Supply phase: crates spawn around the arena; the player walks to collect
  health/ammo. Phase ends on timer (`WaveTable.supply_duration`).
- Multiple weapons, each with its own ammo; unlocked permanently in the shop
  (`WeaponDef.unlock_cost`), switched during a run.

## Zombie indices
`ZombieManager` indices are valid only until the next physics tick (dead zombies
are swap-removed at tick start). To follow a zombie across ticks, keep its `uid`
and call `resolve(uid, hint)`; re-acquire when it returns -1 (see `AutoAim`).

## Physics tick order
`process_physics_priority`: WaveDirector (-30) advances the wave loop → Spawner
(-20) adds zombies → Zombies (-10) compact, move, rebuild the grid →
Player + components (0) aim and fire → Projectiles (10) resolve hits → Grenades (12) fly and explode → Coins (20) home in and get collected → Pickups (22) offer items to the bag →
Supplies (25) check crate pickups.

## Spawning
- `ZombieSpawner` decides when/where; `ZombieManager` only simulates
  (`spawn_at()` refuses when full — the spawner holds the request, never drops it).
- Timed batches (`start_batch`) use `WaveTable` for count, interval, type mix and
  HP/speed scaling; bursts (`spawn_burst`) are for debug/events.
- Spawn points: uniform over four bands framing the camera view, clipped to the
  arena — always off-screen. At most `max_per_tick` spawns per tick.
- `WaveDirector` loop: BREAK (countdown) → COMBAT (batch from the spawner) →
  cleared once nothing is alive or pending → BREAK (`WaveTable.supply_duration`,
  skippable) → next wave. It polls counts, so zombies removed without kill
  signals still end a wave. Emits signals only; `run.gd` forwards them to the HUD.

## Combat
- `AutoAim` follows its target via uid each tick; nearest-search runs at 10 Hz
  or when the target is lost.
- `WeaponHolder` owns the loadout and magazines; emits
  `projectile_requested`, which `run.gd` connects to `ProjectileManager.spawn`.
- Reserve ammo is bag ammo: a weapon with `WeaponDef.ammo_item` draws its
  reserve from `WeaponHolder.ammo_source` (= `RunState.inventory`, set before
  `set_loadout`). Ammo is taken when a reload *finishes*, so bag changes
  mid-reload are safe. The HUD reserve is `count_of(ammo_item)`, refreshed on
  every bag change (except mid-reload). Weapons without an ammo_item keep
  their own `reserve` (old path). Starting reserve (Ammo Pouch applied) comes
  from `starting_ammo()`, which `run._stock_starting_ammo()` puts in the bag;
  overflow is dropped at the player's feet as a pickup.
- Manual reload: `WeaponHolder.reload()` (HUD RELOAD button).
- Projectiles move on the ground plane (zombie feet) and are drawn 6 px higher.

## Money
- `ZombieManager.zombie_killed` → `run.gd` → `CoinManager.spawn(pos, coin_value)`.
  Coins are packed arrays drawn in one `_draw` (like projectiles), on the ground
  layer below the y-sorted `World`.
- Resting coins start homing inside `magnet_radius` (shop upgrade hook);
  `collect_all()` on wave clear vacuums the rest. A full pool awards the value
  at once, so money is never dropped.
- `CoinManager.collected` → `RunState.add_coins` → HUD. Only the run total is
  banked into `SaveService` on death; ground coins at death are lost.

## Supply phase
- Every break after a cleared wave is a supply phase (not the countdown before
  wave 1). `run.gd` plans the crate kinds and calls
  `SupplyManager.drop_crates(kinds, break_duration)`; `wave_started` clears
  leftovers.
- Planning: `run._crate_count()` is `WaveTable.supply_crates`, or
  `health_only_crates` when no weapon uses ammo. `run._plan_crates(count)`: no
  limited-ammo weapon → all health; otherwise one health + one ammo, extras go
  to whichever is lower (HP vs `WeaponHolder.ammo_fill_ratio()`). With the
  shipped `supply_crates = 2` there are no extras.
- Crates land in a ring around the player (`min/max_drop_distance`, spaced by
  `min_spacing`), fall in over `DROP_TIME` and can only be picked up once landed;
  they blink near the end of the break. The `Indicators` child (z 50) draws
  edge arrows for off-screen crates.
- Touching a landed crate calls `SupplyManager.accept` (`run._accept_supply`).
  Health crates put `WaveTable.supply_medkits` × `supply_medkit` in the bag;
  ammo crates put `WeaponHolder.ammo_refill(supply_ammo_fraction)` ammo items
  in it (plus `add_ammo()` for own-reserve weapons). If nothing fits, accept
  returns false: the crate stays and "BAG FULL" shows (throttled to 1/s). A
  partly fitting ammo crate is used up. `collected` fires only for crates
  actually taken.

## Shop + settings
- `ShopCatalog` (`data/shop_catalog.tres`) lists `UpgradeDef`s (levelled, cost
  grows by `cost_growth`) and every `WeaponDef` (unlock_cost 0 = owned from the
  start). The run uses it for its weapon list too. Items with a `shop_price`
  are sold too (one `shop_bundle` per purchase).
- Purchases are single `SaveService` calls (`purchase_upgrade`, `purchase_weapon`,
  `purchase_item`) that spend and grant in one save. `ShopPanel` only checks max
  level, shows prices and refreshes on `coins_changed` / `upgrades_changed` /
  `stash_changed`.
- `run._apply_upgrades()` turns owned levels into stats via
  `ShopCatalog.bonus(stat, SaveService.get_upgrade_level)`: max HP (flat),
  damage / move speed / coin magnet / starting ammo (fractions), bag slots
  (`ShopCatalog.bag_slots`, Backpack). Runs before the loadout is built.

## Stash + loadout
- Bought items go to `SaveData.stash` (item id → units, no slot limit). Only
  the run's bag has slots.
- PLAY: `PreparePanel.has_items_to_bring()` (a stash item this build knows) →
  `PreparePanel.open()`, else `SceneRouter.start_run()` with no loadout.
  The panel restores `SaveData.last_loadout`, clamped to the stash and to the
  bag (`ShopCatalog.bag_slots`; consumables before ammo, then catalog order).
  Its slot count includes the starting ammo the run stocks first
  (`ShopCatalog.starting_ammo(owned_weapons, level_of)`, the same
  `WeaponDef.starting_reserve()` the run uses); picked ammo tops up those
  stacks, like `Inventory.add`. +/− change one unit (ammo: one `shop_bundle`);
  + is disabled when the stash is out or the bag has no slot left. START
  emits `start_requested(loadout)` (possibly empty) → `SceneRouter.start_run(loadout)`.
- `SceneRouter` only carries the request across the scene change
  (`take_run_loadout()`, handed over once). null = no choice was made (PLAY
  skipped PREPARE): the run takes nothing and `last_loadout` stays. A
  Dictionary, even empty, is a choice: the run drops ids the catalog doesn't
  know (they stay in the stash) and calls `SaveService.take_loadout(known)` in
  `_ready`, after stocking starting ammo: one save that removes what's
  available from the stash and stores the request as `last_loadout`. Nothing
  leaves the stash if the run never starts.
- Taken items go into the bag, consumables before ammo; what doesn't fit is a
  held pickup at the player's feet. They are run items now: death empties the
  bag, the stash keeps the rest. RETRY calls `start_run(last_loadout)`, so an
  empty choice is retried as empty.
- Settings live in `SaveData.settings` (JSON, type-checked against
  `DEFAULT_SETTINGS`). `SaveService` applies master volume itself; the run reads
  `vibration` (throttled hurt buzz) and `show_fps` (HUD label).
- Android back / Esc closes the open menu panel; `quit_on_go_back` is off so the
  main menu decides when back quits.

## Items + inventory
- `ItemDef` (`data/items/`) describes an item: `kind` (AMMO, MEDKIT, GRENADE,
  DAMAGE_BOOST, MAX_HP_BOOST), `stack_limit`, effect `value`, shop price and
  bundle, grenade blast data. `ShopCatalog.items` lists them all;
  `find_item(id)` resolves saved ids (unknown → null).
- `WeaponDef.ammo_item` names the item a weapon's reserve is made of (null =
  own reserve / infinite).
- `Inventory` (`systems/`) is pure logic: N slots, one stack of one item per
  slot. `add()` tops up open stacks before empty slots and returns how much
  fit, so callers keep the rest (pickups stay on the ground). `take()` drains
  the smallest stacks first. `to_entries()` / `add_entries()` convert to plain
  `{id, count}` data for saving.
- The run's bag is `RunState.inventory` (8 slots + Backpack). It
  and the run-only boosts (`damage_bonus`, `max_hp_bonus`) die with the run;
  `_on_player_died` empties it.
- Bag UI: `Hud.bag_pressed` (or `open_inventory`) → `run.open_bag()` pauses
  the tree and opens `InventoryPanel` (process mode ALWAYS). The panel only
  emits `use_requested` / `drop_requested` / `closed`; `run.use_item(slot)`
  applies the effect via `_apply_item()` and consumes one unit only if it did
  something (medkit at full HP is refused). Feedback goes to the panel while
  it's open (HUD tweens are paused), otherwise to the HUD toast.
- Quick buttons (HUD): MED → `run._quick_use(MEDKIT)` (smallest stack
  first), RELOAD → `WeaponHolder.reload()`, GREN shows the count and is the grenade aim stick (see Grenades).
  Counts refresh on `Inventory.changed`.
- Decided rules (Phases 15–20): reserve ammo lives in the bag; boosts last the
  run only; shop items go to a permanent stash and only what's brought into a
  run is lost on death; opening the bag pauses; pickups last 30 s.

## Loot + pickups
- `ZombieDef.loot` is a list of `LootEntry` (item, chance, min/max count); each
  entry is rolled on its own per kill (`LootEntry.roll`). `run._drop_loot` skips
  AMMO items no loadout weapon uses (`_wants_loot`).
- `PickupManager` holds item pickups on the ground (plain objects, one `_draw`,
  ground layer). Loot pops out over `POP_TIME` and can't be taken mid-air;
  pickups expire after `lifetime` (30 s) and blink for the last 5 s. When
  `max_pickups` is reached the oldest makes room.
- Walking over a pickup calls `accept(def, count) -> int` (`run._accept_pickup`
  → `Inventory.add`): the bag takes what fits, the rest stays; 0 → "BAG FULL".
  `collected` drives the HUD toast.
- Bag DROP and starting-ammo overflow spawn pickups at the player's feet with
  `hold = true`: they only become collectable after the player has been
  `rearm_distance` away, so they aren't picked straight back up.
- Death sets `target = null`: nothing is collected after banking.

## Grenades
- The HUD's GREN button is an `AimButton`: press + drag aims (vector up to
  length 1 = `max_drag` px), release throws, dragging out and back inside
  `dead_zone` cancels, a tap (never dragged out) reports `tapped`. It tracks
  one touch index, so it works while another finger holds the joystick;
  emulated mouse events are ignored, real mouse works on desktop.
- `Hud` forwards `grenade_aim_*` / `grenade_tapped`; the run turns the aim
  into a landing point (`aim × ItemDef.throw_range` from the player) and shows
  it with `GrenadeManager.show_aim()` (blast circle + range ring).
- `run.throw_grenade(target)` takes one grenade (smallest stack), clamps the
  target to `throw_range` and calls `GrenadeManager.throw()` with
  `damage × WeaponHolder.damage_multiplier` (Firepower + Rage).
  `throw_grenade_at_nearest()` (tap, `throw_grenade` action = G) aims at the
  nearest zombie in range, or shows "NO TARGET" and uses nothing.
- `GrenadeManager` (packed arrays, one `_draw`, priority 12) arcs each
  grenade to its landing point over `ItemDef.fuse`, then calls
  `ZombieManager.blast(center, radius, damage, knockback)`: a grid query;
  damage falls off from full at the centre to half at the edge (distance to
  the zombie's body). The player is never damaged. Kills go through the usual
  `zombie_killed` path (coins, loot, kill count).
- Opening the bag and death cancel the aim; death also clears grenades still
  in the air so nothing scores after banking.

## Save system
- `SaveData` (JSON) is versioned: `VERSION` is what this build writes;
  `from_dict()` runs `migrate()` first, which upgrades older dictionaries one
  step at a time (`_migrate_v1_to_v2` added lifetime `stats`,
  `_migrate_v2_to_v3` the item `stash` and `last_loadout`). To change the
  format: bump `VERSION`, add a `_migrate_vN_to_vN+1`, register it in `migrate()`.
- Files next to `save.json`: `.tmp` (write in progress), `.bak` (previous save,
  rotated on every write), `.session.bak` (save as it was at game start, before
  the first write), `.corrupt` (unreadable save moved aside), `.vN.bak` (a save
  from a newer build, kept before this build overwrites it).
- Load order: `save.json` → `.bak` → fresh. A leftover `.tmp` is discarded.
- Runs bank progress in steps (`run._bank_progress`): on wave clear, app pause
  (Android background), window close and death. Only unbanked coins are added,
  so repeated checkpoints never double-count. Death also calls `record_run`.
- `reset_progress()` (Settings → two taps) wipes progress but keeps settings.

## Death
- `HealthComponent.died` → `run.gd` stops the director, banks coins and best wave
  in `SaveService` immediately, then after `GAME_OVER_DELAY` hides the HUD and
  shows `GameOverScreen`. The screen only emits `retry_pressed` / `menu_pressed`;
  the run routes them to `SceneRouter`.
- Hurt feedback: `Player` flashes its sprite on `damaged`; `Hud.flash_damage()`
  pulses a red overlay and ignores hits while the pulse is bright (no strobing).

## Tests / benchmarks
Test scripts (any `res://tests/...` on the command line) make `SaveService` use
`user://test_save.json`, wiped at start, so tests never touch the real save.
```
godot --headless --path . -s res://tests/zombie_stress_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/weapon_smoke_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/spawner_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/wave_director_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/game_over_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/coin_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/supply_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/shop_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/save_system_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/loot_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/grenade_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/loadout_test.gd
godot --headless --path . -s res://tests/inventory_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/inventory_ui_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/full_run_test.gd
```
- `tests/support/run_bot.gd` is a scripted player (a Node added to a Run,
  physics priority -5): it steers through the `move_*` actions and calls the
  same run methods the HUD does (`use_item`, `throw_grenade`), and records
  per-wave numbers. It reads zombies via `ZombieManager.slot_count()` /
  `is_alive()` and counts loot via `PickupManager.spawned` / `collected`.
- `tests/full_run_test.gd` uses it for a five-wave integration run;
  `tests/balance_sim.gd` for balance numbers (profiles, skills, one JSON line
  per run, its own save file per process). See [BALANCE.md](BALANCE.md).
