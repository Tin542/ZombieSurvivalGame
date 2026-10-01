class_name SaveData
extends RefCounted
## Persistent player progress. Serialized as JSON rather than as a Resource so a
## tampered save file can never execute code.

const VERSION := 1

var coins: int = 0
var best_wave: int = 0
var upgrade_levels: Dictionary[StringName, int] = {}
var unlocked_weapons: Array[StringName] = [&"pistol"]


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
	}


static func from_dict(dict: Dictionary) -> SaveData:
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
	return data
