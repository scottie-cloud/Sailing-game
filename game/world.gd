extends RefCounted
## The map: Port Phillip Bay, from real coastline data (see tools/build_bay.py).
## 400 px = 1 nautical mile, north is up the screen.

const Bay = preload("res://game/bay_data.gd")
const Tide = preload("res://sim/tide.gd")

const SIZE: Vector2 = Bay.SIZE

const PortData = preload("res://data/ports.gd")
const Features = preload("res://data/chart_features.gd")
const ShoalData = preload("res://data/shoals.gd")
const Shoals = preload("res://sim/shoals.gd")
const PLACES: Array = Features.PLACES
const LIGHTS: Array = Features.LIGHTS
const PORTS: Dictionary = PortData.PORTS
## Ports sit at least this far (px) off the land, so there is room to dock.
const PORT_CLEARANCE := 260.0

## The middle of the Rip, the narrow entrance to the bay, and the direction
## the flood tide runs through it.
const RIP_CENTRE := Vector2(6350, 12470)
const FLOOD_BEARING_DEG := 65.0

## The prevailing breeze: south-westerly.
const WIND_FROM_DEG := 225.0
const WIND_KN := 12.0

## Cell size of the grid used to find a pilot's route between ports.
const GRID_CELL := 400
## Pilot routes keep at least this far off the land.
const PILOT_CLEARANCE := 250.0

static var _rings: Array[PackedVector2Array] = []
static var _triangles := PackedVector2Array()
## Pilot grids and routes, one set for each draught asked for.
static var _grids := {}
static var _routes := {}
static var _shoals: Array[Dictionary] = []
static var _port_positions := {}

## Size (px) of the squares the coastline and land triangles are sorted into,
## so a view can ask for just the pieces near it.
const BUCKET := 1000.0
## The coarse grid from the map file: 0 all water, 1 all land, 2 shore.
static var _cells := PackedByteArray()
static var _cells_wide := 0
static var _edge_from := PackedVector2Array()
static var _edge_to := PackedVector2Array()
static var _edge_buckets := {}
static var _longest_edge := 0.0
static var _triangle_buckets := {}
static var _minimap: ImageTexture


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


## Where a port sits on the chart: its real position, moved to the nearest
## water with room to dock.
static func port_position(port: String) -> Vector2:
	if not _port_positions.has(port):
		var lon: float = PORTS[port]["lon"]
		var lat: float = PORTS[port]["lat"]
		_port_positions[port] = _roomy_water_near(lonlat_to_px(lon, lat))
	return _port_positions[port]


static func _roomy_water_near(wanted: Vector2) -> Vector2:
	if distance_to_land(wanted) >= PORT_CLEARANCE:
		return wanted
	# Search outwards in rings; in the first ring with room, take the roomiest spot.
	for ring in range(1, 81):
		var best := wanted
		var best_clearance := 0.0
		for step in 32:
			var candidate := wanted + Vector2.RIGHT.rotated(TAU * step / 32.0) * ring * 50.0
			var clearance := distance_to_land(candidate)
			if clearance >= PORT_CLEARANCE and clearance > best_clearance:
				best = candidate
				best_clearance = clearance
		if best_clearance > 0.0:
			return best.round()
	return wanted


static func port_name(port: String) -> String:
	return PORTS[port]["name"]


## How much extra trade with this port pays for being hard to reach (1.0 = none).
static func port_premium(port: String) -> float:
	return PORTS[port].get("premium", 1.0)


## The premium on a route is that of its harder end.
static func route_premium(from_port: String, to_port: String) -> float:
	return maxf(port_premium(from_port), port_premium(to_port))


## The tidal stream at a position, in knots.
static func current_kn(position: Vector2, clock_hours: float) -> Vector2:
	return Tide.current_kn(position, clock_hours, RIP_CENTRE, deg_to_rad(FLOOD_BEARING_DEG))


## Every port that can be sailed to from this one.
static func destinations(port: String) -> Array[String]:
	var others: Array[String] = []
	for other: String in PORTS:
		if other != port:
			others.append(other)
	return others


static func lonlat_to_px(lon: float, lat: float) -> Vector2:
	return Vector2((lon - Bay.WEST) * Bay.PX_PER_DEGREE_LON, (Bay.NORTH - lat) * Bay.PX_PER_DEGREE_LAT)


## Where a named place or a light from data/chart_features.gd sits on the chart.
static func feature_position(feature: Dictionary) -> Vector2:
	var lon: float = feature["lon"]
	var lat: float = feature["lat"]
	return lonlat_to_px(lon, lat)


## "Point Lonsdale Light (1863)": how a light is labelled.
static func light_label(light: Dictionary) -> String:
	var title: String = light["name"]
	if not title.contains("Light"):
		title += " Light"
	return "%s (%d)" % [title, int(light["year"])]


static func in_bounds(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, SIZE).has_point(p)


static func _load_cells() -> void:
	var rows: Array = Bay.LAND_GRID
	_cells_wide = String(rows[0]).length()
	for row: String in rows:
		for letter in row.to_ascii_buffer():
			# W, L, M in the map file.
			_cells.append(0 if letter == 87 else (1 if letter == 76 else 2))


## 0 where the square holding this point is all water, 1 all land, 2 where
## the shore runs through it. Off the chart counts as water.
static func cell_state(p: Vector2) -> int:
	if _cells.is_empty():
		_load_cells()
	if not in_bounds(p):
		return 0
	return _cells[int(p.y / Bay.LAND_GRID_CELL) * _cells_wide + int(p.x / Bay.LAND_GRID_CELL)]


static func is_land(p: Vector2) -> bool:
	var state := cell_state(p)
	if state != 2:
		return state == 1
	for polygon in land():
		if Geometry2D.is_point_in_polygon(p, polygon):
			return true
	return false


## Land, or off the edge of the chart: nowhere a ship can be.
static func is_blocked(p: Vector2) -> bool:
	return not in_bounds(p) or is_land(p)


static func _bucket_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / BUCKET)), int(floor(p.y / BUCKET)))


static func _on_chart_edge(p: Vector2) -> bool:
	return p.x <= 0.5 or p.y <= 0.5 or p.x >= SIZE.x - 0.5 or p.y >= SIZE.y - 0.5


static func _index_edges() -> void:
	for polygon in land():
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			# Where the land runs off the chart there is no shore to draw or measure to.
			if _on_chart_edge(a) and _on_chart_edge(b):
				continue
			var key := _bucket_of((a + b) / 2.0)
			if not _edge_buckets.has(key):
				_edge_buckets[key] = []
			_edge_buckets[key].append(_edge_from.size())
			_edge_from.append(a)
			_edge_to.append(b)
			_longest_edge = maxf(_longest_edge, a.distance_to(b))


## The stretches of coastline in or near a rectangle, as numbers to pass to
## edge_from() and edge_to().
static func edges_near(rect: Rect2) -> Array:
	if _edge_from.is_empty():
		_index_edges()
	# Each stretch is filed under its middle, so look half a stretch further out.
	var wide := rect.grow(_longest_edge / 2.0 + 1.0)
	var first := _bucket_of(wide.position)
	var last := _bucket_of(wide.end)
	var found: Array = []
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var key := Vector2i(x, y)
			if _edge_buckets.has(key):
				found.append_array(_edge_buckets[key])
	return found


static func edge_from(index: int) -> Vector2:
	return _edge_from[index]


static func edge_to(index: int) -> Vector2:
	return _edge_to[index]


static func _index_triangles() -> void:
	var points := triangles()
	for i in range(0, points.size(), 3):
		var bounds := Rect2(points[i], Vector2.ZERO).expand(points[i + 1]).expand(points[i + 2])
		var first := _bucket_of(bounds.position)
		var last := _bucket_of(bounds.end)
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				var key := Vector2i(x, y)
				if not _triangle_buckets.has(key):
					_triangle_buckets[key] = []
				_triangle_buckets[key].append(i)


## The land triangles that may show in a rectangle, each as the index of its
## first point in triangles().
static func triangles_near(rect: Rect2) -> Array:
	if _triangle_buckets.is_empty():
		_index_triangles()
	var first := _bucket_of(rect.position)
	var last := _bucket_of(rect.end)
	var seen := {}
	var found: Array = []
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var key := Vector2i(x, y)
			if not _triangle_buckets.has(key):
				continue
			for index: int in _triangle_buckets[key]:
				if not seen.has(index):
					seen[index] = true
					found.append(index)
	return found


static func _distance_to_edge(p: Vector2, index: int) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, _edge_from[index], _edge_to[index]))


## Distance to the nearest land or chart edge.
static func distance_to_land(p: Vector2) -> float:
	if is_blocked(p):
		return 0.0
	var best := minf(minf(p.x, SIZE.x - p.x), minf(p.y, SIZE.y - p.y))
	# Look nearby first: anything found within the reach is the nearest there is.
	for reach: float in [600.0, 2500.0]:
		if best <= reach:
			return best
		var nearest := best
		for index: int in edges_near(Rect2(p - Vector2(reach, reach), Vector2(reach, reach) * 2.0)):
			nearest = minf(nearest, _distance_to_edge(p, index))
		if nearest <= reach:
			return nearest
	for index in _edge_from.size():
		best = minf(best, _distance_to_edge(p, index))
	return best


## A small picture of the whole chart for the minimap: one dot per square of
## the coarse grid.
static func minimap_texture() -> ImageTexture:
	if _minimap == null:
		if _cells.is_empty():
			_load_cells()
		var tall := _cells.size() / _cells_wide
		var image := Image.create(_cells_wide, tall, false, Image.FORMAT_RGBA8)
		for y in tall:
			for x in _cells_wide:
				var state := _cells[y * _cells_wide + x]
				image.set_pixel(x, y, Color(0.36, 0.54, 0.29) if state == 1 else (Color(0.27, 0.46, 0.34) if state == 2 else Color(0, 0, 0, 0)))
		_minimap = ImageTexture.create_from_image(image)
	return _minimap


## True if the straight line from a to b touches land or leaves the chart.
static func segment_crosses_land(a: Vector2, b: Vector2, step: float = 40.0) -> bool:
	var steps := maxi(1, int(ceil(a.distance_to(b) / step)))
	for i in steps + 1:
		if is_blocked(a.lerp(b, float(i) / steps)):
			return true
	return false


# --- Shallow water -----------------------------------------------------------

## The shoals from data/shoals.gd, each with its outline in chart pixels
## ("polygon"), the box around it ("bounds") and a point to label it ("centre").
static func shoals() -> Array[Dictionary]:
	if _shoals.is_empty():
		for entry: Dictionary in ShoalData.SHOALS:
			var polygon := PackedVector2Array()
			var total := Vector2.ZERO
			var outline: Array = entry["outline"]
			for corner: Array in outline:
				var p := lonlat_to_px(corner[0], corner[1])
				polygon.append(p)
				total += p
			var bounds := Rect2(polygon[0], Vector2.ZERO)
			for p in polygon:
				bounds = bounds.expand(p)
			var shoal := entry.duplicate()
			shoal["polygon"] = polygon
			shoal["bounds"] = bounds
			shoal["centre"] = total / polygon.size()
			_shoals.append(shoal)
	return _shoals


## The shoal under a point (the shallowest, if two overlap), or an empty dictionary.
static func shoal_at(p: Vector2) -> Dictionary:
	var found := {}
	for shoal in shoals():
		var bounds: Rect2 = shoal["bounds"]
		if not bounds.has_point(p) or not Geometry2D.is_point_in_polygon(p, shoal["polygon"]):
			continue
		if found.is_empty() or float(shoal["depth"]) < float(found["depth"]):
			found = shoal
	return found


## Depth of water at a point with the tide at this height: INF away from the shoals.
static func depth_at(p: Vector2, tide_height: float) -> float:
	var shoal := shoal_at(p)
	if shoal.is_empty():
		return INF
	return Shoals.depth_m(shoal["depth"], tide_height)


## The name of the first shoal along a line that is too shallow for this
## draught at this height of tide, or "" if she floats all the way.
static func shoal_on_segment(a: Vector2, b: Vector2, draught: float, tide_height: float, step: float = 60.0) -> String:
	var steps := maxi(1, int(ceil(a.distance_to(b) / step)))
	for i in steps + 1:
		var shoal := shoal_at(a.lerp(b, float(i) / steps))
		if not shoal.is_empty() and not Shoals.can_float(Shoals.depth_m(shoal["depth"], tide_height), draught):
			return shoal["name"]
	return ""


# --- Pilot routes ------------------------------------------------------------

static func _cell_centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GRID_CELL


## The grid a pilot plans on for a ship of this draught: land is closed to
## her, and so is every shoal she could not cross at low water.
static func _pilot_grid(draught: float) -> AStarGrid2D:
	var key := snappedf(draught, 0.1)
	if _grids.has(key):
		return _grids[key]
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, int(ceil(SIZE.x / GRID_CELL)), int(ceil(SIZE.y / GRID_CELL)))
	grid.cell_size = Vector2(GRID_CELL, GRID_CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(PILOT_CLEARANCE, 0), Vector2(-PILOT_CLEARANCE, 0),
		Vector2(0, PILOT_CLEARANCE), Vector2(0, -PILOT_CLEARANCE)]
	for x in grid.region.size.x:
		for y in grid.region.size.y:
			var centre := _cell_centre(Vector2i(x, y))
			var closed := draught > 0.0 and not Shoals.can_float(depth_at(centre, 0.0), draught)
			for offset in offsets:
				if closed:
					break
				closed = is_blocked(centre + offset)
			if closed:
				grid.set_point_solid(Vector2i(x, y), true)
	_grids[key] = grid
	return grid


## The open-water grid cell nearest to a point.
static func _open_cell_near(grid: AStarGrid2D, p: Vector2) -> Vector2i:
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


static func _pilot_cells(from_port: String, to_port: String, draught: float) -> Array[Vector2i]:
	var grid := _pilot_grid(draught)
	return grid.get_id_path(_open_cell_near(grid, port_position(from_port)), _open_cell_near(grid, port_position(to_port)))


## True if a ship of this draught can get from one port to the other at low
## water without crossing a shoal too shallow for her.
static func has_pilot_route(from_port: String, to_port: String, draught: float) -> bool:
	return not _pilot_cells(from_port, to_port, draught).is_empty()


## A safe course between two ports that keeps clear of the land, and of any
## shoal too shallow at low water for a ship of this draught: the port
## positions at each end and the turning points between them. It ignores the
## wind, so it is a starting point for a plan, not the fastest course. If
## there is no such course for her draught, the course for a ship of no
## draught is given instead.
static func pilot_route(from_port: String, to_port: String, draught: float = 0.0) -> Array[Vector2]:
	var key := "%s>%s@%.1f" % [from_port, to_port, draught]
	if not _routes.has(key):
		var cells := _pilot_cells(from_port, to_port, draught)
		if cells.is_empty() and draught > 0.0:
			_routes[key] = pilot_route(from_port, to_port, 0.0)
		else:
			var start := port_position(from_port)
			var finish := port_position(to_port)
			var raw: Array[Vector2] = [start]
			for cell in cells:
				raw.append(_cell_centre(cell))
			raw.append(finish)
			# Keep only the corners: from each point, skip ahead to the furthest one in clear sight.
			var route: Array[Vector2] = [start]
			var i := 0
			while i < raw.size() - 1:
				var j := raw.size() - 1
				while j > i + 1 and (segment_crosses_land(raw[i], raw[j], 100.0)
						or (draught > 0.0 and shoal_on_segment(raw[i], raw[j], draught, 0.0, 100.0) != "")):
					j -= 1
				route.append(raw[j])
				i = j
			_routes[key] = route
	var result: Array[Vector2] = []
	result.assign(_routes[key])
	return result


static func route_length_nm(route: Array[Vector2]) -> float:
	var length := 0.0
	for i in range(1, route.size()):
		length += route[i - 1].distance_to(route[i])
	return length / 400.0
