class_name WeaponDef
extends Resource
## Static data for one weapon. Shop upgrades are applied as multipliers by the
## run, never written back here.

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D

@export_group("Damage")
@export var damage: float = 5.0
## Seconds between shots.
@export var fire_interval: float = 0.3
@export var projectiles_per_shot: int = 1
@export_range(0.0, 90.0) var spread_degrees: float = 0.0
@export var projectile_speed: float = 300.0
## Auto-aim only engages zombies within this distance.
@export var attack_range: float = 150.0
## How many extra zombies a projectile passes through.
@export var pierce: int = 0
## Pixels each hit pushes a zombie along the shot direction.
@export var knockback: float = 2.0

@export_group("Ammo")
@export var magazine_size: int = 12
@export var reload_time: float = 1.0
@export var infinite_ammo: bool = false
## Reserve ammo cap (ignored when infinite_ammo).
@export var max_reserve_ammo: int = 120
## Reserve ammo at the start of a run (clamped to max_reserve_ammo).
@export var start_reserve_ammo: int = 60

@export_group("Shop")
## Coins to unlock permanently. 0 = unlocked from the start.
@export var unlock_cost: int = 0
