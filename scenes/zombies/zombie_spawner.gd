class_name ZombieSpawner
extends Node
## Decides when and where zombies appear; ZombieManager only simulates them.
##
## - Timed batches: start_batch() releases N zombies at a steady interval, using
##   the WaveTable for type mix and per-wave HP/speed scaling.
## - Bursts: spawn_burst() releases N zombies as fast as allowed (debug, events).
## - Never drops a zombie: while the manager is full, spawns wait.
## - At most max_per_tick spawns per physics tick, so big bursts don't hitch.
## - Spawn points sit just outside the camera view (all four sides), inside the
##   arena, so zombies walk in from off-screen near the player.

## Every zombie of the current timed batch has been spawned.
signal batch_finished
signal zombie_spawned(def: ZombieDef)

## Extra distance beyond the screen edge. Must exceed the tallest zombie sprite
## so bodies drawn above the feet aren't visible on spawn.
@export var view_margin: float = 24.0
## Spawn band thickness beyond view_margin.
@export var band_depth: float = 96.0
@export var max_per_tick: int = 8

var _zombies: ZombieManager
var _target: Node2D
var _bounds: Rect2
var _table: WaveTable
var _rng := RandomNumberGenerator.new()

var _batch_active := false
var _batch_remaining := 0
var _batch_interval := 1.0
var _batch_timer := 0.0
var _batch_wave := 1

var _burst_remaining := 0
var _burst_wave := 1


## `target` is what the view is centred on when no Camera2D is current.
func setup(zombies: ZombieManager, target: Node2D, bounds: Rect2, table: WaveTable) -> void:
	_zombies = zombies
	_target = target
	_bounds = bounds
	_table = table


## Spawns `count` zombies for `wave`, one every `interval` seconds (the first
## immediately). Replaces any batch in progress.
func start_batch(count: int, interval: float, wave: int) -> void:
	_batch_active = count > 0
	_batch_remaining = maxi(count, 0)
	_batch_interval = maxf(interval, 0.0)
	_batch_timer = 0.0
	_batch_wave = wave


## Spawns `count` extra zombies as fast as capacity allows, using the type mix
## and scaling of `wave`.
func spawn_burst(count: int, wave: int) -> void:
	_burst_remaining += maxi(count, 0)
	_burst_wave = wave


## Cancels the batch and any pending burst.
func stop() -> void:
	_batch_active = false
	_batch_remaining = 0
	_burst_remaining = 0


func is_batch_active() -> bool:
	return _batch_active


## Zombies requested but not spawned yet.
func pending_count() -> int:
	return _batch_remaining + _burst_remaining


func _physics_process(delta: float) -> void:
	if _zombies == null:
		return
	var budget := max_per_tick

	if _batch_active:
		_batch_timer -= delta
		while _batch_remaining > 0 and _batch_timer <= 0.0 and budget > 0:
			if not _spawn_one(_batch_wave):
				# Full: hold the timer so capacity freeing up later doesn't
				# release a backlog all at once.
				_batch_timer = 0.0
				break
			_batch_remaining -= 1
			_batch_timer += _batch_interval
			budget -= 1
		if _batch_remaining == 0:
			_batch_active = false
			batch_finished.emit()

	while _burst_remaining > 0 and budget > 0:
		if not _spawn_one(_burst_wave):
			break
		_burst_remaining -= 1
		budget -= 1


func _spawn_one(wave: int) -> bool:
	if _zombies.is_full():
		return false
	var def := _table.pick_zombie(wave, _rng)
	if def == null:
		push_warning("ZombieSpawner: WaveTable has no zombie for wave %d" % wave)
		return true  # Consume the request so a bad table can't stall the run.
	var at := pick_spawn_point()
	_zombies.spawn_at(def, at, _table.hp_multiplier(wave), _table.speed_multiplier(wave))
	zombie_spawned.emit(def)
	return true


## A point inside the arena just outside the visible screen: uniform over the
## four bands framing the view (top, bottom, left, right), clipped to the
## arena. Any point chosen this way is off-screen by construction. Only if the
## arena leaves no room at all around the view does it fall back to the arena
## corner furthest from the view centre.
func pick_spawn_point() -> Vector2:
	var center := _view_center()
	var half := _view_half_size()
	var area := _bounds.grow(-4.0)
	var inner := Rect2(center - half, half * 2.0).grow(view_margin)
	var outer := inner.grow(band_depth)
	var bands: Array[Rect2] = [
		Rect2(outer.position.x, outer.position.y, outer.size.x, band_depth),
		Rect2(outer.position.x, inner.end.y, outer.size.x, band_depth),
		Rect2(outer.position.x, inner.position.y, band_depth, inner.size.y),
		Rect2(inner.end.x, inner.position.y, band_depth, inner.size.y),
	]
	var total := 0.0
	for k in bands.size():
		bands[k] = bands[k].intersection(area)
		total += bands[k].get_area()
	if total <= 0.0:
		return _farthest_corner(area, center)

	var roll := _rng.randf() * total
	var chosen := Rect2()
	for band in bands:
		if band.get_area() <= 0.0:
			continue
		chosen = band
		roll -= band.get_area()
		if roll <= 0.0:
			break
	return Vector2(
		_rng.randf_range(chosen.position.x, chosen.end.x),
		_rng.randf_range(chosen.position.y, chosen.end.y))


func _farthest_corner(area: Rect2, from: Vector2) -> Vector2:
	var corners: Array[Vector2] = [
		area.position, Vector2(area.end.x, area.position.y),
		Vector2(area.position.x, area.end.y), area.end,
	]
	var best := corners[0]
	for corner in corners:
		if corner.distance_squared_to(from) > best.distance_squared_to(from):
			best = corner
	return best


func _view_center() -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		return camera.get_screen_center_position()
	return _target.global_position if _target != null else _bounds.get_center()


func _view_half_size() -> Vector2:
	var size := get_viewport().get_visible_rect().size
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		size /= camera.zoom
	return size * 0.5
