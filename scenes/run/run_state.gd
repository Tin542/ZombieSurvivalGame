class_name RunState
extends RefCounted
## Progress of the current run. Owned by the Run scene and discarded with it;
## only the final coins/wave are handed to SaveService.

signal coins_changed(coins: int)
signal wave_changed(wave: int)

var wave: int = 1:
	set(value):
		wave = value
		wave_changed.emit(wave)
var coins: int = 0
var kills: int = 0


func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	coins_changed.emit(coins)
