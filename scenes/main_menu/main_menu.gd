extends Control
## Entry screen: persistent progress plus the way into a run, the shop and
## settings. The panels are full-screen overlays; Android back / Esc closes
## whichever is open.

@onready var _coins_label: Label = %CoinsLabel
@onready var _best_wave_label: Label = %BestWaveLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _shop: ShopPanel = %ShopPanel
@onready var _settings: SettingsPanel = %SettingsPanel


func _ready() -> void:
	%PlayButton.pressed.connect(SceneRouter.start_run)
	%ShopButton.pressed.connect(_shop.open)
	%SettingsButton.pressed.connect(_settings.open)
	SaveService.coins_changed.connect(_on_coins_changed)
	SaveService.progress_reset.connect(_refresh_progress)
	_on_coins_changed(SaveService.get_coins())
	_refresh_progress()


func _notification(what: int) -> void:
	# quit_on_go_back is off in project settings so back can close panels first.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not _close_panel():
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _close_panel():
		get_viewport().set_input_as_handled()


## Closes the open panel, if any. True if one was open.
func _close_panel() -> bool:
	for panel: Control in [_shop, _settings]:
		if panel.visible:
			panel.call(&"close")
			return true
	return false


func _on_coins_changed(total: int) -> void:
	_coins_label.text = "$ %d" % total


func _refresh_progress() -> void:
	var best := SaveService.data.best_wave
	_best_wave_label.text = "Best wave: %d" % best if best > 0 else "No runs yet"
	var runs := SaveService.get_stat("runs_played")
	_stats_label.visible = runs > 0
	_stats_label.text = "Runs %d  |  Kills %d  |  Coins earned %d" % [
		runs, SaveService.get_stat("total_kills"), SaveService.get_stat("coins_earned")]
