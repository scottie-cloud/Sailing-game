extends Node2D
## The sailing view from above: water, coast, ports, the plan and the ship.
## It reads the state of the game and draws it; it changes nothing.

const SailingModel = preload("res://sim/sailing_model.gd")
const ShipState = preload("res://sim/ship_state.gd")
const Shipyard = preload("res://sim/shipyard.gd")
const World = preload("res://game/world.gd")
const ShipArt = preload("res://game/ship_art.gd")
const Palette = preload("res://game/palette.gd")
const LAND_FILL := Palette.LAND_FILL
const LAND_EDGE := Palette.LAND_EDGE
const SHALLOW_OUTER := Palette.SHALLOW_OUTER
const SHALLOW_INNER := Palette.SHALLOW_INNER
const GOLD := Palette.GOLD
const RECORD := Palette.RECORD

var game

# The parts of the game this view draws from.
var ship: ShipState:
	get:
		return game.ship
var wind_from: float:
	get:
		return game.wind_from
var wind_kn: float:
	get:
		return game.wind_kn
var anim_time: float:
	get:
		return game.anim_time
var passage_seconds: float:
	get:
		return game.passage_seconds
var plan: Array[Vector2]:
	get:
		return game.plan
var wake: Array[Vector2]:
	get:
		return game.wake
var next_mark: int:
	get:
		return game.next_mark
var destination: String:
	get:
		return game.destination
var current_port: String:
	get:
		return game.current_port
var ship_id: String:
	get:
		return game.ship_id
var camera: Camera2D:
	get:
		return game.camera
var deck_view: Control:
	get:
		return game.deck_view


func route_points(start: Vector2, from_mark: int) -> Array[Vector2]:
	return game.route_points(start, from_mark)


func squalls_at(hours: float) -> Array[Dictionary]:
	return game.squalls_at(hours)


func record_track() -> Array[Vector2]:
	return game.record_track()


func target_point() -> Vector2:
	return game.target_point()


func _draw() -> void:
	# From the deck, the deck view draws everything instead.
	if deck_view.visible:
		return
	var view_size := get_viewport_rect().size / camera.zoom
	var view := Rect2(ship.position - view_size / 2.0, view_size).grow(40.0)
	_draw_shallows(view)
	_draw_waves()
	# Only the land near the ship is drawn.
	var triangles := World.triangles()
	for i in range(0, triangles.size(), 3):
		var a := triangles[i]
		var b := triangles[i + 1]
		var c := triangles[i + 2]
		var bounds := Rect2(a, Vector2.ZERO).expand(b).expand(c)
		if bounds.intersects(view):
			draw_colored_polygon(PackedVector2Array([a, b, c]), LAND_FILL)
	_draw_scrub(view)
	for polygon in World.land():
		for i in polygon.size():
			var from := polygon[i]
			var to := polygon[(i + 1) % polygon.size()]
			if Rect2(from, Vector2.ZERO).expand(to).grow(16.0).intersects(view):
				draw_line(from, to, LAND_EDGE, 16.0)
				draw_circle(from, 8.0, LAND_EDGE)
	_draw_ports()
	if game.is_sailing():
		_draw_squalls()
		_draw_record()
		_draw_plan()
		_draw_wake()
		_draw_ship()


## Pale water along the coast, as over sand in the shallows.
func _draw_shallows(view: Rect2) -> void:
	var wide := view.grow(260.0)
	for polygon in World.land():
		for i in polygon.size():
			var from := polygon[i]
			var to := polygon[(i + 1) % polygon.size()]
			if Rect2(from, Vector2.ZERO).expand(to).intersects(wide):
				draw_line(from, to, SHALLOW_OUTER, 420.0)
				draw_circle(from, 210.0, SHALLOW_OUTER)
	for polygon in World.land():
		for i in polygon.size():
			var from := polygon[i]
			var to := polygon[(i + 1) % polygon.size()]
			if Rect2(from, Vector2.ZERO).expand(to).intersects(wide):
				draw_line(from, to, SHALLOW_INNER, 150.0)
				draw_circle(from, 75.0, SHALLOW_INNER)


## Darker clumps of scrub scattered over the land.
func _draw_scrub(view: Rect2) -> void:
	var spacing := 150
	for ix in range(int(floor(view.position.x / spacing)), int(view.end.x / spacing) + 1):
		for iy in range(int(floor(view.position.y / spacing)), int(view.end.y / spacing) + 1):
			var seed_value := posmod(hash(Vector2i(ix * 3 + 1, iy * 5 + 2)), 10000)
			var p := Vector2(ix * spacing + seed_value % 130, iy * spacing + (seed_value / 100) % 130)
			if World.is_land(p):
				draw_circle(p, 16.0 + seed_value % 14, Color(0.25, 0.42, 0.24, 0.55))


## Wave crests drift downwind. More wind brings more and whiter crests.
func _draw_waves() -> void:
	var view := get_viewport_rect().size / camera.zoom
	var top_left := ship.position - view / 2.0
	var spacing := 150
	var across := SailingModel.bearing_to_vector(wind_from + PI / 2.0)
	var downwind := SailingModel.bearing_to_vector(wind_from + PI)
	var strength := clampf(wind_kn / 14.0, 0.4, 1.8)
	var first_x := int(floor(top_left.x / spacing)) - 1
	var first_y := int(floor(top_left.y / spacing)) - 1
	for ix in range(first_x, first_x + int(view.x / spacing) + 4):
		for iy in range(first_y, first_y + int(view.y / spacing) + 4):
			var seed_value := posmod(hash(Vector2i(ix, iy)), 8100)
			# Each crest runs downwind across its cell, fading in and out.
			var phase := fposmod(anim_time * 0.12 * strength + seed_value / 8100.0, 1.0)
			var p := Vector2(ix * spacing + seed_value % 90, iy * spacing + seed_value / 90) + downwind * (phase - 0.5) * spacing
			var alpha := sin(phase * PI) * 0.22 * strength
			var half := (9.0 + seed_value % 9) * strength
			draw_line(p - across * half, p + across * half, Color(1, 1, 1, alpha), 2.5)
			if wind_kn > 15.0 and seed_value % 3 == 0:
				draw_line(p - across * half * 0.5 + downwind * 5.0, p + across * half * 0.5 + downwind * 5.0, Color(1, 1, 1, alpha * 1.4), 4.0)


## Foam left astern, fading with age.
func _draw_wake() -> void:
	var count := wake.size()
	for i in range(1, count):
		var age := 1.0 - float(i) / count
		var spread := 4.0 + age * 26.0
		var along := (wake[i] - wake[i - 1]).normalized()
		var out := along.orthogonal() * spread
		var alpha := (1.0 - age) * 0.45
		draw_line(wake[i - 1] + out, wake[i] + out, Color(1, 1, 1, alpha), 3.0)
		draw_line(wake[i - 1] - out, wake[i] - out, Color(1, 1, 1, alpha), 3.0)
		draw_line(wake[i - 1], wake[i], Color(0.8, 0.95, 1.0, alpha * 0.5), 6.0)


func _draw_ports() -> void:
	var font := ThemeDB.fallback_font
	for port: String in World.PORTS:
		var p := World.port_position(port)
		if game.is_sailing() and port == destination:
			draw_arc(p, game.DOCK_RADIUS, 0.0, TAU, 48, GOLD, 4.0)
		draw_circle(p, 26.0, Color("7a5230"))
		draw_circle(p, 14.0, Color("f4ecd8"))
		draw_string(font, p + Vector2(-120, -44), World.port_name(port), HORIZONTAL_ALIGNMENT_CENTER, 240, 30, Color.WHITE)


## Squalls darken the water they are over.
func _draw_squalls() -> void:
	for squall in squalls_at(passage_seconds / 3600.0):
		var centre: Vector2 = squall["centre"]
		var radius: float = squall["radius"]
		if centre.distance_to(ship.position) < radius + 2000.0:
			draw_circle(centre, radius, Color(0.08, 0.1, 0.16, 0.3))
			draw_circle(centre, radius * 0.6, Color(0.08, 0.1, 0.16, 0.25))


## The course of the record passage on this route, as a faint dashed line.
func _draw_record() -> void:
	var record := record_track()
	for i in range(1, record.size()):
		draw_dashed_line(record[i - 1], record[i], Color(RECORD, 0.45), 3.0, 14.0)


## The planned route on the water: a dashed line through numbered marks.
func _draw_plan() -> void:
	if plan.is_empty():
		return
	var font := ThemeDB.fallback_font
	var points := route_points(World.port_position(current_port), 0)
	for i in range(1, points.size()):
		draw_dashed_line(points[i - 1], points[i], Color(1, 1, 1, 0.35), 4.0, 24.0)
	for i in plan.size():
		var colour := GOLD if i == next_mark else Color(1, 1, 1, 0.3 if i < next_mark else 0.7)
		draw_arc(plan[i], game.MARK_RADIUS, 0.0, TAU, 48, Color(colour, colour.a * 0.5), 3.0)
		draw_circle(plan[i], 20.0, colour)
		draw_string(font, plan[i] + Vector2(-20, 9), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 26, Color.BLACK)


func _draw_ship() -> void:
	var side_angle := SailingModel.signed_wind_angle(ship.heading, wind_from)
	var twa := absf(rad_to_deg(side_angle))
	var no_go := SailingModel.in_no_go(twa)

	# The no-go zone: a red wedge pointing at where the wind comes from.
	var wedge := PackedVector2Array([ship.position])
	for i in 13:
		var spread := deg_to_rad(lerpf(-SailingModel.NO_GO_DEG, SailingModel.NO_GO_DEG, i / 12.0))
		wedge.append(ship.position + SailingModel.bearing_to_vector(wind_from + spread) * 180.0)
	draw_colored_polygon(wedge, Color(0.9, 0.15, 0.1, 0.45 if no_go else 0.2))

	# Gold arrow towards the next mark, or the destination.
	var to_target := target_point() - ship.position
	var direction := to_target.normalized()
	var tip := ship.position + direction * 250.0
	var base := ship.position + direction * 215.0
	var wing := direction.orthogonal() * 16.0
	draw_colored_polygon(PackedVector2Array([tip, base + wing, base - wing]), GOLD)
	draw_string(ThemeDB.fallback_font, tip + direction * 34.0 + Vector2(-60, 8),
		"%.1f nm" % (to_target.length() / ShipState.PX_PER_NM), HORIZONTAL_ALIGNMENT_CENTER, 120, 22, GOLD)

	var ship_size: float = Shipyard.SHIPS[ship_id]["size"]
	draw_set_transform(ship.position, ship.heading, Vector2(ship_size, ship_size))
	# The sails swing out to the downwind side, and flap in the no-go zone.
	var ideal_sheet := SailingModel.ideal_sheet_deg(twa)
	var sheet := deg_to_rad(ship.sheet_deg if ship.manual_trim else ideal_sheet)
	var flutter := 0.0
	if ship.manual_trim and ship.sheet_deg > ideal_sheet + 15.0:
		# Eased too far: the sail spills the wind and flutters.
		flutter = sin(anim_time * 18.0) * 0.1
	if no_go:
		sheet = deg_to_rad(6.0)
		flutter = sin(anim_time * 18.0) * 0.14
	var side := 1.0 if side_angle >= 0.0 else -1.0
	ShipArt.draw_top_down(self, ship_id, sheet, side, flutter)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
