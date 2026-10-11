extends SceneTree
## Headless checks for the inventory core and item data: stacking, partial
## adds, full inventory, take/remove, capacity, entries round trip, catalog.
## Run: godot --headless --path . -s res://tests/inventory_test.gd
## Exits with code 1 if any check fails.

const CATALOG := preload("res://data/shop_catalog.tres")
const SMG_AMMO := preload("res://data/items/smg_ammo.tres")
const SHELLS := preload("res://data/items/shotgun_ammo.tres")
const MEDKIT := preload("res://data/items/medkit.tres")
const GRENADE := preload("res://data/items/grenade.tres")

var _failures := 0


func _initialize() -> void:
	# --- Item data -----------------------------------------------------------
	_check(MEDKIT.stack_limit == 3 and GRENADE.stack_limit == 3, "medkit and grenade stack to 3")
	_check(GRENADE.kind == ItemDef.Kind.GRENADE and GRENADE.radius > 0.0, "grenade has blast data")
	var smg: WeaponDef = load("res://data/weapons/smg.tres")
	var pistol: WeaponDef = load("res://data/weapons/pistol.tres")
	_check(smg.ammo_item == SMG_AMMO and pistol.ammo_item == null, "weapons point at their ammo item")
	_check(CATALOG.find_item(&"grenade") == GRENADE, "catalog finds items by id")
	_check(CATALOG.find_item(&"no_such_item") == null, "unknown id gives null")
	var ids := {}
	for item in CATALOG.items:
		ids[item.id] = true
		_check(item.stack_limit >= 1, "%s stack_limit >= 1" % item.id)
	_check(ids.size() == CATALOG.items.size(), "item ids are unique")

	# --- Stacking ------------------------------------------------------------
	# A local item, so balance changes to the real stack limits never break this.
	var ammo := ItemDef.new()
	ammo.id = &"test_ammo"
	ammo.stack_limit = 60
	var inv := Inventory.new(8)
	var changes := [0]
	inv.changed.connect(func() -> void: changes[0] += 1)
	_check(inv.capacity == 8 and inv.used_slots() == 0, "starts with 8 empty slots")
	_check(inv.add(ammo, 100) == 100, "adds 100 ammo")
	_check(inv.used_slots() == 2 and inv.get_count(0) == 60 and inv.get_count(1) == 40, "splits into 60 + 40")
	_check(inv.add(ammo, 30) == 30 and inv.get_count(1) == 60 and inv.get_count(2) == 10, "tops up the open stack first")
	_check(inv.count_of(ammo) == 130, "count_of sums stacks")
	_check(inv.add(MEDKIT, 2) == 2 and inv.get_def(3) == MEDKIT, "different item takes its own slot")
	_check(changes[0] == 3, "changed fires once per add")

	# --- Full inventory: partial add, then nothing --------------------------
	_check(inv.space_for(MEDKIT) == 1 + 4 * 3, "space_for: open stack + empty slots")
	_check(inv.add(GRENADE, 20) == 12, "partial add returns what fit (4 slots x 3)")
	_check(inv.used_slots() == 8, "inventory now full")
	_check(inv.add(GRENADE, 1) == 0 and inv.add(SHELLS, 5) == 0, "full: nothing added")
	_check(inv.add(MEDKIT, 5) == 1, "full: only the open medkit stack fills")
	var before: int = changes[0]
	inv.add(SHELLS, 1)
	_check(changes[0] == before, "no changed signal when nothing fit")

	# --- Take / remove ------------------------------------------------------
	_check(inv.take(ammo, 15) == 15, "take 15 ammo")
	_check(inv.get_count(2) == 0 and inv.is_empty_slot(2), "smallest stack drained first, slot freed")
	_check(inv.get_count(0) == 60 and inv.get_count(1) == 55, "then the next smallest")
	_check(inv.take(ammo, 999) == 115 and inv.count_of(ammo) == 0, "take more than owned returns owned")
	_check(inv.take(SHELLS, 1) == 0, "take missing item returns 0")
	_check(inv.remove_at(3, 2) == 2 and inv.get_count(3) == 1, "remove_at takes from one slot")
	_check(inv.remove_at(3, 9) == 1 and inv.is_empty_slot(3), "remove_at empties the slot")
	_check(inv.remove_at(3, 1) == 0 and inv.remove_at(99, 1) == 0, "remove_at on empty / bad slot is 0")

	# --- Capacity -----------------------------------------------------------
	var small := Inventory.new(2)
	small.add(MEDKIT, 3)
	_check(small.set_capacity(4) and small.capacity == 4, "capacity grows")
	_check(small.set_capacity(1) and small.capacity == 1, "shrinks over empty slots")
	_check(not small.set_capacity(0) and small.capacity == 1, "won't drop an occupied slot")

	# --- Entries round trip -------------------------------------------------
	var src := Inventory.new(8)
	var full: int = SMG_AMMO.stack_limit
	src.add(SMG_AMMO, full + 10)
	src.add(GRENADE, 2)
	var entries := src.to_entries()
	_check(entries == [{"id": "smg_ammo", "count": full}, {"id": "smg_ammo", "count": 10}, {"id": "grenade", "count": 2}], "to_entries is plain data")
	var copy := Inventory.new(8)
	var bad: Array = entries + [{"id": "ghost", "count": 5}, {"id": "medkit", "count": -3}, "junk"]
	_check(copy.add_entries(bad, CATALOG.find_item) == 0, "unknown ids and bad counts skipped")
	_check(copy.to_entries() == entries, "round trip keeps contents")
	var tiny := Inventory.new(1)
	_check(tiny.add_entries(entries, CATALOG.find_item) == 12, "add_entries reports overflow")

	inv.clear()
	_check(inv.used_slots() == 0, "clear empties everything")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
