extends CanvasLayer
## Dev-only stats and stress-test controls. Frees itself in release builds.

signal spawn_requested(count: int)
signal clear_requested

const STATS_INTERVAL := 0.25

## Injected by the run, for stats only.
var zombies: ZombieManager
var projectiles: ProjectileManager

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
	if zombies != null:
		text += "\nZ %d" % zombies.alive_count()
		if zombies.queued_count() > 0:
			text += " +%d" % zombies.queued_count()
	if projectiles != null:
		text += "\nB %d" % projectiles.active_count()
	_stats.text = text
