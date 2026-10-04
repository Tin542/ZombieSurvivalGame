class_name ShopPanel
extends Control
## Persistent shop: levelled upgrades and weapon unlocks from a ShopCatalog.
## Decides what is buyable and what it costs; each purchase is a single
## SaveService call, so coins and the bought item are saved together.

signal closed

const ROW_SCENE := preload("res://scenes/main_menu/shop_row.tscn")

@export var catalog: ShopCatalog

var _upgrade_rows: Dictionary[UpgradeDef, ShopRow] = {}
var _weapon_rows: Dictionary[WeaponDef, ShopRow] = {}

@onready var _coins_label: Label = %ShopCoinsLabel
@onready var _list: VBoxContainer = %List
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(close)
	SaveService.coins_changed.connect(_refresh.unbind(1))
	SaveService.upgrades_changed.connect(_refresh)
	_build()
	hide()


func open() -> void:
	_refresh()
	show()


func close() -> void:
	hide()
	closed.emit()


## Buys the next level of `upgrade`. False if maxed or unaffordable.
func buy_upgrade(upgrade: UpgradeDef) -> bool:
	var level := SaveService.get_upgrade_level(upgrade.id)
	if upgrade.is_maxed(level):
		return false
	return SaveService.purchase_upgrade(upgrade.id, upgrade.cost_for_level(level))


## Unlocks `weapon` for good. False if owned already or unaffordable.
func buy_weapon(weapon: WeaponDef) -> bool:
	return SaveService.purchase_weapon(weapon.id, weapon.unlock_cost)


func get_upgrade_row(upgrade: UpgradeDef) -> ShopRow:
	return _upgrade_rows.get(upgrade)


func get_weapon_row(weapon: WeaponDef) -> ShopRow:
	return _weapon_rows.get(weapon)


func _build() -> void:
	_add_header("UPGRADES")
	for upgrade in catalog.upgrades:
		var row := _add_row()
		row.buy_pressed.connect(buy_upgrade.bind(upgrade))
		_upgrade_rows[upgrade] = row
	_add_header("WEAPONS")
	for weapon in catalog.weapons:
		if weapon.unlock_cost <= 0:
			continue  # owned from the start; nothing to sell
		var row := _add_row()
		row.buy_pressed.connect(buy_weapon.bind(weapon))
		_weapon_rows[weapon] = row


func _refresh() -> void:
	var coins := SaveService.get_coins()
	_coins_label.text = "$ %d" % coins
	for upgrade in _upgrade_rows:
		var level := SaveService.get_upgrade_level(upgrade.id)
		var maxed := upgrade.is_maxed(level)
		var cost := upgrade.cost_for_level(level)
		_upgrade_rows[upgrade].configure(
			upgrade.display_name,
			upgrade.description % upgrade.value_text(),
			"Lv %d/%d" % [mini(level, upgrade.max_level), upgrade.max_level],
			"MAX" if maxed else "$ %d" % cost,
			not maxed and coins >= cost)
	for weapon in _weapon_rows:
		var owned := SaveService.is_weapon_unlocked(weapon.id)
		_weapon_rows[weapon].configure(
			weapon.display_name,
			_weapon_info(weapon),
			"",
			"OWNED" if owned else "$ %d" % weapon.unlock_cost,
			not owned and coins >= weapon.unlock_cost)


func _weapon_info(weapon: WeaponDef) -> String:
	var damage := "%d" % roundi(weapon.damage)
	if weapon.projectiles_per_shot > 1:
		damage += "x%d" % weapon.projectiles_per_shot
	return "DMG %s  |  %.1f shots/s  |  %d mag" % [damage, 1.0 / weapon.fire_interval, weapon.magazine_size]


func _add_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	_list.add_child(label)


func _add_row() -> ShopRow:
	var row: ShopRow = ROW_SCENE.instantiate()
	_list.add_child(row)
	return row
