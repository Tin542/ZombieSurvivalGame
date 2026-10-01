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
	var player: Player = run.get_node("World/Player")
	player.health.set_max_hp(1e9)
	var pool: Array[ZombieDef] = run.debug_zombie_pool
	for i in SPAWN_COUNT:
		zombies.spawn(pool[i % pool.size()])

	for i in WARMUP_FRAMES:
		await physics_frame
	print("alive=%d queued=%d" % [zombies.alive_count(), zombies.queued_count()])

	# Drive the manager's tick manually so only its own cost is timed.
	zombies.set_physics_process(false)
	var dt := 1.0 / 60.0
	var start := Time.get_ticks_usec()
	for i in MEASURE_FRAMES:
		zombies._physics_process(dt)
	var avg_ms := (Time.get_ticks_usec() - start) / 1000.0 / MEASURE_FRAMES
	print("avg ZombieManager tick: %.3f ms over %d ticks" % [avg_ms, MEASURE_FRAMES])

	# Sanity: kill everything and check compaction drains the queue.
	for i in range(zombies.alive_count() - 1, -1, -1):
		zombies.damage(i, 1e9)
	zombies._physics_process(dt)
	print("after mass kill: alive=%d queued=%d" % [zombies.alive_count(), zombies.queued_count()])
	quit()
