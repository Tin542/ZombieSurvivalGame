class_name SpawnEntry
extends Resource
## One weighted zombie type in a WaveTable.

@export var zombie: ZombieDef
@export var weight: float = 1.0
## First wave (1-based) this zombie can appear in.
@export var min_wave: int = 1
