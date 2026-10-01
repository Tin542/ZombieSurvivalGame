class_name AutoAim
extends Node
## Keeps a target on the nearest zombie in range, measured from the parent
## Node2D. Follows the current target every tick (O(1) via its uid) and only
## runs the nearest-zombie search on a timer or when the target is lost.

@export var retarget_interval: float = 0.1

## Injected by the run.
var zombies: ZombieManager
## Set by WeaponHolder from the equipped weapon.
var max_range: float = 150.0

var has_target := false
var target_position := Vector2.ZERO

var _index := -1
var _uid := 0
var _retarget_timer := 0.0

@onready var _origin: Node2D = get_parent()


func _physics_process(delta: float) -> void:
	if zombies == null:
		return
	var from := _origin.global_position
	var range_sq := max_range * max_range

	_index = zombies.resolve(_uid, _index)
	if _index != -1 and from.distance_squared_to(zombies.get_zombie_position(_index)) > range_sq:
		_index = -1

	_retarget_timer -= delta
	if _index == -1 or _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		_index = zombies.find_nearest(from, max_range)
		_uid = zombies.get_uid(_index) if _index != -1 else 0

	has_target = _index != -1
	if has_target:
		target_position = zombies.get_zombie_position(_index)
