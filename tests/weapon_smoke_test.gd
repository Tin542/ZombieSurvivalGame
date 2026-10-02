extends SceneTree
## Headless end-to-end check of auto-aim, weapons and projectiles.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/weapon_smoke_test.gd
## Exits with code 1 if any check fails.

const RUN_SCENE := "res://scenes/run/run.tscn"

var _failures := 0


func _initialize() -> void:
	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	await process_frame

	var zombies: ZombieManager = run.get_node("World/Zombies")
	var projectiles: ProjectileManager = run.get_node("Projectiles")
	var player: Player = run.get_node("World/Player")
	var spawner: ZombieSpawner = run.get_node("Spawner")
	var weapons := player.weapons
	player.health.set_max_hp(1e9)
	run.get_node("WaveDirector").stop()
	zombies.clear()

	var shots := [0]
	weapons.fired.connect(func(_dir: Vector2) -> void: shots[0] += 1)
	var reloads := [0]
	weapons.reload_started.connect(func(_t: float) -> void: reloads[0] += 1)

	_check(weapons.weapon_count() == 3, "debug loadout has all 3 weapons")
	_check(weapons.current_weapon().id == &"pistol", "starts on pistol")

	# --- Pistol vs a small wave -------------------------------------------
	var walker: ZombieDef = load("res://data/zombies/walker.tres")
	spawner.spawn_burst(30, 1)
	await _frames(60 * 25)
	print("pistol: shots=%d kills=%d reloads=%d alive=%d" % [shots[0], run.state.kills, reloads[0], zombies.alive_count()])
	_check(shots[0] > 0, "pistol fired")
	_check(run.state.kills > 0, "pistol killed zombies")
	_check(reloads[0] > 0, "pistol reloaded")
	_check(weapons._slots[0].reserve == 0 and weapons._slots[0].def.infinite_ammo, "pistol ammo stays infinite")

	# --- SMG consumes reserve ---------------------------------------------
	zombies.clear()
	weapons.switch_to(1)
	var smg_slot = weapons._slots[1]
	var reserve_before: int = smg_slot.reserve
	spawner.spawn_burst(30, 1)
	await _frames(60 * 20)
	print("smg: reserve %d -> %d, mag=%d, kills=%d" % [reserve_before, smg_slot.reserve, smg_slot.magazine, run.state.kills])
	_check(smg_slot.reserve < reserve_before, "smg spent reserve ammo")

	# --- Dry weapon falls back --------------------------------------------
	smg_slot.reserve = 0
	smg_slot.magazine = 0
	weapons.switch_to(0)
	weapons.switch_to(1)
	await _frames(2)
	_check(weapons.current_weapon().id != &"smg", "dry smg falls back to another weapon")
	weapons.cycle_weapon()
	_check(weapons.current_weapon().id != &"smg", "cycle skips dry smg")

	# --- Ammo refill (supply crate hook) ----------------------------------
	weapons.add_ammo(0.5)
	_check(smg_slot.reserve == ceili(smg_slot.def.max_reserve_ammo * 0.5), "add_ammo refills reserve")

	# --- Projectile throughput --------------------------------------------
	zombies.clear()
	var bounds: Rect2 = run.get_node("Arena").bounds
	var place_rng := RandomNumberGenerator.new()
	for i in 400:
		var at := Vector2(place_rng.randf_range(bounds.position.x, bounds.end.x), place_rng.randf_range(bounds.position.y, bounds.end.y))
		zombies.spawn_at(walker, at, 1000.0)
	await _frames(5)
	projectiles.set_physics_process(false)
	var rng := RandomNumberGenerator.new()
	var origin := player.global_position
	var elapsed := 0
	for tick in 300:
		while projectiles.active_count() < 300:
			var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
			projectiles.spawn(origin, dir * 320.0, 1.0, 0, 2.0, 0.0)
		var start := Time.get_ticks_usec()
		projectiles._physics_process(1.0 / 60.0)
		elapsed += Time.get_ticks_usec() - start
	print("avg ProjectileManager tick (300 bullets, 400 zombies): %.3f ms" % (elapsed / 1000.0 / 300))

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
