class_name SaveData
extends RefCounted
## Persistent player progress. Serialized as JSON rather than as a Resource so a
## tampered save file can never execute code.
##
## Versioning: VERSION is the format this build writes. from_dict() first runs
## migrate(), which upgrades an older dictionary one step at a time
## (_migrate_v1_to_v2, ...), so the field parsing below only ever sees the
## current format. When the format changes: bump VERSION, add a
## _migrate_vN_to_vN+1 step, and register it in migrate().

const VERSION := 2
const DEFAULT_SETTINGS := {
	"master_volume": 1.0,
	"vibration": true,
	"show_fps": false,
}
const DEFAULT_STATS := {
	"runs_played": 0,
	"total_kills": 0,
	"coins_earned": 0,
}

var coins: int = 0
var best_wave: int = 0
var upgrade_levels: Dictionary[StringName, int] = {}
var unlocked_weapons: Array[StringName] = [&"pistol"]
## Player preferences. Keys and default values come from DEFAULT_SETTINGS; values
## loaded from disk are only kept when their type matches the default.
var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
## Lifetime counters (keys from DEFAULT_STATS), shown in the main menu.
var stats: Dictionary = DEFAULT_STATS.duplicate()


## Format version of a raw save dictionary. Saves from before versioning
## existed count as version 1.
static func version_of(dict: Dictionary) -> int:
	return maxi(int(dict.get("version", 1)), 1)


## Upgrades `dict` to VERSION, one step at a time. Never modifies the input.
## Dictionaries from a newer version are returned unchanged; from_dict() then
## keeps whatever fields it still understands.
static func migrate(dict: Dictionary) -> Dictionary:
	var result := dict.duplicate(true)
	var version := version_of(result)
	if version < 2:
		result = _migrate_v1_to_v2(result)
	return result


## v2 added lifetime stats. Older saves start counting from zero; runs that
## happened before can't be reconstructed.
static func _migrate_v1_to_v2(dict: Dictionary) -> Dictionary:
	dict["stats"] = DEFAULT_STATS.duplicate()
	dict["version"] = 2
	return dict


func to_dict() -> Dictionary:
	var levels := {}
	for id in upgrade_levels:
		levels[String(id)] = upgrade_levels[id]
	var weapons: Array[String] = []
	for id in unlocked_weapons:
		weapons.append(String(id))
	return {
		"version": VERSION,
		"coins": coins,
		"best_wave": best_wave,
		"upgrade_levels": levels,
		"unlocked_weapons": weapons,
		"settings": settings.duplicate(),
		"stats": stats.duplicate(),
	}


static func from_dict(raw: Dictionary) -> SaveData:
	var dict := migrate(raw)
	var data := SaveData.new()
	data.coins = maxi(int(dict.get("coins", 0)), 0)
	data.best_wave = maxi(int(dict.get("best_wave", 0)), 0)

	var levels: Variant = dict.get("upgrade_levels", {})
	if levels is Dictionary:
		for key in levels:
			data.upgrade_levels[StringName(str(key))] = maxi(int(levels[key]), 0)

	var weapons: Variant = dict.get("unlocked_weapons", [])
	if weapons is Array:
		for value in weapons:
			var id := StringName(str(value))
			if id not in data.unlocked_weapons:
				data.unlocked_weapons.append(id)

	var loaded_settings: Variant = dict.get("settings", {})
	if loaded_settings is Dictionary:
		for key in DEFAULT_SETTINGS:
			var value: Variant = loaded_settings.get(key)
			# JSON has one number type, so accept ints where a float is expected.
			if DEFAULT_SETTINGS[key] is float and (value is int or value is float):
				data.settings[key] = float(value)
			elif typeof(value) == typeof(DEFAULT_SETTINGS[key]):
				data.settings[key] = value

	var loaded_stats: Variant = dict.get("stats", {})
	if loaded_stats is Dictionary:
		for key in DEFAULT_STATS:
			var value: Variant = loaded_stats.get(key)
			if value is int or value is float:
				data.stats[key] = maxi(int(value), 0)
	return data
