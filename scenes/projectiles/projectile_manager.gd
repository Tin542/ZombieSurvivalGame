class_name ProjectileManager
extends Node2D
## All player projectiles, simulated over packed arrays and drawn in a single
## _draw call (no node per bullet). Hits are resolved against ZombieManager's
## spatial grid.
##
## Projectiles travel on the ground plane (same as zombie feet) and are only
## drawn raised by DRAW_OFFSET so they appear to leave the gun.
## Keep this node at the origin, like ZombieManager.

const DRAW_OFFSET := Vector2(0.0, -6.0)
## Seconds of travel shown as the tracer trail.
const TRAIL_TIME := 0.015

@export var max_projectiles: int = 512
@export var hit_radius: float = 2.0
@export var color := Color(1.0, 0.92, 0.55)

## Injected by the run.
var zombies: ZombieManager

var _bounds: Rect2
var _count := 0
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _damage := PackedFloat32Array()
var _life := PackedFloat32Array()
var _knockback := PackedFloat32Array()
var _pierce := PackedInt32Array()
## Last zombie hit, so piercing shots don't re-hit it on the next tick.
var _last_hit := PackedInt32Array()
var _drawn_count := 0


func setup(bounds: Rect2) -> void:
	_bounds = bounds
	_pos.resize(max_projectiles)
	_vel.resize(max_projectiles)
	_damage.resize(max_projectiles)
	_life.resize(max_projectiles)
	_knockback.resize(max_projectiles)
	_pierce.resize(max_projectiles)
	_last_hit.resize(max_projectiles)


## Spawns one projectile. Silently dropped when the pool is full.
func spawn(origin: Vector2, velocity: Vector2, damage: float, pierce: int, lifetime: float, knockback: float) -> void:
	if _count >= max_projectiles:
		return
	var i := _count
	_count += 1
	_pos[i] = to_local(origin)
	_vel[i] = velocity
	_damage[i] = damage
	_life[i] = lifetime
	_knockback[i] = knockback
	_pierce[i] = pierce
	_last_hit[i] = 0


func active_count() -> int:
	return _count


func clear() -> void:
	_count = 0
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _count == 0 and _drawn_count == 0:
		return
	var i := 0
	while i < _count:
		var p := _pos[i] + _vel[i] * delta
		_pos[i] = p
		_life[i] -= delta
		var alive := _life[i] > 0.0 and _bounds.has_point(p)

		if alive and zombies != null:
			var hit := zombies.find_hit(p, hit_radius, _last_hit[i])
			if hit != -1:
				_last_hit[i] = zombies.get_uid(hit)
				var push := _vel[i].normalized() * _knockback[i]
				zombies.damage(hit, _damage[i], push)
				if _pierce[i] > 0:
					_pierce[i] -= 1
				else:
					alive = false

		if alive:
			i += 1
		else:
			_remove_at(i)
	queue_redraw()


func _draw() -> void:
	_drawn_count = _count
	for i in _count:
		var head := _pos[i] + DRAW_OFFSET
		draw_line(head - _vel[i] * TRAIL_TIME, head, color, 1.0)


func _remove_at(i: int) -> void:
	var last := _count - 1
	if i != last:
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_damage[i] = _damage[last]
		_life[i] = _life[last]
		_knockback[i] = _knockback[last]
		_pierce[i] = _pierce[last]
		_last_hit[i] = _last_hit[last]
	_count = last
