extends Control
## The chart. Opened under sail it shows the course sailed and where she is
## against the plan, and changes nothing. In port it is used to plan a route. Tap the water to add marks; each
## leg is coloured by how well the boat can sail it and labelled with an
## estimated speed and time.

const SailingModel = preload("res://sim/sailing_model.gd")
const World = preload("res://game/world.gd")
const Shoals = preload("res://sim/shoals.gd")
const Survey = preload("res://sim/survey.gd")
const Tide = preload("res://sim/tide.gd")

const BAR_HEIGHT := 112.0
const Palette = preload("res://game/palette.gd")
const SEA := Palette.SEA
const LAND_FILL := Palette.LAND_FILL
const GOLD := Palette.GOLD
const RECORD := Palette.RECORD
const SLOW_LEG := Color("ffe36b")
const FAST_LEG := Color("5fe36a")
const UPWIND_LEG := Color("ff5a4a")
const LAND_LEG := Color("ff9f1c")

var game
var summary: Label
var record_button: Button
## The buttons that change the plan: hidden when the chart is opened under sail.
var planning_buttons: Array[Button] = []
var done_button: Button


func setup(game_ref) -> void:
	game = game_ref
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 20
	bar.offset_right = -20
	bar.offset_top = -BAR_HEIGHT + 10
	bar.offset_bottom = -12
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)

	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size", 18)
	bar.add_child(summary)
	record_button = _button("Record", use_record)
	planning_buttons = [record_button, _button("Undo", undo), _button("Clear", clear)]
	for button in planning_buttons:
		bar.add_child(button)
	done_button = _button("Done", _done)
	bar.add_child(done_button)

	# Waiting in port lets the tide turn before you leave.
	var wait := _button("Wait 1h", _wait)
	wait.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wait.offset_left = -150
	wait.offset_right = -16
	wait.offset_top = 12
	wait.offset_bottom = 76
	add_child(wait)
	planning_buttons.append(wait)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(112, 64)
	button.pressed.connect(action)
	return button


func refresh() -> void:
	var sailing: bool = game.is_sailing()
	summary.text = game.position_report() if sailing else game.plan_summary(true)
	for button in planning_buttons:
		button.visible = not sailing
	done_button.text = "Helm" if sailing else "Done"
	record_button.disabled = game.record_track().is_empty()
	queue_redraw()


func undo() -> void:
	if not game.plan.is_empty():
		game.plan.pop_back()
		game.plan_changed()
		refresh()


func clear() -> void:
	game.plan.clear()
	game.plan_changed()
	refresh()


## Replace the plan with the course of the best passage on this route.
func use_record() -> void:
	var record: Array[Vector2] = game.record_track()
	if record.is_empty():
		return
	game.follow_track(record)
	refresh()


func _wait() -> void:
	game.wait_hour()
	refresh()


func _done() -> void:
	game.close_chart()


func chart_scale() -> float:
	return minf(size.x / World.SIZE.x, (size.y - BAR_HEIGHT) / World.SIZE.y)


func chart_origin() -> Vector2:
	return Vector2((size.x - World.SIZE.x * chart_scale()) / 2.0, 0.0)


func to_screen(world_point: Vector2) -> Vector2:
	return chart_origin() + world_point * chart_scale()


func to_world(screen_point: Vector2) -> Vector2:
	return (screen_point - chart_origin()) / chart_scale()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		add_mark(to_world(event.position))


func add_mark(world_point: Vector2) -> void:
	# The plan is made in port; under sail the chart is only for looking.
	if game.is_sailing() or game.plan.size() >= game.MAX_MARKS:
		return
	# A mark can go anywhere but on land she knows to be land.
	if not World.in_bounds(world_point) or (game.survey.is_known(world_point) and World.is_land(world_point)):
		return
	game.plan.append(world_point)
	game.plan_changed()
	refresh()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var s := chart_scale()
	var origin := chart_origin()
	var map_rect := Rect2(origin, World.SIZE * s)
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d2b3e"))
	draw_rect(map_rect, SEA)

	var triangles := World.triangles()
	for i in range(0, triangles.size(), 3):
		# Drawn as plain triangles: at this scale many are too thin for the polygon routine.
		draw_primitive(PackedVector2Array([to_screen(triangles[i]), to_screen(triangles[i + 1]), to_screen(triangles[i + 2])]),
			PackedColorArray([LAND_FILL, LAND_FILL, LAND_FILL]), PackedVector2Array())

	# Shoals, coloured by whether this ship, loaded as she is, can cross them:
	# sand at any tide, amber only with enough tide, red not at all.
	var draws: float = game.draught()
	for shoal: Dictionary in World.shoals():
		# Only the shoals her lead has found.
		if not game.known_shoals.has(shoal["name"]):
			continue
		var outline := PackedVector2Array()
		for point: Vector2 in shoal["polygon"]:
			outline.append(to_screen(point))
		var standing := Shoals.passage(shoal["depth"], draws, Tide.RANGE_M)
		var tint := Palette.SHOAL
		if standing == Shoals.Passage.ON_THE_TIDE:
			tint = Palette.SHOAL_ON_TIDE
		elif standing == Shoals.Passage.NEVER:
			tint = Palette.SHOAL_TOO_SHALLOW
		draw_colored_polygon(outline, Color(tint, 0.45))
		outline.append(outline[0])
		draw_polyline(outline, Color(tint, 0.9), 1.5)
		draw_string(font, to_screen(shoal["centre"]) + Vector2(-80, 4), "%.1f m" % float(shoal["depth"]), HORIZONTAL_ALIGNMENT_CENTER, 160, 13, Color.WHITE)

	# Names of the main waters and districts, and every light.
	for place: Dictionary in World.PLACES:
		if int(place["rank"]) > 1 or not game.survey.is_known(World.feature_position(place)):
			continue
		var at := to_screen(World.feature_position(place))
		var colour := Color(0.82, 0.92, 1.0, 0.75) if place["kind"] == "water" else Color(0.96, 0.94, 0.82, 0.8)
		draw_string(font, at + Vector2(-110, 5), place["name"], HORIZONTAL_ALIGNMENT_CENTER, 220, 15, colour)
	for light: Dictionary in World.LIGHTS:
		if not game.survey.is_known(World.feature_position(light)):
			continue
		var at := to_screen(World.feature_position(light))
		draw_circle(at, 4.5, Color.WHITE)
		draw_circle(at, 2.5, GOLD)

	# Everything she has not surveyed is blank.
	var fog: ImageTexture = game.fog_texture
	# Only the part of the picture that lies on the chart is used, so nothing spills past its edge.
	draw_texture_rect_region(fog, map_rect, Rect2(Vector2.ZERO, World.SIZE / Survey.CELL))
	draw_string(font, Vector2(map_rect.position.x + 8.0, map_rect.end.y - 8.0),
		"Blank: not yet surveyed. Gold dots: lights. Shoals: amber needs the tide, red is too shallow.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.15, 0.12, 0.05, 0.85))

	# Wind arrows across the open water.
	var blowing_to: Vector2 = SailingModel.bearing_to_vector(game.wind_from + PI)
	var barb := blowing_to.orthogonal() * 6.0
	for x in range(1200, int(World.SIZE.x), 2400):
		for y in range(1200, int(World.SIZE.y), 2400):
			var at := Vector2(x, y)
			# Over unsurveyed squares the arrows are drawn everywhere, so they give no coast away.
			if game.survey.is_known(at) and World.distance_to_land(at) < 400.0:
				continue
			var centre := to_screen(at)
			var head := centre + blowing_to * 16.0
			draw_line(centre - blowing_to * 16.0, head, Color(1, 1, 1, 0.4), 2.0)
			draw_colored_polygon(PackedVector2Array([head + blowing_to * 8.0, head + barb, head - barb]), Color(1, 1, 1, 0.4))


	# The course of the best passage so far on this route.
	var record: Array[Vector2] = game.record_track()
	for i in range(1, record.size()):
		draw_dashed_line(to_screen(record[i - 1]), to_screen(record[i]), RECORD, 2.0, 8.0)
	draw_string(font, map_rect.position + Vector2(12, 26), "Wind today: %s" % game.forecast_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_string(font, map_rect.position + Vector2(12, 50), game.tide_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	if not record.is_empty():
		draw_string(font, map_rect.position + Vector2(12, 74), "Dashed blue: your record course", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, RECORD)

	# The tidal stream in the Rip: an arrow the way it is running now.
	var stream: Vector2 = World.current_kn(World.RIP_CENTRE, game.now_hours())
	if stream.length() > 0.3 and game.survey.is_known(World.RIP_CENTRE):
		var rip := to_screen(World.RIP_CENTRE)
		var flow := stream.normalized()
		var flow_head := rip + flow * (8.0 + stream.length() * 8.0)
		draw_line(rip - flow * 8.0, flow_head, RECORD, 3.0)
		draw_colored_polygon(PackedVector2Array([flow_head + flow * 9.0, flow_head + flow.orthogonal() * 6.0, flow_head - flow.orthogonal() * 6.0]), RECORD)

	# Forecast squalls: each one's track across the chart, with its place marked
	# hour by hour for the next eight hours. Only what falls on the chart is drawn.
	var sailing: bool = game.is_sailing()
	var hours_out: float = game.passage_seconds / 3600.0 if sailing else 0.0
	for hour in range(0, 9):
		var squalls: Array[Dictionary] = game.squalls_at(hours_out + float(hour))
		var next_hour: Array[Dictionary] = game.squalls_at(hours_out + float(hour) + 1.0)
		for i in squalls.size():
			var centre: Vector2 = squalls[i]["centre"]
			var onward: Vector2 = next_hour[i]["centre"]
			if not World.in_bounds(centre):
				continue
			if World.in_bounds(onward):
				draw_dashed_line(to_screen(centre), to_screen(onward), Color(0.05, 0.05, 0.1, 0.8), 2.0, 6.0)
			draw_circle(to_screen(centre), 5.0, Color(0.05, 0.05, 0.1, 0.9))
			draw_string(font, to_screen(centre) + Vector2(7, 5), "squall +%dh" % hour if hour > 0 else "squall now",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	var route: Array[Vector2] = game.route_points(World.port_position(game.current_port), 0)
	var legs: Array[Dictionary] = game.estimate(route)
	var best: float = game.best_speed()

	# The no-go wedge at the start of the last leg: where the next mark can't go.
	var last_start := to_screen(route[route.size() - 2])
	var wedge := PackedVector2Array([last_start])
	for i in 9:
		var spread := deg_to_rad(lerpf(-SailingModel.NO_GO_DEG, SailingModel.NO_GO_DEG, i / 8.0))
		wedge.append(last_start + SailingModel.bearing_to_vector(game.wind_from + spread) * 90.0)
	if not sailing:
		draw_colored_polygon(wedge, Color(0.9, 0.15, 0.1, 0.3))

	for leg in legs:
		var a := to_screen(leg["from"])
		var b := to_screen(leg["to"])
		var colour := UPWIND_LEG
		var label := "zig-zag, about %s" % game.format_hours(leg["hours"])
		if leg["crosses_land"]:
			colour = LAND_LEG
			label = "crosses land"
		elif leg["shoal"] != "":
			colour = LAND_LEG
			label = "too shallow"
		elif leg["direct"]:
			var speed: float = leg["speed_kn"]
			colour = SLOW_LEG.lerp(FAST_LEG, clampf(inverse_lerp(0.4, 1.0, speed / best), 0.0, 1.0))
			label = "%.1f kn, %s" % [speed, game.format_hours(leg["hours"])]
		if leg["uncharted"] and not leg["crosses_land"] and leg["shoal"] == "":
			label += ", uncharted"
		draw_line(a, b, colour, 5.0)
		var middle := (a + b) / 2.0
		draw_string(font, middle + Vector2(-99, -9), label, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color.BLACK)
		draw_string(font, middle + Vector2(-100, -10), label, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color.WHITE)

	for i in game.plan.size():
		var mark := to_screen(game.plan[i])
		draw_circle(mark, 13.0, GOLD)
		draw_string(font, mark + Vector2(-13, 7), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 26, 18, Color.BLACK)

	# Only the ports she knows of. One she has heard of but never seen is marked as reported.
	for port: String in World.PORTS:
		if not game.knows_port(port):
			continue
		var seen: bool = game.survey.is_known(World.port_position(port))
		var p := to_screen(World.port_position(port))
		draw_circle(p, 10.0, Color("7a5230"))
		draw_circle(p, 6.0, GOLD if port == game.destination else Color.WHITE)
		var title := World.port_name(port) if seen else World.port_name(port) + " (reported)"
		draw_string(font, p + Vector2(-109, -15), title, HORIZONTAL_ALIGNMENT_CENTER, 220, 18, Color(0, 0, 0, 0.7))
		draw_string(font, p + Vector2(-110, -16), title, HORIZONTAL_ALIGNMENT_CENTER, 220, 18, Color.WHITE)

	if sailing:
		_draw_position()
	draw_rect(map_rect, Color(1, 1, 1, 0.6), false, 2.0)


## Under sail: the course she has sailed so far and where she is now.
func _draw_position() -> void:
	var sailed: Array[Vector2] = game.track
	var line := PackedVector2Array()
	for point in sailed:
		line.append(to_screen(point))
	var ship_at := to_screen(game.ship.position)
	line.append(ship_at)
	if line.size() >= 2:
		draw_polyline(line, Color.WHITE, 2.5)
	var bow: Vector2 = SailingModel.bearing_to_vector(game.ship.heading)
	draw_line(ship_at, ship_at + bow * 22.0, Color.WHITE, 3.0)
	draw_circle(ship_at, 8.0, Color.WHITE)
	draw_circle(ship_at, 5.5, Color("ff5a4a"))
