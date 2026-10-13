class_name WeaponHolder
extends Node
## The run's weapon loadout with per-weapon ammo. Fires automatically at the
## AutoAim target, reloads on its own, and falls back to another weapon when
## the current one is completely dry. Shots leave as `projectile_requested`
## signals, so this node never touches the projectile system.
##
## Reserve ammo: a weapon with an ammo_item draws it from `ammo_source` (the
## run's bag), so ammo in the bag *is* the reserve. Weapons without one (or
## with no ammo_source set) keep their own reserve, as before.

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
	## Own reserve; unused for weapons that draw from ammo_source.
	var reserve: int

	func _init(weapon: WeaponDef, own_reserve: int) -> void:
		def = weapon
		magazine = weapon.magazine_size
		reserve = own_reserve


## Set by the owner (Player).
var aim: AutoAim
## Shop upgrade hook, applied to every shot.
var damage_multiplier: float = 1.0
## Shop upgrade hook: scales starting reserve ammo. Set before set_loadout().
var start_ammo_multiplier: float = 1.0
## Bag that ammo_item weapons draw their reserve from. Set before set_loadout().
var ammo_source: Inventory:
	set(value):
		if ammo_source != null:
			ammo_source.changed.disconnect(_emit_ammo)
		ammo_source = value
		if ammo_source != null:
			ammo_source.changed.connect(_emit_ammo)

var _slots: Array[WeaponSlot] = []
var _current := -1
var _cooldown := 0.0
var _reload_left := 0.0
var _rng := RandomNumberGenerator.new()

@onready var _origin: Node2D = get_parent()


func set_loadout(weapons: Array[WeaponDef]) -> void:
	_slots.clear()
	for weapon in weapons:
		var own := 0 if _uses_bag(weapon) else starting_reserve(weapon)
		_slots.append(WeaponSlot.new(weapon, own))
	_current = -1
	if not _slots.is_empty():
		switch_to(0)


## Reserve ammo `weapon` starts a run with (Ammo Pouch applied, capped).
func starting_reserve(weapon: WeaponDef) -> int:
	return weapon.starting_reserve(start_ammo_multiplier)


## Ammo items the loadout starts with, for the run to put in the bag.
func starting_ammo() -> Dictionary[ItemDef, int]:
	var kit: Dictionary[ItemDef, int] = {}
	for slot in _slots:
		if _uses_bag(slot.def):
			kit[slot.def.ammo_item] = kit.get(slot.def.ammo_item, 0) + starting_reserve(slot.def)
	return kit


## Ammo items a supply crate restoring `fraction` of each weapon's max
## reserve is worth, for the run to put in the bag.
func ammo_refill(fraction: float) -> Dictionary[ItemDef, int]:
	var refill: Dictionary[ItemDef, int] = {}
	for slot in _slots:
		if _uses_bag(slot.def):
			refill[slot.def.ammo_item] = refill.get(slot.def.ammo_item, 0) + ceili(slot.def.max_reserve_ammo * fraction)
	return refill


func current_weapon() -> WeaponDef:
	return _slots[_current].def if _current != -1 else null


func weapon_count() -> int:
	return _slots.size()


func loadout() -> Array[WeaponDef]:
	var defs: Array[WeaponDef] = []
	for slot in _slots:
		defs.append(slot.def)
	return defs


func is_reloading() -> bool:
	return _reload_left > 0.0


## Reserve of loadout weapon `index` (bag count for ammo_item weapons).
func reserve_count(index: int) -> int:
	return _reserve(_slots[index])


func magazine_count(index: int) -> int:
	return _slots[index].magazine


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


## Starts a manual reload (quick button). False if already reloading, the
## magazine is full or there is nothing to reload with.
func reload() -> bool:
	if _current == -1 or is_reloading():
		return false
	var slot := _slots[_current]
	if not _can_reload(slot):
		return false
	_start_reload(slot)
	return true


## True if any weapon in the loadout runs on limited ammo (so ammo pickups
## are worth anything).
func has_limited_ammo() -> bool:
	for slot in _slots:
		if not slot.def.infinite_ammo:
			return true
	return false


## How full the limited-ammo weapons are overall, 0..1 (magazines included,
## max_reserve_ammo as the reference). 1.0 when there are no limited weapons.
func ammo_fill_ratio() -> float:
	var have := 0
	var cap := 0
	for slot in _slots:
		if not slot.def.infinite_ammo:
			have += slot.magazine + _reserve(slot)
			cap += slot.def.magazine_size + slot.def.max_reserve_ammo
	return minf(float(have) / cap, 1.0) if cap > 0 else 1.0


## Refills the own reserve of weapons that don't use the bag by `fraction` of
## their max. Bag weapons get ammo items instead (see ammo_refill()).
func add_ammo(fraction: float) -> void:
	for slot in _slots:
		if not slot.def.infinite_ammo and not _uses_bag(slot.def):
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
	elif _can_reload(slot):
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


func _uses_bag(weapon: WeaponDef) -> bool:
	return weapon.ammo_item != null and not weapon.infinite_ammo and ammo_source != null


func _reserve(slot: WeaponSlot) -> int:
	if slot.def.infinite_ammo:
		return 0
	if _uses_bag(slot.def):
		return ammo_source.count_of(slot.def.ammo_item)
	return slot.reserve


func _has_any_ammo(slot: WeaponSlot) -> bool:
	return slot.def.infinite_ammo or slot.magazine > 0 or _reserve(slot) > 0


func _can_reload(slot: WeaponSlot) -> bool:
	return slot.magazine < slot.def.magazine_size and (slot.def.infinite_ammo or _reserve(slot) > 0)


func _reload_or_fall_back() -> void:
	var slot := _slots[_current]
	if _can_reload(slot):
		_start_reload(slot)
	else:
		cycle_weapon()


func _start_reload(slot: WeaponSlot) -> void:
	if _reload_left > 0.0:
		return
	_reload_left = slot.def.reload_time
	reload_started.emit(slot.def.reload_time)


## Ammo is taken when the reload finishes, so the bag can change mid-reload
## (drop, pickups) without going negative.
func _finish_reload(slot: WeaponSlot) -> void:
	_reload_left = 0.0
	var needed := slot.def.magazine_size - slot.magazine
	if _uses_bag(slot.def):
		needed = ammo_source.take(slot.def.ammo_item, needed)
	elif not slot.def.infinite_ammo:
		needed = mini(needed, slot.reserve)
		slot.reserve -= needed
	slot.magazine += needed
	_emit_ammo()


func _next_with_ammo() -> int:
	for step in range(1, _slots.size()):
		var index := (_current + step) % _slots.size()
		if _has_any_ammo(_slots[index]):
			return index
	return -1


## Also runs on every bag change; skipped mid-reload so the HUD keeps showing
## the reload (the finished reload emits the new numbers).
func _emit_ammo() -> void:
	if _current == -1 or is_reloading():
		return
	var slot := _slots[_current]
	ammo_changed.emit(slot.magazine, _reserve(slot), slot.def.infinite_ammo)
