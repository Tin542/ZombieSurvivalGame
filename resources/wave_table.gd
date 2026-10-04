class_name WaveTable
extends Resource
## Difficulty curve: how many zombies, which types and how strong for wave N
## (1-based). Tune balance here instead of in code.

@export var entries: Array[SpawnEntry] = []

@export_group("Count")
@export var base_count: int = 12
@export var count_per_wave: int = 6

@export_group("Spawn rate")
@export var base_spawn_interval: float = 0.8
## Interval is multiplied by this each wave.
@export var spawn_interval_decay: float = 0.9
@export var min_spawn_interval: float = 0.1

@export_group("Scaling")
@export var hp_growth_per_wave: float = 0.12
@export var speed_growth_per_wave: float = 0.03
@export var max_speed_multiplier: float = 1.6

@export_group("Supply phase")
## Length of the break between waves, when supply crates are on the ground.
@export var supply_duration: float = 20.0
@export var supply_crates: int = 3
## Fraction of max HP a health crate restores.
@export var supply_heal_fraction: float = 0.35
## Fraction of each limited weapon's max reserve an ammo crate restores.
@export var supply_ammo_fraction: float = 0.4


func zombie_count(wave: int) -> int:
	return base_count + count_per_wave * (wave - 1)


func spawn_interval(wave: int) -> float:
	return maxf(base_spawn_interval * pow(spawn_interval_decay, wave - 1), min_spawn_interval)


func hp_multiplier(wave: int) -> float:
	return 1.0 + hp_growth_per_wave * (wave - 1)


func speed_multiplier(wave: int) -> float:
	return minf(1.0 + speed_growth_per_wave * (wave - 1), max_speed_multiplier)


## Weighted random pick among entries unlocked at `wave`. Null if none qualify.
func pick_zombie(wave: int, rng: RandomNumberGenerator) -> ZombieDef:
	var total := 0.0
	for entry in entries:
		if entry.min_wave <= wave:
			total += entry.weight
	if total <= 0.0:
		return null

	var roll := rng.randf() * total
	var last_eligible: ZombieDef = null
	for entry in entries:
		if entry.min_wave > wave:
			continue
		last_eligible = entry.zombie
		roll -= entry.weight
		if roll <= 0.0:
			return entry.zombie
	return last_eligible
