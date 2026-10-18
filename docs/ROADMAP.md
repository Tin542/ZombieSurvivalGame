# Roadmap

✅ done · 🟡 partly done (foundation in place) · ⬜ not started

| # | Phase | Status | Notes |
|---|---|---|---|
| 01 | Project architecture | ✅ | Folder layout, 2 autoloads, Resource defs, [ARCHITECTURE.md](ARCHITECTURE.md) |
| 02 | Player + movement | ✅ | `CharacterBody2D`, keyboard + touch via `move_*` actions, arena walls |
| 03 | Camera + mobile joystick | ✅ | Camera limited to arena; Godot's native `VirtualJoystick` (dynamic, left 40% of screen) |
| 04 | Zombie | ✅ | `ZombieManager`: packed arrays + spatial grid, separation, contact damage, hit flash, knockback. 3 types |
| 05 | Weapon + auto aim | ✅ | `AutoAim`, `WeaponHolder` (3 weapons, per-weapon ammo, auto reload, fallback), `ProjectileManager`, HUD ammo + SWAP |
| 06 | Zombie spawning | ✅ | `ZombieSpawner`: timed batches + bursts, always off-screen, holds at the 400 cap, ≤8 spawns/tick |
| 07 | Wave system | ✅ | `WaveDirector`: countdown → combat → cleared → break (skippable) → next wave. HUD wave/remaining/banner/countdown |
| 08 | HP + death | ✅ | HP bar, contact damage, hurt feedback (sprite flash + red screen pulse), results banked on death, game-over screen (wave, kills, coins, best) with RETRY / MENU |
| 09 | Money | ✅ | `CoinManager`: kill drops worth `coin_value`, magnet pickup, vacuum on wave clear, overflow awarded directly, HUD `$` counter. Banked to `SaveService` on death |
| 10 | Supply phase | ✅ | `SupplyManager`: health/ammo crates drop around the player after each cleared wave (12 s break), fall-in + land, edge arrows when off-screen, blink before the next wave, leftovers removed. Mix: one health + one ammo, extra crates by HP vs ammo (since Phase 21: 2 crates, so a fixed 1 + 1; 1 health crate with no ammo weapon); HUD toast |
| 11 | Main menu | ✅ | PLAY / SHOP / SETTINGS, coins + best wave. Settings: master volume, vibrate on hit, show FPS (saved in the save file). Android back / Esc closes panels |
| 12 | Shop | ✅ | 5 levelled upgrades (Toughness, Firepower, Sprint, Coin Magnet, Ammo Pouch) + SMG / Shotgun unlocks from `ShopCatalog`. Atomic purchases; owned levels applied at run start |
| 13 | Save system | ✅ | Versioned JSON with step-by-step migration (v2 adds lifetime stats). Rotating `.bak`, per-session backup, corrupt-file recovery, interrupted-write cleanup, newer-format protection. Run coins banked at wave clear / app pause / close / death. Reset progress (2 taps). Tests isolated to `test_save.json` |
| 14 | Inventory core + item data | ✅ | `ItemDef` (ammo, medkit, grenade, damage / max-HP boosts; per-item `stack_limit`), `Inventory` (pure logic: stacking, partial adds, take smallest-first, capacity, plain-data entries), 6 items in `data/items/`, `ShopCatalog.items` + `find_item`, `WeaponDef.ammo_item`. No gameplay change yet |
| 15 | In-game inventory UI | ✅ | Bag (BAG button / I / B) pauses the run: 8-slot grid, select → USE / DROP (whole stack), CLOSE / Esc / Android back. Quick buttons: GREN (count; aim stick since Phase 18), MED (uses one), RELOAD (`WeaponHolder.reload()`). Medkit / Rage Pill / Vitality Shot effects (run-only boosts). Bag emptied on death. Debug “+Items”. |
| 16 | Ammo from inventory + supply items | ✅ | Reserve ammo = bag ammo (`WeaponDef.ammo_item`; reload takes it when it finishes); starting ammo (with Ammo Pouch) stocked into the bag; HUD reserve = bag count. Health crate → medkit into the bag, ammo crate → ammo items; crate stays when the bag is full (“BAG FULL”). Ammo stacks 120 (SMG) / 24 (shells) so each weapon starts in one slot |
| 17 | Zombie loot + pickups | ✅ | `LootEntry` lists on each `ZombieDef` (independent rolls; no ammo for weapons not carried). `PickupManager`: pop-out, 30 s lifetime + blink, partial pickup, stays when the bag is full ("BAG FULL"), oldest dropped at the 96 cap. Bag DROP and starting-ammo overflow land at the player's feet and wait until the player steps away |
| 18 | Grenades + aim stick | ✅ | GREN button is an aim stick (`AimButton`: drag to aim with a landing reticle, release to throw, drag back to cancel, tap = nearest zombie in range; tracks its own finger next to the joystick). `G` key throws at the nearest zombie. `GrenadeManager` arcs the grenade over its fuse, then `ZombieManager.blast()` hits through the grid (full damage at the centre, half at the edge, knockback). No self-damage; weapon damage multiplier (Firepower + Rage) applies. Opening the bag or dying cancels the aim; death clears grenades in the air |
| 19 | Shop items + stash + loadout | ✅ | Shop ITEMS section buys bundles into a permanent stash (`SaveService.purchase_item`, atomic). PLAY opens PREPARE when the stash has items: +/− per item (ammo steps by shop bundle), limited by stash and bag slots, restores the last loadout (consumables before ammo when the bag is short). The run takes the loadout from the stash when it starts (`SaveService.take_loadout`), overflow lands at the player's feet, everything brought is lost on death; RETRY brings the same loadout again. Backpack upgrade: +2 bag slots per level (max 2) |
| 20 | Save v3 | ✅ | `stash` and `last_loadout` (item id → units), `_migrate_v2_to_v3`, v1 saves migrate through v2 (landed with Phase 19). Hardening after review: an empty PREPARE choice is remembered (RETRY no longer re-takes the old loadout), PREPARE counts the starting-ammo slots so picks never overflow, unknown item ids stay in the stash and don't open an empty PREPARE |
| 21 | Integration + balancing | ✅ | Scripted bot (`tests/support/run_bot.gd`, casual / good skill) plays whole runs headless. `full_run_test` drives five waves with weapons, upgrades and a loadout and checks the systems together (pickup pool cap exercised). `balance_sim` + `summarize_sim.py` measure runs per player profile; data retuned against ten targets in [BALANCE.md](BALANCE.md): a fresh pistol player now dies around wave 7 (was 16), SMG ~9, mid ~11, late ~20; waves 1–7 stay under ~50 s; a fresh run earns ~130 coins; free healing no longer piles up (`WaveTable.health_only_crates`). Stack limits unchanged |
| 22 | Visual polish, performance, Android | 🟡 | Old phases 14–16 (pixel art, on-device profiling, APK export) folded in. Built for crowds from the start (SoA, grid, pooling, single-draw bullets) + headless benchmarks |

## Headless tests
| Test | Covers |
|---|---|
| `tests/zombie_stress_test.gd` | ZombieManager tick cost at 400 zombies |
| `tests/weapon_smoke_test.gd` | Auto-aim, firing, kills, reload from the bag, HUD reserve, weapon fallback, late ammo pickup, bullet cost |
| `tests/spawner_test.gd` | Off-screen placement, cap/backpressure, pacing, wave type mix |
| `tests/wave_director_test.gd` | Wave loop, clear conditions, break skip/timeout, stop on death |
| `tests/coin_test.gd` | Kill drops, magnet pickup, wave-clear vacuum, full pool, no pickup after death |
| `tests/game_over_test.gd` | Hurt feedback, results saved on death, game-over screen + button lock |
| `tests/supply_test.gd` | Crate drop timing, placement, landing, medkit / ammo items into the bag, crate stays when the bag is full, crate planning, cleanup, no pickup after death |
| `tests/shop_test.gd` | Pricing, atomic purchases on disk, settings persistence + volume, menu/shop/settings UI, upgrades + unlocks applied in a run |
| `tests/save_system_test.gd` | Migration, backup rotation, session backup, corruption recovery, interrupted writes, newer-format saves, stats, reset, mid-run banking |
| `tests/inventory_test.gd` | Item data, stacking, partial / full adds, take / remove, capacity, entries round trip |
| `tests/inventory_ui_test.gd` | Quick buttons, pause while open, slot selection rules, USE / DROP, medkit / boost effects, manual reload, close, death clears the bag |
| `tests/loadout_test.gd` | Save v3 + migration, item purchases on disk, shop item rows, take_loadout clamping / remembering, PREPARE restore, +/− limits (stash, bag slots incl. starting ammo, ammo bundles), Backpack slots, run brings the loadout, empty choice remembered vs no PREPARE, unknown ids kept, overflow (consumables first), loss on death |
| `tests/grenade_test.gd` | Blast falloff via the grid, kills counted, fuse, no self-damage, damage multiplier, range clamp, aim stick drag / release / cancel / tap, touch index tracking, bag + death cancel |
| `tests/full_run_test.gd` | Bot plays waves 1–5 with SMG + shotgun, upgrades and a loadout: loadout from the stash, wave order, crates every break, loot, bag ammo, grenades, coins banked at every clear and on death, stats, stash kept, bag lost, game-over screen, pickup pool held at a reachable cap, frame cost |
| `tests/balance_sim.gd` | Not pass/fail: plays N runs per profile / skill and writes JSON lines (see [BALANCE.md](BALANCE.md)) |
| `tests/loot_test.gd` | Loot rolls + data, drops on kill, ammo filtered by loadout, landing, partial pickup, BAG FULL, expiry, bag drops, starting-ammo overflow, pool cap, death |

Run any of them with:
```
godot --headless --path . --fixed-fps 60 -s res://tests/<name>.gd
```
