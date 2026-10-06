class_name SettingsPanel
extends Control
## Player preferences. Every change is written straight to SaveService, which
## persists it (and applies master volume); there is no separate "apply" step.

signal closed

## Seconds the reset button stays armed after the first tap.
const RESET_CONFIRM_TIME := 3.0
const RESET_TEXT := "RESET PROGRESS"
const RESET_CONFIRM_TEXT := "TAP AGAIN TO RESET"

var _reset_armed_until := 0.0

@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_value: Label = %VolumeValue
@onready var _vibration_check: CheckButton = %VibrationCheck
@onready var _fps_check: CheckButton = %FpsCheck
@onready var _back_button: Button = %BackButton
@onready var _reset_button: Button = %ResetButton


func _ready() -> void:
	_back_button.pressed.connect(close)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_vibration_check.toggled.connect(_on_vibration_toggled)
	_fps_check.toggled.connect(_on_fps_toggled)
	_reset_button.pressed.connect(_on_reset_pressed)
	hide()


func open() -> void:
	# set_value_no_signal: syncing the controls must not write settings back.
	_volume_slider.set_value_no_signal(SaveService.get_setting("master_volume"))
	_vibration_check.set_pressed_no_signal(SaveService.get_setting("vibration"))
	_fps_check.set_pressed_no_signal(SaveService.get_setting("show_fps"))
	_disarm_reset()
	_update_volume_label()
	show()


func close() -> void:
	hide()
	closed.emit()


func _on_volume_changed(value: float) -> void:
	SaveService.set_setting("master_volume", value)
	_update_volume_label()


func _on_vibration_toggled(on: bool) -> void:
	SaveService.set_setting("vibration", on)


func _on_fps_toggled(on: bool) -> void:
	SaveService.set_setting("show_fps", on)


## Wiping progress is two taps: the first arms the button for a few seconds.
func _on_reset_pressed() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _reset_armed_until:
		SaveService.reset_progress()
		_disarm_reset()
		_reset_button.text = "PROGRESS RESET"
		return
	_reset_armed_until = now + RESET_CONFIRM_TIME
	_reset_button.text = RESET_CONFIRM_TEXT
	get_tree().create_timer(RESET_CONFIRM_TIME).timeout.connect(_disarm_reset_if_expired)


func _disarm_reset() -> void:
	_reset_armed_until = 0.0
	_reset_button.text = RESET_TEXT


func _disarm_reset_if_expired() -> void:
	if _reset_armed_until > 0.0 and Time.get_ticks_msec() / 1000.0 >= _reset_armed_until:
		_disarm_reset()


func _update_volume_label() -> void:
	_volume_value.text = "%d%%" % roundi(_volume_slider.value * 100.0)
