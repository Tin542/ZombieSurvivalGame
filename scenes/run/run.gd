extends Node2D
## Gameplay root. Builds and wires the run's systems and owns per-run state.
## Systems never reference their siblings; every cross-system link is made here.
##
## Physics order within a tick (process_physics_priority): WaveDirector (-30)
## advances the wave loop, Spawner (-20) adds zombies, Zombies (-10) move and
## rebuild the grid, then Player and its components (0) aim and fire, then
## Projectiles (10) resolve hits against fresh positions, then Coins (20)
## home in on the player and get collected, then Supplies (25) check crate
## pickups.

## Debug overlay bursts use at least this wave, so every zombie type shows up.
const DEBUG_BURST_MIN_WAVE := 10
## Seconds between death and the game-over screen, so the death reads first.
const GAME_OVER_DELAY := 1.0
## Hurt vibration length (ms) and the minimum gap between buzzes, so a crowd
## landing hits every frame doesn't keep the motor running.
const HURT_VIBRATION_MS := 40
const HURT_VIBRATION_COOLDOWN := 0.35

## Shop items: weapons (in loadout order; locked ones are filtered out) and
## the upgrades whose owned levels are applied at the start of the run.
@export var catalog: ShopCatalog
## Debug builds only: start with every weapon regardless of shop unlocks.
@export var debug_unlock_all_weapons: bool = false
## Difficulty curve: zombie count, type mix and scaling per wave.
@export var wave_table: WaveTable

var state := RunState.new()

var _last_vibration_ms := -100000
## Run coins already added to SaveService (progress is banked in steps, see
## _bank_progress), and the best wave before this run, for the NEW BEST check.
var _banked_coins := 0
var _best_wave_before_run := 0

@onready var _arena: Arena = $Arena
@onready var _zombies: ZombieManager = $World/Zombies
@onready var _director: WaveDirector = $WaveDirector
@onready var _spawner: ZombieSpawner = $Spawner
@onready var _player: Player = $World/Player
@onready var _projectiles: ProjectileManager = $Projectiles
@onready var _coins: CoinManager = $Coins
@onready var _supplies: SupplyManager = $Supplies
@onready var _hud: Hud = $HUD
@onready var _game_over: GameOverScreen = $GameOver


func _ready() -> void:
	_best_wave_before_run = SaveService.data.best_wave
	var bounds := _arena.bounds

	_player.global_position = bounds.get_center()
	_player.set_camera_limits(bounds)
	_player.health.hp_changed.connect(_hud.set_hp)
	_player.health.damaged.connect(_hud.flash_damage.unbind(1))
	_player.health.died.connect(_on_player_died)
	_player.health.damaged.connect(_vibrate_on_hurt.unbind(1))
	_game_over.retry_pressed.connect(SceneRouter.start_run)
	_game_over.menu_pressed.connect(SceneRouter.go_to_main_menu)

	_zombies.setup(bounds)
	_zombies.target = _player
	_zombies.target_radius = _player.body_radius
	_zombies.target_hit.connect(_player.health.take_damage)
	_zombies.zombie_killed.connect(_on_zombie_killed)

	_spawner.setup(_zombies, _player, bounds, wave_table)
	_director.setup(_spawner, _zombies, wave_table)
	_director.wave_started.connect(_on_wave_started)
	_director.wave_cleared.connect(_on_wave_cleared)
	_director.break_started.connect(_hud.show_break)
	_director.break_started.connect(_on_break_started)
	_director.remaining_changed.connect(_hud.set_remaining)
	_hud.skip_break_pressed.connect(_director.skip_break)

	_projectiles.setup(bounds)
	_projectiles.zombies = _zombies

	_coins.setup(bounds)
	_coins.target = _player
	_coins.collected.connect(state.add_coins)
	state.coins_changed.connect(_hud.set_coins)
	_hud.set_coins(state.coins)

	_supplies.setup(bounds)
	_supplies.target = _player
	_supplies.collected.connect(_on_supply_collected)

	var weapons := _player.weapons
	_player.aim.zombies = _zombies
	weapons.projectile_requested.connect(_projectiles.spawn)
	weapons.weapon_changed.connect(_hud.set_weapon)
	weapons.ammo_changed.connect(_hud.set_ammo)
	weapons.reload_started.connect(_hud.show_reload)
	_hud.switch_weapon_pressed.connect(weapons.cycle_weapon)

	_apply_upgrades()
	_hud.set_hp(_player.health.hp, _player.health.max_hp)
	_hud.set_fps_visible(SaveService.get_setting("show_fps"))
	weapons.set_loadout(_build_loadout())
	_hud.set_switch_visible(weapons.weapon_count() > 1)

	if OS.is_debug_build():
		_wire_debug_overlay()

	_director.start()


func _build_loadout() -> Array[WeaponDef]:
	var unlock_all := debug_unlock_all_weapons and OS.is_debug_build()
	var loadout: Array[WeaponDef] = []
	for weapon in catalog.weapons:
		if unlock_all or weapon.unlock_cost == 0 or SaveService.is_weapon_unlocked(weapon.id):
			loadout.append(weapon)
	return loadout


## Turns owned shop levels into this run's stats. Must run before the loadout
## is built (starting ammo) and before the HUD reads max HP.
func _apply_upgrades() -> void:
	var level_of := SaveService.get_upgrade_level
	var health := _player.health
	health.set_max_hp(health.max_hp + catalog.bonus(UpgradeDef.Stat.MAX_HP, level_of))
	_player.weapons.damage_multiplier = 1.0 + catalog.bonus(UpgradeDef.Stat.DAMAGE, level_of)
	_player.weapons.start_ammo_multiplier = 1.0 + catalog.bonus(UpgradeDef.Stat.START_AMMO, level_of)
	_player.move_speed *= 1.0 + catalog.bonus(UpgradeDef.Stat.MOVE_SPEED, level_of)
	_coins.magnet_radius *= 1.0 + catalog.bonus(UpgradeDef.Stat.MAGNET, level_of)


func _vibrate_on_hurt() -> void:
	if not SaveService.get_setting("vibration"):
		return
	var now := Time.get_ticks_msec()
	if now - _last_vibration_ms < HURT_VIBRATION_COOLDOWN * 1000.0:
		return
	_last_vibration_ms = now
	Input.vibrate_handheld(HURT_VIBRATION_MS)


func _wire_debug_overlay() -> void:
	var overlay := $DebugOverlay
	overlay.zombies = _zombies
	overlay.spawner = _spawner
	overlay.run_state = state
	overlay.projectiles = _projectiles
	overlay.coins = _coins
	overlay.spawn_requested.connect(_debug_spawn)
	overlay.clear_requested.connect(_zombies.clear)


func _debug_spawn(count: int) -> void:
	_spawner.spawn_burst(count, maxi(state.wave, DEBUG_BURST_MIN_WAVE))


func _on_wave_started(wave: int, _zombie_count: int) -> void:
	state.wave = wave
	_hud.set_wave(wave)
	_hud.hide_break()
	_hud.show_banner("WAVE %d" % wave)
	_supplies.clear()


func _on_wave_cleared(_wave: int) -> void:
	_hud.show_banner("WAVE CLEARED")
	_coins.collect_all()
	_bank_progress()


## Every break after a cleared wave is a supply phase; the countdown before
## wave 1 is not.
func _on_break_started(next_wave: int, duration: float) -> void:
	if next_wave <= 1:
		return
	_supplies.drop_crates(_plan_crates(wave_table.supply_crates), duration)
	_hud.show_toast("SUPPLIES DROPPED")


## Which crates to drop. Ammo is useless without a limited-ammo weapon, so
## then every crate is health. Otherwise one of each, and the rest go to
## whichever the player is shorter on.
func _plan_crates(count: int) -> Array[SupplyManager.Kind]:
	var kinds: Array[SupplyManager.Kind] = []
	var weapons := _player.weapons
	if not weapons.has_limited_ammo():
		for i in count:
			kinds.append(SupplyManager.Kind.HEALTH)
		return kinds
	var health := _player.health
	var hp_missing := 1.0 - health.hp / health.max_hp
	var ammo_missing := 1.0 - weapons.ammo_fill_ratio()
	var extra := SupplyManager.Kind.HEALTH if hp_missing >= ammo_missing else SupplyManager.Kind.AMMO
	for i in count:
		if i == 0:
			kinds.append(SupplyManager.Kind.HEALTH)
		elif i == 1:
			kinds.append(SupplyManager.Kind.AMMO)
		else:
			kinds.append(extra)
	return kinds


func _on_supply_collected(kind: SupplyManager.Kind, _position: Vector2) -> void:
	match kind:
		SupplyManager.Kind.HEALTH:
			var health := _player.health
			var before := health.hp
			health.heal(health.max_hp * wave_table.supply_heal_fraction)
			var gained := roundi(health.hp - before)
			_hud.show_toast("+%d HP" % gained if gained > 0 else "HP FULL")
		SupplyManager.Kind.AMMO:
			_player.weapons.add_ammo(wave_table.supply_ammo_fraction)
			_hud.show_toast("+AMMO")


## `position` is in ZombieManager space, which matches world space (both at the origin).
func _on_zombie_killed(position: Vector2, def: ZombieDef) -> void:
	state.kills += 1
	_coins.spawn(_zombies.to_global(position), def.coin_value)


func _on_player_died() -> void:
	# Coins still on the ground are lost; none can be collected after banking.
	_coins.target = null
	_supplies.target = null
	_director.stop()
	_hud.hide_break()
	# Commit results right away, so quitting during the delay loses nothing.
	_bank_progress()
	SaveService.record_run(state.kills)
	var new_best := state.wave > _best_wave_before_run
	await get_tree().create_timer(GAME_OVER_DELAY).timeout
	_hud.hide()
	_game_over.show_results(state.wave, state.kills, state.coins, SaveService.data.best_wave, new_best)


## Saves what the run has earned so far: coins not yet banked and the wave
## reached. Called at checkpoints (wave cleared, app paused or closing, death)
## so quitting mid-run never loses coins. Only the unbanked difference is
## added, so calling it repeatedly can't double-count.
func _bank_progress() -> void:
	var unbanked := state.coins - _banked_coins
	if unbanked > 0:
		SaveService.add_coins(unbanked)
		_banked_coins = state.coins
	SaveService.submit_wave_reached(state.wave)


func _notification(what: int) -> void:
	# Android may kill a backgrounded app without warning; desktop can close.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_node_ready():
			_bank_progress()
