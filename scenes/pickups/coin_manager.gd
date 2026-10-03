class_name CoinManager
extends Node2D
## Coin drops, simulated over packed arrays and drawn in a single _draw call
## (no node per coin). Coins rest where they dropped until the target comes
## within magnet_radius, then home in with growing speed and are collected.
## Collected value leaves as the `collected` signal; this node never touches
## run state. Keep this node at the origin, like ZombieManager.

## Coins picked up this tick, summed.
signal collected(amount: int)

## Drops worth at least this are drawn as a bigger coin.
const BIG_VALUE := 5
const BOB_SPEED := 5.0
const OUTLINE := Color(0.25, 0.15, 0.0)

@export var max_coins: int = 512
## Shop upgrade hook: distance at which resting coins start homing.
@export var magnet_radius: float = 40.0
@export var pickup_radius: float = 6.0
@export var home_speed: float = 60.0
@export var home_accel: float = 500.0
## Drops land up to this far from the kill so piles don't stack on one pixel.
@export var drop_scatter: float = 4.0
@export var color := Color(1.0, 0.8, 0.2)
@export var big_color := Color(1.0, 0.95, 0.55)

## What coins home in on. Null = coins stay put and nothing is collected.
var target: Node2D

var _bounds: Rect2
var _count := 0
var _pos := PackedVector2Array()
var _value := PackedInt32Array()
## 0 while resting, otherwise current homing speed.
var _speed := PackedFloat32Array()
var _time := 0.0
var _drawn_count := 0
var _rng := RandomNumberGenerator.new()


func setup(bounds: Rect2) -> void:
	_bounds = bounds
	_pos.resize(max_coins)
	_value.resize(max_coins)
	_speed.resize(max_coins)


## Drops a coin worth `value` at `world_position`. When the pool is full the
## value is awarded at once instead, so money is never lost.
func spawn(world_position: Vector2, value: int) -> void:
	if value <= 0:
		return
	if _count >= max_coins:
		collected.emit(value)
		return
	var i := _count
	_count += 1
	var at := to_local(world_position) + Vector2(
		_rng.randf_range(-drop_scatter, drop_scatter),
		_rng.randf_range(-drop_scatter, drop_scatter))
	_pos[i] = at.clamp(_bounds.position, _bounds.end)
	_value[i] = value
	_speed[i] = 0.0


## Sends every coin on the ground to the target (e.g. when a wave is cleared).
func collect_all() -> void:
	for i in _count:
		if _speed[i] == 0.0:
			_speed[i] = home_speed


func active_count() -> int:
	return _count


func clear() -> void:
	_count = 0
	queue_redraw()


func _physics_process(delta: float) -> void:
	_time += delta
	if _count == 0:
		if _drawn_count > 0:
			queue_redraw()
		return
	queue_redraw()
	if target == null:
		return

	var target_pos := to_local(target.global_position)
	var magnet_sq := magnet_radius * magnet_radius
	var pickup_sq := pickup_radius * pickup_radius
	var total := 0
	var i := 0
	while i < _count:
		var p := _pos[i]
		var d2 := p.distance_squared_to(target_pos)
		var speed := _speed[i]
		if speed == 0.0 and d2 <= magnet_sq:
			speed = home_speed
		if speed > 0.0:
			speed += home_accel * delta
			_speed[i] = speed
			var dist := sqrt(d2)
			var step := speed * delta
			if dist > step + pickup_radius:
				_pos[i] = p + (target_pos - p) * (step / dist)
				i += 1
				continue
		elif d2 > pickup_sq:
			i += 1
			continue
		total += _value[i]
		_remove_at(i)

	if total > 0:
		collected.emit(total)


func _draw() -> void:
	_drawn_count = _count
	for i in _count:
		var big := _value[i] >= BIG_VALUE
		var size := 4.0 if big else 3.0
		# Resting coins bob a pixel; homing ones fly straight.
		var bob := 0.0
		if _speed[i] == 0.0:
			bob = roundf(sin(_time * BOB_SPEED + float(i)) * 0.5 - 0.5)
		var top_left := (_pos[i] + Vector2(-size * 0.5, -size - 1.0 + bob)).round()
		draw_rect(Rect2(top_left - Vector2.ONE, Vector2(size + 2.0, size + 2.0)), OUTLINE)
		draw_rect(Rect2(top_left, Vector2(size, size)), big_color if big else color)


func _remove_at(i: int) -> void:
	var last := _count - 1
	if i != last:
		_pos[i] = _pos[last]
		_value[i] = _value[last]
		_speed[i] = _speed[last]
	_count = last
