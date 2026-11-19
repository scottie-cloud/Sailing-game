extends Control
## The chart used in port to plan a route. Tap the water to add marks; each
## leg is coloured by how well the boat can sail it and labelled with an
## estimated speed and time.

const SailingModel = preload("res://sim/sailing_model.gd")
const World = preload("res://game/world.gd")

const BAR_HEIGHT := 112.0
const SEA := Color("1f6f9c")
const LAND_FILL := Color("5d8a4a")
const GOLD := Color("ffd24a")
const RECORD := Color("7fe7ff")
const SLOW_LEG := Color("ffe36b")
const FAST_LEG := Color("5fe36a")
const UPWIND_LEG := Color("ff5a4a")
const LAND_LEG := Color("ff9f1c")

var game
var summary: Label
var record_button: Button


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
	summary.add_theme_font_size_override("font_size", 20)
	bar.add_child(summary)
	bar.add_child(_button("Pilot", use_pilot))
	record_button = _button("Record", use_record)
	bar.add_child(record_button)
	bar.add_child(_button("Undo", undo))
	bar.add_child(_button("Clear", clear))
	bar.add_child(_button("Done", _done))


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(112, 64)
	button.pressed.connect(action)
	return button


func refresh() -> void:
	summary.text = game.plan_summary(true)
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


## Replace the plan with the pilot's safe course around the land.
func use_pilot() -> void:
	game.follow_track(World.pilot_route(game.current_port, game.destination))
	refresh()


## Replace the plan with the course of the best passage on this route.
func use_record() -> void:
	var record: Array[Vector2] = game.record_track()
	if record.is_empty():
		return
	game.follow_track(record)
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
	if game.plan.size() >= game.MAX_MARKS:
		return
	if World.is_blocked(world_point):
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
		draw_colored_polygon(PackedVector2Array([to_screen(triangles[i]), to_screen(triangles[i + 1]), to_screen(triangles[i + 2])]), LAND_FILL)

	# Wind arrows across the open water.
	var blowing_to: Vector2 = SailingModel.bearing_to_vector(game.wind_from + PI)
	var barb := blowing_to.orthogonal() * 6.0
	for x in range(1200, int(World.SIZE.x), 2400):
		for y in range(1200, int(World.SIZE.y), 2400):
			var at := Vector2(x, y)
			if World.distance_to_land(at) < 400.0:
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
	if not record.is_empty():
		draw_string(font, map_rect.position + Vector2(12, 52), "Dashed blue: your record course", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, RECORD)

	var route: Array[Vector2] = game.route_points(World.port_position(game.current_port), 0)
	var legs: Array[Dictionary] = game.estimate(route)
	var best: float = game.best_speed()

	# The no-go wedge at the start of the last leg: where the next mark can't go.
	var last_start := to_screen(route[route.size() - 2])
	var wedge := PackedVector2Array([last_start])
	for i in 9:
		var spread := deg_to_rad(lerpf(-SailingModel.NO_GO_DEG, SailingModel.NO_GO_DEG, i / 8.0))
		wedge.append(last_start + SailingModel.bearing_to_vector(game.wind_from + spread) * 90.0)
	draw_colored_polygon(wedge, Color(0.9, 0.15, 0.1, 0.3))

	for leg in legs:
		var a := to_screen(leg["from"])
		var b := to_screen(leg["to"])
		var colour := UPWIND_LEG
		var label := "zig-zag, about %s" % game.format_hours(leg["hours"])
		if leg["crosses_land"]:
			colour = LAND_LEG
			label = "crosses land"
		elif leg["direct"]:
			var speed: float = leg["speed_kn"]
			colour = SLOW_LEG.lerp(FAST_LEG, clampf(inverse_lerp(0.4, 1.0, speed / best), 0.0, 1.0))
			label = "%.1f kn, %s" % [speed, game.format_hours(leg["hours"])]
		draw_line(a, b, colour, 5.0)
		var middle := (a + b) / 2.0
		draw_string(font, middle + Vector2(-99, -9), label, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color.BLACK)
		draw_string(font, middle + Vector2(-100, -10), label, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color.WHITE)

	for i in game.plan.size():
		var mark := to_screen(game.plan[i])
		draw_circle(mark, 13.0, GOLD)
		draw_string(font, mark + Vector2(-13, 7), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 26, 18, Color.BLACK)

	for port: String in World.PORTS:
		var p := to_screen(World.port_position(port))
		draw_circle(p, 10.0, Color("7a5230"))
		draw_circle(p, 6.0, GOLD if port == game.destination else Color.WHITE)
		draw_string(font, p + Vector2(-90, -16), World.port_name(port), HORIZONTAL_ALIGNMENT_CENTER, 180, 20, Color.WHITE)

	draw_rect(map_rect, Color(1, 1, 1, 0.6), false, 2.0)
