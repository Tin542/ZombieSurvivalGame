extends SceneTree
## Headless checks for shop items, the stash and the PREPARE loadout: save v3
## (stash, last_loadout, migration), atomic item purchases on disk, shop item
## rows, take_loadout clamping + remembering, the PREPARE panel (restore, +/-,
## stash and bag-slot limits, Backpack upgrade), and a run bringing the
## loadout into its bag (overflow on the ground, lost on death).
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/loadout_test.gd
## Exits with code 1 if any check fails. The real save is restored afterwards.

const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const RUN_SCENE := "res://scenes/run/run.tscn"
const CATALOG := preload("res://data/shop_catalog.tres")
const BACKPACK := preload("res://data/upgrades/backpack.tres")
const MEDKIT := preload("res://data/items/medkit.tres")
const GRENADE := preload("res://data/items/grenade.tres")
const RAGE := preload("res://data/items/damage_boost.tres")
const SMG_AMMO := preload("res://data/items/smg_ammo.tres")

var _failures := 0
var _save: Node


func _initialize() -> void:
	await process_frame  # let SaveService load
	_save = root.get_node("SaveService")
	var router: Node = root.get_node("SceneRouter")
	var backup: Dictionary = _save.data.to_dict()

	# --- Save v3 --------------------------------------------------------------------
	_check(SaveData.VERSION == 3, "save format is v3")
	var v2 := {"version": 2, "coins": 9, "stats": {"runs_played": 4}}
	var migrated := SaveData.migrate(v2)
	_check(migrated["version"] == 3 and migrated["stash"] == {} and migrated["last_loadout"] == {}, "v2 migrates to v3 with an empty stash and loadout")
	var from_v1 := SaveData.from_dict({"version": 1, "coins": 5})
	_check(from_v1.coins == 5 and from_v1.stash.is_empty() and from_v1.stats["runs_played"] == 0, "v1 still migrates all the way")
	var parsed := SaveData.from_dict({"version": 3, "stash": {"medkit": 3, "grenade": 2.0, "bad": "x", "neg": -1, "zero": 0}, "last_loadout": {"medkit": 1}})
	_check(parsed.stash == {&"medkit": 3, &"grenade": 2} and parsed.last_loadout == {&"medkit": 1}, "stash parsing keeps positive counts only")
	var round_trip := SaveData.from_dict(parsed.to_dict())
	_check(round_trip.stash == parsed.stash and round_trip.last_loadout == parsed.last_loadout, "stash and loadout round-trip through JSON data")
	_check(BACKPACK.value_text() == "+2 slots" and BACKPACK in CATALOG.upgrades, "Backpack upgrade in the catalog")
	_check(CATALOG.bag_slots(8, func(_id): return 0) == 8 and CATALOG.bag_slots(8, func(id): return 2 if id == &"backpack" else 0) == 12, "bag slots: 8 base, +2 per Backpack level")

	# --- Item purchases ---------------------------------------------------------------
	_save.data = SaveData.new()
	_save.data.coins = 100
	_check(_save.purchase_item(&"medkit", 1, 30), "affordable item bought")
	_check(_save.get_coins() == 70 and _save.get_stash_count(&"medkit") == 1 and _save.has_stash(), "coins spent, item in the stash")
	_check(not _save.purchase_item(&"medkit", 1, 80) and _save.get_coins() == 70 and _save.get_stash_count(&"medkit") == 1, "unaffordable item refused, nothing changes")
	var reloaded: SaveData = _save._load()
	_check(reloaded.coins == 70 and reloaded.stash.get(&"medkit") == 1, "purchase is on disk")

	# --- take_loadout -----------------------------------------------------------------
	_save.data.stash = _counts({&"medkit": 3, &"grenade": 1})
	var taken: Dictionary = _save.take_loadout({&"medkit": 2, &"grenade": 5, &"damage_boost": 1, &"nothing": 0})
	_check(taken == {&"medkit": 2, &"grenade": 1}, "takes what the stash has, clamped")
	_check(_save.data.stash == {&"medkit": 1}, "taken items leave the stash")
	_check(_save.data.last_loadout == {&"medkit": 2, &"grenade": 5, &"damage_boost": 1}, "the choice is remembered as asked")
	reloaded = _save._load()
	_check(reloaded.stash == {&"medkit": 1} and reloaded.last_loadout.size() == 3, "taking is saved")

	# --- Shop item rows ---------------------------------------------------------------
	_save.data = SaveData.new()
	_save.data.coins = 100
	var menu: Control = load(MENU_SCENE).instantiate()
	root.add_child(menu)
	await process_frame
	var shop: Control = menu.get_node("%ShopPanel")
	shop.open()
	var med_row: ShopRow = shop.get_item_row(MEDKIT)
	_check(med_row != null and med_row.get_button_text() == "$ %d" % MEDKIT.shop_price and med_row.is_buyable(), "medkit sold in the shop")
	med_row.buy_pressed.emit()
	_check(_save.get_stash_count(&"medkit") == 1 and _save.get_coins() == 100 - MEDKIT.shop_price, "buying puts a medkit in the stash")
	shop.get_item_row(SMG_AMMO).buy_pressed.emit()
	_check(_save.get_stash_count(&"smg_ammo") == SMG_AMMO.shop_bundle, "ammo is sold in bundles (%d)" % SMG_AMMO.shop_bundle)
	_save.data.coins = 0
	_save.coins_changed.emit(0)
	_check(not med_row.is_buyable(), "unaffordable item row disabled")
	shop.close()

	# --- PREPARE panel ----------------------------------------------------------------
	var prepare: Control = menu.get_node("%PreparePanel")
	_save.data.stash = _counts({&"medkit": 5, &"grenade": 4, &"smg_ammo": 300})
	_save.data.last_loadout = _counts({&"medkit": 4, &"grenade": 2, &"smg_ammo": 300, &"damage_boost": 1})
	menu.get_node("%PlayButton").pressed.emit()
	_check(prepare.visible, "PLAY with a stash opens PREPARE")
	_check(prepare.get_count(MEDKIT) == 4 and prepare.get_count(GRENADE) == 2 and prepare.get_count(SMG_AMMO) == 300, "last loadout restored")
	_check(prepare.get_count(RAGE) == 0, "items not in the stash restore as 0")
	_check(prepare.used_slots() == 2 + 1 + 3 and prepare.get_node("%BagLabel").text == "BAG 6/8", "slots counted per stack (6/8)")
	_check(prepare.increase(MEDKIT) and not prepare.increase(MEDKIT), "+ stops at the stash count")
	_check(prepare.decrease(GRENADE) and prepare.get_count(GRENADE) == 1, "- removes one")
	_check(prepare.decrease(SMG_AMMO) and prepare.get_count(SMG_AMMO) == 300 - SMG_AMMO.shop_bundle, "ammo - steps by a shop bundle")
	_check(prepare.increase(SMG_AMMO) and prepare.get_count(SMG_AMMO) == 300, "ammo + steps by a shop bundle, up to the stash")
	_check(not prepare.increase(SMG_AMMO), "ammo + stops at the stash count")
	_save.data.stash[&"smg_ammo"] = 2000
	var presses := 0
	while prepare.increase(SMG_AMMO):
		presses += 1
	_check(presses == (600 - 300) / SMG_AMMO.shop_bundle, "%d presses of + fill the bag" % presses)
	_check(prepare.used_slots() == 8 and not prepare.can_add(SMG_AMMO), "+ stops when the bag is full")
	_check(prepare.get_loadout() == {&"medkit": 5, &"grenade": 1, &"smg_ammo": 5 * 120}, "loadout reports the picks")

	prepare.close()
	_save.data.last_loadout = _counts({&"medkit": 99, &"smg_ammo": 5000})
	prepare.open()
	_check(prepare.get_count(MEDKIT) == 5, "restore clamps to the stash")
	_check(prepare.used_slots() == 8 and prepare.get_count(SMG_AMMO) == 6 * 120, "restore clamps to the bag; consumables before ammo")
	prepare.close()
	_save.data.upgrade_levels[&"backpack"] = 1
	prepare.open()
	_check(prepare.bag_capacity() == 10 and prepare.get_count(SMG_AMMO) == 8 * 120, "Backpack lv1: 10 slots in PREPARE")
	var started: Array = []
	prepare.start_requested.disconnect(router.start_run)  # don't change scenes in the test
	prepare.start_requested.connect(func(loadout: Dictionary) -> void: started.append(loadout))
	prepare.get_node("%StartButton").pressed.emit()
	_check(started.size() == 1 and started[0] == prepare.get_loadout(), "START hands the loadout over")
	_check(_save.get_stash_count(&"medkit") == 5, "nothing leaves the stash until the run starts")
	prepare.close()
	menu.queue_free()
	await process_frame

	# --- A run brings the loadout ------------------------------------------------------
	_save.data = SaveData.new()
	_save.data.upgrade_levels[&"backpack"] = 1
	_save.data.stash = _counts({&"medkit": 3, &"grenade": 1, &"damage_boost": 1})
	router._run_loadout = {&"medkit": 2, &"grenade": 1, &"damage_boost": 5}
	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	await process_frame
	run.get_node("WaveDirector").stop()
	var player: Player = run.get_node("World/Player")
	var bag: Inventory = run.state.inventory
	_check(bag.capacity == 10, "Backpack lv1: 10 bag slots in the run")
	_check(bag.count_of(MEDKIT) == 2 and bag.count_of(GRENADE) == 1 and bag.count_of(RAGE) == 1, "loadout is in the bag")
	_check(_save.data.stash == {&"medkit": 1}, "brought items left the stash")
	_check(router.take_run_loadout().is_empty(), "loadout handed over once")
	player.health.take_damage(1e9)
	await process_frame
	_check(bag.used_slots() == 0 and _save.data.stash == {&"medkit": 1}, "death loses what was brought, the stash keeps the rest")
	_check(_save.data.last_loadout == {&"medkit": 2, &"grenade": 1, &"damage_boost": 5}, "RETRY's loadout is remembered")
	run.queue_free()
	await process_frame

	# --- Overflow lands on the ground --------------------------------------------------
	_save.data = SaveData.new()
	_save.data.stash = _counts({&"smg_ammo": 2000})
	router._run_loadout = {&"smg_ammo": 2000}
	run = load(RUN_SCENE).instantiate()
	root.add_child(run)
	await process_frame
	run.get_node("WaveDirector").stop()
	var pickups: PickupManager = run.get_node("Pickups")
	_check(run.state.inventory.count_of(SMG_AMMO) == 8 * 120 and pickups.count_on_ground(SMG_AMMO) == 2000 - 8 * 120, "what doesn't fit is dropped at the player's feet")
	run.queue_free()
	await process_frame

	_save.data = SaveData.from_dict(backup)
	_save.save()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _counts(raw: Dictionary) -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for key in raw:
		counts[StringName(key)] = raw[key]
	return counts


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
