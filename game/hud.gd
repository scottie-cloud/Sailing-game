extends Control
## Screen-space extras drawn over the sailing view: wind dial, minimap, trim
## bar and the speed panel.

const SailingModel = preload("res://sim/sailing_model.gd")
const Weather = preload("res://sim/weather.gd")
const World = preload("res://game/world.gd")
const Palette = preload("res://game/palette.gd")
const GOLD := Palette.GOLD
const LAND_FILL := Palette.LAND_FILL

var game

func _draw() -> void:
	if not game.is_sailing():
		return
	var font := ThemeDB.fallback_font
	# Night falls over the chart view; the deck view has its own sky.
	if not game.deck_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.12, 0.45 * (1.0 - game.daylight())))
	_draw_wind_dial(font)
	_draw_minimap()
	_draw_speed_panel(font)

func _draw_wind_dial(font: Font) -> void:
	var centre := Vector2(84, 128)
	draw_circle(centre, 56.0, Color(0, 0, 0, 0.35))
	var blowing_to: Vector2 = SailingModel.bearing_to_vector(game.wind_from + PI)
	var head := centre + blowing_to * 40.0
	draw_line(centre - blowing_to * 40.0, head, Color.WHITE, 5.0)
	var barb := blowing_to.orthogonal() * 11.0
	draw_colored_polygon(PackedVector2Array([head + blowing_to * 12.0, head - blowing_to * 8.0 + barb, head - blowing_to * 8.0 - barb]), Color.WHITE)
	# A faint arrow shows the forecast, so a shift away from it is visible.
	var forecast_deg: float = game.forecast["from_deg"]
	var forecast_to: Vector2 = SailingModel.bearing_to_vector(deg_to_rad(forecast_deg) + PI)
	draw_line(centre - forecast_to * 40.0, centre + forecast_to * 48.0, Color(1, 1, 1, 0.3), 2.0)
	draw_string(font, Vector2(-16, 214), "Wind %s %d kn" % [Weather.compass_name(rad_to_deg(game.wind_from)), roundi(game.wind_kn)],
		HORIZONTAL_ALIGNMENT_CENTER, 200, 20, Color.WHITE)

func _draw_minimap() -> void:
	var map_scale: float = 200.0 / World.SIZE.x
	var map_size: Vector2 = World.SIZE * map_scale
	var origin := Vector2(size.x - map_size.x - 20.0, 56.0)
	draw_rect(Rect2(origin, map_size), Color(0.05, 0.2, 0.32, 0.85))
	var triangles := World.triangles()
	for i in range(0, triangles.size(), 3):
		draw_colored_polygon(PackedVector2Array([origin + triangles[i] * map_scale,
			origin + triangles[i + 1] * map_scale, origin + triangles[i + 2] * map_scale]), LAND_FILL)
	var route: Array[Vector2] = game.route_points(World.port_position(game.current_port), 0)
	if route.size() > 2:
		for i in range(1, route.size()):
			draw_line(origin + route[i - 1] * map_scale, origin + route[i] * map_scale, Color(1, 1, 1, 0.6), 1.5)
	for port: String in World.PORTS:
		var colour := GOLD if port == game.destination else Color.WHITE
		draw_circle(origin + World.port_position(port) * map_scale, 5.0, colour)
	for squall: Dictionary in game.squalls_at(game.passage_seconds / 3600.0):
		var squall_centre: Vector2 = squall["centre"]
		var squall_radius: float = squall["radius"]
		if World.in_bounds(squall_centre):
			draw_circle(origin + squall_centre * map_scale, squall_radius * map_scale, Color(0.05, 0.05, 0.1, 0.55))
	var target: Vector2 = game.target_point()
	draw_circle(origin + target * map_scale, 4.0, GOLD)
	var ship_at: Vector2 = origin + game.ship.position * map_scale
	var bow: Vector2 = SailingModel.bearing_to_vector(game.ship.heading)
	draw_line(ship_at, ship_at + bow * 14.0, Color.WHITE, 2.0)
	draw_circle(ship_at, 4.0, Color("ff5a4a"))
	draw_rect(Rect2(origin, map_size), Color(1, 1, 1, 0.6), false, 2.0)

## A strip above the speed panel: the sheet runs from hauled in (left) to
## eased out (right). The green band is where the sail sets well for this
## heading, and it slides as the heading or wind changes. Keep the white
## marker inside it.
func _draw_trim_bar(font: Font, panel: Rect2, twa: float) -> void:
	var bar := Rect2(panel.position.x + 60.0, panel.position.y - 40.0, panel.size.x - 120.0, 26.0)
	draw_rect(Rect2(panel.position.x, bar.position.y - 6.0, panel.size.x, 38.0), Color(0, 0, 0, 0.5))
	draw_string(font, Vector2(panel.position.x + 12.0, bar.position.y + 20.0), "IN", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(font, Vector2(bar.end.x + 8.0, bar.position.y + 20.0), "OUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_rect(bar, Color(1, 1, 1, 0.15))
	var ideal: float = SailingModel.ideal_sheet_deg(twa)
	var manual: bool = game.ship.manual_trim
	# Within about 11 degrees of ideal, hand trim beats the automatic trim.
	var good_from := inverse_lerp(5.0, 90.0, clampf(ideal - 11.0, 5.0, 90.0))
	var good_to := inverse_lerp(5.0, 90.0, clampf(ideal + 11.0, 5.0, 90.0))
	var band := Rect2(bar.position.x + bar.size.x * good_from, bar.position.y, bar.size.x * (good_to - good_from), bar.size.y)
	draw_rect(band, Color(0.37, 0.89, 0.42, 0.75 if manual else 0.3))
	var sheet_now: float = game.ship.sheet_deg if manual else ideal
	var marker_x := bar.position.x + bar.size.x * inverse_lerp(5.0, 90.0, sheet_now)
	draw_rect(Rect2(marker_x - 4.0, bar.position.y - 5.0, 8.0, bar.size.y + 10.0), Color.WHITE if manual else Color(1, 1, 1, 0.5))
	if not manual:
		draw_string(font, bar.position + Vector2(8.0, 19.0), "Automatic trim", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.7))

## Speed now, what this heading is worth, and why.
func _draw_speed_panel(font: Font) -> void:
	var panel := Rect2(size.x / 2.0 - 320.0, size.y - 200.0, 640.0, 190.0)
	draw_rect(panel, Color(0, 0, 0, 0.5))

	var heading: float = game.ship.heading
	var wind_from: float = game.wind_from
	var twa: float = SailingModel.true_wind_angle_deg(heading, wind_from)
	var hull: float = game.ship.hull_speed_kn
	var trim: float = game.ship.trim_efficiency
	# Her best is with the sail set perfectly, which only hand trim can reach.
	var best: float = SailingModel.best_speed_kn(game.wind_kn, hull, 1.0)
	var worth: float = SailingModel.target_speed_kn(twa, game.wind_kn, hull, trim)
	var speed: float = game.ship.speed_kn

	# Speed dial: how fast she goes on every heading. The further the
	# curve is from the centre, the faster that direction is.
	var centre := panel.position + Vector2(96, 96)
	var radius := 78.0
	draw_circle(centre, radius, Color(1, 1, 1, 0.08))
	var wedge := PackedVector2Array([centre])
	for i in 9:
		var spread := deg_to_rad(lerpf(-SailingModel.NO_GO_DEG, SailingModel.NO_GO_DEG, i / 8.0))
		wedge.append(centre + SailingModel.bearing_to_vector(wind_from + spread) * radius)
	draw_colored_polygon(wedge, Color(0.9, 0.15, 0.1, 0.35))
	var curve := PackedVector2Array()
	for step in 73:
		var bearing := deg_to_rad(step * 5.0)
		var fraction: float = SailingModel.polar_fraction(SailingModel.true_wind_angle_deg(bearing, wind_from))
		curve.append(centre + SailingModel.bearing_to_vector(bearing) * radius * fraction)
	draw_polyline(curve, Color(0.6, 0.9, 1.0), 2.5)
	var to_target: Vector2 = game.target_point() - game.ship.position
	draw_circle(centre + to_target.normalized() * radius, 6.0, GOLD)
	var bow: Vector2 = SailingModel.bearing_to_vector(heading)
	draw_line(centre, centre + bow * radius, Color(1, 1, 1, 0.35), 2.0)
	draw_circle(centre + bow * radius * SailingModel.polar_fraction(twa), 7.0, Color.WHITE)

	var x := panel.position.x + 196.0
	var y := panel.position.y
	draw_string(font, Vector2(x, y + 46.0), "%.1f kn" % speed, HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color.WHITE)
	# Bar: speed now against her best; the tick is what this heading is worth.
	var bar := Rect2(x + 160.0, y + 22.0, 264.0, 16.0)
	draw_rect(bar, Color(1, 1, 1, 0.15))
	var fill := bar
	fill.size.x = bar.size.x * clampf(speed / best, 0.0, 1.0)
	draw_rect(fill, Color(0.37, 0.89, 0.42))
	var tick_x := bar.position.x + bar.size.x * clampf(worth / best, 0.0, 1.0)
	draw_line(Vector2(tick_x, bar.position.y - 5.0), Vector2(tick_x, bar.end.y + 5.0), Color.WHITE, 3.0)

	var sailing_line := "%s: wind %d° off the bow" % [SailingModel.point_of_sail(twa), roundi(twa)]
	var stream: Vector2 = World.current_kn(game.ship.position, game.now_hours())
	if stream.length() > 0.2:
		sailing_line += "   Tide %.1f kn to %s" % [stream.length(), Weather.compass_name(rad_to_deg(SailingModel.vector_to_bearing(stream)))]
	draw_string(font, Vector2(x, y + 78.0), sailing_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	_draw_trim_bar(font, panel, twa)
	draw_string(font, Vector2(x, y + 106.0), "This heading is worth %.1f kn (her best is %.1f)" % [worth, best],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	var over_ground: float = game.ship.ground_speed_kn()
	var course: float = SailingModel.vector_to_bearing(game.ship.velocity) if over_ground > 0.05 else heading
	var made_good: float = SailingModel.vmg_kn(over_ground, course, SailingModel.vector_to_bearing(to_target))
	var progress := "Towards %s: %.1f kn" % [game.target_name(), made_good]
	if made_good < 0.0:
		progress = "Moving away from %s" % game.target_name()
	draw_string(font, Vector2(x, y + 134.0), progress, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD)

	var tip: String = SailingModel.point_of_sail_tip(twa)
	if not SailingModel.in_no_go(twa):
		if speed < worth * 0.8:
			tip = "Picking up speed. Every turn costs some."
		elif speed > worth * 1.15:
			tip = "Slowing: this heading is worth less."
	if game.ship.manual_trim and not SailingModel.in_no_go(twa):
		var ideal: float = SailingModel.ideal_sheet_deg(twa)
		var sheet_now: float = game.ship.sheet_deg
		if trim >= 0.97:
			tip = "Trim %d%%: well set. Automatic trim only manages 85%%." % roundi(trim * 100.0)
		elif sheet_now < ideal:
			tip = "Trim %d%%: the sail is in too tight. Ease out." % roundi(trim * 100.0)
		else:
			tip = "Trim %d%%: the sail is out too far. Haul in." % roundi(trim * 100.0)
	draw_string(font, Vector2(x, y + 164.0), tip, HORIZONTAL_ALIGNMENT_LEFT, 430, 17, Color(1, 1, 1, 0.8))
