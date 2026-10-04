extends Node
## Owns persistent progress (coins, upgrades, unlocks) and settings, and is the
## only code that touches the save file. Run-specific state never lives here.
## Also applies the one engine-global setting (master volume) so it holds from
## the first frame, whichever scene starts.

signal coins_changed(total: int)
signal upgrades_changed
signal setting_changed(key: String, value: Variant)

const SAVE_PATH := "user://save.json"
## Used instead of SAVE_PATH when a headless test script (res://tests/...) is
## running, so tests can never touch the player's real save, even if they crash
## before cleaning up. Starts empty every test run.
const TEST_SAVE_PATH := "user://test_save.json"

var data: SaveData
var save_path := SAVE_PATH


func _ready() -> void:
	if _running_test_script():
		save_path = TEST_SAVE_PATH
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	data = _load()
	_apply_volume()


func get_coins() -> int:
	return data.coins


func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	data.coins += amount
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


func submit_wave_reached(wave: int) -> void:
	if wave <= data.best_wave:
		return
	data.best_wave = wave
	save()


## Writes to a temp file first, then renames over the real save, so a crash or
## kill mid-write never leaves a corrupt save behind.
func save() -> void:
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: cannot write %s (%s)" % [temp_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data.to_dict()))
	file.close()

	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(save_path))
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


func _load() -> SaveData:
	if not FileAccess.file_exists(save_path):
		return SaveData.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if parsed is Dictionary:
		return SaveData.from_dict(parsed)
	push_warning("SaveService: save file unreadable, starting fresh")
	return SaveData.new()
