class_name PickupManager
extends Node2D
## Item pickups on the ground: zombie loot, stacks dropped from the bag, and
## starting ammo that didn't fit. Walking over a landed pickup offers it to
## `accept`; whatever the bag can't take stays on the ground, so a stack can be
## picked up in parts. Pickups expire after `lifetime` seconds and blink
## before they go.
##
## Like CoinManager this node never touches run state: `accept` (set by the
## run) decides what taking an item means, and `collected` reports it. There
## are only ever a few dozen, so they are plain objects in an array, drawn in
## one _draw call on the ground layer. Keep this node at the origin, like
## ZombieManager.

## `count` units of `def` were taken at `world_position`.
signal collected(def: ItemDef, count: int, world_position: Vector2)
## A pickup of `count` units of `def` was put on the ground.
signal spawned(def: ItemDef, count: int)

## Loot pops out of the kill in an arc and can't be taken until it lands.
const POP_TIME := 0.3
const POP_HEIGHT := 10.0
const BLINK_TIME := 5.0
const BLINK_RATE := 6.0
const SIZE := 5.0
const OUTLINE := Color(0.1, 0.08, 0.05)

## When full, the oldest pickup makes room for the new one.
@export var max_pickups: int = 96
@export var lifetime: float = 30.0
@export var pickup_radius: float = 10.0
## Drops land up to this far from where they came from.
@export var scatter: float = 10.0
## A held pickup (dropped at the player's feet) only becomes collectable once
## the target has been at least this far from it.
@export var rearm_distance: float = 18.0

## What collects pickups. Null = nothing is collected.
var target: Node2D
## (def: ItemDef, count: int) -> int: how many units were taken (0 = none fit).
var accept: Callable

var _bounds: Rect2
var _pickups: Array[Pickup] = []
var _drawn_count := 0
var _rng := RandomNumberGenerator.new()


class Pickup:
	var def: ItemDef
	var count: int
	## Where it popped out from; it arcs to `position`.
	var origin: Vector2
	var position: Vector2
	var age: float
	## Waits for the target to step away before it can be collected.
	var held: bool


func setup(bounds: Rect2) -> void:
	_bounds = bounds


## Drops `count` units of `def` near `world_position`. `hold` keeps it from
## being collected until the target has moved away (for drops at the
## player's own feet).
func spawn(world_position: Vector2, def: ItemDef, count: int, hold: bool = false) -> void:
	if def == null or count <= 0:
		return
	if _pickups.size() >= maxi(max_pickups, 1):
		_pickups.remove_at(0)
	var area := _bounds.grow(-SIZE)
	var pickup := Pickup.new()
	pickup.def = def
	pickup.count = count
	pickup.origin = to_local(world_position).clamp(area.position, area.end)
	var offset := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(scatter * 0.4, scatter)
	pickup.position = (pickup.origin + offset).clamp(area.position, area.end)
	pickup.age = 0.0
	pickup.held = hold
	_pickups.append(pickup)
	queue_redraw()
	spawned.emit(def, count)


func clear() -> void:
	_pickups.clear()
	queue_redraw()


func active_count() -> int:
	return _pickups.size()


func get_pickup_def(index: int) -> ItemDef:
	return _pickups[index].def


func get_pickup_count(index: int) -> int:
	return _pickups[index].count


func get_pickup_position(index: int) -> Vector2:
	return to_global(_pickups[index].position)


func is_pickup_landed(index: int) -> bool:
	return _pickups[index].age >= POP_TIME


## Units of `def` lying on the ground.
func count_on_ground(def: ItemDef) -> int:
	var total := 0
	for pickup in _pickups:
		if pickup.def == def:
			total += pickup.count
	return total


func _physics_process(delta: float) -> void:
	if _pickups.is_empty():
		return
	for i in range(_pickups.size() - 1, -1, -1):
		var pickup := _pickups[i]
		pickup.age += delta
		if pickup.age >= lifetime:
			_pickups.remove_at(i)
	if target == null or not accept.is_valid():
		return

	var target_pos := to_local(target.global_position)
	var reach_sq := pickup_radius * pickup_radius
	var rearm_sq := rearm_distance * rearm_distance
	for i in range(_pickups.size() - 1, -1, -1):
		var pickup := _pickups[i]
		if pickup.age < POP_TIME:
			continue
		var d2 := pickup.position.distance_squared_to(target_pos)
		if pickup.held:
			if d2 >= rearm_sq:
				pickup.held = false
			continue
		if d2 > reach_sq:
			continue
		var taken: int = accept.call(pickup.def, pickup.count)
		if taken <= 0:
			continue
		pickup.count -= taken
		if pickup.count <= 0:
			_pickups.remove_at(i)
		collected.emit(pickup.def, taken, to_global(pickup.position))


func _process(_delta: float) -> void:
	# Pop arcs and blinking change every frame; one more redraw clears the last.
	if not _pickups.is_empty() or _drawn_count > 0:
		queue_redraw()


func _draw() -> void:
	_drawn_count = _pickups.size()
	for pickup in _pickups:
		var left := lifetime - pickup.age
		if left < BLINK_TIME and fmod(left * BLINK_RATE, 2.0) < 1.0:
			continue
		var t := clampf(pickup.age / POP_TIME, 0.0, 1.0)
		var ground := pickup.origin.lerp(pickup.position, t)
		var lift := sin(t * PI) * POP_HEIGHT
		draw_rect(Rect2(ground + Vector2(-SIZE * 0.5, -1.0), Vector2(SIZE, 2.0)), Color(0, 0, 0, 0.3))
		var top_left := (ground - Vector2(SIZE * 0.5, SIZE + 1.0 + lift)).round()
		draw_rect(Rect2(top_left - Vector2.ONE, Vector2(SIZE + 2.0, SIZE + 2.0)), OUTLINE)
		draw_rect(Rect2(top_left, Vector2(SIZE, SIZE)), pickup.def.color)
		draw_rect(Rect2(top_left, Vector2.ONE), Color(1, 1, 1, 0.8))
