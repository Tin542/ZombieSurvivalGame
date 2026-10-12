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
| `scenes/main_menu/` | Main menu, `ShopPanel` + `ShopRow`, `SettingsPanel` |
| `scenes/player/` | Player body + `components/` |
| `scenes/zombies/` | `ZombieManager`, `ZombieSpawner` |
| `scenes/waves/` | `WaveDirector` |
| `scenes/projectiles/` | `ProjectileManager` |
| `scenes/pickups/` | `CoinManager`, `SupplyManager`, `PickupManager` |
| `scenes/world/` | `Arena` (fixed bounded map) |
| `scenes/ui/` | HUD (native `VirtualJoystick` → `move_*` actions, quick buttons), `InventoryPanel` + `InventorySlotButton`, game-over screen, debug overlay |
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
Player + components (0) aim and fire → Projectiles (10) resolve hits → Coins (20) home in and get collected → Pickups (22) offer items to the bag →
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
- Planning (`run._plan_crates`): no limited-ammo weapon → all health; otherwise
  one health + one ammo, extras go to whichever is lower (HP vs
  `WeaponHolder.ammo_fill_ratio()`).
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
  start). The run uses it for its weapon list too.
- Purchases are single `SaveService` calls (`purchase_upgrade`, `purchase_weapon`)
  that spend and grant in one save. `ShopPanel` only checks max level, shows
  prices and refreshes on `coins_changed` / `upgrades_changed`.
- `run._apply_upgrades()` turns owned levels into stats via
  `ShopCatalog.bonus(stat, SaveService.get_upgrade_level)`: max HP (flat),
  damage / move speed / coin magnet / starting ammo (fractions). Runs before the
  loadout is built.
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
- The run's bag is `RunState.inventory` (8 slots; shop upgrade later). It
  and the run-only boosts (`damage_bonus`, `max_hp_bonus`) die with the run;
  `_on_player_died` empties it.
- Bag UI: `Hud.bag_pressed` (or `open_inventory`) → `run.open_bag()` pauses
  the tree and opens `InventoryPanel` (process mode ALWAYS). The panel only
  emits `use_requested` / `drop_requested` / `closed`; `run.use_item(slot)`
  applies the effect via `_apply_item()` and consumes one unit only if it did
  something (medkit at full HP is refused). Feedback goes to the panel while
  it's open (HUD tweens are paused), otherwise to the HUD toast.
- Quick buttons (HUD): MED → `run._quick_use(MEDKIT)` (smallest stack
  first), RELOAD → `WeaponHolder.reload()`, GREN shows the count (Phase 18).
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

## Save system
- `SaveData` (JSON) is versioned: `VERSION` is what this build writes;
  `from_dict()` runs `migrate()` first, which upgrades older dictionaries one
  step at a time (`_migrate_v1_to_v2` added lifetime `stats`). To change the
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
godot --headless --path . -s res://tests/inventory_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/inventory_ui_test.gd
```
