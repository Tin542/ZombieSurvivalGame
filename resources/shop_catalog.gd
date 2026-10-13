class_name ShopCatalog
extends Resource
## Everything the persistent shop sells: levelled upgrades, weapon unlocks and
## inventory items. Shared by the shop UI (what to list) and the run (which
## weapons and items exist and what owned upgrades add up to).

@export var upgrades: Array[UpgradeDef] = []
## Every weapon in the game, in loadout order. Ones with unlock_cost 0 are
## owned from the start.
@export var weapons: Array[WeaponDef] = []
## Every inventory item in the game. Ones with shop_price 0 are not sold.
@export var items: Array[ItemDef] = []

var _items_by_id: Dictionary[StringName, ItemDef] = {}


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


## Bag slots in a run: the base size plus owned Backpack levels.
func bag_slots(base: int, level_of: Callable) -> int:
	return base + roundi(bonus(UpgradeDef.Stat.BAG_SLOTS, level_of))


## Item with `id`, or null if no such item exists (e.g. an old save entry).
func find_item(id: StringName) -> ItemDef:
	if _items_by_id.size() != items.size():
		_items_by_id.clear()
		for item in items:
			_items_by_id[item.id] = item
	return _items_by_id.get(id)
