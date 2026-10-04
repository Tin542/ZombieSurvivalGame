class_name ShopRow
extends PanelContainer
## One line in the shop: name, description, level and a buy button. Pure view:
## ShopPanel decides every value and listens for buy_pressed.

signal buy_pressed

@onready var _name_label: Label = %NameLabel
@onready var _info_label: Label = %InfoLabel
@onready var _level_label: Label = %LevelLabel
@onready var _buy_button: Button = %BuyButton


func _ready() -> void:
	_buy_button.pressed.connect(buy_pressed.emit)


func configure(title: String, info: String, level_text: String, button_text: String, can_buy: bool) -> void:
	_name_label.text = title
	_info_label.text = info
	_level_label.text = level_text
	_buy_button.text = button_text
	_buy_button.disabled = not can_buy


func get_button_text() -> String:
	return _buy_button.text


func is_buyable() -> bool:
	return not _buy_button.disabled
