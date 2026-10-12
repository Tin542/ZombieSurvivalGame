class_name GrenadeManager
extends Node2D
## Thrown grenades and their explosions, simulated over packed arrays and
## drawn in a single _draw call. A grenade flies in an arc from the thrower to
## its landing point over its fuse time and explodes on arrival; the blast
## goes through ZombieManager.blast() (the zombie grid), so the player is
## never hurt. Also draws the landing reticle while the player is aiming.
## Keep this node at the origin, like ZombieManager.

## A grenade went off at `world_position`; `kills` zombies died in the blast.
signal exploded(world_position: Vector2, radius: float, kills: int)

const ARC_HEIGHT := 28.0
const SIZE := 3.0
const BLAST_TIME := 0.3
const MAX_BLASTS := 16
const BODY_COLOR := Color(0.3, 0.38, 0.2)
const OUTLINE := Color(0.08, 0.08, 0.05)
const BLAST_COLOR := Color(1.0, 0.65, 0.2)
const RETICLE_COLOR := Color(1.0, 0.85, 0.3)

@export var max_grenades: int = 16
## Zombies at the blast centre are pushed this far (less towards the edge).
@export var knockback: float = 10.0

## Injected by the run.
var zombies: ZombieManager

var _bounds: Rect2
var _count := 0
var _from := PackedVector2Array()
var _to := PackedVector2Array()
var _age := PackedFloat32Array()
var _fuse := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _radius := PackedFloat32Array()

var _blast_count := 0
var _blast_pos := PackedVector2Array()
var _blast_radius := PackedFloat32Array()
var _blast_age := PackedFloat32Array()

var _aiming := false
var _aim_origin := Vector2.ZERO
var _aim_point := Vector2.ZERO
var _aim_radius := 0.0
var _aim_range := 0.0
var _drawn := false


func setup(bounds: Rect2) -> void:
	_bounds = bounds
	_from.resize(max_grenades)
	_to.resize(max_grenades)
	_age.resize(max_grenades)
	_fuse.resize(max_grenades)
	_damage.resize(max_grenades)
	_radius.resize(max_grenades)
	_blast_pos.resize(MAX_BLASTS)
	_blast_radius.resize(MAX_BLASTS)
	_blast_age.resize(MAX_BLASTS)


## Throws a grenade from `from_world` to `to_world` (clamped into the arena).
## It explodes after `fuse` seconds with `damage` at the centre. Returns false
## when too many grenades are already in the air.
func throw(from_world: Vector2, to_world: Vector2, fuse: float, damage: float, radius: float) -> bool:
	if _count >= max_grenades:
		return false
	var i := _count
	_count += 1
	_from[i] = to_local(from_world)
	_to[i] = to_local(to_world).clamp(_bounds.position, _bounds.end)
	_age[i] = 0.0
	_fuse[i] = maxf(fuse, 0.01)
	_damage[i] = damage
	_radius[i] = radius
	queue_redraw()
	return true


## Shows where a grenade would land: the blast circle at `world_point` and
## the throw range around `origin_world`.
func show_aim(origin_world: Vector2, world_point: Vector2, blast_radius: float, throw_range: float) -> void:
	_aiming = true
	_aim_origin = to_local(origin_world)
	_aim_point = to_local(world_point).clamp(_bounds.position, _bounds.end)
	_aim_radius = blast_radius
	_aim_range = throw_range
	queue_redraw()


func hide_aim() -> void:
	if _aiming:
		_aiming = false
		queue_redraw()


func is_aiming() -> bool:
	return _aiming


func active_count() -> int:
	return _count


## Grenade `index`'s landing point, in world space.
func get_landing_point(index: int) -> Vector2:
	return to_global(_to[index])


## Removes grenades in the air (they don't explode) and the aim reticle.
func clear() -> void:
	_count = 0
	_blast_count = 0
	_aiming = false
	queue_redraw()


func _physics_process(delta: float) -> void:
	var i := 0
	while i < _count:
		_age[i] += delta
		if _age[i] < _fuse[i]:
			i += 1
			continue
		var at := _to[i]
		var radius := _radius[i]
		var damage := _damage[i]
		_remove_at(i)
		_explode(at, radius, damage)

	i = 0
	while i < _blast_count:
		_blast_age[i] += delta
		if _blast_age[i] >= BLAST_TIME:
			_remove_blast(i)
		else:
			i += 1


func _process(_delta: float) -> void:
	if _count > 0 or _blast_count > 0 or _aiming or _drawn:
		queue_redraw()


func _explode(at: Vector2, radius: float, damage: float) -> void:
	var kills := 0
	if zombies != null:
		kills = zombies.blast(to_global(at), radius, damage, knockback)
	if _blast_count < MAX_BLASTS:
		_blast_pos[_blast_count] = at
		_blast_radius[_blast_count] = radius
		_blast_age[_blast_count] = 0.0
		_blast_count += 1
	exploded.emit(to_global(at), radius, kills)


func _draw() -> void:
	_drawn = _count > 0 or _blast_count > 0 or _aiming
	if _aiming:
		draw_arc(_aim_origin, _aim_range, 0.0, TAU, 48, Color(RETICLE_COLOR, 0.25), 1.0)
		draw_circle(_aim_point, _aim_radius, Color(RETICLE_COLOR, 0.12))
		draw_arc(_aim_point, _aim_radius, 0.0, TAU, 32, RETICLE_COLOR, 1.0)
		draw_rect(Rect2(_aim_point - Vector2.ONE, Vector2(2, 2)), RETICLE_COLOR)

	for i in _blast_count:
		var t := _blast_age[i] / BLAST_TIME
		var r := _blast_radius[i] * (0.4 + 0.6 * t)
		draw_circle(_blast_pos[i], r, Color(BLAST_COLOR, 0.55 * (1.0 - t)))
		draw_arc(_blast_pos[i], r, 0.0, TAU, 32, Color(1.0, 0.95, 0.7, 1.0 - t), 2.0)

	for i in _count:
		var t := clampf(_age[i] / _fuse[i], 0.0, 1.0)
		var ground := _from[i].lerp(_to[i], t)
		var lift := 4.0 * t * (1.0 - t) * ARC_HEIGHT
		draw_rect(Rect2(ground + Vector2(-SIZE * 0.5, -0.5), Vector2(SIZE, 1.0)), Color(0, 0, 0, 0.35))
		var top_left := (ground - Vector2(SIZE * 0.5, SIZE + lift)).round()
		draw_rect(Rect2(top_left - Vector2.ONE, Vector2(SIZE + 2.0, SIZE + 2.0)), OUTLINE)
		draw_rect(Rect2(top_left, Vector2(SIZE, SIZE)), BODY_COLOR)


func _remove_at(i: int) -> void:
	var last := _count - 1
	if i != last:
		_from[i] = _from[last]
		_to[i] = _to[last]
		_age[i] = _age[last]
		_fuse[i] = _fuse[last]
		_damage[i] = _damage[last]
		_radius[i] = _radius[last]
	_count = last


func _remove_blast(i: int) -> void:
	var last := _blast_count - 1
	if i != last:
		_blast_pos[i] = _blast_pos[last]
		_blast_radius[i] = _blast_radius[last]
		_blast_age[i] = _blast_age[last]
	_blast_count = last
