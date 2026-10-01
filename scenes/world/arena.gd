class_name Arena
extends Node2D
## Fixed, bounded play area: placeholder checker floor plus solid walls.
## Will become a TileMapLayer-based scene once tile art exists; `bounds` is the
## only contract other systems rely on.

const WALL_THICKNESS := 32.0

@export var size := Vector2(1280, 768)
@export var tile_size: int = 32
@export var floor_color_a := Color(0.16, 0.17, 0.15)
@export var floor_color_b := Color(0.18, 0.19, 0.17)
@export var border_color := Color(0.35, 0.3, 0.25)

var bounds: Rect2:
	get:
		return Rect2(Vector2.ZERO, size)


func _ready() -> void:
	_build_walls()


func _draw() -> void:
	var cols := ceili(size.x / tile_size)
	var rows := ceili(size.y / tile_size)
	for y in rows:
		for x in cols:
			var rect := Rect2(x * tile_size, y * tile_size, tile_size, tile_size).intersection(bounds)
			draw_rect(rect, floor_color_a if (x + y) % 2 == 0 else floor_color_b)
	draw_rect(bounds, border_color, false, 2.0)


func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)

	var t := WALL_THICKNESS
	var rects: Array[Rect2] = [
		Rect2(-t, -t, size.x + 2.0 * t, t),
		Rect2(-t, size.y, size.x + 2.0 * t, t),
		Rect2(-t, 0.0, t, size.y),
		Rect2(size.x, 0.0, t, size.y),
	]
	for rect in rects:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = rect.get_center()
		walls.add_child(collider)
