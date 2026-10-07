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
| 10 | Supply phase | ✅ | `SupplyManager`: health/ammo crates drop around the player after each cleared wave (12 s break), fall-in + land, edge arrows when off-screen, blink before the next wave, leftovers removed. Smart mix by HP vs ammo; HUD toast |
| 11 | Main menu | ✅ | PLAY / SHOP / SETTINGS, coins + best wave. Settings: master volume, vibrate on hit, show FPS (saved in the save file). Android back / Esc closes panels |
| 12 | Shop | ✅ | 5 levelled upgrades (Toughness, Firepower, Sprint, Coin Magnet, Ammo Pouch) + SMG / Shotgun unlocks from `ShopCatalog`. Atomic purchases; owned levels applied at run start |
| 13 | Save system | ✅ | Versioned JSON with step-by-step migration (v2 adds lifetime stats). Rotating `.bak`, per-session backup, corrupt-file recovery, interrupted-write cleanup, newer-format protection. Run coins banked at wave clear / app pause / close / death. Reset progress (2 taps). Tests isolated to `test_save.json` |
| 14 | Pixel art + animation | ⬜ | All visuals are gradient placeholders |
| 15 | Optimization | 🟡 | Built for crowds from the start (SoA, grid, pooling, single-draw bullets) + headless benchmarks. **Missing:** on-device profiling |
| 16 | Android APK | ⬜ | Settings are mobile-ready (GL Compatibility, landscape); export preset not created |

## Headless tests
| Test | Covers |
|---|---|
| `tests/zombie_stress_test.gd` | ZombieManager tick cost at 400 zombies |
| `tests/weapon_smoke_test.gd` | Auto-aim, firing, kills, reload, weapon fallback, ammo refill, bullet cost |
| `tests/spawner_test.gd` | Off-screen placement, cap/backpressure, pacing, wave type mix |
| `tests/wave_director_test.gd` | Wave loop, clear conditions, break skip/timeout, stop on death |
| `tests/coin_test.gd` | Kill drops, magnet pickup, wave-clear vacuum, full pool, no pickup after death |
| `tests/game_over_test.gd` | Hurt feedback, results saved on death, game-over screen + button lock |
| `tests/supply_test.gd` | Crate drop timing, placement, landing, heal/ammo effects, crate planning, cleanup, no pickup after death |
| `tests/shop_test.gd` | Pricing, atomic purchases on disk, settings persistence + volume, menu/shop/settings UI, upgrades + unlocks applied in a run |
| `tests/save_system_test.gd` | Migration, backup rotation, session backup, corruption recovery, interrupted writes, newer-format saves, stats, reset, mid-run banking |

Run any of them with:
```
godot --headless --path . --fixed-fps 60 -s res://tests/<name>.gd
```
