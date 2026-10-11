extends SceneTree
## Headless checks for the in-game bag UI: quick buttons, pausing, slot view,
## USE / DROP, item effects, manual reload, closing, death clears the bag.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/inventory_ui_test.gd
## Exits with code 1 if any check fails.

const RUN_SCENE := "res://scenes/run/run.tscn"
const SMG_AMMO := preload("res://data/items/smg_ammo.tres")
const MEDKIT := preload("res://data/items/medkit.tres")
const GRENADE := preload("res://data/items/grenade.tres")
const RAGE := preload("res://data/items/damage_boost.tres")
const VITALITY := preload("res://data/items/max_hp_boost.tres")

var _failures := 0


func _initialize() -> void:
	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	await process_frame
	var player: Player = run.get_node("World/Player")
	var hud: Hud = run.get_node("HUD")
	var director: WaveDirector = run.get_node("WaveDirector")
	var bag: InventoryPanel = hud.bag_panel
	var inventory: Inventory = run.state.inventory
	player.weapons.set_physics_process(false)
	var medkit_button: Button = hud.get_node("%MedkitButton")
	var grenade_button: Button = hud.get_node("%GrenadeButton")

	# --- Quick buttons follow the bag --------------------------------------
	_check(inventory.capacity == 8, "run bag has 8 slots")
	_check(medkit_button.disabled and grenade_button.disabled, "quick buttons greyed out when empty")
	inventory.add(SMG_AMMO, 60)
	inventory.add(MEDKIT, 2)
	inventory.add(GRENADE, 1)
	inventory.add(RAGE, 1)
	inventory.add(VITALITY, 1)
	_check(medkit_button.text == "MED 2" and not medkit_button.disabled, "medkit button shows 2")
	_check(grenade_button.text == "GREN 1" and not grenade_button.disabled, "grenade button shows 1")

	# --- Opening pauses ------------------------------------------------------
	var break_left := director.break_time_left()
	hud.get_node("%BagButton").pressed.emit()
	_check(paused and bag.visible, "BAG button opens the bag and pauses")
	await _frames(30)
	_check(is_equal_approx(director.break_time_left(), break_left), "wave countdown frozen while paused")
	_check(bag.get_node("%TitleLabel").text == "BAG  5/8", "title shows used / capacity")
	var grid: GridContainer = bag.get_node("%Grid")
	_check(grid.get_child_count() == 8, "8 slot buttons")
	var use_button: Button = bag.get_node("%UseButton")
	var drop_button: Button = bag.get_node("%DropButton")
	_check(use_button.disabled and drop_button.disabled, "nothing selected: USE / DROP disabled")

	# --- Selection rules -------------------------------------------------------
	grid.get_child(0).pressed.emit()  # SMG ammo
	_check(bag.selected_slot() == 0, "tapping a slot selects it")
	_check(use_button.disabled and not drop_button.disabled, "ammo can be dropped, not used")
	grid.get_child(2).pressed.emit()  # grenade
	_check(use_button.disabled, "grenade isn't used from the bag")
	grid.get_child(7).pressed.emit()  # empty
	_check(bag.selected_slot() == -1, "tapping an empty slot clears the selection")

	# --- Medkit --------------------------------------------------------------
	var health := player.health
	grid.get_child(1).pressed.emit()
	use_button.pressed.emit()
	_check(inventory.count_of(MEDKIT) == 2, "medkit at full HP is not consumed")
	_check(bag.get_node("%InfoLabel").text == "HP FULL", "bag says HP FULL")
	health.take_damage(50.0)
	var hp_before := health.hp
	use_button.pressed.emit()
	_check(health.hp == hp_before + MEDKIT.value, "medkit heals %d" % MEDKIT.value)
	_check(inventory.count_of(MEDKIT) == 1 and bag.selected_slot() == 1, "one medkit used, slot stays selected")

	# --- Boosts (run only) -----------------------------------------------------
	var damage_before := player.weapons.damage_multiplier
	grid.get_child(3).pressed.emit()
	use_button.pressed.emit()
	_check(is_equal_approx(player.weapons.damage_multiplier, damage_before + RAGE.value), "rage pill adds damage")
	_check(inventory.count_of(RAGE) == 0 and bag.selected_slot() == -1, "used up: slot empties, selection cleared")
	var max_before := health.max_hp
	hp_before = health.hp
	grid.get_child(4).pressed.emit()
	use_button.pressed.emit()
	_check(health.max_hp == max_before + VITALITY.value and health.hp == hp_before + VITALITY.value, "vitality raises max HP and HP")
	_check(is_equal_approx(run.state.max_hp_bonus, VITALITY.value), "bonus recorded in run state")

	# --- Drop ------------------------------------------------------------------
	grid.get_child(0).pressed.emit()
	drop_button.pressed.emit()
	_check(inventory.count_of(SMG_AMMO) == 0, "DROP removes the whole stack")

	# --- Close (Esc) unpauses ----------------------------------------------------
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await _frames(2)
	_check(not bag.visible and not paused, "Esc closes the bag and unpauses")

	# --- Quick medkit + reload while playing -------------------------------------
	health.take_damage(30.0)
	hp_before = health.hp
	medkit_button.pressed.emit()
	_check(health.hp > hp_before and inventory.count_of(MEDKIT) == 0, "quick medkit uses one from the bag")
	_check(medkit_button.disabled, "medkit button greys out at 0")
	var weapons := player.weapons
	_check(not weapons.reload(), "reload refused with a full magazine")
	weapons._slots[weapons._current].magazine = 3
	hud.get_node("%ReloadButton").pressed.emit()
	_check(weapons.is_reloading(), "RELOAD button starts a reload")

	# --- Keyboard toggle + death -------------------------------------------------
	run.open_bag()
	_check(paused, "open_bag pauses")
	bag.get_node("%CloseButton").pressed.emit()
	_check(not paused and not bag.visible, "CLOSE unpauses")
	health.take_damage(1e9)
	_check(inventory.used_slots() == 0, "death empties the bag")
	run.open_bag()
	_check(not bag.visible and not paused, "bag can't open after death")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
