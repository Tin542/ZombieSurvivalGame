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
| `scenes/zombies/` | `ZombieManager` |
| `scenes/world/` | `Arena` (fixed bounded map) |
| `scenes/ui/` | HUD (native `VirtualJoystick` → `move_*` actions), debug overlay |
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
`process_physics_priority`: Zombies (-10) compact, move, rebuild the grid →
Player + components (0) aim and fire → Projectiles (10) resolve hits.

## Combat
- `AutoAim` follows its target via uid each tick; nearest-search runs at 10 Hz
  or when the target is lost.
- `WeaponHolder` owns the loadout and per-weapon ammo; emits
  `projectile_requested`, which `run.gd` connects to `ProjectileManager.spawn`.
- Projectiles move on the ground plane (zombie feet) and are drawn 6 px higher.

## Tests / benchmarks
```
godot --headless --path . -s res://tests/zombie_stress_test.gd
godot --headless --path . --fixed-fps 60 -s res://tests/weapon_smoke_test.gd
```
