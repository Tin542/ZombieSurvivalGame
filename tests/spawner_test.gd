extends SceneTree
## Headless checks for ZombieSpawner: placement, capacity, pacing, wave mix.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/spawner_test.gd
## Exits with code 1 if any check fails.

const RUN_SCENE := "res://scenes/run/run.tscn"

var _failures := 0


func _initialize() -> void:
	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	await process_frame

	var zombies: ZombieManager = run.get_node("World/Zombies")
	var spawner: ZombieSpawner = run.get_node("Spawner")
	var player: Player = run.get_node("World/Player")
	var bounds: Rect2 = run.get_node("Arena").bounds
	var table: WaveTable = run.wave_table
	player.health.set_max_hp(1e9)
	player.weapons.set_physics_process(false)  # keep zombies alive for counting
	# Drive the spawner by hand; the wave loop is covered by wave_director_test.
	run.get_node("WaveDirector").stop()
	zombies.clear()

	# --- Placement: off-screen, inside arena ------------------------------
	var view_half := root.get_visible_rect().size * 0.5
	print("view size: %s" % (view_half * 2.0))
	_check_placement(spawner, player, bounds, view_half, bounds.get_center(), "centre")
	_check_placement(spawner, player, bounds, view_half, bounds.position + Vector2(20, 20), "top-left corner")
	_check_placement(spawner, player, bounds, view_half, bounds.end - Vector2(20, 20), "bottom-right corner")
	player.global_position = bounds.get_center()
	await _frames(2)

	# --- Capacity + per-tick throttle -------------------------------------
	spawner.spawn_burst(600, 1)
	await _frames(1)
	_check(zombies.alive_count() <= spawner.max_per_tick, "burst respects max_per_tick (%d after 1 tick)" % zombies.alive_count())
	await _frames(120)
	print("burst 600: alive=%d pending=%d" % [zombies.alive_count(), spawner.pending_count()])
	_check(zombies.alive_count() == zombies.max_alive, "fills up to max_alive")
	_check(spawner.pending_count() == 600 - zombies.max_alive, "overflow waits instead of being dropped")
	for i in range(zombies.alive_count() - 1, -1, -1):
		zombies.damage(i, 1e9)
	await _frames(60)
	print("after killing all: alive=%d pending=%d" % [zombies.alive_count(), spawner.pending_count()])
	_check(zombies.alive_count() == 200 and spawner.pending_count() == 0, "held-back zombies spawn once room frees up")
	spawner.stop()
	zombies.clear()

	# --- Batch pacing -----------------------------------------------------
	var spawned := [0]
	var finished := [0]
	spawner.zombie_spawned.connect(func(_def: ZombieDef) -> void: spawned[0] += 1)
	spawner.batch_finished.connect(func() -> void: finished[0] += 1)
	spawner.start_batch(10, 0.5, 1)
	# Spawns land at t = 0, 0.5, 1.0 ...; sample between beats to avoid float edges.
	await _frames(60 * 3 + 6)
	_check(spawned[0] == 7 and finished[0] == 0, "batch paced at interval (7 after 3.1s, got %d)" % spawned[0])
	await _frames(60 * 2)
	_check(spawned[0] == 10 and finished[0] == 1, "batch finishes once with all 10 spawned")
	_check(not spawner.is_batch_active(), "batch inactive after finishing")

	# --- Wave mix + scaling -----------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	_check(_types_for_wave(table, 1, rng) == [&"walker"], "wave 1 is walkers only")
	_check(_types_for_wave(table, 3, rng) == [&"runner", &"walker"], "wave 3 adds runners")
	_check(_types_for_wave(table, 5, rng) == [&"brute", &"runner", &"walker"], "wave 5 adds brutes")
	for wave in [1, 5, 10, 20]:
		print("wave %2d: count=%d interval=%.2fs hp x%.2f speed x%.2f" % [
			wave, table.zombie_count(wave), table.spawn_interval(wave),
			table.hp_multiplier(wave), table.speed_multiplier(wave)])

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_placement(spawner: ZombieSpawner, player: Player, bounds: Rect2, view_half: Vector2, player_pos: Vector2, label: String) -> void:
	player.global_position = player_pos
	player.camera.reset_smoothing()
	player.camera.force_update_scroll()
	var center := player.camera.get_screen_center_position()
	var view := Rect2(center - view_half, view_half * 2.0)
	var visible := 0
	var outside := 0
	for i in 20000:
		var p := spawner.pick_spawn_point()
		if view.has_point(p):
			visible += 1
		if not bounds.has_point(p):
			outside += 1
	_check(visible == 0 and outside == 0, "placement from %s: 0 on-screen, 0 outside arena (got %d, %d)" % [label, visible, outside])


func _types_for_wave(table: WaveTable, wave: int, rng: RandomNumberGenerator) -> Array:
	var ids := {}
	for i in 500:
		ids[table.pick_zombie(wave, rng).id] = true
	var sorted := ids.keys()
	sorted.sort()
	return sorted


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
