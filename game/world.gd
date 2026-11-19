extends RefCounted
## The map: Port Phillip Bay, from real coastline data (see tools/build_bay.py).
## 400 px = 1 nautical mile, north is up the screen.

const Bay = preload("res://game/bay_data.gd")

const SIZE: Vector2 = Bay.SIZE

const PORTS := {
	"melbourne": {"name": "Melbourne"},
	"geelong": {"name": "Geelong"},
	"queenscliff": {"name": "Queenscliff"},
	"mornington": {"name": "Mornington"},
}

## The prevailing breeze: south-westerly.
const WIND_FROM_DEG := 225.0
const WIND_KN := 12.0

## Cell size of the grid used to find a pilot's route between ports.
const GRID_CELL := 400
## Pilot routes keep at least this far off the land.
const PILOT_CLEARANCE := 250.0

static var _rings: Array[PackedVector2Array] = []
static var _triangles := PackedVector2Array()
static var _grid: AStarGrid2D
static var _routes := {}


## Coastline outlines, one closed ring per piece of land.
static func land() -> Array[PackedVector2Array]:
	if _rings.is_empty():
		for points: Array in Bay.LAND_RINGS:
			_rings.append(PackedVector2Array(points))
	return _rings


## The land as triangles for drawing: three points each.
static func triangles() -> PackedVector2Array:
	if _triangles.is_empty():
		_triangles = PackedVector2Array(Bay.LAND_TRIANGLES)
	return _triangles


static func port_position(port: String) -> Vector2:
	return Bay.PORT_POSITIONS[port]


static func port_name(port: String) -> String:
	return PORTS[port]["name"]


## Every port that can be sailed to from this one.
static func destinations(port: String) -> Array[String]:
	var others: Array[String] = []
	for other: String in PORTS:
		if other != port:
			others.append(other)
	return others


static func lonlat_to_px(lon: float, lat: float) -> Vector2:
	return Vector2((lon - Bay.WEST) * Bay.PX_PER_DEGREE_LON, (Bay.NORTH - lat) * Bay.PX_PER_DEGREE_LAT)


static func in_bounds(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, SIZE).has_point(p)


static func is_land(p: Vector2) -> bool:
	for polygon in land():
		if Geometry2D.is_point_in_polygon(p, polygon):
			return true
	return false


## Land, or off the edge of the chart: nowhere a ship can be.
static func is_blocked(p: Vector2) -> bool:
	return not in_bounds(p) or is_land(p)


## Distance to the nearest land or chart edge.
static func distance_to_land(p: Vector2) -> float:
	if is_blocked(p):
		return 0.0
	var best := minf(minf(p.x, SIZE.x - p.x), minf(p.y, SIZE.y - p.y))
	for polygon in land():
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## True if the straight line from a to b touches land or leaves the chart.
static func segment_crosses_land(a: Vector2, b: Vector2, step: float = 40.0) -> bool:
	var steps := maxi(1, int(ceil(a.distance_to(b) / step)))
	for i in steps + 1:
		if is_blocked(a.lerp(b, float(i) / steps)):
			return true
	return false


# --- Pilot routes ------------------------------------------------------------

static func _cell_centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GRID_CELL


static func _pilot_grid() -> AStarGrid2D:
	if _grid != null:
		return _grid
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, int(ceil(SIZE.x / GRID_CELL)), int(ceil(SIZE.y / GRID_CELL)))
	_grid.cell_size = Vector2(GRID_CELL, GRID_CELL)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(PILOT_CLEARANCE, 0), Vector2(-PILOT_CLEARANCE, 0),
		Vector2(0, PILOT_CLEARANCE), Vector2(0, -PILOT_CLEARANCE)]
	for x in _grid.region.size.x:
		for y in _grid.region.size.y:
			var centre := _cell_centre(Vector2i(x, y))
			for offset in offsets:
				if is_blocked(centre + offset):
					_grid.set_point_solid(Vector2i(x, y), true)
					break
	return _grid


## The open-water grid cell nearest to a point.
static func _open_cell_near(p: Vector2) -> Vector2i:
	var grid := _pilot_grid()
	var home := Vector2i(int(p.x / GRID_CELL), int(p.y / GRID_CELL))
	var best := home
	var best_distance := INF
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var cell := home + Vector2i(dx, dy)
			if not grid.region.has_point(cell) or grid.is_point_solid(cell):
				continue
			var distance := p.distance_to(_cell_centre(cell))
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best


## A safe course between two ports that keeps clear of the land: the port
## positions at each end and the turning points between them. It ignores the
## wind, so it is a starting point for a plan, not the fastest course.
static func pilot_route(from_port: String, to_port: String) -> Array[Vector2]:
	var key := "%s>%s" % [from_port, to_port]
	if _routes.has(key):
		var cached: Array[Vector2] = []
		cached.assign(_routes[key])
		return cached
	var start := port_position(from_port)
	var finish := port_position(to_port)
	var raw: Array[Vector2] = [start]
	for cell in _pilot_grid().get_id_path(_open_cell_near(start), _open_cell_near(finish)):
		raw.append(_cell_centre(cell))
	raw.append(finish)
	# Keep only the corners: from each point, skip ahead to the furthest one in clear sight.
	var route: Array[Vector2] = [start]
	var i := 0
	while i < raw.size() - 1:
		var j := raw.size() - 1
		while j > i + 1 and segment_crosses_land(raw[i], raw[j], 100.0):
			j -= 1
		route.append(raw[j])
		i = j
	_routes[key] = route
	var result: Array[Vector2] = []
	result.assign(route)
	return result


static func route_length_nm(route: Array[Vector2]) -> float:
	var length := 0.0
	for i in range(1, route.size()):
		length += route[i - 1].distance_to(route[i])
	return length / 400.0
