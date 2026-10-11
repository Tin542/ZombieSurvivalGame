class_name RunState
extends RefCounted
## Progress of the current run. Owned by the Run scene and discarded with it;
## only the final coins/wave are handed to SaveService. Everything in the bag
## and every boost belongs to this run only.

signal coins_changed(coins: int)
signal wave_changed(wave: int)

## Bag size before shop upgrades.
const BASE_BAG_SLOTS := 8

var wave: int = 1:
	set(value):
		wave = value
		wave_changed.emit(wave)
var coins: int = 0
var kills: int = 0
var inventory := Inventory.new(BASE_BAG_SLOTS)
## Run-only bonuses from boost items (on top of permanent shop upgrades).
var damage_bonus: float = 0.0
var max_hp_bonus: float = 0.0


func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	coins_changed.emit(coins)
