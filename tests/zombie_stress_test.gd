extends SceneTree
## Headless benchmark for ZombieManager simulation cost (no rendering).
## Run: godot --headless --path . -s res://tests/zombie_stress_test.gd

const RUN_SCENE := "res://scenes/run/run.tscn"
const SPAWN_COUNT := 500
const WARMUP_FRAMES := 30
const MEASURE_FRAMES := 300


func _initialize() -> void:
	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	await process_frame

	var zombies: ZombieManager = run.get_node("World/Zombies")
	var spawner: ZombieSpawner = run.get_node("Spawner")
	var player: Player = run.get_node("World/Player")
	var bounds: Rect2 = run.get_node("Arena").bounds
	run.get_node("WaveDirector").stop()
	zombies.clear()
	player.health.set_max_hp(1e9)

	var defs: Array[ZombieDef] = [
		load("res://data/zombies/walker.tres"),
		load("res://data/zombies/runner.tres"),
		load("res://data/zombies/brute.tres"),
	]
	var rng := RandomNumberGenerator.new()
	var accepted := 0
	for i in SPAWN_COUNT:
		var at := Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.y, bounds.end.y))
		if zombies.spawn_at(defs[i % defs.size()], at):
			accepted += 1
	print("requested=%d accepted=%d (cap %d)" % [SPAWN_COUNT, accepted, zombies.max_alive])

	for i in WARMUP_FRAMES:
		await physics_frame

	# Drive the manager's tick manually so only its own cost is timed.
	zombies.set_physics_process(false)
	var dt := 1.0 / 60.0
	var start := Time.get_ticks_usec()
	for i in MEASURE_FRAMES:
		zombies._physics_process(dt)
	var avg_ms := (Time.get_ticks_usec() - start) / 1000.0 / MEASURE_FRAMES
	print("avg ZombieManager tick (%d zombies): %.3f ms over %d ticks" % [zombies.alive_count(), avg_ms, MEASURE_FRAMES])

	for i in range(zombies.alive_count() - 1, -1, -1):
		zombies.damage(i, 1e9)
	zombies._physics_process(dt)
	print("after mass kill: alive=%d full=%s" % [zombies.alive_count(), zombies.is_full()])
	quit()
