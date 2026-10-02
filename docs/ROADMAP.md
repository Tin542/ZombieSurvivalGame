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
| 08 | HP + death | 🟡 | HP, HP bar, contact damage, death stops the run and returns to menu. **Missing:** game-over screen (wave reached, kills, coins), hurt feedback |
| 09 | Money | ⬜ | `RunState.coins` and `ZombieDef.coin_value` exist; no coin drops / pickup yet |
| 10 | Supply phase | ⬜ | Break window exists (`WaveTable.supply_duration`, `WeaponHolder.add_ammo()`, `HealthComponent.heal()`). **Missing:** crates spawned in the arena, walk to collect |
| 11 | Main menu | 🟡 | Title, coins, best wave, PLAY. **Missing:** shop entry, settings |
| 12 | Shop | ⬜ | `SaveService.try_spend()`, upgrade levels, weapon unlocks and `WeaponDef.unlock_cost` exist; no UI or upgrade defs |
| 13 | Save system | 🟡 | `SaveService` JSON with atomic write. **Missing:** wiring real coin income, save versioning/migration test |
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

Run any of them with:
```
godot --headless --path . --fixed-fps 60 -s res://tests/<name>.gd
```
