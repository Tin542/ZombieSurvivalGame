extends SceneTree
## Headless checks for HP + death: hurt feedback, results committed on death,
## game-over screen contents and button lock.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/game_over_test.gd
## Exits with code 1 if any check fails. The real save is restored afterwards.

const RUN_SCENE := "res://scenes/run/run.tscn"

var _failures := 0


func _initialize() -> void:
	await process_frame  # let SaveService load
	var save_service: Node = root.get_node("SaveService")
	var backup: Dictionary = save_service.data.to_dict()
	save_service.data.best_wave = 2
	var coins_before: int = save_service.get_coins()

	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	var player: Player = run.get_node("World/Player")
	var hud: Hud = run.get_node("HUD")
	var game_over: GameOverScreen = run.get_node("GameOver")
	var director: WaveDirector = run.get_node("WaveDirector")
	await process_frame
	player.weapons.set_physics_process(false)

	_check(not game_over.visible, "game-over screen hidden during play")

	# --- Hurt feedback ------------------------------------------------------
	player.health.take_damage(10.0)
	var sprite: Sprite2D = player.get_node("Sprite")
	var flash: ColorRect = hud.get_node("%DamageFlash")
	_check(sprite.modulate != Color.WHITE, "player sprite flashes on hit")
	_check(flash.modulate.a > 0.0, "HUD screen flash on hit")
	await _frames(30)
	_check(sprite.modulate.is_equal_approx(Color.WHITE), "sprite flash fades back")
	_check(is_zero_approx(flash.modulate.a), "screen flash fades out")
	_check(player.health.hp == 90.0, "damage applied")

	# --- Death ----------------------------------------------------------------
	run.state.wave = 5
	run.state.kills = 42
	run.state.add_coins(17)
	player.health.take_damage(999.0)
	await _frames(1)
	_check(director.phase == WaveDirector.Phase.STOPPED, "death stops the wave loop")
	_check(save_service.get_coins() == coins_before + 17, "run coins banked on death")
	_check(save_service.data.best_wave == 5, "best wave saved on death")
	_check(not game_over.visible, "screen waits for the death delay")

	await _frames(int(run.GAME_OVER_DELAY * 60) + 5)
	_check(game_over.visible, "game-over screen shown after delay")
	_check(not hud.visible, "HUD hidden behind game-over screen")
	_check(game_over.get_node("%WaveLabel").text == "Wave reached: 5", "shows wave reached")
	_check(game_over.get_node("%KillsLabel").text == "Kills: 42", "shows kills")
	_check(game_over.get_node("%CoinsLabel").text == "Coins earned: +17", "shows coins earned")
	_check(game_over.get_node("%BestLabel").text == "NEW BEST!", "flags a new best wave")

	# --- Button lock (signal only; the run's scene change is disconnected) ---
	for connection in game_over.retry_pressed.get_connections():
		game_over.retry_pressed.disconnect(connection.callable)
	var presses := [0]
	game_over.retry_pressed.connect(func() -> void: presses[0] += 1)
	var retry: Button = game_over.get_node("%RetryButton")
	retry.pressed.emit()
	_check(presses[0] == 1 and retry.disabled, "retry emits once and locks buttons")
	_check(game_over.get_node("%MenuButton").disabled, "menu locked after a choice")

	# --- Not a new best -------------------------------------------------------
	game_over.show_results(3, 1, 0, 5, false)
	_check(game_over.get_node("%BestLabel").text == "Best wave: 5", "shows existing best otherwise")

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
