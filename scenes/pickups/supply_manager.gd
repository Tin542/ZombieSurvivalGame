class_name SupplyManager
extends Node2D
## Supply crates for the break between waves. drop_crates() scatters a few
## crates within walking distance of the target; walking over a landed crate
## collects it. Crates still on the ground when the run calls clear() (next
## wave starting) are gone.
##
## Like CoinManager this node only reports pickups (`collected`) and never
## touches player or run state; the run decides what a crate gives. Crates are
## drawn in this node's _draw on the ground layer; the off-screen arrows are
## drawn by the Indicators child, which sits above the world.
## Keep this node at the origin, like ZombieManager.

signal collected(kind: Kind, world_position: Vector2)

enum Kind { HEALTH, AMMO }

const CRATE_SIZE := Vector2(10, 9)
## Crates fall in from this height and can't be picked up until they land.
const DROP_HEIGHT := 48.0
const DROP_TIME := 0.45
## Seconds between crate landings, so a drop reads as a sequence.
const DROP_STAGGER := 0.15
## Crates blink during the last seconds before they disappear.
const BLINK_TIME := 2.5
const BLINK_RATE := 8.0
const ARROW_INSET := 10.0
const ARROW_SIZE := 5.0

@export var pickup_radius: float = 10.0
## Crates land between these distances from the target...
@export var min_drop_distance: float = 60.0
@export var max_drop_distance: float = 200.0
## ...and at least this far from each other.
@export var min_spacing: float = 40.0

## What collects crates. Null = nothing is collected.
var target: Node2D

var _bounds: Rect2
var _crates: Array[Crate] = []
## Seconds until the run clears the crates (drives the end-of-break blink).
var _lifetime_left := 0.0
var _rng := RandomNumberGenerator.new()

@onready var _indicators: Node2D = $Indicators


class Crate:
	var kind: Kind
	var position: Vector2
	## Seconds since the drop started; negative while waiting its turn.
	var age: float
	var landed: bool:
		get:
			return age >= DROP_TIME


func _ready() -> void:
	_indicators.draw.connect(_draw_indicators)


func setup(bounds: Rect2) -> void:
	_bounds = bounds


## Replaces any crates with one crate per entry of `kinds`, scattered around
## the target. `lifetime` is how long until the run clears them (for blinking).
func drop_crates(kinds: Array[Kind], lifetime: float) -> void:
	_crates.clear()
	_lifetime_left = lifetime
	var center := to_local(target.global_position) if target != null else _bounds.get_center()
	var area := _bounds.grow(-CRATE_SIZE.x)
	for k in kinds.size():
		var crate := Crate.new()
		crate.kind = kinds[k]
		crate.position = _pick_drop_point(center, area)
		crate.age = -DROP_STAGGER * k
		_crates.append(crate)
	_redraw()


func clear() -> void:
	_crates.clear()
	_redraw()


func active_count() -> int:
	return _crates.size()


func get_crate_kind(index: int) -> Kind:
	return _crates[index].kind


func get_crate_position(index: int) -> Vector2:
	return to_global(_crates[index].position)


func is_crate_landed(index: int) -> bool:
	return _crates[index].landed


func _physics_process(delta: float) -> void:
	if _crates.is_empty():
		return
	_lifetime_left -= delta
	for crate in _crates:
		crate.age += delta
	if target == null:
		return

	var target_pos := to_local(target.global_position)
	var reach_sq := pickup_radius * pickup_radius
	for i in range(_crates.size() - 1, -1, -1):
		var crate := _crates[i]
		if crate.landed and crate.position.distance_squared_to(target_pos) <= reach_sq:
			_crates.remove_at(i)
			collected.emit(crate.kind, to_global(crate.position))
			_redraw()


func _process(_delta: float) -> void:
	# Falling, blinking and the camera-relative arrows all change every frame.
	if not _crates.is_empty():
		_redraw()


func _draw() -> void:
	var hidden_by_blink := _lifetime_left < BLINK_TIME and fmod(_lifetime_left * BLINK_RATE, 2.0) < 1.0
	for crate in _crates:
		if crate.age < 0.0:
			continue
		var t := clampf(crate.age / DROP_TIME, 0.0, 1.0)
		var lift := DROP_HEIGHT * (1.0 - t * t)
		# Shadow grows as the crate approaches the ground.
		var shadow_w := lerpf(4.0, CRATE_SIZE.x, t)
		draw_rect(Rect2(crate.position + Vector2(-shadow_w * 0.5, -1.0), Vector2(shadow_w, 2.0)), Color(0, 0, 0, 0.35))
		if crate.landed and hidden_by_blink:
			continue
		var top_left := (crate.position - Vector2(CRATE_SIZE.x * 0.5, CRATE_SIZE.y + lift)).round()
		_draw_crate(top_left, crate.kind)


func _draw_crate(top_left: Vector2, kind: Kind) -> void:
	var body := Rect2(top_left, CRATE_SIZE)
	draw_rect(body.grow(1.0), Color(0.12, 0.08, 0.04))
	if kind == Kind.HEALTH:
		draw_rect(body, Color(0.92, 0.92, 0.88))
		draw_rect(Rect2(top_left + Vector2(4, 2), Vector2(2, 5)), Color(0.85, 0.15, 0.15))
		draw_rect(Rect2(top_left + Vector2(2, 3.5), Vector2(6, 2)), Color(0.85, 0.15, 0.15))
	else:
		draw_rect(body, Color(0.42, 0.45, 0.22))
		for x in [2, 5, 8]:
			draw_rect(Rect2(top_left + Vector2(x - 1, 2), Vector2(1, 5)), Color(1.0, 0.82, 0.25))


## Arrows at the screen edge pointing at crates that are off-screen. Drawn on
## the Indicators child (high z_index) in world space, clamped to the view.
func _draw_indicators() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var half := get_viewport().get_visible_rect().size / camera.zoom * 0.5
	var center := _indicators.to_local(camera.get_screen_center_position())
	var view := Rect2(center - half, half * 2.0)
	var inner := view.grow(-ARROW_INSET)
	for crate in _crates:
		var p := _indicators.to_local(to_global(crate.position))
		if view.has_point(p):
			continue
		var dir := center.direction_to(p)
		var tip := p.clamp(inner.position, inner.end)
		var side := dir.orthogonal() * ARROW_SIZE * 0.6
		var base := tip - dir * ARROW_SIZE
		var color := Color(0.95, 0.3, 0.3) if crate.kind == Kind.HEALTH else Color(1.0, 0.82, 0.25)
		_indicators.draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), color)


func _redraw() -> void:
	queue_redraw()
	_indicators.queue_redraw()


## Random point in the drop ring around `center`, inside `area` and away from
## other crates. Gives up on spacing after a few tries rather than looping.
func _pick_drop_point(center: Vector2, area: Rect2) -> Vector2:
	var fallback := center.clamp(area.position, area.end)
	for _attempt in 24:
		var p := center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(min_drop_distance, max_drop_distance)
		if not area.has_point(p):
			continue
		fallback = p
		var spaced := true
		for crate in _crates:
			if crate.position.distance_to(p) < min_spacing:
				spaced = false
				break
		if spaced:
			return p
	return fallback
