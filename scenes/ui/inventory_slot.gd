class_name InventorySlotButton
extends Button
## One bag slot: colour swatch, short name and stack count. Pure view; the
## InventoryPanel fills it and listens for `pressed`.

const SIZE := Vector2(34, 34)
const FILL := Color(0.17, 0.18, 0.16)
const BORDER := Color(0.32, 0.3, 0.26)
const SELECTED_BORDER := Color(1.0, 0.82, 0.25)

var _swatch: ColorRect
var _name_label: Label
var _count_label: Label


func _init() -> void:
	custom_minimum_size = SIZE
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	var normal := _box(FILL, BORDER)
	for state in [&"normal", &"disabled"]:
		add_theme_stylebox_override(state, normal)
	add_theme_stylebox_override(&"hover", _box(FILL.lightened(0.08), BORDER))
	var selected := _box(FILL.lightened(0.12), SELECTED_BORDER)
	for state in [&"pressed", &"hover_pressed"]:
		add_theme_stylebox_override(state, selected)

	_swatch = ColorRect.new()
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swatch.position = Vector2(4, 4)
	_swatch.size = Vector2(8, 8)
	add_child(_swatch)

	_name_label = _make_label(Vector2(2, 13), HORIZONTAL_ALIGNMENT_CENTER)
	_count_label = _make_label(Vector2(2, 22), HORIZONTAL_ALIGNMENT_RIGHT)


func show_stack(def: ItemDef, count: int) -> void:
	disabled = false
	_swatch.visible = def != null
	_name_label.visible = def != null
	_count_label.visible = def != null and count > 1
	if def != null:
		_swatch.color = def.color
		_name_label.text = def.short_name
		_count_label.text = "x%d" % count


static func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	return box


func _make_label(at: Vector2, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = at
	label.size = Vector2(SIZE.x - 4.0, 10.0)
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	add_child(label)
	return label
