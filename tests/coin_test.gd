extends SceneTree
## Headless checks for money: kill drops, magnet pickup, wave-clear vacuum,
## full-pool fallback, no pickup after death, and drop cost at a full pool.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/coin_test.gd
## Exits with code 1 if any check fails. The real save is restored afterwards.

const RUN_SCENE := "res://scenes/run/run.tscn"
const WALKER := preload("res://data/zombies/walker.tres")
const BRUTE := preload("res://data/zombies/brute.tres")

var _failures := 0


func _initialize() -> void:
	await process_frame  # let SaveService load
	var save_service: Node = root.get_node("SaveService")
	var backup: Dictionary = save_service.data.to_dict()

	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	var player: Player = run.get_node("World/Player")
	var zombies: ZombieManager = run.get_node("World/Zombies")
	var coins: CoinManager = run.get_node("Coins")
	var director: WaveDirector = run.get_node("WaveDirector")
	var hud: Hud = run.get_node("HUD")
	await process_frame
	director.stop()  # the test spawns everything itself
	player.weapons.set_physics_process(false)
	player.health.set_max_hp(1e9)
	var home := player.global_position

	# --- Kill drops a coin worth coin_value where the zombie died ----------
	var far := home + Vector2(150, 0)
	zombies.spawn_at(BRUTE, far)
	zombies.target = null  # keep it still
	zombies.damage(0, 1e9)
	_check(coins.active_count() == 1, "kill drops one coin")
	_check(run.state.kills == 1, "kill counted")
	await _frames(30)
	_check(coins.active_count() == 1 and run.state.coins == 0, "far coin rests, not collected")

	# --- Walking into magnet range collects it -----------------------------
	player.global_position = far + Vector2(-20, 0)
	await _frames(30)
	_check(coins.active_count() == 0, "coin homes in and is picked up")
	_check(run.state.coins == BRUTE.coin_value, "coin value added to run (%d)" % run.state.coins)
	_check(hud.get_node("%CoinLabel").text == "$ %d" % BRUTE.coin_value, "HUD shows coins")
	player.global_position = home

	# --- Wave clear vacuums every coin on the ground -----------------------
	var before: int = run.state.coins
	for k in 20:
		coins.spawn(home + Vector2(200, -100 + k * 10), 1)
	await _frames(10)
	_check(coins.active_count() == 20, "20 coins resting far away")
	director.wave_cleared.emit(1)
	await _frames(120)
	_check(coins.active_count() == 0, "wave clear collects all coins")
	_check(run.state.coins == before + 20, "all 20 counted")

	# --- Full pool awards at once ------------------------------------------
	before = run.state.coins
	var far_corner := home + Vector2(250, 150)
	for k in coins.max_coins:
		coins.spawn(far_corner, 1)
	coins.spawn(far_corner, 7)
	await _frames(1)
	_check(coins.active_count() == coins.max_coins, "pool full")
	_check(run.state.coins == before + 7, "overflow drop awarded directly")

	# --- Drawing a full pool -----------------------------------------------
	var t0 := Time.get_ticks_usec()
	for k in 60:
		await process_frame
	print("  info full-pool frame avg: %.3f ms" % ((Time.get_ticks_usec() - t0) / 60000.0))

	# --- Nothing collected after death -------------------------------------
	coins.clear()
	coins.spawn(home, 3)
	player.health.set_max_hp(1.0)
	player.health.take_damage(10.0)
	before = run.state.coins
	await _frames(30)
	_check(run.state.coins == before and coins.active_count() == 1, "no pickup after death")

	save_service.data = SaveData.from_dict(backup)
	save_service.save()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
