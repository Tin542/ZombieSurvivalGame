class_name SettingsPanel
extends Control
## Player preferences. Every change is written straight to SaveService, which
## persists it (and applies master volume); there is no separate "apply" step.

signal closed

@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_value: Label = %VolumeValue
@onready var _vibration_check: CheckButton = %VibrationCheck
@onready var _fps_check: CheckButton = %FpsCheck
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(close)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_vibration_check.toggled.connect(_on_vibration_toggled)
	_fps_check.toggled.connect(_on_fps_toggled)
	hide()


func open() -> void:
	# set_value_no_signal: syncing the controls must not write settings back.
	_volume_slider.set_value_no_signal(SaveService.get_setting("master_volume"))
	_vibration_check.set_pressed_no_signal(SaveService.get_setting("vibration"))
	_fps_check.set_pressed_no_signal(SaveService.get_setting("show_fps"))
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


func _update_volume_label() -> void:
	_volume_value.text = "%d%%" % roundi(_volume_slider.value * 100.0)
