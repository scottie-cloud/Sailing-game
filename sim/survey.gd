extends RefCounted
## The player's own chart: which squares of the bay she has surveyed. A
## square is charted once the ship has passed within sight of it, and stays
## charted.

## Size of a square in chart pixels: one nautical mile.
const CELL := 400.0

var wide := 0
var tall := 0
## One byte a square, row by row from the north: 0 unsurveyed, 1 charted.
var cells := PackedByteArray()


func _init(size: Vector2 = Vector2.ZERO) -> void:
	wide = int(ceil(size.x / CELL))
	tall = int(ceil(size.y / CELL))
	cells.resize(wide * tall)
	cells.fill(0)


func _index(p: Vector2) -> int:
	var x := int(floor(p.x / CELL))
	var y := int(floor(p.y / CELL))
	if x < 0 or y < 0 or x >= wide or y >= tall:
		return -1
	return y * wide + x


func is_known(p: Vector2) -> bool:
	var index := _index(p)
	return index >= 0 and cells[index] == 1


## Chart every square whose middle lies within radius of a point. Returns
## how many squares were new.
func reveal(p: Vector2, radius: float) -> int:
	var gained := 0
	var reach := int(ceil(radius / CELL))
	var home_x := int(floor(p.x / CELL))
	var home_y := int(floor(p.y / CELL))
	for y in range(maxi(home_y - reach, 0), mini(home_y + reach, tall - 1) + 1):
		for x in range(maxi(home_x - reach, 0), mini(home_x + reach, wide - 1) + 1):
			var middle := Vector2(x + 0.5, y + 0.5) * CELL
			if cells[y * wide + x] == 0 and middle.distance_to(p) <= radius:
				cells[y * wide + x] = 1
				gained += 1
	return gained


## True if every part of a straight line lies on charted squares.
func segment_known(a: Vector2, b: Vector2, step: float = 100.0) -> bool:
	var steps := maxi(1, int(ceil(a.distance_to(b) / step)))
	for i in steps + 1:
		if not is_known(a.lerp(b, float(i) / steps)):
			return false
	return true


## How much of the chart is surveyed, 0 to 1.
func known_fraction() -> float:
	if cells.is_empty():
		return 0.0
	return float(cells.count(1)) / cells.size()


## For the save file.
func to_text() -> String:
	return Marshalls.raw_to_base64(cells)


## Read a saved survey back. Returns false, changing nothing, if it does not fit this chart.
func from_text(text: String) -> bool:
	var raw := Marshalls.base64_to_raw(text)
	if raw.size() != cells.size():
		return false
	cells = raw
	return true
