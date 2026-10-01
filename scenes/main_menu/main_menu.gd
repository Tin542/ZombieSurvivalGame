extends Control
## Entry screen. Shows persistent progress; the shop panel will live here.

@onready var _coins_label: Label = %CoinsLabel
@onready var _best_wave_label: Label = %BestWaveLabel


func _ready() -> void:
	%PlayButton.pressed.connect(SceneRouter.start_run)
	SaveService.coins_changed.connect(_on_coins_changed)
	_on_coins_changed(SaveService.get_coins())
	_best_wave_label.text = "Best wave: %d" % SaveService.data.best_wave


func _on_coins_changed(total: int) -> void:
	_coins_label.text = "Coins: %d" % total
