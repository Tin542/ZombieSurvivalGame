class_name ZombieDef
extends Resource
## Static data for one zombie type. Per-wave scaling is applied at spawn time,
## never written back here (these resources are shared).

@export var id: StringName

@export_group("Stats")
@export var max_hp: float = 10.0
@export var move_speed: float = 30.0
@export var contact_damage: float = 5.0
@export var attack_interval: float = 0.8
## Body radius in pixels, used for separation, hits and contact range.
@export var radius: float = 5.0

@export_group("Rewards")
@export var coin_value: int = 1

@export_group("Visuals")
## Drawn with its bottom edge at the zombie's feet.
@export var texture: Texture2D
@export var tint: Color = Color.WHITE
