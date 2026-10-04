class_name UpgradeDef
extends Resource
## One permanent, levelled shop upgrade. The run turns owned levels into stat
## bonuses via ShopCatalog.bonus(); this resource only describes the item.

enum Stat {
	## Flat extra max HP per level.
	MAX_HP,
	## Extra weapon damage, as a fraction per level (0.1 = +10%).
	DAMAGE,
	## Extra move speed, fraction per level.
	MOVE_SPEED,
	## Extra coin magnet radius, fraction per level.
	MAGNET,
	## Extra starting reserve ammo, fraction per level.
	START_AMMO,
}

@export var id: StringName
@export var display_name: String
## Shown under the name; "%s" is replaced with the per-level value text.
@export var description: String
@export var icon: Texture2D
@export var stat: Stat
@export var value_per_level: float = 0.1
@export var max_level: int = 5

@export_group("Cost")
@export var base_cost: int = 50
## Each level costs this much more than the previous one (multiplicative).
@export var cost_growth: float = 1.5


## Price of buying the level after `owned_level`. Only valid below max_level.
func cost_for_level(owned_level: int) -> int:
	return roundi(base_cost * pow(cost_growth, owned_level))


func is_maxed(owned_level: int) -> bool:
	return owned_level >= max_level


## Human-readable per-level value, e.g. "+15 HP" or "+10%".
func value_text() -> String:
	if stat == Stat.MAX_HP:
		return "+%d HP" % roundi(value_per_level)
	return "+%d%%" % roundi(value_per_level * 100.0)
