extends Node2D
## Gameplay root. Builds and wires the run's systems and owns per-run state.
## Systems never reference their siblings; every cross-system link is made here.
##
## Physics order within a tick (process_physics_priority): Zombies (-10) move
## and rebuild the grid, then Player and its components (0) aim and fire, then
## Projectiles (10) resolve hits against fresh positions.

## Every weapon in the game, in loadout order. Locked ones are filtered out.
@export var weapon_catalog: Array[WeaponDef] = []
## Debug builds only: start with every weapon regardless of shop unlocks.
@export var debug_unlock_all_weapons: bool = false
## Zombie types the debug overlay spawns for stress tests.
@export var debug_zombie_pool: Array[ZombieDef] = []

var state := RunState.new()

@onready var _arena: Arena = $Arena
@onready var _zombies: ZombieManager = $World/Zombies
@onready var _player: Player = $World/Player
@onready var _projectiles: ProjectileManager = $Projectiles
@onready var _hud: Hud = $HUD


func _ready() -> void:
	var bounds := _arena.bounds

	_player.global_position = bounds.get_center()
	_player.set_camera_limits(bounds)
	_player.health.hp_changed.connect(_hud.set_hp)
	_player.health.died.connect(_on_player_died)
	_hud.set_hp(_player.health.hp, _player.health.max_hp)

	_zombies.setup(bounds)
	_zombies.target = _player
	_zombies.target_radius = _player.body_radius
	_zombies.target_hit.connect(_player.health.take_damage)
	_zombies.zombie_killed.connect(_on_zombie_killed)

	_projectiles.setup(bounds)
	_projectiles.zombies = _zombies

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
	overlay.projectiles = _projectiles
	overlay.spawn_requested.connect(_debug_spawn)
	overlay.clear_requested.connect(_zombies.clear)


func _debug_spawn(count: int) -> void:
	if debug_zombie_pool.is_empty():
		return
	for i in count:
		_zombies.spawn(debug_zombie_pool.pick_random())


func _on_zombie_killed(_position: Vector2, _def: ZombieDef) -> void:
	state.kills += 1


func _on_player_died() -> void:
	SaveService.add_coins(state.coins)
	SaveService.submit_wave_reached(state.wave)
	await get_tree().create_timer(1.5).timeout
	SceneRouter.go_to_main_menu()
