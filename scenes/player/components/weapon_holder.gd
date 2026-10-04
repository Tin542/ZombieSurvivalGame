class_name WeaponHolder
extends Node
## The run's weapon loadout with per-weapon ammo. Fires automatically at the
## AutoAim target, reloads on its own, and falls back to another weapon when
## the current one is completely dry. Shots leave as `projectile_requested`
## signals, so this node never touches the projectile system.

signal projectile_requested(origin: Vector2, velocity: Vector2, damage: float, pierce: int, lifetime: float, knockback: float)
signal fired(direction: Vector2)
signal weapon_changed(weapon: WeaponDef)
signal ammo_changed(magazine: int, reserve: int, infinite: bool)
signal reload_started(duration: float)

## Delay before a freshly switched weapon can fire.
const SWITCH_DELAY := 0.15
## Projectiles fly a bit past attack_range so targets at the edge still get hit.
const RANGE_OVERSHOOT := 1.2


class WeaponSlot:
	var def: WeaponDef
	var magazine: int
	var reserve: int

	func _init(weapon: WeaponDef) -> void:
		def = weapon
		magazine = weapon.magazine_size
		reserve = clampi(weapon.start_reserve_ammo, 0, weapon.max_reserve_ammo)

	func has_any_ammo() -> bool:
		return def.infinite_ammo or magazine > 0 or reserve > 0

	func can_reload() -> bool:
		return magazine < def.magazine_size and (def.infinite_ammo or reserve > 0)


## Set by the owner (Player).
var aim: AutoAim
## Shop upgrade hook, applied to every shot.
var damage_multiplier: float = 1.0

var _slots: Array[WeaponSlot] = []
var _current := -1
var _cooldown := 0.0
var _reload_left := 0.0
var _rng := RandomNumberGenerator.new()

@onready var _origin: Node2D = get_parent()


func set_loadout(weapons: Array[WeaponDef]) -> void:
	_slots.clear()
	for weapon in weapons:
		_slots.append(WeaponSlot.new(weapon))
	_current = -1
	if not _slots.is_empty():
		switch_to(0)


func current_weapon() -> WeaponDef:
	return _slots[_current].def if _current != -1 else null


func weapon_count() -> int:
	return _slots.size()


func is_reloading() -> bool:
	return _reload_left > 0.0


func switch_to(index: int) -> void:
	if index == _current or index < 0 or index >= _slots.size():
		return
	_current = index
	_reload_left = 0.0
	_cooldown = maxf(_cooldown, SWITCH_DELAY)
	var slot := _slots[_current]
	if aim != null:
		aim.max_range = slot.def.attack_range
	weapon_changed.emit(slot.def)
	_emit_ammo()
	if slot.magazine == 0:
		_reload_or_fall_back()


## Switches to the next weapon that still has ammo.
func cycle_weapon() -> void:
	var next := _next_with_ammo()
	if next != -1:
		switch_to(next)


## True if any weapon in the loadout runs on limited ammo (so ammo pickups
## are worth anything).
func has_limited_ammo() -> bool:
	for slot in _slots:
		if not slot.def.infinite_ammo:
			return true
	return false


## How full the limited-ammo weapons are overall, 0..1 (magazines included).
## 1.0 when the loadout has no limited weapons.
func ammo_fill_ratio() -> float:
	var have := 0
	var cap := 0
	for slot in _slots:
		if not slot.def.infinite_ammo:
			have += slot.magazine + slot.reserve
			cap += slot.def.magazine_size + slot.def.max_reserve_ammo
	return float(have) / cap if cap > 0 else 1.0


## Refills every weapon's reserve by `fraction` of its max (supply crates).
func add_ammo(fraction: float) -> void:
	for slot in _slots:
		if not slot.def.infinite_ammo:
			var amount := ceili(slot.def.max_reserve_ammo * fraction)
			slot.reserve = mini(slot.reserve + amount, slot.def.max_reserve_ammo)
	_emit_ammo()


func _physics_process(delta: float) -> void:
	if _current == -1:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	var slot := _slots[_current]

	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload(slot)
		return

	if slot.magazine == 0:
		_reload_or_fall_back()
	elif aim.has_target:
		if _cooldown == 0.0:
			_fire(slot)
	elif slot.can_reload():
		# Top up the magazine during lulls.
		_start_reload(slot)


func _fire(slot: WeaponSlot) -> void:
	var def := slot.def
	_cooldown = def.fire_interval
	slot.magazine -= 1

	var origin := _origin.global_position
	var direction := origin.direction_to(aim.target_position)
	var half_spread := deg_to_rad(def.spread_degrees) * 0.5
	var lifetime := def.attack_range * RANGE_OVERSHOOT / def.projectile_speed
	var damage := def.damage * damage_multiplier
	var pellets := def.projectiles_per_shot
	for p in pellets:
		var angle := _rng.randf_range(-half_spread, half_spread)
		if pellets > 1:
			# Even fan with a little jitter so pellets don't look gridded.
			angle = lerpf(-half_spread, half_spread, float(p) / (pellets - 1)) + angle * 0.2
		var velocity := direction.rotated(angle) * def.projectile_speed
		projectile_requested.emit(origin, velocity, damage, def.pierce, lifetime, def.knockback)

	fired.emit(direction)
	_emit_ammo()
	if slot.magazine == 0:
		_reload_or_fall_back()


func _reload_or_fall_back() -> void:
	var slot := _slots[_current]
	if slot.can_reload():
		_start_reload(slot)
	else:
		cycle_weapon()


func _start_reload(slot: WeaponSlot) -> void:
	if _reload_left > 0.0:
		return
	_reload_left = slot.def.reload_time
	reload_started.emit(slot.def.reload_time)


func _finish_reload(slot: WeaponSlot) -> void:
	_reload_left = 0.0
	var needed := slot.def.magazine_size - slot.magazine
	if not slot.def.infinite_ammo:
		needed = mini(needed, slot.reserve)
		slot.reserve -= needed
	slot.magazine += needed
	_emit_ammo()


func _next_with_ammo() -> int:
	for step in range(1, _slots.size()):
		var index := (_current + step) % _slots.size()
		if _slots[index].has_any_ammo():
			return index
	return -1


func _emit_ammo() -> void:
	if _current == -1:
		return
	var slot := _slots[_current]
	ammo_changed.emit(slot.magazine, slot.reserve, slot.def.infinite_ammo)
