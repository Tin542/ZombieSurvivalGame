class_name ZombieManager
extends Node2D
## Simulates every zombie in one loop over packed arrays (structure-of-arrays).
## Zombie nodes are display-only pooled sprites: no per-zombie scripts or
## physics bodies. Hits, separation and contact all go through SpatialGrid.
##
## Positions are in this node's local space, which must match the arena's
## (keep this node at the origin).
##
## Zombie indices are only stable until the next physics tick: dead zombies are
## compacted (swap-remove) at the start of each tick. To follow one zombie
## across ticks, keep its uid and call resolve().

signal zombie_killed(position: Vector2, def: ZombieDef)
## A zombie landed a contact attack on `target`.
signal target_hit(damage: float)

const FLASH_TIME := 0.06
const FLASH_COLOR := Color(1.0, 0.35, 0.35)

## Hard cap on simulated zombies; extra spawns wait in a queue.
@export var max_alive: int = 400
@export var grid_cell_size: float = 32.0
## Each zombie recomputes separation every N ticks (staggered) to spread cost.
@export_range(1, 8) var separation_stride: int = 2
@export var separation_strength: float = 8.0
@export var max_separation_speed: float = 60.0
## Spawns try to land at least this far from the target (i.e. off-screen).
@export var min_spawn_distance: float = 380.0

## What zombies chase and attack. Null = zombies idle.
var target: Node2D
var target_radius: float = 5.0

var _bounds: Rect2
var _grid: SpatialGrid
var _rng := RandomNumberGenerator.new()
var _tick := 0
var _has_dead := false
var _max_radius := 0.0
var _next_uid := 1

var _count := 0
var _uid := PackedInt32Array()
var _pos := PackedVector2Array()
var _push := PackedVector2Array()
var _hp := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _attack_cd := PackedFloat32Array()
var _flash := PackedFloat32Array()
var _def: Array[ZombieDef] = []
var _view: Array[Sprite2D] = []

## Spawns waiting for a free slot: [def, hp_multiplier, speed_multiplier].
var _queue: Array[Array] = []


func setup(bounds: Rect2) -> void:
	_bounds = bounds
	_grid = SpatialGrid.new(bounds, grid_cell_size)
	_uid.resize(max_alive)
	_pos.resize(max_alive)
	_push.resize(max_alive)
	_hp.resize(max_alive)
	_speed.resize(max_alive)
	_radius.resize(max_alive)
	_attack_cd.resize(max_alive)
	_flash.resize(max_alive)
	_def.resize(max_alive)
	_view.resize(max_alive)


## Spawns one zombie at a random off-screen point in the arena, or queues it if
## max_alive is reached.
func spawn(def: ZombieDef, hp_multiplier: float = 1.0, speed_multiplier: float = 1.0) -> void:
	if _count >= max_alive:
		_queue.append([def, hp_multiplier, speed_multiplier])
		return
	_activate(def, _pick_spawn_position(), hp_multiplier, speed_multiplier)


## Applies damage to zombie `index` and nudges it by `knockback`. Returns true
## if this hit killed it.
func damage(index: int, amount: float, knockback: Vector2 = Vector2.ZERO) -> bool:
	if not is_alive(index):
		return false
	_hp[index] -= amount
	var view := _view[index]
	if _hp[index] > 0.0:
		_pos[index] += knockback
		_flash[index] = FLASH_TIME
		view.modulate = FLASH_COLOR
		return false
	view.visible = false
	_has_dead = true
	zombie_killed.emit(_pos[index], _def[index])
	return true


## Index of the closest living zombie within `max_distance`, or -1.
func find_nearest(from: Vector2, max_distance: float) -> int:
	if _grid == null:
		return -1
	var n := _grid.query_radius(from, max_distance)
	var results := _grid.results
	var best := -1
	var best_d2 := INF
	for k in n:
		var i := results[k]
		if _hp[i] <= 0.0:
			continue
		var d2 := from.distance_squared_to(_pos[i])
		if d2 < best_d2:
			best_d2 = d2
			best = i
	return best


## Index of a living zombie whose body overlaps the circle (`point`, `radius`),
## skipping the zombie with uid `ignore_uid`. -1 if none.
func find_hit(point: Vector2, radius: float, ignore_uid: int = 0) -> int:
	if _grid == null:
		return -1
	var n := _grid.query_radius(point, radius + _max_radius)
	var results := _grid.results
	for k in n:
		var i := results[k]
		if _hp[i] <= 0.0 or _uid[i] == ignore_uid:
			continue
		var reach := radius + _radius[i]
		if point.distance_squared_to(_pos[i]) <= reach * reach:
			return i
	return -1


## Returns `hint` if it still refers to the living zombie `uid`, else -1.
## Cheap O(1) check; callers re-acquire a target when it returns -1.
func resolve(uid: int, hint: int) -> int:
	if is_alive(hint) and _uid[hint] == uid:
		return hint
	return -1


func is_alive(index: int) -> bool:
	return index >= 0 and index < _count and _hp[index] > 0.0


func get_uid(index: int) -> int:
	return _uid[index]


func get_zombie_position(index: int) -> Vector2:
	return _pos[index]


func get_zombie_radius(index: int) -> float:
	return _radius[index]


func alive_count() -> int:
	return _count


func queued_count() -> int:
	return _queue.size()


## Removes every zombie and pending spawn.
func clear() -> void:
	for i in _count:
		_view[i].visible = false
		_def[i] = null
	_count = 0
	_queue.clear()
	_has_dead = false


func _physics_process(delta: float) -> void:
	if _grid == null:
		return
	if _has_dead:
		_compact()
	_drain_queue()
	_grid.rebuild(_pos, _count)
	if _count == 0 or target == null:
		return

	_tick += 1
	var target_pos := to_local(target.global_position)
	var min_x := _bounds.position.x
	var max_x := _bounds.end.x
	var min_y := _bounds.position.y
	var max_y := _bounds.end.y

	for i in _count:
		var p := _pos[i]
		var r := _radius[i]
		var to_target := target_pos - p
		var dist := to_target.length()
		var reach := r + target_radius

		var velocity := Vector2.ZERO
		if dist > reach:
			velocity = to_target * (_speed[i] / dist)
		if (i + _tick) % separation_stride == 0:
			_push[i] = _separation(i, p, r)
		velocity += _push[i]

		p += velocity * delta
		p.x = clampf(p.x, min_x + r, max_x - r)
		p.y = clampf(p.y, min_y + r, max_y - r)
		_pos[i] = p

		var view := _view[i]
		view.position = p
		if absf(to_target.x) > 1.0:
			view.flip_h = to_target.x < 0.0
		if _flash[i] > 0.0:
			_flash[i] -= delta
			if _flash[i] <= 0.0:
				view.modulate = _def[i].tint

		var cooldown := _attack_cd[i] - delta
		if cooldown <= 0.0:
			cooldown = 0.0
			if dist <= reach + 1.0:
				var def := _def[i]
				cooldown = def.attack_interval
				target_hit.emit(def.contact_damage)
		_attack_cd[i] = cooldown


func _separation(i: int, p: Vector2, r: float) -> Vector2:
	var n := _grid.query_radius(p, r + _max_radius)
	var results := _grid.results
	var push := Vector2.ZERO
	for k in n:
		var j := results[k]
		if j == i or _hp[j] <= 0.0:
			continue
		var min_dist := r + _radius[j]
		var diff := p - _pos[j]
		var d2 := diff.length_squared()
		if d2 >= min_dist * min_dist:
			continue
		if d2 < 0.0001:
			# Exactly stacked: fan out by golden angle so they don't move as one.
			diff = Vector2.RIGHT.rotated(float(i) * 2.39996)
			d2 = 1.0
		var d := sqrt(d2)
		push += diff * ((min_dist - d) / d)
	return (push * separation_strength).limit_length(max_separation_speed)


func _activate(def: ZombieDef, at: Vector2, hp_multiplier: float, speed_multiplier: float) -> void:
	var i := _count
	_count += 1
	_uid[i] = _next_uid
	_next_uid = _next_uid + 1 if _next_uid < 0x7FFFFFFF else 1
	_pos[i] = at
	_push[i] = Vector2.ZERO
	_hp[i] = def.max_hp * hp_multiplier
	_speed[i] = def.move_speed * speed_multiplier
	_radius[i] = def.radius
	_attack_cd[i] = def.attack_interval
	_flash[i] = 0.0
	_def[i] = def
	_max_radius = maxf(_max_radius, def.radius)

	var view := _view[i]
	if view == null:
		view = Sprite2D.new()
		add_child(view)
		_view[i] = view
	view.texture = def.texture
	view.offset = Vector2(0.0, -def.texture.get_height() * 0.5) if def.texture else Vector2.ZERO
	view.modulate = def.tint
	view.position = at
	view.visible = true


## Swap-removes dead zombies. Iterates backwards so each swapped-in element
## (from the end) has already been checked.
func _compact() -> void:
	_has_dead = false
	for i in range(_count - 1, -1, -1):
		if _hp[i] > 0.0:
			continue
		var last := _count - 1
		if i != last:
			_uid[i] = _uid[last]
			_pos[i] = _pos[last]
			_push[i] = _push[last]
			_hp[i] = _hp[last]
			_speed[i] = _speed[last]
			_radius[i] = _radius[last]
			_attack_cd[i] = _attack_cd[last]
			_flash[i] = _flash[last]
			_def[i] = _def[last]
			# Keep the hidden view in the now-free slot for reuse.
			var dead_view := _view[i]
			_view[i] = _view[last]
			_view[last] = dead_view
		_def[last] = null
		_count = last


func _drain_queue() -> void:
	while not _queue.is_empty() and _count < max_alive:
		var pending: Array = _queue.pop_front()
		_activate(pending[0], _pick_spawn_position(), pending[1], pending[2])


## Random point inside the arena, preferring ones far from the target.
func _pick_spawn_position() -> Vector2:
	var area := _bounds.grow(-8.0)
	var avoid := to_local(target.global_position) if target else area.get_center()
	var min_d2 := min_spawn_distance * min_spawn_distance
	var best := area.get_center()
	var best_d2 := -1.0
	for _attempt in 8:
		var p := Vector2(
			_rng.randf_range(area.position.x, area.end.x),
			_rng.randf_range(area.position.y, area.end.y))
		var d2 := p.distance_squared_to(avoid)
		if d2 >= min_d2:
			return p
		if d2 > best_d2:
			best_d2 = d2
			best = p
	return best
