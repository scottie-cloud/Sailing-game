extends Control
## Screen-space extras drawn over the sailing view: compass, wind dial,
## minimap, trim bar and the speed panel.

const SailingModel = preload("res://sim/sailing_model.gd")
const Weather = preload("res://sim/weather.gd")
const World = preload("res://game/world.gd")
const Palette = preload("res://game/palette.gd")
const Survey = preload("res://sim/survey.gd")
const GOLD := Palette.GOLD
const LAND_FILL := Palette.LAND_FILL

var game

func _draw() -> void:
	if not game.at_helm():
		return
	var font := ThemeDB.fallback_font
	# Night falls over the chart view; the deck view has its own sky.
	if not game.deck_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.12, 0.45 * (1.0 - game.daylight())))
	_draw_wind_dial(font)
	_draw_minimap()
	_draw_speed_panel(font)
	_draw_compass(size.x, game.ship.heading)

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
	draw_texture_rect(World.minimap_texture(), Rect2(origin, map_size), false)
	# What she has not surveyed is blank.
	var fog: ImageTexture = game.fog_texture
	draw_texture_rect_region(fog, Rect2(origin, map_size), Rect2(Vector2.ZERO, World.SIZE / Survey.CELL))
	for port: String in World.PORTS:
		if not game.knows_port(port):
			continue
		var colour := GOLD if port == game.destination else Color.WHITE
		draw_circle(origin + World.port_position(port) * map_scale, 5.0, colour)
	for squall: Dictionary in game.squalls_at(game.passage_seconds / 3600.0):
		var squall_centre: Vector2 = squall["centre"]
		var squall_radius: float = squall["radius"]
		if World.in_bounds(squall_centre):
			draw_circle(origin + squall_centre * map_scale, squall_radius * map_scale, Color(0.05, 0.05, 0.1, 0.55))
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
	# The gold dot is the course laid off on the chart, not a sight of the mark.
	var course_laid: float = game.course_to_steer()
	draw_circle(centre + SailingModel.bearing_to_vector(course_laid) * radius, 6.0, GOLD)
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
	if stream.length() > 0.3:
		sailing_line = "%s, wind %d°. Tide %.1f kn %s" % [SailingModel.point_of_sail(twa), roundi(twa), stream.length(),
			Weather.compass_name(rad_to_deg(SailingModel.vector_to_bearing(stream)))]
	draw_string(font, Vector2(x, y + 78.0), sailing_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	_draw_trim_bar(font, panel, twa)
	draw_string(font, Vector2(x, y + 106.0), "This heading is worth %.1f kn (her best is %.1f)" % [worth, best],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	var over_ground: float = game.ship.ground_speed_kn()
	var course: float = SailingModel.vector_to_bearing(game.ship.velocity) if over_ground > 0.05 else heading
	var made_good: float = SailingModel.vmg_kn(over_ground, course, course_laid)
	var progress := "Along your course: %.1f kn" % made_good
	if made_good < 0.0:
		progress = "Making no way along your course"
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


## A strip of compass across the top, in both views. There is no line on
## the water: she is steered by this, and checked against the chart.
func _draw_compass(w: float, heading: float) -> void:
	var font := ThemeDB.fallback_font
	var centre := w / 2.0
	var top := 180.0
	var half_width := 300.0
	var px_per_degree := 5.0
	draw_rect(Rect2(centre - half_width, top, half_width * 2.0, 48.0), Color(0, 0, 0, 0.55))
	var heading_deg := rad_to_deg(heading)
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	for degrees in range(0, 360, 5):
		var offset := wrapf(degrees - heading_deg, -180.0, 180.0)
		if absf(offset) > half_width / px_per_degree - 2.0:
			continue
		var x := centre + offset * px_per_degree
		var major := degrees % 15 == 0
		draw_line(Vector2(x, top + 48.0), Vector2(x, top + (30.0 if major else 40.0)), Color.WHITE, 2.0)
		if names.has(degrees):
			draw_string(font, Vector2(x - 30.0, top + 24.0), names[degrees], HORIZONTAL_ALIGNMENT_CENTER, 60, 22, Color.WHITE)
		elif degrees % 30 == 0:
			draw_string(font, Vector2(x - 30.0, top + 24.0), str(degrees), HORIZONTAL_ALIGNMENT_CENTER, 60, 18, Color(1, 1, 1, 0.8))
	# Where the wind is coming from (blue) and the course laid off on the chart (gold).
	_compass_marker(centre, top, half_width, px_per_degree, rad_to_deg(game.wind_from) - heading_deg, Color("7fd0ff"), "WIND", 0.0)
	var course_deg := rad_to_deg(game.course_to_steer())
	_compass_marker(centre, top, half_width, px_per_degree, course_deg - heading_deg, GOLD, "COURSE", 14.0)
	draw_colored_polygon(PackedVector2Array([Vector2(centre - 9.0, top - 2.0), Vector2(centre + 9.0, top - 2.0), Vector2(centre, top + 12.0)]), Color.WHITE)
	var steer := "Heading %03d°    Steer %03d° for %s" % [posmod(roundi(heading_deg), 360), posmod(roundi(course_deg), 360), game.target_name()]
	draw_string(font, Vector2(centre - 259.0, top + 119.0), steer, HORIZONTAL_ALIGNMENT_CENTER, 520, 22, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(centre - 260.0, top + 118.0), steer, HORIZONTAL_ALIGNMENT_CENTER, 520, 22, Color.WHITE)


## A marker under the strip. Off the end of the strip it sits at the edge,
## showing which way to turn to bring it round. The label sits label_drop
## lower, so two markers at the same place can both be read.
func _compass_marker(centre: float, top: float, half_width: float, px_per_degree: float, offset_deg: float, colour: Color, label: String, label_drop: float) -> void:
	var offset := wrapf(offset_deg, -180.0, 180.0)
	var x := centre + clampf(offset * px_per_degree, -half_width + 10.0, half_width - 10.0)
	draw_colored_polygon(PackedVector2Array([Vector2(x - 9.0, top + 62.0), Vector2(x + 9.0, top + 62.0), Vector2(x, top + 48.0)]), colour)
	draw_string(ThemeDB.fallback_font, Vector2(x - 40.0, top + 80.0 + label_drop), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, colour)
