extends Node
## Owns persistent progress (coins, upgrades, unlocks) and is the only code that
## touches the save file. Run-specific state never lives here.

signal coins_changed(total: int)

const SAVE_PATH := "user://save.json"
const TEMP_PATH := "user://save.json.tmp"

var data: SaveData


func _ready() -> void:
	data = _load()


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


func submit_wave_reached(wave: int) -> void:
	if wave <= data.best_wave:
		return
	data.best_wave = wave
	save()


## Writes to a temp file first, then renames over the real save, so a crash or
## kill mid-write never leaves a corrupt save behind.
func save() -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: cannot write %s (%s)" % [TEMP_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data.to_dict()))
	file.close()

	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_PATH),
		ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_error("SaveService: cannot replace save file (%s)" % error_string(err))


func _load() -> SaveData:
	if not FileAccess.file_exists(SAVE_PATH):
		return SaveData.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		return SaveData.from_dict(parsed)
	push_warning("SaveService: save file unreadable, starting fresh")
	return SaveData.new()
