extends Node
## Scripted player for headless full-run tests and balance simulations. Added
## as a child of a Run; drives the player through the move_* input actions
## (like the joystick) and the same run calls the HUD buttons make:
## kites away from nearby zombies while weapons auto-fire, walks to crates and
## loot when it's safe, heals when low, uses boosts, throws grenades at
## clusters, prefers a weapon with ammo over the pistol, and skips the break
## once nothing is left to collect. Records per-wave numbers for reports.
##
## Skill presets (configure()): "good" reacts every tick and watches a wide
## area; "casual" reacts ~5 times a second, notices zombies later, steers a
## bit sloppily and heals / throws later. Balance targets use "casual".

## Ticks between the slower decisions (weapon, grenades, boosts).
const THINK_INTERVAL := 15
## Loot / crates are only fetched when no zombie is this close to them.
const SAFE_RADIUS := 70.0
## Distance from the arena edge where walls start pushing back.
const WALL_MARGIN := 90.0
## Ticks without getting closer to a target before giving up on it (a held
## drop the bot stands on, a crate a full bag refuses).
const STUCK_TICKS := 60

@export var heal_below: float = 0.45
## Fewest zombies inside a blast worth a grenade.
@export var grenade_cluster: int = 4
@export var skip_breaks: bool = true
## Zombies closer than this push the bot away.
@export var danger_radius: float = 130.0
## A movement decision is kept for this many ticks (reaction time).
@export var reaction_ticks: int = 1
## Random steering error, in radians either way.
@export var steer_noise: float = 0.0
## How far the bot detours for loot during a wave.
@export var combat_loot_reach: float = 140.0

## Waves, one Dictionary each (see _new_wave_record). A wave's record stays
## open through the break after it (crates, break loot, vacuumed coins) and
## closes when the next wave starts; the wave the bot died in has
## "died" = true.
var waves: Array[Dictionary] = []
var died := false
var peak_alive := 0
## Physics tick cost (ms) of the whole frame, sampled each tick.
var tick_ms_total := 0.0
var tick_ms_max := 0.0
var ticks := 0

var _run: Node
var _player: Player
var _zombies: ZombieManager
var _pickups: PickupManager
var _supplies: SupplyManager
var _director: WaveDirector
var _bag: Inventory
## Ammo items of the loadout's limited weapons (tracked for "ammo_min").
var _ammo_items: Array[ItemDef] = []
var _tick := 0
var _wave: Dictionary = {}
var _move := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _stuck := {}
var _target_key := ""
var _target_best_d := INF
var _target_progress_tick := 0
var _last_usec := 0


func _init() -> void:
	# After the zombies move (-10), before the player reads input (0).
	process_physics_priority = -5


## Applies a skill preset: "good" or "casual".
func configure(skill: String) -> void:
	match skill:
		"good":
			heal_below = 0.45
			grenade_cluster = 4
			danger_radius = 130.0
			reaction_ticks = 1
			steer_noise = 0.0
			combat_loot_reach = 140.0
		"casual":
			heal_below = 0.3
			grenade_cluster = 6
			danger_radius = 90.0
			reaction_ticks = 12
			steer_noise = 0.5
			combat_loot_reach = 60.0
		_:
			push_error("RunBot: unknown skill %s" % skill)


func attach(run: Node) -> void:
	_run = run
	_player = run.get_node("World/Player")
	_zombies = run.get_node("World/Zombies")
	_pickups = run.get_node("Pickups")
	_supplies = run.get_node("Supplies")
	_director = run.get_node("WaveDirector")
	_bag = run.state.inventory
	for weapon in _player.weapons.loadout():
		if weapon.ammo_item != null and not weapon.infinite_ammo and weapon.ammo_item not in _ammo_items:
			_ammo_items.append(weapon.ammo_item)
	_director.wave_started.connect(_on_wave_started)
	_director.wave_cleared.connect(_on_wave_cleared)
	_player.health.damaged.connect(_on_damaged)
	_player.health.healed.connect(func(amount: float) -> void: _add("healed", amount))
	_player.health.died.connect(_on_died)
	_player.weapons.fired.connect(_on_fired)
	_pickups.spawned.connect(func(def: ItemDef, count: int) -> void: _add_item("loot_dropped", def, count))
	_pickups.collected.connect(func(def: ItemDef, count: int, _at: Vector2) -> void: _add_item("loot_picked", def, count))
	_supplies.collected.connect(func(kind: SupplyManager.Kind, _at: Vector2) -> void:
		_add("crates_health" if kind == SupplyManager.Kind.HEALTH else "crates_ammo", 1))
	_last_usec = Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	ticks += 1
	tick_ms_total += ms
	tick_ms_max = maxf(tick_ms_max, ms) if ticks > 5 else tick_ms_max
	if _run == null or died:
		_steer(Vector2.ZERO)
		return
	_tick += 1
	peak_alive = maxi(peak_alive, _zombies.alive_count())
	if not _wave.is_empty():
		var health := _player.health
		_wave["min_hp_ratio"] = minf(_wave["min_hp_ratio"], health.hp / health.max_hp)
		var ammo_min: Dictionary = _wave["ammo_min"]
		for item in _ammo_items:
			var id := String(item.id)
			ammo_min[id] = mini(ammo_min.get(id, 1 << 30), _bag.count_of(item))
	_heal_if_low()
	if _tick % THINK_INTERVAL == 0:
		_pick_weapon()
		_use_boosts()
		_throw_at_cluster()
	if _tick % maxi(reaction_ticks, 1) == 0:
		_move = _decide_move()
		if steer_noise > 0.0 and _move != Vector2.ZERO:
			_move = _move.rotated(_rng.randf_range(-steer_noise, steer_noise))
	_steer(_move)
	if _director.phase == WaveDirector.Phase.BREAK and _director.wave >= 1 and skip_breaks:
		if _break_done():
			_director.skip_break()


## Summary for reports: wave reached, coins, kills, per-wave records (an
## unfinished last wave is included with "unfinished" = true).
func report() -> Dictionary:
	var all := waves.duplicate(true)
	if not _wave.is_empty():
		var open := _finish_record(_wave.duplicate(true))
		open["unfinished"] = true
		all.append(open)
	return {
		"wave_reached": _director.wave,
		"died": died,
		"kills": _run.state.kills,
		"coins": _run.state.coins,
		"waves": all,
		"peak_alive": peak_alive,
		"tick_ms_avg": tick_ms_total / maxf(ticks, 1),
		"tick_ms_max": tick_ms_max,
	}


# --- Movement -----------------------------------------------------------------

func _decide_move() -> Vector2:
	var p := _player.global_position
	var flee := Vector2.ZERO
	var nearest := INF
	# Never back off beyond what the current weapon can hit, or a lone zombie
	# trailing the bot would never die (shotgun range is 110 px).
	var radius := minf(danger_radius, _player.weapons.current_weapon().attack_range * 0.75)
	for i in _zombies.slot_count():
		if not _zombies.is_alive(i):
			continue
		var offset := p - _zombies.to_global(_zombies.get_zombie_position(i))
		var d := offset.length()
		nearest = minf(nearest, d)
		if d < radius and d > 0.01:
			var w := 1.0 - d / radius
			flee += offset / d * w * w * 4.0
	var bounds: Rect2 = _run.get_node("Arena").bounds
	var wall := Vector2.ZERO
	wall.x += maxf(WALL_MARGIN - (p.x - bounds.position.x), 0.0) / WALL_MARGIN
	wall.x -= maxf(WALL_MARGIN - (bounds.end.x - p.x), 0.0) / WALL_MARGIN
	wall.y += maxf(WALL_MARGIN - (p.y - bounds.position.y), 0.0) / WALL_MARGIN
	wall.y -= maxf(WALL_MARGIN - (bounds.end.y - p.y), 0.0) / WALL_MARGIN

	var goal := _goal(p, nearest)
	var move := Vector2.ZERO
	if flee.length() > 0.05:
		# Back away and circle (towards the centre) so the bot doesn't run
		# itself into a corner.
		var away := flee.normalized()
		var side := away.orthogonal()
		if side.dot(bounds.get_center() - p) < 0.0:
			side = -side
		move = away * 1.0 + side * 0.7 + wall * 2.5
		if goal != Vector2.INF and nearest > SAFE_RADIUS:
			move += (goal - p).normalized() * 0.6
	elif goal != Vector2.INF:
		# No zombie close: walls are no threat (the body collides with them)
		# and pushing back would stop the bot short of loot near an edge.
		move = goal - p
		if p.distance_to(goal) < 2.0:
			move = Vector2.ZERO
	else:
		# Nothing close: drift back towards the middle to keep room to kite.
		var to_center := bounds.get_center() - p
		move = to_center / 200.0 if to_center.length() > 120.0 else Vector2.ZERO
		move += wall
	return move.limit_length(1.0) if move.length() < 0.2 else move.normalized()


## Nearest crate or pickup worth fetching, or Vector2.INF.
func _goal(p: Vector2, nearest_zombie: float) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	var best_key := ""
	var combat := _director.phase == WaveDirector.Phase.COMBAT
	var reach := combat_loot_reach if combat else INF
	for i in _supplies.active_count():
		if not _supplies.is_crate_landed(i):
			continue
		var at := _supplies.get_crate_position(i)
		var key := "c%d,%d" % [roundi(at.x), roundi(at.y)]
		var d := p.distance_to(at)
		if d < best_d and d < reach and not _stuck.has(key) and _safe(at):
			best = at
			best_d = d
			best_key = key
	for i in _pickups.active_count():
		if not _pickups.is_pickup_landed(i):
			continue
		var def := _pickups.get_pickup_def(i)
		if _bag.space_for(def) <= 0:
			continue
		var at := _pickups.get_pickup_position(i)
		var key := "p%d,%d,%s" % [roundi(at.x), roundi(at.y), def.id]
		var d := p.distance_to(at)
		if d < best_d and d < reach and not _stuck.has(key) and _safe(at):
			best = at
			best_d = d
			best_key = key
	if combat and nearest_zombie < SAFE_RADIUS:
		return Vector2.INF
	if best_key == "":
		_target_key = ""
		return best
	# Give up on a target the bot stops getting closer to without collecting
	# it (held drop, crate refused by a full bag).
	if best_key != _target_key:
		_target_key = best_key
		_target_best_d = best_d
		_target_progress_tick = _tick
	elif best_d < _target_best_d - 0.5:
		_target_best_d = best_d
		_target_progress_tick = _tick
	elif _tick - _target_progress_tick > STUCK_TICKS:
		_stuck[best_key] = true
		return Vector2.INF
	return best


func _safe(at: Vector2) -> bool:
	var n := _zombies.find_nearest(_zombies.to_local(at), SAFE_RADIUS)
	return n == -1


func _break_done() -> bool:
	for i in _supplies.active_count():
		if not _supplies.is_crate_landed(i):
			return false
	return _goal(_player.global_position, INF) == Vector2.INF


func _steer(move: Vector2) -> void:
	_set_action(&"move_right", maxf(move.x, 0.0))
	_set_action(&"move_left", maxf(-move.x, 0.0))
	_set_action(&"move_down", maxf(move.y, 0.0))
	_set_action(&"move_up", maxf(-move.y, 0.0))


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


# --- Items and weapons ---------------------------------------------------------

func _heal_if_low() -> void:
	var health := _player.health
	if health.hp / health.max_hp >= heal_below:
		return
	var slot := _bag.smallest_slot_where(func(def: ItemDef) -> bool: return def.kind == ItemDef.Kind.MEDKIT)
	if slot != -1 and _run.use_item(slot):
		_add("medkits_used", 1)


func _use_boosts() -> void:
	var slot := _bag.smallest_slot_where(func(def: ItemDef) -> bool:
		return def.kind == ItemDef.Kind.DAMAGE_BOOST or def.kind == ItemDef.Kind.MAX_HP_BOOST)
	if slot != -1 and _run.use_item(slot):
		_add("boosts_used", 1)


## Prefers any weapon with ammo over the infinite pistol (the best DPS first).
func _pick_weapon() -> void:
	var weapons := _player.weapons
	var best := -1
	var best_dps := -1.0
	for i in weapons.weapon_count():
		var def: WeaponDef = weapons.loadout()[i]
		if not def.infinite_ammo and weapons.magazine_count(i) + weapons.reserve_count(i) <= 0:
			continue
		var dps := def.damage * def.projectiles_per_shot / def.fire_interval
		if dps > best_dps:
			best_dps = dps
			best = i
	if best != -1 and weapons.current_weapon() != weapons.loadout()[best]:
		weapons.switch_to(best)


func _throw_at_cluster() -> void:
	var slot := _bag.smallest_slot_where(func(def: ItemDef) -> bool: return def.kind == ItemDef.Kind.GRENADE)
	if slot == -1:
		return
	var grenade := _bag.get_def(slot)
	var p := _player.global_position
	var near: Array[Vector2] = []
	for i in _zombies.slot_count():
		if _zombies.is_alive(i):
			var at := _zombies.to_global(_zombies.get_zombie_position(i))
			if at.distance_to(p) <= grenade.throw_range:
				near.append(at)
	var best_count := 0
	var best_at := Vector2.ZERO
	var radius_sq := grenade.radius * grenade.radius
	for a in near.slice(0, 48):
		var count := 0
		for b in near:
			if a.distance_squared_to(b) <= radius_sq:
				count += 1
		if count > best_count:
			best_count = count
			best_at = a
	if best_count >= grenade_cluster and _run.throw_grenade(best_at):
		_add("grenades_thrown", 1)


# --- Records -------------------------------------------------------------------

func _on_wave_started(wave: int, zombie_count: int) -> void:
	if not _wave.is_empty():
		waves.append(_finish_record(_wave))
	_stuck.clear()
	_wave = _new_wave_record(wave, zombie_count)


func _on_wave_cleared(_wave_number: int) -> void:
	if not _wave.is_empty():
		_wave["combat_seconds"] = (_tick - _wave["start_tick"]) / float(Engine.physics_ticks_per_second)
		_wave["cleared"] = true


func _on_damaged(amount: float) -> void:
	_add("damage_taken", amount)
	# The run empties the bag on death before the bot hears about it, so take
	# the death-wave snapshot now (damaged is emitted before died).
	if _player.health.hp <= 0.0 and not _wave.is_empty():
		_wave["min_hp_ratio"] = 0.0
		_wave["bag_at_death"] = _bag_counts()


func _on_died() -> void:
	died = true
	_steer(Vector2.ZERO)
	if not _wave.is_empty():
		_wave["died"] = true
		waves.append(_finish_record(_wave))
		_wave = {}


## Fills in the totals of an open record; the record is returned for chaining.
func _finish_record(record: Dictionary) -> Dictionary:
	if not record.has("combat_seconds"):
		record["combat_seconds"] = (_tick - record["start_tick"]) / float(Engine.physics_ticks_per_second)
	record["kills"] = _run.state.kills - record["kills_before"]
	record["coins"] = _run.state.coins - record["coins_before"]
	record["hp_end"] = _player.health.hp
	record["bag_end"] = record.get("bag_at_death", _bag_counts())
	record.erase("bag_at_death")
	for key in ["start_tick", "kills_before", "coins_before"]:
		record.erase(key)
	return record


func _new_wave_record(wave: int, zombie_count: int) -> Dictionary:
	return {
		"wave": wave, "zombies": zombie_count, "start_tick": _tick, "cleared": false, "died": false,
		"kills_before": _run.state.kills, "coins_before": _run.state.coins,
		"hp_start": _player.health.hp, "max_hp": _player.health.max_hp, "min_hp_ratio": 1.0,
		"damage_taken": 0.0, "healed": 0.0, "medkits_used": 0, "boosts_used": 0,
		"grenades_thrown": 0, "crates_health": 0, "crates_ammo": 0,
		"shots": {}, "loot_dropped": {}, "loot_picked": {}, "ammo_min": {}, "bag_start": _bag_counts(),
	}


func _bag_counts() -> Dictionary:
	var counts := {}
	for i in _bag.capacity:
		var def := _bag.get_def(i)
		if def != null:
			counts[String(def.id)] = counts.get(String(def.id), 0) + _bag.get_count(i)
	return counts


func _on_fired(_direction: Vector2) -> void:
	if _wave.is_empty():
		return
	var id := String(_player.weapons.current_weapon().id)
	_wave["shots"][id] = _wave["shots"].get(id, 0) + 1


## The open wave record (it stays open through the following break), or an
## empty Dictionary before wave 1 and after death.
func _record() -> Dictionary:
	return _wave


func _add(key: String, amount: float) -> void:
	var record := _record()
	if not record.is_empty():
		record[key] = record.get(key, 0) + amount


func _add_item(key: String, def: ItemDef, count: int) -> void:
	var record := _record()
	if not record.is_empty():
		var bucket: Dictionary = record[key]
		bucket[String(def.id)] = bucket.get(String(def.id), 0) + count
