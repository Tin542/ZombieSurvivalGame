class_name GameOverScreen
extends CanvasLayer
## End-of-run results. Displays the numbers the run hands it and reports the
## player's choice as signals; scene changes are the run's call.

signal retry_pressed
signal menu_pressed

const FADE_TIME := 0.35

@onready var _root: Control = %Root
@onready var _wave_label: Label = %WaveLabel
@onready var _kills_label: Label = %KillsLabel
@onready var _coins_label: Label = %CoinsLabel
@onready var _best_label: Label = %BestLabel
@onready var _retry_button: Button = %RetryButton
@onready var _menu_button: Button = %MenuButton


func _ready() -> void:
	_retry_button.pressed.connect(_choose.bind(retry_pressed))
	_menu_button.pressed.connect(_choose.bind(menu_pressed))
	hide()


func show_results(wave: int, kills: int, coins: int, best_wave: int, new_best: bool) -> void:
	_wave_label.text = "Wave reached: %d" % wave
	_kills_label.text = "Kills: %d" % kills
	_coins_label.text = "Coins earned: +%d" % coins
	_best_label.text = "NEW BEST!" if new_best else "Best wave: %d" % best_wave
	_best_label.modulate = Color(1.0, 0.85, 0.4) if new_best else Color.WHITE
	_retry_button.disabled = false
	_menu_button.disabled = false
	_root.modulate.a = 0.0
	show()
	create_tween().tween_property(_root, "modulate:a", 1.0, FADE_TIME)


## One choice per screen: buttons lock so a double tap can't fire twice.
func _choose(choice: Signal) -> void:
	_retry_button.disabled = true
	_menu_button.disabled = true
	choice.emit()
