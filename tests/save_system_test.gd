extends SceneTree
## Headless checks for the save system: format migration, backup rotation,
## session backup, corruption recovery, interrupted writes, saves from newer
## builds, progress reset, lifetime stats, and mid-run banking.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/save_system_test.gd
## Exits with code 1 if any check fails. Uses SaveService's test save file only.

const RUN_SCENE := "res://scenes/run/run.tscn"
const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"

var _failures := 0
var _save: Node
var _path: String


func _initialize() -> void:
	await process_frame  # let SaveService load
	_save = root.get_node("SaveService")
	_path = _save.save_path
	_check(_path == "user://test_save.json", "tests run on the isolated test save")

	# --- Migration -------------------------------------------------------------
	var v1 := {"version": 1, "coins": 42, "best_wave": 7, "upgrade_levels": {"damage": 2}, "unlocked_weapons": ["pistol", "smg"]}
	var migrated := SaveData.migrate(v1)
	_check(migrated["version"] == SaveData.VERSION and migrated.has("stats"), "v1 migrates to v%d with stats" % SaveData.VERSION)
	_check(not v1.has("stats") and v1["version"] == 1, "migration doesn't modify its input")
	var from_v1 := SaveData.from_dict(v1)
	_check(from_v1.coins == 42 and from_v1.best_wave == 7 and from_v1.upgrade_levels[&"damage"] == 2 and &"smg" in from_v1.unlocked_weapons, "v1 progress survives migration")
	_check(from_v1.stats == SaveData.DEFAULT_STATS, "v1 stats start at zero")
	_check(SaveData.version_of({"coins": 1}) == 1, "unversioned save counts as v1")
	_check(SaveData.from_dict(from_v1.to_dict()).to_dict() == from_v1.to_dict(), "to_dict / from_dict round-trip")

	# --- Backup rotation + session backup --------------------------------------
	_save.data = SaveData.new()
	_save.data.coins = 1
	_save.save()
	_check(_exists(_path) and not _exists(_path + ".bak"), "first write: save only, nothing to rotate")
	_save.data.coins = 2
	_save.save()
	_check(_coins_in(_path) == 2 and _coins_in(_path + ".bak") == 1, "each write rotates the previous save to .bak")
	_save.reload()  # new "session": its backup is the file as it is now (2 coins)
	_save.data.coins = 3
	_save.save()
	_save.data.coins = 4
	_save.save()
	_check(_coins_in(_path + ".session.bak") == 2, "session backup holds the save from session start")
	_check(_coins_in(_path) == 4 and _coins_in(_path + ".bak") == 3, "rotation continues after the session backup")

	# --- Corruption recovery ------------------------------------------------------
	_write(_path, "{ this is not json")
	_save.reload()
	_check(_save.get_coins() == 3, "corrupt save -> progress recovered from .bak")
	_check(_exists(_path + ".corrupt") and not _exists(_path), "corrupt file moved aside, not deleted")
	_save.save()
	_check(_coins_in(_path + ".bak") == 3, "next write doesn't rotate the corrupt file over the good .bak")
	_check(_coins_in(_path) == 3, "save rewritten from the recovered data")

	_write(_path, "garbage")
	_write(_path + ".bak", "")
	_save.reload()
	_check(_save.get_coins() == 0, "both unreadable -> fresh start (no crash)")

	# --- Interrupted write ----------------------------------------------------
	_save.data.coins = 9
	_save.save()
	_write(_path + ".tmp", "{\"coins\": 999")
	_save.reload()
	_check(_save.get_coins() == 9 and not _exists(_path + ".tmp"), "leftover .tmp ignored and cleaned up")

	# --- Save from a newer build ------------------------------------------------
	_write(_path, JSON.stringify({"version": 99, "coins": 77, "best_wave": 4, "future_field": [1, 2]}))
	_save.reload()
	_check(_save.get_coins() == 77 and _save.data.best_wave == 4, "newer-format save: known fields loaded")
	_check(_exists(_path + ".v99.bak") and FileAccess.get_file_as_string(_path + ".v99.bak").contains("future_field"), "newer-format save kept as .v99.bak before overwrite")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path + ".v99.bak"))

	# --- Stats + reset ------------------------------------------------------------
	_save.data = SaveData.new()
	_save.set_setting("show_fps", true)
	_save.add_coins(30)
	_save.record_run(12)
	_save.record_run(5)
	_check(_save.get_stat("coins_earned") == 30 and _save.get_stat("runs_played") == 2 and _save.get_stat("total_kills") == 17, "lifetime stats count coins, runs, kills")
	_save.purchase_upgrade(&"damage", 10)
	_check(_save.get_stat("coins_earned") == 30, "spending doesn't reduce coins_earned")
	var resets := [0]
	_save.progress_reset.connect(func() -> void: resets[0] += 1)
	_save.reset_progress()
	_check(_save.get_coins() == 0 and _save.get_upgrade_level(&"damage") == 0 and _save.get_stat("runs_played") == 0, "reset wipes progress")
	_check(_save.get_setting("show_fps") == true and resets[0] == 1, "reset keeps settings and signals")
	_check(_coins_in(_path + ".bak") == 20, "state before the reset is in .bak")

	# --- Mid-run banking ------------------------------------------------------------
	_save.data = SaveData.new()
	_save.data.best_wave = 3
	_save.save()
	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	await process_frame
	var director: WaveDirector = run.get_node("WaveDirector")
	director.stop()
	run.get_node("World/Player").weapons.set_physics_process(false)
	run.state.wave = 2
	run.state.add_coins(10)
	director.wave_cleared.emit(2)
	_check(_save.get_coins() == 10, "wave clear banks run coins")
	director.wave_cleared.emit(2)
	_check(_save.get_coins() == 10, "banking twice doesn't double-count")
	run.state.add_coins(5)
	run.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(_save.get_coins() == 15, "app pause banks new coins (Android background)")
	run.state.add_coins(4)
	run.state.kills = 8
	var player: Player = run.get_node("World/Player")
	player.health.take_damage(1e9)
	await _frames(1)
	_check(_save.get_coins() == 19, "death banks only the remainder (19 total, no double count)")
	_check(_save.get_stat("runs_played") == 1 and _save.get_stat("total_kills") == 8, "death records the run in stats")
	await _frames(int(run.GAME_OVER_DELAY * 60) + 5)
	_check(run.get_node("GameOver").get_node("%BestLabel").text == "Best wave: 3", "no false NEW BEST when an earlier wave was banked")
	run.queue_free()
	await process_frame

	# --- Menu shows stats; settings reset needs two taps ---------------------------------
	var menu: Control = load(MENU_SCENE).instantiate()
	root.add_child(menu)
	await process_frame
	var stats_label: Label = menu.get_node("%StatsLabel")
	_check(stats_label.visible and stats_label.text.contains("Runs 1") and stats_label.text.contains("Kills 8"), "menu shows lifetime stats")
	var settings: Control = menu.get_node("%SettingsPanel")
	settings.call("open")
	var reset_button: Button = settings.get_node("%ResetButton")
	reset_button.pressed.emit()
	_check(_save.get_coins() == 19 and reset_button.text == "TAP AGAIN TO RESET", "first tap only arms reset")
	reset_button.pressed.emit()
	_check(_save.get_coins() == 0, "second tap resets progress")
	_check(menu.get_node("%CoinsLabel").text == "$ 0" and menu.get_node("%BestWaveLabel").text == "No runs yet" and not stats_label.visible, "menu refreshes after reset")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _exists(path: String) -> bool:
	return FileAccess.file_exists(path)


func _coins_in(path: String) -> int:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return int(parsed.get("coins", -1)) if parsed is Dictionary else -1


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
