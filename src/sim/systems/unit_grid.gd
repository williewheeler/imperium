class_name UnitGrid
extends RefCounted
## A coarse grid over where the units stand, so that "who is near here" costs a handful of units instead of all of
## them. Rebuilt from the units array whenever it is needed; it holds their indices in that array.
##
## A query gives back the units in the cell round a point and the eight cells about it, which is at least CELL tiles
## in every direction, and gives them in ascending index order. That is the order a loop over every unit would meet
## them in, so what is worked out from the answer (a sum, "the nearest", "the first") comes out exactly as it did
## when every unit was looked at. The grid is only a shortcut: it must not change what happens.
##
## Callers keep to two rules: ask only about distances well inside CELL (less the little a unit may have moved since
## the grid was built), and do not add or remove units between building it and asking.

const CELL := 2.0  # tiles
const ROW := 4096  # cells in a row of the key (the largest map is 480 tiles across)

var _cells := {}  # key -> Array of indices into the units array, ascending


func rebuild(units: Array[Unit]) -> void:
	_cells.clear()
	for i in units.size():
		var k := _key(units[i].pos)
		var cell: Array = _cells.get(k, [])
		if cell.is_empty():
			_cells[k] = cell
		cell.append(i)


## The indices of the units in the cells round `pos`, ascending.
func near(pos: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cx := maxi(0, floori(pos.x / CELL))
	var cy := maxi(0, floori(pos.y / CELL))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell: Array = _cells.get((cy + dy) * ROW + cx + dx, [])
			for i: int in cell:
				out.append(i)
	out.sort()
	return out


func _key(pos: Vector2) -> int:
	return maxi(0, floori(pos.y / CELL)) * ROW + maxi(0, floori(pos.x / CELL))
