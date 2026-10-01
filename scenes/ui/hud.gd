class_name Hud
extends CanvasLayer
## View of the run. Displays values the run feeds it and reports button presses
## as signals; never mutates gameplay itself. The Joystick node is Godot's
## native VirtualJoystick, which drives the move_* input actions directly.

signal switch_weapon_pressed

@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _switch_button: Button = %SwitchButton


func _ready() -> void:
	_switch_button.pressed.connect(switch_weapon_pressed.emit)


func set_hp(hp: float, max_hp: float) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = hp
	_hp_label.text = "HP %d/%d" % [ceili(hp), ceili(max_hp)]


func set_weapon(weapon: WeaponDef) -> void:
	_weapon_label.text = weapon.display_name


func set_ammo(magazine: int, reserve: int, infinite: bool) -> void:
	_ammo_label.text = "%d / %s" % [magazine, "∞" if infinite else str(reserve)]


func show_reload(_duration: float) -> void:
	_ammo_label.text = "RELOAD..."


func set_switch_visible(show: bool) -> void:
	_switch_button.visible = show
