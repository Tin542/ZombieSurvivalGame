class_name ShopCatalog
extends Resource
## Everything the persistent shop sells: levelled upgrades and weapon unlocks.
## Shared by the shop UI (what to list) and the run (which weapons exist and
## what owned upgrades add up to).

@export var upgrades: Array[UpgradeDef] = []
## Every weapon in the game, in loadout order. Ones with unlock_cost 0 are
## owned from the start.
@export var weapons: Array[WeaponDef] = []


## Total bonus for `stat` from all owned upgrade levels. `level_of` maps an
## upgrade id to its owned level (normally SaveService.get_upgrade_level).
## Levels above max_level (e.g. after a rebalance) are capped.
func bonus(stat: UpgradeDef.Stat, level_of: Callable) -> float:
	var total := 0.0
	for upgrade in upgrades:
		if upgrade.stat == stat:
			var level: int = clampi(level_of.call(upgrade.id), 0, upgrade.max_level)
			total += upgrade.value_per_level * level
	return total
