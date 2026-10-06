extends Node
## Owns persistent progress (coins, upgrades, unlocks, stats) and settings, and
## is the only code that touches the save file. Run-specific state never lives
## here. Also applies the one engine-global setting (master volume) so it holds
## from the first frame, whichever scene starts.
##
## Files, all next to save_path:
##   save.json              current save
##   save.json.tmp          write in progress; renamed over save.json when done
##   save.json.bak          the previous save.json, rotated on every write;
##                          loaded automatically if save.json is unreadable
##   save.json.session.bak  copy of save.json as it was when the game started
##                          (taken before the first write); manual recovery
##                          after a bad session
##   save.json.corrupt      an unreadable save.json, moved aside (never deleted)
##   save.json.vN.bak       a save from a newer game version (format N), kept
##                          before this older build overwrites it

signal coins_changed(total: int)
signal upgrades_changed
signal setting_changed(key: String, value: Variant)
## Progress was wiped (settings kept).
signal progress_reset

const SAVE_PATH := "user://save.json"
## Used instead of SAVE_PATH when a headless test script (res://tests/...) is
## running, so tests can never touch the player's real save, even if they crash
## before cleaning up. Starts empty every test run.
const TEST_SAVE_PATH := "user://test_save.json"

var data: SaveData
var save_path := SAVE_PATH

var _session_backup_done := false


func _ready() -> void:
	if _running_test_script():
		save_path = TEST_SAVE_PATH
		for path in _all_paths():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	reload()


## Re-reads the save from disk (with backup fallback and migration).
func reload() -> void:
	data = _load()
	_apply_volume()


func get_coins() -> int:
	return data.coins


## Adds run income. Also counts towards the lifetime coins_earned stat.
func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	data.coins += amount
	data.stats["coins_earned"] += amount
	coins_changed.emit(data.coins)
	save()


## Deducts `amount` if affordable. Returns false (and changes nothing) otherwise.
func try_spend(amount: int) -> bool:
	if amount < 0 or data.coins < amount:
		return false
	data.coins -= amount
	coins_changed.emit(data.coins)
	save()
	return true


func get_upgrade_level(id: StringName) -> int:
	return data.upgrade_levels.get(id, 0)


func set_upgrade_level(id: StringName, level: int) -> void:
	data.upgrade_levels[id] = maxi(level, 0)
	save()


func is_weapon_unlocked(id: StringName) -> bool:
	return id in data.unlocked_weapons


func unlock_weapon(id: StringName) -> void:
	if is_weapon_unlocked(id):
		return
	data.unlocked_weapons.append(id)
	save()


## Spends `cost` and raises upgrade `id` one level, in a single save so a crash
## can never take the coins without granting the level. False if unaffordable.
## Max-level checks belong to the caller (it knows the UpgradeDef).
func purchase_upgrade(id: StringName, cost: int) -> bool:
	if cost < 0 or data.coins < cost:
		return false
	data.coins -= cost
	data.upgrade_levels[id] = get_upgrade_level(id) + 1
	save()
	coins_changed.emit(data.coins)
	upgrades_changed.emit()
	return true


## Spends `cost` and unlocks weapon `id` in a single save. False if already
## owned or unaffordable.
func purchase_weapon(id: StringName, cost: int) -> bool:
	if is_weapon_unlocked(id) or cost < 0 or data.coins < cost:
		return false
	data.coins -= cost
	data.unlocked_weapons.append(id)
	save()
	coins_changed.emit(data.coins)
	upgrades_changed.emit()
	return true


func get_setting(key: String) -> Variant:
	return data.settings.get(key, SaveData.DEFAULT_SETTINGS.get(key))


## Stores a known setting (unknown keys or wrong types are ignored) and saves.
func set_setting(key: String, value: Variant) -> void:
	if not SaveData.DEFAULT_SETTINGS.has(key):
		push_warning("SaveService: unknown setting %s" % key)
		return
	if typeof(value) != typeof(SaveData.DEFAULT_SETTINGS[key]):
		push_warning("SaveService: wrong type for setting %s" % key)
		return
	if key == "master_volume":
		value = clampf(value, 0.0, 1.0)
	if data.settings.get(key) == value:
		return
	data.settings[key] = value
	if key == "master_volume":
		_apply_volume()
	save()
	setting_changed.emit(key, value)


func get_stat(key: String) -> int:
	return data.stats.get(key, 0)


func submit_wave_reached(wave: int) -> void:
	if wave <= data.best_wave:
		return
	data.best_wave = wave
	save()


## Counts a finished run (on death) in the lifetime stats.
func record_run(kills: int) -> void:
	data.stats["runs_played"] += 1
	data.stats["total_kills"] += maxi(kills, 0)
	save()


## Wipes coins, upgrades, unlocks, best wave and stats; keeps settings. The
## session backup still holds the state from when the game started.
func reset_progress() -> void:
	var settings := data.settings.duplicate()
	data = SaveData.new()
	data.settings = settings
	save()
	coins_changed.emit(data.coins)
	upgrades_changed.emit()
	progress_reset.emit()


## Writes save.json safely: the new content goes to .tmp first; the old
## save.json is rotated to .bak; then .tmp is renamed into place. A crash at
## any point leaves either the new save, or the previous one in .bak.
func save() -> void:
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: cannot write %s (%s)" % [temp_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data.to_dict()))
	file.close()

	if FileAccess.file_exists(save_path):
		if not _session_backup_done:
			_copy(save_path, save_path + ".session.bak")
		_move(save_path, save_path + ".bak")
	_session_backup_done = true
	var err := _move(temp_path, save_path)
	if err != OK:
		push_error("SaveService: cannot replace save file (%s)" % error_string(err))


func _apply_volume() -> void:
	var volume: float = clampf(get_setting("master_volume"), 0.0, 1.0)
	var master := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_mute(master, volume <= 0.0)
	if volume > 0.0:
		AudioServer.set_bus_volume_db(master, linear_to_db(volume))


static func _running_test_script() -> bool:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("res://tests/"):
			return true
	return false


## Loads save.json, falling back to save.json.bak. An unreadable save.json is
## moved to .corrupt (so the next write can't rotate it over the good .bak).
## A leftover .tmp is an interrupted write and is discarded.
func _load() -> SaveData:
	_session_backup_done = false
	var temp_path := save_path + ".tmp"
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))

	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			if path != save_path:
				push_warning("SaveService: recovered progress from %s" % path)
			_keep_if_newer_format(path, parsed)
			return SaveData.from_dict(parsed)
		push_warning("SaveService: %s is unreadable" % path)
		if path == save_path:
			_move(save_path, save_path + ".corrupt")
	return SaveData.new()


## A save written by a newer build may hold data this build doesn't know about
## and would drop on its next write, so keep a copy of it first.
func _keep_if_newer_format(path: String, parsed: Dictionary) -> void:
	var version := SaveData.version_of(parsed)
	if version > SaveData.VERSION:
		push_warning("SaveService: save is format %d, this build writes %d; keeping a copy" % [version, SaveData.VERSION])
		_copy(path, "%s.v%d.bak" % [save_path, version])


func _all_paths() -> Array[String]:
	var paths: Array[String] = [save_path]
	for suffix in [".tmp", ".bak", ".session.bak", ".corrupt"]:
		paths.append(save_path + suffix)
	return paths


func _move(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))


func _copy(from: String, to: String) -> Error:
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
