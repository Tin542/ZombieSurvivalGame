extends CanvasLayer
## Dev-only stats and stress-test controls. Frees itself in release builds.

signal spawn_requested(count: int)
signal clear_requested

const STATS_INTERVAL := 0.25

## Injected by the run, for stats only.
var zombies: ZombieManager
var spawner: ZombieSpawner
var projectiles: ProjectileManager
var coins: CoinManager
var run_state: RunState

var _stats_timer := 0.0

@onready var _stats: Label = %Stats


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	%Spawn50.pressed.connect(spawn_requested.emit.bind(50))
	%Spawn200.pressed.connect(spawn_requested.emit.bind(200))
	%Clear.pressed.connect(clear_requested.emit)


func _process(delta: float) -> void:
	_stats_timer -= delta
	if _stats_timer > 0.0:
		return
	_stats_timer = STATS_INTERVAL
	var text := "FPS %d" % Engine.get_frames_per_second()
	if run_state != null:
		text += "\nW %d" % run_state.wave
	if zombies != null:
		text += "\nZ %d" % zombies.alive_count()
	if spawner != null and spawner.pending_count() > 0:
		text += " +%d" % spawner.pending_count()
	if projectiles != null:
		text += "\nB %d" % projectiles.active_count()
	if coins != null:
		text += "\nC %d" % coins.active_count()
	_stats.text = text
