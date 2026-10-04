extends SceneTree
## Headless checks for the main menu, shop and settings: upgrade pricing,
## atomic purchases persisted to disk, shop UI state, upgrades applied in a
## run, weapon unlocks feeding the loadout, settings persistence and effects.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/shop_test.gd
## Exits with code 1 if any check fails. The real save is restored afterwards.

const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const RUN_SCENE := "res://scenes/run/run.tscn"
const CATALOG := preload("res://data/shop_catalog.tres")
const MAX_HP := preload("res://data/upgrades/max_hp.tres")
const DAMAGE := preload("res://data/upgrades/damage.tres")
const SPRINT := preload("res://data/upgrades/move_speed.tres")
const MAGNET := preload("res://data/upgrades/magnet.tres")
const AMMO := preload("res://data/upgrades/start_ammo.tres")
const SMG := preload("res://data/weapons/smg.tres")
const SHOTGUN := preload("res://data/weapons/shotgun.tres")

var _failures := 0
var _save: Node


func _initialize() -> void:
	await process_frame  # let SaveService load
	_save = root.get_node("SaveService")
	var backup: Dictionary = _save.data.to_dict()
	_save.data = SaveData.new()

	# --- Pricing ------------------------------------------------------------
	_check(MAX_HP.cost_for_level(0) == 50 and MAX_HP.cost_for_level(1) == 80, "cost grows per level (50, 80)")
	_check(MAX_HP.is_maxed(MAX_HP.max_level) and not MAX_HP.is_maxed(0), "max level detection")
	_check(MAX_HP.value_text() == "+15 HP" and DAMAGE.value_text() == "+10%", "value text")
	var levels := {&"max_hp": 2, &"damage": 99}
	_check(is_equal_approx(CATALOG.bonus(UpgradeDef.Stat.MAX_HP, func(id): return levels.get(id, 0)), 30.0), "bonus sums owned levels")
	_check(is_equal_approx(CATALOG.bonus(UpgradeDef.Stat.DAMAGE, func(id): return levels.get(id, 0)), 0.5), "bonus caps at max_level")

	# --- Atomic purchases, persisted -----------------------------------------
	_save.data.coins = 100
	_check(_save.purchase_upgrade(&"max_hp", 50), "affordable upgrade bought")
	_check(_save.get_coins() == 50 and _save.get_upgrade_level(&"max_hp") == 1, "coins spent and level raised")
	_check(not _save.purchase_upgrade(&"max_hp", 80), "unaffordable upgrade refused")
	_check(_save.get_coins() == 50 and _save.get_upgrade_level(&"max_hp") == 1, "refused purchase changes nothing")
	_save.data.coins = 600
	_check(_save.purchase_weapon(&"smg", 300) and _save.is_weapon_unlocked(&"smg"), "weapon unlocked")
	_check(not _save.purchase_weapon(&"smg", 300) and _save.get_coins() == 300, "owned weapon can't be bought twice")
	var reloaded: SaveData = _save._load()
	_check(reloaded.coins == 300 and reloaded.upgrade_levels.get(&"max_hp") == 1 and &"smg" in reloaded.unlocked_weapons, "purchases are on disk")

	# --- Settings -------------------------------------------------------------
	_save.set_setting("master_volume", 0.5)
	var master := AudioServer.get_bus_index(&"Master")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(master), linear_to_db(0.5)), "volume applied to Master bus")
	_save.set_setting("master_volume", 0.0)
	_check(AudioServer.is_bus_mute(master), "volume 0 mutes")
	_save.set_setting("master_volume", 1.0)
	_save.set_setting("show_fps", true)
	_save.set_setting("show_fps", 1)  # wrong type: ignored
	_save.set_setting("bogus", true)  # unknown: ignored
	reloaded = _save._load()
	_check(reloaded.settings["show_fps"] == true and not reloaded.settings.has("bogus"), "settings persisted, bad writes ignored")
	var from_old := SaveData.from_dict({"coins": 5, "settings": {"master_volume": 1, "vibration": "yes"}})
	_check(from_old.settings["master_volume"] == 1.0 and from_old.settings["vibration"] == true, "loading coerces numbers, rejects bad types")
	_check(SaveData.from_dict({"coins": 5}).settings == SaveData.DEFAULT_SETTINGS, "old saves get default settings")

	# --- Main menu + shop UI --------------------------------------------------
	_save.data = SaveData.new()
	_save.data.coins = 200
	var menu: Control = load(MENU_SCENE).instantiate()
	root.add_child(menu)
	await process_frame
	# Untyped on purpose: ShopPanel/SettingsPanel use the SaveService autoload,
	# which a -s test script can't reference at compile time.
	var shop: Control = menu.get_node("%ShopPanel")
	var settings: Control = menu.get_node("%SettingsPanel")
	_check(menu.get_node("%CoinsLabel").text == "$ 200", "menu shows coins")
	_check(not shop.visible and not settings.visible, "panels start closed")
	menu.get_node("%ShopButton").pressed.emit()
	_check(shop.visible, "SHOP opens the shop")

	var hp_row: ShopRow = shop.get_upgrade_row(MAX_HP)
	_check(hp_row.get_button_text() == "$ 50" and hp_row.is_buyable(), "row shows price and is buyable")
	_check(shop.get_weapon_row(SHOTGUN).get_button_text() == "$ 500" and not shop.get_weapon_row(SHOTGUN).is_buyable(), "unaffordable weapon disabled")
	_check(shop.get_weapon_row(preload("res://data/weapons/pistol.tres")) == null, "starter weapon not for sale")
	hp_row.buy_pressed.emit()
	_check(_save.get_upgrade_level(&"max_hp") == 1 and _save.get_coins() == 150, "buy button purchases")
	_check(hp_row.get_button_text() == "$ 80" and menu.get_node("%CoinsLabel").text == "$ 150", "row and menu refresh after buying")
	_save.data.coins = 100000
	_save.coins_changed.emit(_save.data.coins)
	for i in 10:
		hp_row.buy_pressed.emit()
	_check(_save.get_upgrade_level(&"max_hp") == MAX_HP.max_level, "can't buy past max level")
	_check(hp_row.get_button_text() == "MAX" and not hp_row.is_buyable(), "maxed row says MAX")
	shop.get_weapon_row(SHOTGUN).buy_pressed.emit()
	_check(shop.get_weapon_row(SHOTGUN).get_button_text() == "OWNED", "bought weapon shows OWNED")

	var back := InputEventAction.new()
	back.action = &"ui_cancel"
	back.pressed = true
	Input.parse_input_event(back)
	await process_frame
	_check(not shop.visible, "Esc / back closes the shop")

	menu.get_node("%SettingsButton").pressed.emit()
	_check(settings.visible, "SETTINGS opens settings")
	var fps_check: CheckButton = settings.get_node("%FpsCheck")
	fps_check.button_pressed = true
	_check(_save.get_setting("show_fps") == true, "FPS toggle saves")
	var slider: HSlider = settings.get_node("%VolumeSlider")
	slider.value = 0.25
	_check(is_equal_approx(_save.get_setting("master_volume"), 0.25) and settings.get_node("%VolumeValue").text == "25%", "volume slider saves and shows %")
	settings.close()
	menu.queue_free()
	await process_frame

	# --- Upgrades and unlocks applied in a run -------------------------------
	_save.data = SaveData.new()
	var owned: Dictionary[StringName, int] = {&"max_hp": 2, &"damage": 3, &"move_speed": 1, &"magnet": 2, &"start_ammo": 1}
	_save.data.upgrade_levels = owned
	_save.data.unlocked_weapons.append(&"smg")
	_save.data.settings["show_fps"] = true
	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	await process_frame
	run.get_node("WaveDirector").stop()
	var player: Player = run.get_node("World/Player")
	var weapons := player.weapons
	_check(is_equal_approx(player.health.max_hp, 130.0) and is_equal_approx(player.health.hp, 130.0), "Toughness lv2: 130 max HP, full")
	_check(run.get_node("HUD").get_node("%HpLabel").text == "HP 130/130", "HUD shows upgraded HP")
	_check(is_equal_approx(weapons.damage_multiplier, 1.3), "Firepower lv3: x1.3 damage")
	_check(is_equal_approx(player.move_speed, 80.0 * 1.06), "Sprint lv1: +6% speed")
	_check(is_equal_approx(run.get_node("Coins").magnet_radius, 40.0 * 1.5), "Magnet lv2: +50% radius")
	_check(weapons.weapon_count() == 2 and weapons._slots[1].def == SMG, "loadout = pistol + unlocked SMG only")
	_check(weapons._slots[1].reserve == roundi(SMG.start_reserve_ammo * 1.25), "Ammo Pouch lv1: +25% starting reserve")
	_check(run.get_node("HUD").get_node("%FpsLabel").visible, "show_fps setting shows HUD FPS")

	_save.data = SaveData.from_dict(backup)
	_save.save()
	_save._apply_volume()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
