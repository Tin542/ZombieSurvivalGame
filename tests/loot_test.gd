extends SceneTree
## Headless checks for zombie loot and ground pickups: loot rolls, loot data,
## drops on kill, ammo filtered by loadout, landing before pickup, partial
## pickup when the bag is nearly full, BAG FULL, expiry, bag drops that wait
## for the player to step away, starting-ammo overflow, pool cap, death.
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/loot_test.gd
## Exits with code 1 if any check fails.

const RUN_SCENE := "res://scenes/run/run.tscn"
const WALKER := preload("res://data/zombies/walker.tres")
const PISTOL := preload("res://data/weapons/pistol.tres")
const SMG_AMMO := preload("res://data/items/smg_ammo.tres")
const SHELLS := preload("res://data/items/shotgun_ammo.tres")
const MEDKIT := preload("res://data/items/medkit.tres")
const RAGE := preload("res://data/items/damage_boost.tres")

var _failures := 0


func _initialize() -> void:
	# --- LootEntry rolls ----------------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var never := _entry(MEDKIT, 0.0, 1, 1)
	var always := _entry(SMG_AMMO, 1.0, 8, 15)
	var quarter := _entry(MEDKIT, 0.25, 1, 1)
	var never_hits := 0
	var always_ok := true
	var quarter_hits := 0
	for i in 2000:
		never_hits += never.roll(rng)
		var n := always.roll(rng)
		always_ok = always_ok and n >= 8 and n <= 15
		quarter_hits += quarter.roll(rng)
	_check(never_hits == 0, "chance 0 never drops")
	_check(always_ok, "chance 1 always drops min..max")
	_check(quarter_hits > 420 and quarter_hits < 580, "chance 0.25 drops about a quarter (%d / 2000)" % quarter_hits)
	_check(_entry(null, 1.0, 1, 1).roll(rng) == 0 and _entry(MEDKIT, 1.0, 0, 0).roll(rng) == 1, "no item -> 0; bad counts clamp to 1")

	var data_ok := true
	for path in ["walker", "runner", "brute"]:
		var def: ZombieDef = load("res://data/zombies/%s.tres" % path)
		data_ok = data_ok and not def.loot.is_empty()
		for entry in def.loot:
			data_ok = data_ok and entry.item != null and entry.chance > 0.0 and entry.chance <= 1.0 and entry.min_count <= entry.max_count
	_check(data_ok, "every zombie has a valid loot table")

	# --- Run setup ---------------------------------------------------------------
	var run: Node = load(RUN_SCENE).instantiate()
	run.debug_unlock_all_weapons = true  # pistol + SMG + shotgun, so ammo loot counts
	root.add_child(run)
	await process_frame
	run.get_node("WaveDirector").stop()
	var zombies: ZombieManager = run.get_node("World/Zombies")
	var pickups: PickupManager = run.get_node("Pickups")
	var player: Player = run.get_node("World/Player")
	var hud: Hud = run.get_node("HUD")
	var inventory: Inventory = run.state.inventory
	zombies.clear()
	zombies.target = null  # zombies stand still
	player.weapons.set_physics_process(false)
	player.health.set_max_hp(1e9)
	var home := player.global_position
	inventory.clear()

	# --- Kills drop loot -----------------------------------------------------------
	var looter: ZombieDef = WALKER.duplicate()
	looter.loot = [_entry(MEDKIT, 1.0, 2, 2), _entry(SMG_AMMO, 1.0, 10, 10)]
	var kill_at := home + Vector2(150, 0)
	zombies.spawn_at(looter, kill_at)
	zombies.damage(0, 1e9)
	_check(pickups.count_on_ground(MEDKIT) == 2 and pickups.count_on_ground(SMG_AMMO) == 10, "kill drops every successful roll")
	var near := true
	for i in pickups.active_count():
		near = near and pickups.get_pickup_position(i).distance_to(kill_at) <= pickups.scatter + 0.01
	_check(near, "loot lands around the kill")
	_check(not pickups.is_pickup_landed(0), "loot pops out before it can be taken")

	var pistol_only: Array[WeaponDef] = [PISTOL]
	var full_loadout: Array[WeaponDef] = player.weapons.loadout()
	player.weapons.set_loadout(pistol_only)
	pickups.clear()
	await _frames(2)  # the first kill's slot is compacted on the next tick
	zombies.spawn_at(looter, kill_at)
	zombies.damage(0, 1e9)
	_check(pickups.count_on_ground(SMG_AMMO) == 0 and pickups.count_on_ground(MEDKIT) == 2, "no ammo for weapons the player doesn't carry")
	player.weapons.set_loadout(full_loadout)

	# --- Walking over loot -----------------------------------------------------------
	player.global_position = pickups.get_pickup_position(0)
	await _frames(1)
	_check(inventory.count_of(MEDKIT) == 0, "can't grab loot mid-air")
	await _frames(30)
	_check(inventory.count_of(MEDKIT) == 2 and pickups.active_count() == 0, "landed loot goes into the bag")
	_check(hud.get_node("%Toast").text == "+2 MEDKIT", "HUD shows what was picked up")
	player.global_position = home

	# --- Partial pickup + BAG FULL -----------------------------------------------------
	inventory.clear()
	inventory.add(RAGE, 21)  # 7 slots
	inventory.add(SMG_AMMO, 115)  # last slot, 5 short of a full stack
	var spot := home + Vector2(0, 120)
	pickups.spawn(spot, SMG_AMMO, 12)
	await _frames(30)
	player.global_position = pickups.get_pickup_position(0)
	await _frames(2)
	_check(inventory.count_of(SMG_AMMO) == 120 and pickups.get_pickup_count(0) == 7, "bag takes what fits (5), 7 stay on the ground")
	await _frames(70)
	_check(pickups.active_count() == 1 and hud.get_node("%Toast").text == "BAG FULL", "full bag: pickup stays, BAG FULL")
	player.global_position = home
	await _frames(1)

	# --- Expiry -----------------------------------------------------------------------
	pickups.clear()
	pickups.lifetime = 1.0
	pickups.spawn(spot, MEDKIT, 1)
	await _frames(50)
	_check(pickups.active_count() == 1, "pickup still there before lifetime")
	await _frames(15)
	_check(pickups.active_count() == 0, "pickup expires after lifetime")
	pickups.lifetime = 30.0

	# --- Dropping from the bag ----------------------------------------------------------
	inventory.clear()
	inventory.add(MEDKIT, 3)
	var dropped: int = run.drop_item(0)
	_check(dropped == 3 and inventory.count_of(MEDKIT) == 0 and pickups.count_on_ground(MEDKIT) == 3, "DROP puts the stack on the ground")
	await _frames(60)
	_check(inventory.count_of(MEDKIT) == 0, "dropped stack isn't picked straight back up")
	var drop_spot := pickups.get_pickup_position(0)
	player.global_position = drop_spot + Vector2(40, 0)
	await _frames(2)
	player.global_position = drop_spot
	await _frames(2)
	_check(inventory.count_of(MEDKIT) == 3 and pickups.active_count() == 0, "after stepping away it can be picked up again")
	player.global_position = home

	# --- Starting ammo overflow ------------------------------------------------------------
	inventory.clear()
	inventory.add(RAGE, 24)  # bag completely full
	run._stock_starting_ammo()
	var kit: Dictionary = player.weapons.starting_ammo()
	var all_on_ground := true
	for item: ItemDef in kit:
		all_on_ground = all_on_ground and pickups.count_on_ground(item) == kit[item]
	_check(not kit.is_empty() and all_on_ground, "starting ammo that doesn't fit lands at the player's feet")
	pickups.clear()

	# --- Pool cap -----------------------------------------------------------------------------
	pickups.max_pickups = 5
	for n in range(1, 8):
		pickups.spawn(spot, SHELLS, n)
	_check(pickups.active_count() == 5 and pickups.get_pickup_count(0) == 3, "full pool drops the oldest pickup")
	pickups.max_pickups = 96
	pickups.clear()

	# --- Death ----------------------------------------------------------------------------------
	pickups.spawn(home, MEDKIT, 1)
	await _frames(30)
	player.global_position = home + Vector2(100, 0)
	await _frames(1)
	player.health.take_damage(1e12)
	player.global_position = home
	await _frames(30)
	_check(pickups.active_count() == 1, "no pickups after death")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _entry(item: ItemDef, chance: float, low: int, high: int) -> LootEntry:
	var entry := LootEntry.new()
	entry.item = item
	entry.chance = chance
	entry.min_count = low
	entry.max_count = high
	return entry


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
