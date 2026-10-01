class_name HealthComponent
extends Node
## Reusable HP pool. Owners react through signals; this node knows nothing
## about who damages it or what dying means.

signal hp_changed(hp: float, max_hp: float)
signal damaged(amount: float)
signal healed(amount: float)
signal died

@export var max_hp: float = 100.0

var hp: float


func _ready() -> void:
	hp = max_hp


func is_dead() -> bool:
	return hp <= 0.0


func take_damage(amount: float) -> void:
	if amount <= 0.0 or is_dead():
		return
	hp = maxf(hp - amount, 0.0)
	damaged.emit(amount)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if amount <= 0.0 or is_dead():
		return
	var before := hp
	hp = minf(hp + amount, max_hp)
	if hp > before:
		healed.emit(hp - before)
		hp_changed.emit(hp, max_hp)


func set_max_hp(value: float, refill: bool = true) -> void:
	max_hp = maxf(value, 1.0)
	hp = max_hp if refill else minf(hp, max_hp)
	hp_changed.emit(hp, max_hp)
