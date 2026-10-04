extends SceneTree
## Headless checks for the supply phase: crates only after a cleared wave,
## placement, landing before pickup, health/ammo effects, crate planning,
## cleanup when the next wave starts, no pickup after death.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/supply_test.gd
## Exits with code 1 if any check fails. The real save is restored afterwards.

const RUN_SCENE := "res://scenes/run/run.tscn"
const PISTOL := preload("res://data/weapons/pistol.tres")
const SMG := preload("res://data/weapons/smg.tres")
const HEALTH := SupplyManager.Kind.HEALTH
const AMMO := SupplyManager.Kind.AMMO

var _failures := 0


func _initialize() -> void:
	await process_frame  # let SaveService load
	var save_service: Node = root.get_node("SaveService")
	var backup: Dictionary = save_service.data.to_dict()

	var run: Node = load(RUN_SCENE).instantiate()
	# Shrink the curve in memory (never saved) so the test runs quickly.
	var table: WaveTable = run.wave_table
	table.base_count = 1
	table.count_per_wave = 0
	table.base_spawn_interval = 0.1
	table.supply_duration = 6.0
	root.add_child(run)
	var player: Player = run.get_node("World/Player")
	var zombies: ZombieManager = run.get_node("World/Zombies")
	var director: WaveDirector = run.get_node("WaveDirector")
	var supplies: SupplyManager = run.get_node("Supplies")
	var bounds: Rect2 = run.get_node("Arena").bounds
	var hud: Hud = run.get_node("HUD")
	await process_frame
	player.weapons.set_physics_process(false)
	zombies.target = null  # zombies stand still; the test kills them

	var collected: Array = []
	supplies.collected.connect(func(kind, _pos) -> void: collected.append(kind))

	# --- No crates during the countdown before wave 1 ----------------------
	await _frames(60)
	_check(director.phase == WaveDirector.Phase.BREAK and supplies.active_count() == 0, "no crates before wave 1")

	# --- Clearing a wave drops crates ---------------------------------------
	await _wait_for(func() -> bool: return director.wave == 1 and zombies.alive_count() == 1, 300)
	zombies.damage(0, 1e9)
	await _frames(2)
	_check(director.phase == WaveDirector.Phase.BREAK, "wave 1 cleared -> break")
	_check(supplies.active_count() == table.supply_crates, "break drops %d crates" % table.supply_crates)
	_check(hud.get_node("%Toast").visible, "HUD announces the drop")

	var home := player.global_position
	var placement_ok := true
	for i in supplies.active_count():
		var p := supplies.get_crate_position(i)
		var d := p.distance_to(home)
		if not bounds.has_point(p) or d < supplies.min_drop_distance - 0.01 or d > supplies.max_drop_distance + 0.01:
			placement_ok = false
		for j in i:
			if p.distance_to(supplies.get_crate_position(j)) < supplies.min_spacing:
				placement_ok = false
	_check(placement_ok, "crates inside arena, in the drop ring, spaced apart")

	var kinds := []
	for i in supplies.active_count():
		kinds.append(supplies.get_crate_kind(i))
	_check(HEALTH in kinds and AMMO in kinds, "at least one health and one ammo crate")

	# --- Falling crates can't be grabbed -----------------------------------
	var target_index := supplies.active_count() - 1  # dropped last, still in the air
	player.global_position = supplies.get_crate_position(target_index)
	await _frames(1)
	_check(not supplies.is_crate_landed(target_index) and collected.is_empty(), "crate in the air is not collected")
	await _frames(60)
	_check(collected.size() == 1 and supplies.active_count() == table.supply_crates - 1, "landed crate collected on contact")
	player.global_position = home
	await _frames(1)

	# --- Health crate heals the configured fraction --------------------------
	player.health.set_max_hp(100.0)
	player.health.take_damage(60.0)
	collected.clear()
	_walk_to_kind(supplies, player, HEALTH)
	await _frames(2)
	if collected == [HEALTH]:
		_check(is_equal_approx(player.health.hp, 40.0 + 100.0 * table.supply_heal_fraction), "health crate heals %d%% (hp=%.0f)" % [table.supply_heal_fraction * 100, player.health.hp])
		_check(hud.get_node("%Toast").text == "+35 HP", "HUD shows +35 HP")
	else:
		_check(false, "health crate available to test healing")

	# --- Ammo crate refills limited weapons ----------------------------------
	var smg_slot = player.weapons._slots[1]
	smg_slot.reserve = 0
	collected.clear()
	if _walk_to_kind(supplies, player, AMMO):
		await _frames(2)
		_check(smg_slot.reserve == ceili(SMG.max_reserve_ammo * table.supply_ammo_fraction), "ammo crate refills reserve (%d)" % smg_slot.reserve)
	else:
		# The test already used up the only ammo crate above; drop one to test.
		var one_ammo: Array[SupplyManager.Kind] = [AMMO]
		supplies.drop_crates(one_ammo, 5.0)
		await _frames(40)
		_walk_to_kind(supplies, player, AMMO)
		await _frames(2)
		_check(smg_slot.reserve == ceili(SMG.max_reserve_ammo * table.supply_ammo_fraction), "ammo crate refills reserve (%d)" % smg_slot.reserve)

	# --- Next wave removes leftovers ----------------------------------------
	var leftovers: Array[SupplyManager.Kind] = [HEALTH, HEALTH]
	supplies.drop_crates(leftovers, 5.0)
	director.skip_break()
	await _frames(2)
	_check(director.phase == WaveDirector.Phase.COMBAT and supplies.active_count() == 0, "next wave clears uncollected crates")

	# --- Crate planning -------------------------------------------------------
	var weapons := player.weapons
	player.health.set_max_hp(100.0)
	player.health.take_damage(80.0)  # hp 20%, ammo still mostly full
	_check(run._plan_crates(4) == [HEALTH, AMMO, HEALTH, HEALTH], "low HP: extras are health")
	player.health.set_max_hp(100.0)
	for slot in weapons._slots:
		slot.reserve = 0
		slot.magazine = 0
	_check(run._plan_crates(4) == [HEALTH, AMMO, AMMO, AMMO], "low ammo: extras are ammo")
	var pistol_only: Array[WeaponDef] = [PISTOL]
	weapons.set_loadout(pistol_only)
	_check(run._plan_crates(3) == [HEALTH, HEALTH, HEALTH], "pistol-only loadout: all health")
	_check(weapons.ammo_fill_ratio() == 1.0 and not weapons.has_limited_ammo(), "infinite-only loadout reports full ammo")

	# --- Drawing with off-screen crates ---------------------------------------
	var far: Array[SupplyManager.Kind] = [HEALTH, AMMO]
	supplies.max_drop_distance = 400.0
	supplies.min_drop_distance = 380.0
	supplies.drop_crates(far, 5.0)
	for k in 30:
		await process_frame
	_check(supplies.active_count() == 2, "off-screen crates draw arrows without errors")

	# --- No pickup after death ------------------------------------------------
	player.global_position = supplies.get_crate_position(0)
	player.health.take_damage(1e9)
	await _frames(60)
	_check(supplies.active_count() == 2 and collected.size() <= 2, "no crate pickup after death")

	save_service.data = SaveData.from_dict(backup)
	save_service.save()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


## Teleports the player onto the first landed crate of `kind`. False if none.
func _walk_to_kind(supplies: SupplyManager, player: Player, kind: SupplyManager.Kind) -> bool:
	for i in supplies.active_count():
		if supplies.get_crate_kind(i) == kind and supplies.is_crate_landed(i):
			player.global_position = supplies.get_crate_position(i)
			return true
	return false


func _wait_for(condition: Callable, max_frames: int) -> void:
	for i in max_frames:
		if condition.call():
			return
		await physics_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
