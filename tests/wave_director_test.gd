extends SceneTree
## Headless checks for the wave loop: countdown -> combat -> cleared -> break.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/wave_director_test.gd
## Exits with code 1 if any check fails.

const RUN_SCENE := "res://scenes/run/run.tscn"

var _failures := 0
var _started: Array[Vector2i] = []  # (wave, zombie_count)
var _cleared: Array[int] = []
var _breaks: Array[Vector2] = []  # (next_wave, duration)
var _remaining := -1


func _initialize() -> void:
	var run: Node = load(RUN_SCENE).instantiate()
	# Shrink the curve in memory (never saved) so the test runs quickly.
	var table: WaveTable = run.wave_table
	table.base_count = 4
	table.count_per_wave = 2
	table.base_spawn_interval = 0.1
	table.supply_duration = 2.0
	root.add_child(run)

	var director: WaveDirector = run.get_node("WaveDirector")
	var spawner: ZombieSpawner = run.get_node("Spawner")
	var zombies: ZombieManager = run.get_node("World/Zombies")
	var player: Player = run.get_node("World/Player")
	var hud: Hud = run.get_node("HUD")
	director.wave_started.connect(func(w: int, c: int) -> void: _started.append(Vector2i(w, c)))
	director.wave_cleared.connect(func(w: int) -> void: _cleared.append(w))
	director.break_started.connect(func(n: int, d: float) -> void: _breaks.append(Vector2(n, d)))
	director.remaining_changed.connect(func(r: int) -> void: _remaining = r)
	await process_frame
	player.health.set_max_hp(1e9)
	player.weapons.set_physics_process(false)  # the test decides who dies

	# --- Countdown before wave 1 ------------------------------------------
	_check(director.phase == WaveDirector.Phase.BREAK and director.wave == 0, "starts in countdown before wave 1")
	_check(director.break_time_left() > 0.0, "countdown is running")
	_check(zombies.alive_count() == 0 and spawner.pending_count() == 0, "no zombies during countdown")
	await _frames(int(director.first_wave_delay * 60) + 2)
	_check(_started == [Vector2i(1, 4)], "wave 1 starts after countdown with 4 zombies")
	_check(run.state.wave == 1, "run state tracks wave")
	_check(hud.get_node("%WaveLabel").text == "WAVE 1", "HUD shows WAVE 1")

	# --- Clears only when everything spawned AND died ----------------------
	await _frames(30)
	_check(zombies.alive_count() == 4 and _remaining == 4, "all 4 spawned, 4 remaining")
	_kill(zombies, 3)
	await _frames(2)
	_check(_remaining == 1 and _cleared.is_empty(), "remaining counts down, not cleared yet")
	_kill(zombies, 1)
	await _frames(2)
	_check(_cleared == [1], "wave 1 cleared once")
	_check(director.phase == WaveDirector.Phase.BREAK, "enters break after clear")
	_check(_breaks.back() == Vector2(2, 2.0), "break announces wave 2 with supply_duration")
	_check(hud.get_node("%BreakPanel").visible, "HUD shows break countdown")

	# --- Skip break; killing early zombies mid-batch doesn't clear ---------
	director.skip_break()
	await _frames(1)
	_check(_started.back() == Vector2i(2, 6), "skip starts wave 2 at once with 6 zombies")
	_check(not hud.get_node("%BreakPanel").visible, "HUD hides countdown in combat")
	await _frames(8)
	_kill(zombies, zombies.alive_count())
	await _frames(2)
	_check(_cleared.size() == 1 and spawner.is_batch_active(), "not cleared while batch still spawning")
	await _frames(60)
	_kill(zombies, zombies.alive_count())
	await _frames(2)
	_check(_cleared == [1, 2], "wave 2 cleared after the rest spawn and die")

	# --- Break timeout + zombies removed without kill signals --------------
	await _frames(2 * 60 + 2)
	_check(_started.back() == Vector2i(3, 8), "wave 3 starts when the break runs out")
	await _frames(60)
	zombies.clear()  # debug Clear: no zombie_killed signals
	await _frames(2)
	_check(_cleared == [1, 2, 3], "wave clears even when zombies vanish via clear()")

	# --- Stop -------------------------------------------------------------
	director.stop()
	var waves_before := _started.size()
	await _frames(5 * 60)
	_check(_started.size() == waves_before and spawner.pending_count() == 0, "stop() halts the loop")

	# --- Player death stops the director -----------------------------------
	director.start()
	await _frames(1)
	player.health.set_max_hp(10.0)
	player.health.take_damage(999.0)
	await _frames(1)
	_check(director.phase == WaveDirector.Phase.STOPPED, "player death stops the wave loop")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _kill(zombies: ZombieManager, count: int) -> void:
	var killed := 0
	var i := 0
	while killed < count and i < zombies.alive_count() + killed + 8:
		if zombies.damage(i, 1e9):
			killed += 1
		i += 1


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
