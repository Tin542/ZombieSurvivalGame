extends Node2D
## Gameplay root. Builds and wires the run's systems and owns per-run state.
## Systems never reference their siblings; every cross-system link is made here.
##
## Physics order within a tick (process_physics_priority): WaveDirector (-30)
## advances the wave loop, Spawner (-20) adds zombies, Zombies (-10) move and
## rebuild the grid, then Player and its components (0) aim and fire, then
## Projectiles (10) resolve hits against fresh positions, then Coins (20)
## home in on the player and get collected.

## Debug overlay bursts use at least this wave, so every zombie type shows up.
const DEBUG_BURST_MIN_WAVE := 10
## Seconds between death and the game-over screen, so the death reads first.
const GAME_OVER_DELAY := 1.0

## Every weapon in the game, in loadout order. Locked ones are filtered out.
@export var weapon_catalog: Array[WeaponDef] = []
## Debug builds only: start with every weapon regardless of shop unlocks.
@export var debug_unlock_all_weapons: bool = false
## Difficulty curve: zombie count, type mix and scaling per wave.
@export var wave_table: WaveTable

var state := RunState.new()

@onready var _arena: Arena = $Arena
@onready var _zombies: ZombieManager = $World/Zombies
@onready var _director: WaveDirector = $WaveDirector
@onready var _spawner: ZombieSpawner = $Spawner
@onready var _player: Player = $World/Player
@onready var _projectiles: ProjectileManager = $Projectiles
@onready var _coins: CoinManager = $Coins
@onready var _hud: Hud = $HUD
@onready var _game_over: GameOverScreen = $GameOver


func _ready() -> void:
	var bounds := _arena.bounds

	_player.global_position = bounds.get_center()
	_player.set_camera_limits(bounds)
	_player.health.hp_changed.connect(_hud.set_hp)
	_player.health.damaged.connect(_hud.flash_damage.unbind(1))
	_player.health.died.connect(_on_player_died)
	_hud.set_hp(_player.health.hp, _player.health.max_hp)
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
	_director.remaining_changed.connect(_hud.set_remaining)
	_hud.skip_break_pressed.connect(_director.skip_break)

	_projectiles.setup(bounds)
	_projectiles.zombies = _zombies

	_coins.setup(bounds)
	_coins.target = _player
	_coins.collected.connect(state.add_coins)
	state.coins_changed.connect(_hud.set_coins)
	_hud.set_coins(state.coins)

	var weapons := _player.weapons
	_player.aim.zombies = _zombies
	weapons.projectile_requested.connect(_projectiles.spawn)
	weapons.weapon_changed.connect(_hud.set_weapon)
	weapons.ammo_changed.connect(_hud.set_ammo)
	weapons.reload_started.connect(_hud.show_reload)
	_hud.switch_weapon_pressed.connect(weapons.cycle_weapon)
	weapons.set_loadout(_build_loadout())
	_hud.set_switch_visible(weapons.weapon_count() > 1)

	if OS.is_debug_build():
		_wire_debug_overlay()

	_director.start()


func _build_loadout() -> Array[WeaponDef]:
	var unlock_all := debug_unlock_all_weapons and OS.is_debug_build()
	var loadout: Array[WeaponDef] = []
	for weapon in weapon_catalog:
		if unlock_all or weapon.unlock_cost == 0 or SaveService.is_weapon_unlocked(weapon.id):
			loadout.append(weapon)
	return loadout


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


func _on_wave_cleared(_wave: int) -> void:
	_hud.show_banner("WAVE CLEARED")
	_coins.collect_all()


## `position` is in ZombieManager space, which matches world space (both at the origin).
func _on_zombie_killed(position: Vector2, def: ZombieDef) -> void:
	state.kills += 1
	_coins.spawn(_zombies.to_global(position), def.coin_value)


func _on_player_died() -> void:
	# Coins still on the ground are lost; none can be collected after banking.
	_coins.target = null
	_director.stop()
	_hud.hide_break()
	# Commit results right away, so quitting during the delay loses nothing.
	var new_best := state.wave > SaveService.data.best_wave
	SaveService.add_coins(state.coins)
	SaveService.submit_wave_reached(state.wave)
	await get_tree().create_timer(GAME_OVER_DELAY).timeout
	_hud.hide()
	_game_over.show_results(state.wave, state.kills, state.coins, SaveService.data.best_wave, new_best)
