class_name Hud
extends CanvasLayer
## View of the run. Displays values the run feeds it and reports button presses
## as signals; never mutates gameplay itself. The Joystick node is Godot's
## native VirtualJoystick, which drives the move_* input actions directly.

signal switch_weapon_pressed
signal skip_break_pressed

const BANNER_HOLD := 1.4
const BANNER_FADE := 0.4

## Local mirror of the break countdown, for display only (WaveDirector is the
## authority on when the next wave actually starts).
var _break_left := 0.0
var _next_wave := 0
var _banner_tween: Tween

@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _switch_button: Button = %SwitchButton
@onready var _wave_label: Label = %WaveLabel
@onready var _remaining_label: Label = %RemainingLabel
@onready var _banner: Label = %Banner
@onready var _break_panel: Control = %BreakPanel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _skip_button: Button = %SkipButton


func _ready() -> void:
	_switch_button.pressed.connect(switch_weapon_pressed.emit)
	_skip_button.pressed.connect(skip_break_pressed.emit)
	_banner.hide()
	_break_panel.hide()
	_remaining_label.hide()
	set_process(false)


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


func set_wave(wave: int) -> void:
	_wave_label.text = "WAVE %d" % wave


func set_remaining(remaining: int) -> void:
	_remaining_label.text = "%d left" % remaining


## Big centred message that fades out on its own.
func show_banner(text: String) -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	_banner.text = text
	_banner.modulate.a = 1.0
	_banner.show()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(BANNER_HOLD)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, BANNER_FADE)
	_banner_tween.tween_callback(_banner.hide)


func show_break(next_wave: int, duration: float) -> void:
	_next_wave = next_wave
	_break_left = duration
	_update_countdown()
	_remaining_label.hide()
	_break_panel.show()
	set_process(true)


func hide_break() -> void:
	_break_panel.hide()
	_remaining_label.show()
	set_process(false)


func _process(delta: float) -> void:
	_break_left = maxf(_break_left - delta, 0.0)
	_update_countdown()


func _update_countdown() -> void:
	_countdown_label.text = "WAVE %d IN %d" % [_next_wave, ceili(_break_left)]
