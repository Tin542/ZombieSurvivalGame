extends SceneTree
## Balance simulation: plays whole runs with the scripted bot (support/run_bot.gd)
## for a player profile and writes one JSON line per run (waves reached, coins,
## per-wave damage, loot, ammo, crates, grenades, frame cost).
## Not part of the pass/fail suite; docs/BALANCE.md summarises its numbers.
##
## "wave_reached" is the wave the bot died in (or got stuck in); "last_wave" is
## the same, except max_wave for a run that survived to the cap ("capped").
## Run (arguments after "--"):
##   godot --headless --path . --fixed-fps 60 -s res://tests/balance_sim.gd -- \
##       --profile=fresh --skill=casual --runs=5 --max-wave=20 --out=/abs/path/results.jsonl
## Profiles: fresh, smg, mid, late (see PROFILES). Skills: casual, good (see
## RunBot.configure). Each process uses its own
## save file (user://sim_<profile>_<pid>.json), so several can run at once.

const RUN_SCENE := "res://scenes/run/run.tscn"
const BOT := preload("res://tests/support/run_bot.gd")
## Longest a single wave may take before the run is abandoned (bot stuck).
const WAVE_TIMEOUT := 400.0

## Player progress at the start of each run: unlocked weapons, upgrade levels,
## and what PREPARE brings from the stash.
const PROFILES := {
	"fresh": {"weapons": [], "upgrades": {}, "loadout": {}},
	"smg": {"weapons": ["smg"], "upgrades": {}, "loadout": {}},
	"mid": {
		"weapons": ["smg", "shotgun"],
		"upgrades": {"max_hp": 2, "damage": 2, "move_speed": 1, "start_ammo": 1},
		"loadout": {"medkit": 3, "grenade": 2},
	},
	"late": {
		"weapons": ["smg", "shotgun"],
		"upgrades": {"max_hp": 5, "damage": 5, "move_speed": 4, "start_ammo": 4, "magnet": 4, "backpack": 2},
		"loadout": {"medkit": 6, "grenade": 6, "damage_boost": 2, "max_hp_boost": 2, "smg_ammo": 120},
	},
}


func _initialize() -> void:
	await process_frame  # let SaveService load
	var args := _args()
	var profile_name: String = args.get("profile", "fresh")
	var profile: Dictionary = PROFILES[profile_name]
	var skill: String = args.get("skill", "casual")
	var runs := int(args.get("runs", "3"))
	var max_wave := int(args.get("max-wave", "20"))
	var out_path: String = args.get("out", "")
	var save_service: Node = root.get_node("SaveService")
	var router: Node = root.get_node("SceneRouter")
	save_service.save_path = "user://sim_%s_%d.json" % [profile_name, OS.get_process_id()]
	save_service.save()

	var lines: PackedStringArray = []
	for r in runs:
		var data := SaveData.new()
		for id in profile["weapons"]:
			data.unlocked_weapons.append(StringName(id))
		for id in profile["upgrades"]:
			data.upgrade_levels[StringName(id)] = int(profile["upgrades"][id])
		for id in profile["loadout"]:
			data.stash[StringName(id)] = int(profile["loadout"][id])
		save_service.data = data
		router._run_loadout = (profile["loadout"] as Dictionary).duplicate()

		var run: Node = load(RUN_SCENE).instantiate()
		var bot: Node = BOT.new()
		bot.configure(skill)
		root.add_child(run)
		run.add_child(bot)
		bot.attach(run)
		var director: WaveDirector = run.get_node("WaveDirector")
		var wave_seen := 0
		var wave_time := 0.0
		var abandoned := false
		while not bot.died and director.wave <= max_wave:
			await physics_frame
			if director.wave != wave_seen:
				wave_seen = director.wave
				wave_time = 0.0
			wave_time += 1.0 / Engine.physics_ticks_per_second
			if wave_time > WAVE_TIMEOUT:
				abandoned = true
				break
		var report: Dictionary = bot.report()
		report["profile"] = profile_name
		report["skill"] = skill
		report["run"] = r
		report["capped"] = not bot.died and not abandoned
		# A capped run stops as wave max_wave + 1 starts: its last wave is max_wave.
		report["last_wave"] = max_wave if report["capped"] else report["wave_reached"]
		report["abandoned"] = abandoned
		report["banked_coins"] = save_service.data.coins
		lines.append(JSON.stringify(report))
		print("%s/%s run %d: wave %d, kills %d, coins %d%s" % [profile_name, skill, r, report["wave_reached"], report["kills"], report["coins"],
			" (capped)" if report["capped"] else (" (ABANDONED)" if abandoned else "")])
		run.queue_free()
		await process_frame
		await process_frame

	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		file.store_string("\n".join(lines) + "\n")
		file.close()
	for suffix in ["", ".bak", ".tmp", ".session.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_service.save_path + suffix))
	quit(0)


func _args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var pair := arg.substr(2).split("=", true, 1)
			parsed[pair[0]] = pair[1]
	return parsed
