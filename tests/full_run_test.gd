extends SceneTree
## Integration test: a scripted bot (support/run_bot.gd) plays a whole run with
## unlocked weapons, upgrades and a PREPARE loadout through five waves, then
## dies. Checks the systems together: loadout taken from the stash, wave loop,
## supply crates, loot, weapons drawing bag ammo, grenades, coins banked at
## every wave clear and on death, lifetime stats, the bag lost on death, the
## stash kept, the game-over screen, and invariants every tick (bag within
## capacity, pools within their caps). Prints frame-cost numbers.
## The player gets a huge HP pool so the run reliably reaches wave 6; balance
## is measured separately (tests/balance_sim.gd).
## Run: godot --headless --path . --fixed-fps 60 -s res://tests/full_run_test.gd
## Exits with code 1 if any check fails. The real save is restored afterwards.

const RUN_SCENE := "res://scenes/run/run.tscn"
const BOT := preload("res://tests/support/run_bot.gd")
const CATALOG := preload("res://data/shop_catalog.tres")
const MEDKIT := preload("res://data/items/medkit.tres")
const GRENADE := preload("res://data/items/grenade.tres")
const SMG := preload("res://data/weapons/smg.tres")
const WAVES := 5
const START_COINS := 50
## Game seconds allowed for waves 1-5 before the test gives up.
const TIME_LIMIT := 900.0

var _failures := 0


func _initialize() -> void:
	await process_frame  # let SaveService load
	var save: Node = root.get_node("SaveService")
	var router: Node = root.get_node("SceneRouter")
	var backup: Dictionary = save.data.to_dict()

	var data := SaveData.new()
	data.coins = START_COINS
	data.unlocked_weapons.append(&"smg")
	data.unlocked_weapons.append(&"shotgun")
	data.upgrade_levels = _counts({&"damage": 2, &"start_ammo": 1, &"backpack": 1})
	data.stash = _counts({&"medkit": 3, &"grenade": 3, &"damage_boost": 1})
	save.data = data
	save.save()
	router._run_loadout = {&"medkit": 2, &"grenade": 3}

	var run: Node = load(RUN_SCENE).instantiate()
	root.add_child(run)
	var bot: Node = BOT.new()
	bot.configure("good")
	bot.grenade_cluster = 2  # make sure grenades get used in five short waves
	run.add_child(bot)
	bot.attach(run)
	await process_frame
	var player: Player = run.get_node("World/Player")
	var director: WaveDirector = run.get_node("WaveDirector")
	var zombies: ZombieManager = run.get_node("World/Zombies")
	var pickups: PickupManager = run.get_node("Pickups")
	var supplies: SupplyManager = run.get_node("Supplies")
	var bag: Inventory = run.state.inventory
	player.health.set_max_hp(1e6)

	# --- Loadout taken at the start ---------------------------------------------------
	_check(bag.capacity == 10, "Backpack lv1: 10 bag slots")
	_check(bag.count_of(MEDKIT) == 2 and bag.count_of(GRENADE) == 3, "loadout is in the bag")
	_check(bag.count_of(SMG.ammo_item) == SMG.starting_reserve(1.25), "starting SMG ammo (Ammo Pouch lv1) is in the bag")
	_check(save.data.stash == {&"medkit": 1, &"damage_boost": 1}, "brought items left the stash, the rest stayed")
	_check(save.data.last_loadout == {&"medkit": 2, &"grenade": 3}, "loadout remembered")

	# --- Play five waves --------------------------------------------------------------
	var started: Array[int] = []
	var cleared: Array[int] = []
	var bank_ok := [true]
	var crates_dropped := [0]
	director.wave_started.connect(func(wave: int, _count: int) -> void: started.append(wave))
	director.wave_cleared.connect(func(wave: int) -> void:
		cleared.append(wave)
		# run.gd banks in its own wave_cleared handler, connected before this one.
		if save.data.coins != START_COINS + run.state.coins:
			bank_ok[0] = false)
	director.break_started.connect(func(next_wave: int, _duration: float) -> void:
		if next_wave > 1:
			crates_dropped[0] += supplies.active_count())
	var smg_ammo_low := [bag.count_of(SMG.ammo_item)]
	var invariants_ok := true
	var time := 0.0
	while director.wave <= WAVES and time < TIME_LIMIT:
		await physics_frame
		time += 1.0 / Engine.physics_ticks_per_second
		smg_ammo_low[0] = mini(smg_ammo_low[0], bag.count_of(SMG.ammo_item))
		if bag.used_slots() > bag.capacity or pickups.active_count() > pickups.max_pickups or zombies.alive_count() > zombies.max_alive:
			invariants_ok = false
	var kills_at_six: int = run.state.kills
	var report: Dictionary = bot.report()
	print("  info %d game seconds, %d kills, %d coins, peak %d zombies, tick avg %.2f ms (max %.1f)" % [
		time, run.state.kills, run.state.coins, report["peak_alive"], report["tick_ms_avg"], report["tick_ms_max"]])

	_check(time < TIME_LIMIT, "waves 1-%d finished within %d game seconds" % [WAVES, TIME_LIMIT])
	_check(started.slice(0, WAVES + 1) == [1, 2, 3, 4, 5, 6] and cleared == [1, 2, 3, 4, 5], "waves start and clear in order")
	var expected_kills := 0
	for wave in range(1, WAVES + 1):
		expected_kills += run.wave_table.zombie_count(wave)
	_check(kills_at_six >= expected_kills, "every zombie of waves 1-5 was killed (%d >= %d)" % [kills_at_six, expected_kills])
	_check(bank_ok[0], "coins banked to the save at every wave clear")
	_check(crates_dropped[0] == WAVES * run.wave_table.supply_crates, "every break after a cleared wave dropped crates")
	var crates := 0
	var dropped := 0
	var picked := 0
	var grenades := 0
	var smg_shots := 0
	for record: Dictionary in report["waves"]:
		crates += record["crates_health"] + record["crates_ammo"]
		grenades += record["grenades_thrown"]
		smg_shots += record["shots"].get("smg", 0)
		for id in record["loot_dropped"]:
			dropped += record["loot_dropped"][id]
		for id in record["loot_picked"]:
			picked += record["loot_picked"][id]
	_check(crates > 0, "the bot collected supply crates (%d)" % crates)
	_check(dropped > 0 and picked > 0, "zombies dropped loot and some was picked up (%d / %d units)" % [picked, dropped])
	_check(smg_shots > 0 and smg_ammo_low[0] < SMG.starting_reserve(1.25), "SMG fired with ammo drawn from the bag")
	_check(grenades > 0 and bag.count_of(GRENADE) < 3 + _picked(report, "grenade"), "grenades thrown from the bag (%d)" % grenades)
	_check(invariants_ok, "bag, pickups and zombies stayed within their caps every tick")
	_check(report["tick_ms_avg"] < 8.0, "average frame cost under 8 ms headless (%.2f)" % report["tick_ms_avg"])

	# --- Death ------------------------------------------------------------------------
	var stash_before: Dictionary = save.data.stash.duplicate()
	player.health.take_damage(1e9)
	await process_frame
	_check(director.phase == WaveDirector.Phase.STOPPED, "death stops the wave loop")
	_check(bag.used_slots() == 0, "the bag is lost on death")
	_check(save.data.stash == stash_before and save.data.stash.get(&"medkit") == 1, "the stash is untouched by death")
	_check(save.data.coins == START_COINS + run.state.coins, "every run coin is banked on death (%d)" % save.data.coins)
	_check(save.data.best_wave == run.state.wave and run.state.wave == WAVES + 1, "best wave recorded (%d)" % save.data.best_wave)
	_check(save.get_stat("runs_played") == 1 and save.get_stat("total_kills") == run.state.kills, "lifetime stats updated")
	var on_disk: SaveData = save._load()
	_check(on_disk.coins == save.data.coins and on_disk.stash == save.data.stash and on_disk.best_wave == save.data.best_wave, "the save on disk matches")
	var game_over: CanvasLayer = run.get_node("GameOver")
	_check(not game_over.visible, "game-over screen waits for the death delay")
	await create_timer(run.GAME_OVER_DELAY + 0.2).timeout
	_check(game_over.visible and game_over.get_node("%WaveLabel").text == "Wave reached: %d" % (WAVES + 1), "game-over screen shows the run")

	save.data = SaveData.from_dict(backup)
	save.save()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _picked(report: Dictionary, id: String) -> int:
	var total := 0
	for record: Dictionary in report["waves"]:
		total += record["loot_picked"].get(id, 0)
	return total


func _counts(raw: Dictionary) -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for key in raw:
		counts[StringName(key)] = raw[key]
	return counts


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1
