class_name LootEntry
extends Resource
## One independent drop roll in a ZombieDef's loot list: each entry is rolled
## on its own, so one kill can drop several items (or none).

@export var item: ItemDef
## Probability of dropping on a kill, 0..1.
@export_range(0.0, 1.0, 0.005) var chance: float = 0.05
@export var min_count: int = 1
@export var max_count: int = 1


## Units dropped for one kill: 0 when the roll fails, otherwise a count in
## [min_count, max_count] (at least 1).
func roll(rng: RandomNumberGenerator) -> int:
	if item == null or rng.randf() >= chance:
		return 0
	var low := maxi(mini(min_count, max_count), 1)
	var high := maxi(max_count, low)
	return rng.randi_range(low, high)
