class_name SpatialGrid
extends RefCounted
## Uniform grid over a fixed rectangle for fast neighbour / radius queries.
## Rebuilt from scratch each tick with a counting sort: O(items + cells), no
## per-frame allocations once warmed up. Stores indices into a caller-owned
## positions array.

## Output buffer of the last query. Only the first `result_count` entries are
## valid, and only until the next query (queries must not be nested).
var results := PackedInt32Array()
var result_count := 0

var _origin: Vector2
var _inv_cell: float
var _cols: int
var _rows: int
## Size cells + 1. After rebuild, cell c spans [_cell_start[c], _cell_start[c + 1]).
var _cell_start := PackedInt32Array()
var _cell_items := PackedInt32Array()
var _item_cell := PackedInt32Array()
var _positions := PackedVector2Array()


func _init(bounds: Rect2, cell_size: float) -> void:
	_origin = bounds.position
	_inv_cell = 1.0 / cell_size
	_cols = maxi(ceili(bounds.size.x * _inv_cell), 1)
	_rows = maxi(ceili(bounds.size.y * _inv_cell), 1)
	_cell_start.resize(_cols * _rows + 1)


## Re-buckets the first `count` positions. Positions outside the bounds are
## clamped into the edge cells.
func rebuild(positions: PackedVector2Array, count: int) -> void:
	_positions = positions
	var cells := _cols * _rows
	_cell_start.fill(0)
	if _item_cell.size() < count:
		_item_cell.resize(count)
		_cell_items.resize(count)

	for i in count:
		var c := _cell_index(positions[i])
		_item_cell[i] = c
		_cell_start[c] += 1

	# Inclusive prefix sum: _cell_start[c] becomes the end of cell c.
	var running := 0
	for c in cells:
		running += _cell_start[c]
		_cell_start[c] = running
	_cell_start[cells] = count

	# Fill each cell backwards from its end; afterwards _cell_start[c] is its start.
	for i in count:
		var c := _item_cell[i]
		_cell_start[c] -= 1
		_cell_items[_cell_start[c]] = i


## Collects indices whose position lies within `radius` of `center` into
## `results`. Returns the count.
func query_radius(center: Vector2, radius: float) -> int:
	result_count = 0
	var r2 := radius * radius
	var min_x := clampi(int((center.x - radius - _origin.x) * _inv_cell), 0, _cols - 1)
	var max_x := clampi(int((center.x + radius - _origin.x) * _inv_cell), 0, _cols - 1)
	var min_y := clampi(int((center.y - radius - _origin.y) * _inv_cell), 0, _rows - 1)
	var max_y := clampi(int((center.y + radius - _origin.y) * _inv_cell), 0, _rows - 1)

	for cy in range(min_y, max_y + 1):
		var row := cy * _cols
		for cx in range(min_x, max_x + 1):
			var c := row + cx
			for k in range(_cell_start[c], _cell_start[c + 1]):
				var index := _cell_items[k]
				if center.distance_squared_to(_positions[index]) > r2:
					continue
				if result_count == results.size():
					results.resize(result_count * 2 + 16)
				results[result_count] = index
				result_count += 1
	return result_count


func _cell_index(p: Vector2) -> int:
	var cx := clampi(int((p.x - _origin.x) * _inv_cell), 0, _cols - 1)
	var cy := clampi(int((p.y - _origin.y) * _inv_cell), 0, _rows - 1)
	return cy * _cols + cx
