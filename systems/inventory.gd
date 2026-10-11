class_name Inventory
extends RefCounted
## Fixed number of slots, each empty or holding one stack of a single ItemDef
## (at most its stack_limit). Pure logic: no nodes, no saving. Adding fills
## existing stacks before empty slots and reports how much actually fit, so
## callers can leave the rest where it was (on the ground, in the stash).

signal changed

class Stack:
	var def: ItemDef
	var count: int

	func _init(item: ItemDef, amount: int) -> void:
		def = item
		count = amount


var capacity: int:
	get:
		return _slots.size()

## Each entry is a Stack or null.
var _slots: Array = []


func _init(slot_count: int = 8) -> void:
	_slots.resize(maxi(slot_count, 0))


## Grows or shrinks the slot count. Shrinking only removes empty trailing
## slots; returns false (and changes nothing) if an occupied slot would go.
func set_capacity(slot_count: int) -> bool:
	slot_count = maxi(slot_count, 0)
	for i in range(slot_count, _slots.size()):
		if _slots[i] != null:
			return false
	if slot_count != _slots.size():
		_slots.resize(slot_count)
		changed.emit()
	return true


func get_def(slot: int) -> ItemDef:
	var stack: Stack = _slots[slot]
	return stack.def if stack != null else null


func get_count(slot: int) -> int:
	var stack: Stack = _slots[slot]
	return stack.count if stack != null else 0


func is_empty_slot(slot: int) -> bool:
	return _slots[slot] == null


func used_slots() -> int:
	var used := 0
	for stack in _slots:
		if stack != null:
			used += 1
	return used


func count_of(def: ItemDef) -> int:
	var total := 0
	for stack: Stack in _slots:
		if stack != null and stack.def == def:
			total += stack.count
	return total


## How many units of `def` would still fit.
func space_for(def: ItemDef) -> int:
	if def == null:
		return 0
	var limit := maxi(def.stack_limit, 1)
	var space := 0
	for stack: Stack in _slots:
		if stack == null:
			space += limit
		elif stack.def == def:
			space += maxi(limit - stack.count, 0)
	return space


## Adds up to `amount` units, topping up existing stacks first. Returns how
## many were added (0 when full).
func add(def: ItemDef, amount: int) -> int:
	if def == null or amount <= 0:
		return 0
	var limit := maxi(def.stack_limit, 1)
	var left := amount
	for stack: Stack in _slots:
		if left == 0:
			break
		if stack != null and stack.def == def and stack.count < limit:
			var moved := mini(limit - stack.count, left)
			stack.count += moved
			left -= moved
	for i in _slots.size():
		if left == 0:
			break
		if _slots[i] == null:
			var moved := mini(limit, left)
			_slots[i] = Stack.new(def, moved)
			left -= moved
	var added := amount - left
	if added > 0:
		changed.emit()
	return added


## Removes up to `amount` units of `def`, smallest stacks first so slots free
## up as early as possible (ties: the later slot, keeping the front ones
## full). Returns how many were removed.
func take(def: ItemDef, amount: int) -> int:
	if def == null or amount <= 0:
		return 0
	var left := amount
	while left > 0:
		var smallest := smallest_slot_where(func(item: ItemDef) -> bool: return item == def)
		if smallest == -1:
			break
		left -= _remove(smallest, left)
	var taken := amount - left
	if taken > 0:
		changed.emit()
	return taken


## Occupied slot with the smallest stack whose item passes `filter`
## (ItemDef -> bool); ties go to the later slot. -1 if none. Quick-use buttons
## use it so they empty partial stacks first, like take().
func smallest_slot_where(filter: Callable) -> int:
	var smallest := -1
	for i in _slots.size():
		var stack: Stack = _slots[i]
		if stack != null and filter.call(stack.def) and (smallest == -1 or stack.count <= _slots[smallest].count):
			smallest = i
	return smallest


## Total units of every item passing `filter` (ItemDef -> bool).
func count_where(filter: Callable) -> int:
	var total := 0
	for stack: Stack in _slots:
		if stack != null and filter.call(stack.def):
			total += stack.count
	return total


## Removes up to `amount` units from one slot. Returns how many were removed.
func remove_at(slot: int, amount: int) -> int:
	if slot < 0 or slot >= _slots.size() or amount <= 0 or _slots[slot] == null:
		return 0
	var removed := _remove(slot, amount)
	changed.emit()
	return removed


func clear() -> void:
	var had_items := used_slots() > 0
	_slots.fill(null)
	if had_items:
		changed.emit()


## Slot contents in order, as plain data: [{"id": String, "count": int}, ...].
func to_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for stack: Stack in _slots:
		if stack != null:
			entries.append({"id": String(stack.def.id), "count": stack.count})
	return entries


## Adds every entry, resolving ids with `lookup` (id -> ItemDef or null).
## Unknown ids and bad counts are skipped. Returns the units that didn't fit.
func add_entries(entries: Array, lookup: Callable) -> int:
	var overflow := 0
	for entry: Variant in entries:
		if not entry is Dictionary:
			continue
		var def: ItemDef = lookup.call(StringName(str(entry.get("id", ""))))
		var count := int(entry.get("count", 0))
		if def == null or count <= 0:
			continue
		overflow += count - add(def, count)
	return overflow


func _remove(slot: int, amount: int) -> int:
	var stack: Stack = _slots[slot]
	var removed := mini(amount, stack.count)
	stack.count -= removed
	if stack.count == 0:
		_slots[slot] = null
	return removed
