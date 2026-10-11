class_name ItemDef
extends Resource
## Static data for one inventory item. What using it does is decided by the
## run from `kind` and `value`; this resource only describes the item.
## Shared by every inventory and pickup, so never mutate it at runtime.

enum Kind {
	## Weapon reserve ammo; reloads draw from the inventory. See WeaponDef.ammo_item.
	AMMO,
	## Restores `value` HP when used.
	MEDKIT,
	## Thrown with the aim stick; see the Grenade group.
	GRENADE,
	## Extra weapon damage for the rest of the run, fraction (0.15 = +15%).
	DAMAGE_BOOST,
	## Extra max HP for the rest of the run, flat.
	MAX_HP_BOOST,
}

@export var id: StringName
@export var display_name: String
## Up to 4 letters, for slots and quick buttons.
@export var short_name: String
@export var icon: Texture2D
## Placeholder colour for pickups and slots until icons exist.
@export var color: Color = Color.WHITE
@export var kind: Kind
## Most units one inventory slot holds.
@export var stack_limit: int = 1
## Effect strength; meaning depends on `kind`.
@export var value: float = 0.0

@export_group("Shop")
## Coins per bundle. 0 = not sold.
@export var shop_price: int = 0
## Units per purchase.
@export var shop_bundle: int = 1

@export_group("Grenade")
@export var damage: float = 0.0
## Blast radius in pixels; damage falls off to half at the edge.
@export var radius: float = 0.0
## Seconds from throw to explosion.
@export var fuse: float = 0.0
## Farthest landing point from the thrower, in pixels.
@export var throw_range: float = 0.0


## Can be used from the bag's USE button. Ammo is drawn automatically by
## reloads and grenades are thrown with their quick button.
func is_usable_from_bag() -> bool:
	return kind in [Kind.MEDKIT, Kind.DAMAGE_BOOST, Kind.MAX_HP_BOOST]


## One-line effect text for the bag's details row.
func describe() -> String:
	match kind:
		Kind.AMMO:
			return "Reserve ammo. Reloads use it automatically."
		Kind.MEDKIT:
			return "Restores %d HP." % roundi(value)
		Kind.GRENADE:
			return "%d blast damage. Throw with the grenade button." % roundi(damage)
		Kind.DAMAGE_BOOST:
			return "+%d%% weapon damage for this run." % roundi(value * 100.0)
		Kind.MAX_HP_BOOST:
			return "+%d max HP for this run." % roundi(value)
	return ""
