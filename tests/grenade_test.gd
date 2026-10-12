extends SceneTree
## Headless checks for grenades: blast falloff through the zombie grid, no
## self-damage, Firepower / Rage multiplier, fuse timing, aim stick (drag,
## release, tap, cancel, touch index tracking), throw range clamp, reticle,
## bag pause and death cancelling the aim.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/grenade_test.gd
## Exits with code 1 if any check fails. The real save is restored afterwards.

const RUN_SCENE := "res://scenes/run/run.tscn"
const WALKER := preload("res://data/zombies/walker.tres")
const GRENADE := preload("res://data/items/grenade.tres")

var _failures := 0


func _initialize() -> void:
	await process_frame  # let SaveService load
	var save_service: Node = root.get_node("SaveService")
	var backup: Dictionary = save_service.data.to_dict()

	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	await process_frame
	run.get_node("WaveDirector").stop()
	var zombies: ZombieManager = run.get_node("World/Zombies")
	var grenades: GrenadeManager = run.get_node("Grenades")
	var player: Player = run.get_node("World/Player")
	var hud: Hud = run.get_node("HUD")
	var button: AimButton = hud.get_node("%GrenadeButton")
	var toast: Label = hud.get_node("%Toast")
	var inventory: Inventory = run.state.inventory
	zombies.clear()
	zombies.target = null  # zombies stand still
	player.weapons.set_physics_process(false)
	player.health.set_max_hp(100.0)
	var home := player.global_position
	inventory.clear()
	var dmg := GRENADE.damage
	var radius := GRENADE.radius

	_check(grenades.process_physics_priority == 12, "grenades tick after projectiles")

	# --- Blast falloff via the grid ---------------------------------------------------
	var spot := home + Vector2(0, -80)
	var center_tough := _zombie(dmg * 1.1)  # survives a full hit
	var center_soft := _zombie(dmg * 0.9)  # dies to a full hit
	var edge_tough := _zombie(dmg * 0.6)  # survives half damage
	var edge_soft := _zombie(dmg * 0.45)  # dies to half damage
	var outside := _zombie(0.01)  # dies to anything
	zombies.spawn_at(center_tough, spot)
	zombies.spawn_at(center_soft, spot + Vector2(0.5, 0))
	zombies.spawn_at(edge_tough, spot + Vector2(radius + WALKER.radius - 0.5, 0))
	zombies.spawn_at(edge_soft, spot + Vector2(0, radius + WALKER.radius - 0.5))
	zombies.spawn_at(outside, spot + Vector2(-(radius + WALKER.radius + 3.0), 0))
	await _frames(2)  # physics_frame fires before the zombie tick rebuilds the grid
	var kills_before: int = run.state.kills
	var killed := zombies.blast(spot, radius, dmg)
	_check(killed == 2, "blast kills the soft centre and soft edge zombies (%d)" % killed)
	_check(zombies.alive_count() == 3, "tough ones and the one outside survive")
	_check(run.state.kills == kills_before + 2, "blast kills count as kills")
	zombies.clear()

	# --- Throw: fuse, no self-damage, multiplier ---------------------------------------
	inventory.add(GRENADE, 3)
	var near := home + Vector2(30, 0)
	zombies.spawn_at(_zombie(dmg * 0.9), near)
	await _frames(1)
	var hp_before := player.health.hp
	_check(run.throw_grenade(near), "throw_grenade throws")
	_check(inventory.count_of(GRENADE) == 2 and grenades.active_count() == 1, "one grenade taken from the bag, one in the air")
	await _frames(int(GRENADE.fuse * 60.0) - 6)
	_check(zombies.alive_count() == 1 and grenades.active_count() == 1, "nothing explodes before the fuse")
	await _frames(10)
	_check(grenades.active_count() == 0 and zombies.alive_count() == 0, "explodes on landing after the fuse")
	_check(is_equal_approx(player.health.hp, hp_before), "player standing in the blast takes no damage")

	zombies.clear()
	player.weapons.damage_multiplier = 2.0
	zombies.spawn_at(_zombie(dmg * 1.5), near)
	await _frames(1)
	run.throw_grenade(near)
	await _frames(int(GRENADE.fuse * 60.0) + 4)
	_check(zombies.alive_count() == 0, "weapon damage multiplier (Firepower / Rage) applies to grenades")
	player.weapons.damage_multiplier = 1.0
	zombies.clear()

	# --- Range clamp -----------------------------------------------------------------------
	run.throw_grenade(home + Vector2(1000, 0))
	_check(grenades.get_landing_point(0).distance_to(home) <= GRENADE.throw_range + 0.01, "throw is pulled in to throw_range")
	grenades.clear()
	inventory.clear()

	# --- Aim stick: drag + release -------------------------------------------------------------
	inventory.add(GRENADE, 3)
	_check(not button.disabled and button.text == "GREN 3", "grenade button enabled with grenades")
	button.begin_aim(Vector2(20, 15))
	_check(button.aiming and grenades.is_aiming(), "pressing starts aiming and shows the reticle")
	button.drag_to(Vector2(20, 15) + Vector2(button.max_drag * 0.5, 0))
	button.release_aim()
	_check(not grenades.is_aiming(), "reticle hidden after release")
	_check(inventory.count_of(GRENADE) == 2 and grenades.active_count() == 1, "release throws one grenade")
	var landing := grenades.get_landing_point(0)
	var expected := home + Vector2(GRENADE.throw_range * 0.5, 0)
	_check(landing.distance_to(expected) < 0.5, "lands at half range for a half drag (%s)" % landing)
	grenades.clear()

	button.begin_aim(Vector2.ZERO)
	button.drag_to(Vector2(0, -button.max_drag * 3.0))
	button.release_aim()
	_check(grenades.get_landing_point(0).distance_to(home + Vector2(0, -GRENADE.throw_range)) < 0.5, "over-drag aims at full range")
	grenades.clear()

	# --- Drag out and back cancels ----------------------------------------------------------------
	button.begin_aim(Vector2.ZERO)
	button.drag_to(Vector2(button.max_drag, 0))
	button.drag_to(Vector2(1, 0))
	button.release_aim()
	_check(inventory.count_of(GRENADE) == 1 and grenades.active_count() == 0 and not grenades.is_aiming(), "drag back to centre cancels")

	# --- Tap throws at the nearest zombie in range ---------------------------------------------
	button.begin_aim(Vector2.ZERO)
	button.release_aim()
	_check(inventory.count_of(GRENADE) == 1 and toast.text == "NO TARGET", "tap with no zombie in range: NO TARGET, nothing used")
	var target := home + Vector2(-50, 20)
	zombies.spawn_at(_zombie(1.0), target)
	zombies.spawn_at(_zombie(1.0), home + Vector2(GRENADE.throw_range + 40, 0))
	await _frames(1)
	button.begin_aim(Vector2.ZERO)
	button.release_aim()
	_check(inventory.count_of(GRENADE) == 0 and grenades.get_landing_point(0).distance_to(target) < 0.5, "tap throws at the nearest zombie")
	_check(button.disabled and button.text == "GREN 0", "button greys out when the last grenade is gone")
	button.begin_aim(Vector2.ZERO)
	_check(not button.aiming, "disabled button doesn't aim")
	grenades.clear()
	zombies.clear()

	# --- Touch input: tracks its own finger ---------------------------------------------------
	inventory.add(GRENADE, 2)
	button._gui_input(_touch(3, Vector2(10, 10), true))
	button._gui_input(_drag(5, Vector2(200, 10)))  # another finger (joystick) moving
	button._gui_input(_drag(3, Vector2(10, 10 + button.max_drag)))
	button._gui_input(_touch(5, Vector2(200, 10), false))  # other finger lifts
	_check(button.aiming and grenades.active_count() == 0, "other fingers don't release the aim")
	button._gui_input(_touch(3, Vector2(10, 10 + button.max_drag), false))
	_check(grenades.active_count() == 1 and grenades.get_landing_point(0).distance_to(home + Vector2(0, GRENADE.throw_range)) < 0.5, "own finger lifting throws where it was dragged")
	grenades.clear()

	# --- Opening the bag cancels the aim ------------------------------------------------------
	button.begin_aim(Vector2.ZERO)
	button.drag_to(Vector2(button.max_drag, 0))
	run.open_bag()
	_check(not button.aiming and not grenades.is_aiming(), "opening the bag cancels the aim")
	hud.bag_panel.close()
	await process_frame
	paused = false
	_check(inventory.count_of(GRENADE) == 1, "cancelled aim used nothing")

	# --- Death -------------------------------------------------------------------------------
	button.begin_aim(Vector2.ZERO)
	button.drag_to(Vector2(button.max_drag, 0))
	run.throw_grenade(home + Vector2(40, 0))
	player.health.take_damage(1e9)
	_check(not grenades.is_aiming() and grenades.active_count() == 0, "death cancels the aim and grenades in the air")
	_check(not run.throw_grenade(home + Vector2(40, 0)), "no throwing after death")

	save_service.data = SaveData.from_dict(backup)
	save_service.save()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _zombie(hp: float) -> ZombieDef:
	var def: ZombieDef = WALKER.duplicate()
	def.max_hp = hp
	def.loot = []
	def.coin_value = 0
	return def


func _touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func _drag(index: int, position: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	return event


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
