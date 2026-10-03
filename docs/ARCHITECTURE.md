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
| `resources/` | `ZombieDef`, `WeaponDef`, `WaveTable`, `SpawnEntry` |
| `data/` | Balance `.tres` (zombies, weapons, waves) |
| `systems/` | Engine-agnostic helpers: `SpatialGrid`, `SaveData` |
| `scenes/run/` | Gameplay root, `RunState` |
| `scenes/player/` | Player body + `components/` |
| `scenes/zombies/` | `ZombieManager`, `ZombieSpawner` |
| `scenes/waves/` | `WaveDirector` |
| `scenes/projectiles/` | `ProjectileManager` |
| `scenes/world/` | `Arena` (fixed bounded map) |
| `scenes/ui/` | HUD (native `VirtualJoystick` → `move_*` actions), game-over screen, debug overlay |
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
Player + components (0) aim and fire → Projectiles (10) resolve hits.

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
- `WeaponHolder` owns the loadout and per-weapon ammo; emits
  `projectile_requested`, which `run.gd` connects to `ProjectileManager.spawn`.
- Projectiles move on the ground plane (zombie feet) and are drawn 6 px higher.

## Death
- `HealthComponent.died` → `run.gd` stops the director, banks coins and best wave
  in `SaveService` immediately, then after `GAME_OVER_DELAY` hides the HUD and
  shows `GameOverScreen`. The screen only emits `retry_pressed` / `menu_pressed`;
  the run routes them to `SceneRouter`.
- Hurt feedback: `Player` flashes its sprite on `damaged`; `Hud.flash_damage()`
  pulses a red overlay and ignores hits while the pulse is bright (no strobing).

## Tests / benchmarks
```
godot --headless --path . -s res://tests/zombie_stress_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/weapon_smoke_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/spawner_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/wave_director_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/game_over_test.gd
```
