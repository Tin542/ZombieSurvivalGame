class_name PreparePanel
extends Control
## Loadout picker shown before a run when the stash has items: +/- per item,
## limited by what the stash holds and by the bag's slots. Opens with the
## last loadout (clamped to the stash and the bag). START reports the choice;
## the run takes the items from the stash when it begins.

## `loadout`: item id -> units to bring.
signal start_requested(loadout: Dictionary)
signal closed

@export var catalog: ShopCatalog

## Units picked per item.
var _counts: Dictionary[ItemDef, int] = {}
var _rows: Dictionary[ItemDef, Row] = {}
var _capacity := RunState.BASE_BAG_SLOTS

@onready var _bag_label: Label = %BagLabel
@onready var _list: VBoxContainer = %List
@onready var _empty_label: Label = %EmptyLabel


class Row:
	var root: PanelContainer
	var info: Label
	var count: Label
	var minus: Button
	var plus: Button


func _ready() -> void:
	%BackButton.pressed.connect(close)
	%StartButton.pressed.connect(func() -> void: start_requested.emit(get_loadout()))
	_build()
	hide()


## Shows the panel with the last loadout, fitted to the stash and the bag.
func open() -> void:
	_capacity = catalog.bag_slots(RunState.BASE_BAG_SLOTS, SaveService.get_upgrade_level)
	var last := SaveService.data.last_loadout
	_counts.clear()
	for item in _rows:
		_counts[item] = 0
	# When the bag can't hold everything, consumables win over bulky ammo,
	# then catalog order.
	var order: Array[ItemDef] = []
	for item in _rows:
		if item.kind != ItemDef.Kind.AMMO:
			order.append(item)
	for item in _rows:
		if item.kind == ItemDef.Kind.AMMO:
			order.append(item)
	for item in order:
		var want := mini(last.get(item.id, 0), SaveService.get_stash_count(item.id))
		while want > 0 and not _fits(item, want):
			want -= 1
		_counts[item] = want
	_refresh()
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


## Item id -> units, for every item with at least one picked.
func get_loadout() -> Dictionary[StringName, int]:
	var loadout: Dictionary[StringName, int] = {}
	for item in _counts:
		if _counts[item] > 0:
			loadout[item.id] = _counts[item]
	return loadout


func get_count(item: ItemDef) -> int:
	return _counts.get(item, 0)


## + : one more of `item` (ammo: one shop bundle), as much as the stash and
## the bag allow. False if nothing could be added.
func increase(item: ItemDef) -> bool:
	if not can_add(item):
		return false
	var count := get_count(item)
	var amount := mini(_step(item), SaveService.get_stash_count(item.id) - count)
	while amount > 1 and not _fits(item, count + amount):
		amount -= 1
	_counts[item] = count + amount
	_refresh()
	return true


## - : one fewer (ammo: one shop bundle). False if none picked.
func decrease(item: ItemDef) -> bool:
	var count := get_count(item)
	if count <= 0:
		return false
	_counts[item] = count - mini(_step(item), count)
	_refresh()
	return true


func can_add(item: ItemDef) -> bool:
	var count := get_count(item)
	return _rows.has(item) and count < SaveService.get_stash_count(item.id) and _fits(item, count + 1)


## Bag slots the picked items fill (each item stacks up to its stack_limit).
func used_slots() -> int:
	var used := 0
	for item in _counts:
		used += _slots_for(item, _counts[item])
	return used


func bag_capacity() -> int:
	return _capacity


func _step(item: ItemDef) -> int:
	return maxi(item.shop_bundle, 1) if item.kind == ItemDef.Kind.AMMO else 1


func _fits(item: ItemDef, count: int) -> bool:
	return used_slots() - _slots_for(item, get_count(item)) + _slots_for(item, count) <= _capacity


func _slots_for(item: ItemDef, count: int) -> int:
	return ceili(float(count) / maxi(item.stack_limit, 1)) if count > 0 else 0


func _build() -> void:
	for item in catalog.items:
		var row := Row.new()
		row.root = PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.15, 0.13)
		style.set_content_margin_all(3.0)
		style.content_margin_left = 6.0
		row.root.add_theme_stylebox_override("panel", style)
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		row.root.add_child(hbox)

		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		hbox.add_child(text)
		var name_label := Label.new()
		name_label.text = item.display_name
		name_label.add_theme_font_size_override("font_size", 11)
		text.add_child(name_label)
		row.info = Label.new()
		row.info.add_theme_font_size_override("font_size", 9)
		row.info.add_theme_color_override("font_color", Color(0.65, 0.7, 0.62))
		text.add_child(row.info)

		row.minus = _small_button("-")
		row.minus.pressed.connect(func() -> void: decrease(item))
		hbox.add_child(row.minus)
		row.count = Label.new()
		row.count.custom_minimum_size = Vector2(28, 0)
		row.count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.count.add_theme_font_size_override("font_size", 12)
		hbox.add_child(row.count)
		row.plus = _small_button("+")
		row.plus.pressed.connect(func() -> void: increase(item))
		hbox.add_child(row.plus)

		_list.add_child(row.root)
		_rows[item] = row
		_counts[item] = 0


func _small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(26, 22)
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 12)
	return button


func _refresh() -> void:
	var any := false
	for item in _rows:
		var row := _rows[item]
		var stash := SaveService.get_stash_count(item.id)
		row.root.visible = stash > 0
		any = any or stash > 0
		row.info.text = "In stash: %d  |  %s" % [stash, item.describe()]
		row.count.text = str(get_count(item))
		row.minus.disabled = get_count(item) <= 0
		row.plus.disabled = not can_add(item)
	_empty_label.visible = not any
	_bag_label.text = "BAG %d/%d" % [used_slots(), _capacity]
