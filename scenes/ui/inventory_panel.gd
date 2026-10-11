class_name InventoryPanel
extends Control
## Full-screen bag view. Shows an Inventory's slots, lets the player pick one
## and asks to USE or DROP it via signals; the run applies the effect and
## owns pausing. Runs while the tree is paused (process_mode ALWAYS).

signal use_requested(slot: int)
signal drop_requested(slot: int)
signal closed

const COLUMNS := 8

var _inventory: Inventory
var _selected := -1
var _buttons: Array[InventorySlotButton] = []

@onready var _title: Label = %TitleLabel
@onready var _grid: GridContainer = %Grid
@onready var _name_label: Label = %NameLabel
@onready var _info_label: Label = %InfoLabel
@onready var _use_button: Button = %UseButton
@onready var _drop_button: Button = %DropButton


func _ready() -> void:
	_grid.columns = COLUMNS
	%CloseButton.pressed.connect(close)
	_use_button.pressed.connect(func() -> void: use_requested.emit(_selected))
	_drop_button.pressed.connect(func() -> void: drop_requested.emit(_selected))
	hide()


func open(inventory: Inventory) -> void:
	if _inventory != inventory:
		if _inventory != null:
			_inventory.changed.disconnect(_refresh)
		_inventory = inventory
		_inventory.changed.connect(_refresh)
	_selected = -1
	_refresh()
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func selected_slot() -> int:
	return _selected


func select(slot: int) -> void:
	_selected = slot if slot >= 0 and slot < _inventory.capacity and not _inventory.is_empty_slot(slot) else -1
	_refresh()


## Short feedback in the details row, e.g. "HP FULL".
func show_message(text: String) -> void:
	_info_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"open_inventory")):
		close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		close()


func _refresh() -> void:
	if _inventory == null:
		return
	while _buttons.size() < _inventory.capacity:
		var button := InventorySlotButton.new()
		button.pressed.connect(_on_slot_pressed.bind(_buttons.size()))
		_grid.add_child(button)
		_buttons.append(button)
	for i in _buttons.size():
		var button := _buttons[i]
		button.visible = i < _inventory.capacity
		if button.visible:
			button.show_stack(_inventory.get_def(i), _inventory.get_count(i))
	if _selected != -1 and (_selected >= _inventory.capacity or _inventory.is_empty_slot(_selected)):
		_selected = -1
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == _selected)

	_title.text = "BAG  %d/%d" % [_inventory.used_slots(), _inventory.capacity]
	var def := _inventory.get_def(_selected) if _selected != -1 else null
	_use_button.disabled = def == null or not def.is_usable_from_bag()
	_drop_button.disabled = def == null
	if def == null:
		_name_label.text = ""
		_info_label.text = "Tap a slot."
	else:
		_name_label.text = "%s  x%d" % [def.display_name, _inventory.get_count(_selected)]
		_info_label.text = def.describe()


func _on_slot_pressed(slot: int) -> void:
	select(slot if slot != _selected else -1)
