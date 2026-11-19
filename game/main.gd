extends Node2D
## Stage 1 prototype: plan a route, steer a small boat between two ports,
## sell cargo, buy upgrades. Visuals are drawn in code; the rules live in sim/.

const SailingModel = preload("res://sim/sailing_model.gd")
const ShipState = preload("res://sim/ship_state.gd")
const Trade = preload("res://sim/trade.gd")
const TimeCompression = preload("res://sim/time_compression.gd")
const RoutePlan = preload("res://sim/route_plan.gd")
const Weather = preload("res://sim/weather.gd")
const Track = preload("res://sim/track.gd")
const World = preload("res://game/world.gd")
const Chart = preload("res://game/chart.gd")
const LogScreen = preload("res://game/log_screen.gd")

const SAVE_PATH := "user://save.json"
## At 1x, one real second is one game minute.
const GAME_SECONDS_PER_REAL_SECOND := 60.0
const DOCK_RADIUS := 170.0
## How fast the sheet runs in or out while a trim button is held (degrees a second).
const SHEET_RATE_DEG := 30.0
## How close the ship has to pass a planned mark to count as rounding it.
const MARK_RADIUS := 200.0
const MAX_MARKS := 12
## A point is added to the sailed track every time the ship moves this far.
const TRACK_SPACING := 120.0
const MAX_LOG_ENTRIES := 30
const RECORD := Color("7fe7ff")
const BASE_HULL_SPEED_KN := 7.0
const AGROUND_PENALTY_S := 1800.0
const STARTING_MONEY := 100
const MINIMUM_STAKE := 40

const SEA := Color("1f6f9c")
const LAND_FILL := Color("5d8a4a")
const LAND_EDGE := Color("e3d6a1")
const GOLD := Color("ffd24a")

enum Mode { PORT, SAILING }

var ship := ShipState.new()
var mode := Mode.PORT
var wind_from := deg_to_rad(World.WIND_FROM_DEG)
var wind_kn := World.WIND_KN
var rng := RandomNumberGenerator.new()
## Today's wind as forecast in port. Under sail the real wind drifts from it.
var forecast := {}
var passage_par := 0.0
var announced_wind_from := 0.0
var time_scale := 1.0
var passage_seconds := 0.0
var current_port := "melbourne"
var destination := "geelong"
var money := STARTING_MONEY
var cargo := {}
var hold_level := 0
var sail_level := 0
var best_times := {}

## Saved route plans: route key -> Array of Vector2 marks.
var plans := {}
## Marks for the current route, in sailing order. The destination follows the last one.
var plan: Array[Vector2] = []
var next_mark := 0
var planned_hours := 0.0

## The path sailed on this passage, the log of past passages (newest first),
## and the course of the best passage on each route.
var track: Array[Vector2] = []
var ship_log: Array = []
var record_tracks := {}

var land_ahead := false
var last_safe_position := Vector2.ZERO
var anim_time := 0.0
var notice := ""
var notice_until := 0.0

var camera: Camera2D
var overlay: Overlay
var chart: Chart
var log_screen: LogScreen
var status_label: Label
var passage_label: Label
var hint_panel: PanelContainer
var hint_label: Label
var left_button: Button
var right_button: Button
var port_panel: PanelContainer
var port_title: Label
var port_report: Label
var port_money: Label
var plan_label: Label
var goods_box: VBoxContainer
var goods_count_labels := {}
var hold_button: Button
var sails_button: Button
var sail_button: Button
var destination_button: Button
var trim_button: Button
var haul_button: Button
var ease_button: Button


func _ready() -> void:
	RenderingServer.set_default_clear_color(SEA)
	rng.randomize()
	_load_game()
	_build_ui()
	_enter_port(current_port, "Welcome aboard. Buy cargo here, choose where to take it and sell it there.\nFresh cargo pays more the faster you arrive.")


func is_sailing() -> bool:
	return mode == Mode.SAILING


func _process(delta: float) -> void:
	anim_time += delta
	if mode == Mode.SAILING:
		_sail(delta)
	camera.position = ship.position
	_update_hud()
	queue_redraw()
	overlay.queue_redraw()


# --- Route planning ----------------------------------------------------------

func hull_speed() -> float:
	return BASE_HULL_SPEED_KN * Trade.sail_bonus(sail_level)


func best_speed() -> float:
	return SailingModel.best_speed_kn(wind_kn, hull_speed(), SailingModel.AUTO_TRIM_EFFICIENCY)


## The points still to sail through: start, the marks from from_mark on, the destination.
func route_points(start: Vector2, from_mark: int) -> Array[Vector2]:
	var points: Array[Vector2] = [start]
	for i in range(from_mark, plan.size()):
		points.append(plan[i])
	points.append(World.port_position(destination))
	return points


## Estimates are made for the automatic trim, so good hand trim beats them.
func estimate(points: Array[Vector2], check_land: bool = true) -> Array[Dictionary]:
	var legs := RoutePlan.legs(points, wind_from, wind_kn, hull_speed(), SailingModel.AUTO_TRIM_EFFICIENCY)
	for leg in legs:
		leg["crosses_land"] = check_land and World.segment_crosses_land(leg["from"], leg["to"])
	return legs


func plan_hours() -> float:
	return RoutePlan.total_hours(estimate(route_points(World.port_position(current_port), 0)))


## Par for today's passage: what the fresh-cargo prices are judged against.
func route_par() -> float:
	var from_deg: float = forecast["from_deg"]
	var kn: float = forecast["kn"]
	var pilot := RoutePlan.legs(World.pilot_route(current_port, destination), deg_to_rad(from_deg), kn,
		BASE_HULL_SPEED_KN, SailingModel.AUTO_TRIM_EFFICIENCY)
	return Trade.par_from_estimate(RoutePlan.total_hours(pilot))


## How far the cargo travels: the length of the pilot's route.
func route_distance_nm() -> float:
	return World.route_length_nm(World.pilot_route(current_port, destination))


func forecast_text() -> String:
	return Weather.describe(forecast)


## The mark being steered for, or the destination once all marks are rounded.
func target_point() -> Vector2:
	if next_mark < plan.size():
		return plan[next_mark]
	return World.port_position(destination)


func target_name() -> String:
	if next_mark < plan.size():
		return "mark %d" % (next_mark + 1)
	return World.port_name(destination)


func format_hours(hours: float) -> String:
	return _format_time(hours * 3600.0)


func plan_summary(detailed: bool) -> String:
	var legs := estimate(route_points(World.port_position(current_port), 0))
	var upwind := 0
	var blocked := 0
	for leg in legs:
		if leg["crosses_land"]:
			blocked += 1
		elif not leg["direct"]:
			upwind += 1
	var marks := "straight line" if plan.is_empty() else ("%d mark%s" % [plan.size(), "" if plan.size() == 1 else "s"])
	var text := "Route plan: %s, about %s." % [marks, format_hours(RoutePlan.total_hours(legs))]
	if blocked > 0:
		text += " %d leg%s land (orange)." % [blocked, " crosses" if blocked == 1 else "s cross"]
	if upwind > 0:
		text += " %d leg%s too close to the wind (red), so you would have to zig-zag there." % [upwind, " points" if upwind == 1 else "s point"]
	if detailed:
		var par := route_par()
		text += " Fresh cargo earns a premium under %s." % format_hours(Trade.premium_hours(par))
		if plan.is_empty():
			text += " Tap the water to add marks."
	return text


func plan_changed() -> void:
	plans[Trade.route_key(current_port, destination)] = plan.duplicate()
	_refresh_port_panel()
	_save_game()


func open_chart() -> void:
	port_panel.visible = false
	chart.visible = true
	chart.refresh()


func close_chart() -> void:
	chart.visible = false
	port_panel.visible = true
	_refresh_port_panel()


func _points(stored: Array) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for point: Vector2 in stored:
		points.append(point)
	return points


# --- Ship's log --------------------------------------------------------------

## The course of the best passage so far on the current route, if any.
func record_track() -> Array[Vector2]:
	return _points(record_tracks.get(Trade.route_key(current_port, destination), []))


## Turn a sailed course into the route plan.
func follow_track(points: Array[Vector2]) -> void:
	plan = Track.to_marks(points, MAX_MARKS)
	plan_changed()


func open_log() -> void:
	port_panel.visible = false
	log_screen.visible = true
	log_screen.refresh()


func close_log() -> void:
	log_screen.visible = false
	port_panel.visible = true


func follow_log_entry(index: int) -> void:
	var entry: Dictionary = ship_log[index]
	follow_track(_points(entry["track"]))
	log_screen.visible = false
	open_chart()


func _apply_wind(game_seconds: float) -> void:
	var now := Weather.wind_at(forecast, game_seconds)
	wind_from = now["from"]
	wind_kn = now["kn"]


# --- Sailing -----------------------------------------------------------------

func _rudder_input() -> float:
	var rudder := 0.0
	if left_button.is_pressed() or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		rudder -= 1.0
	if right_button.is_pressed() or Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		rudder += 1.0
	return rudder


## -1 hauls the sheet in, +1 eases it out. Only with manual trim.
func _trim_input() -> float:
	if not ship.manual_trim:
		return 0.0
	var trim := 0.0
	if haul_button.is_pressed() or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		trim -= 1.0
	if ease_button.is_pressed() or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		trim += 1.0
	return trim


func _toggle_trim() -> void:
	ship.manual_trim = not ship.manual_trim
	if ship.manual_trim:
		# Hand over with the sail set the way the automatic trim had it.
		ship.sheet_deg = SailingModel.ideal_sheet_deg(ship.true_wind_angle_deg(wind_from))
	_show_sailing_controls(mode == Mode.SAILING)
	_save_game()


func _show_sailing_controls(sailing: bool) -> void:
	left_button.visible = sailing
	right_button.visible = sailing
	trim_button.visible = sailing
	trim_button.text = "Trim: by hand" if ship.manual_trim else "Trim: auto"
	haul_button.visible = sailing and ship.manual_trim
	ease_button.visible = sailing and ship.manual_trim


func _in_no_go() -> bool:
	return SailingModel.in_no_go(ship.true_wind_angle_deg(wind_from))


func _advance_marks() -> void:
	var dest_pos := World.port_position(destination)
	while next_mark < plan.size():
		var mark := plan[next_mark]
		var after := plan[next_mark + 1] if next_mark + 1 < plan.size() else dest_pos
		var rounded := ship.position.distance_to(mark) < MARK_RADIUS
		# Already nearer the following point than the mark is: count it as passed.
		var passed := ship.position.distance_to(after) < mark.distance_to(after)
		if not (rounded or passed):
			break
		next_mark += 1


func _sail(delta: float) -> void:
	var rudder := _rudder_input()
	var trim := _trim_input()
	ship.sheet_deg = clampf(ship.sheet_deg + trim * SHEET_RATE_DEG * delta, 5.0, 90.0)
	var dest_pos := World.port_position(destination)
	_apply_wind(passage_seconds)
	if absf(wrapf(wind_from - announced_wind_from, -PI, PI)) > deg_to_rad(10.0):
		announced_wind_from = wind_from
		time_scale = 1.0
		_show_notice("Wind shift: now from the %s at %d kn. Check your course." % [
			Weather.compass_name(rad_to_deg(wind_from)), roundi(wind_kn)], 5.0)
	var in_irons := _in_no_go() and ship.speed_kn < 1.5

	land_ahead = false
	var ahead := SailingModel.bearing_to_vector(ship.heading)
	var to_destination := ship.position.distance_to(dest_pos)
	for distance: float in [150.0, 300.0, 450.0, 600.0]:
		# The shore behind the port we are heading for is not a hazard.
		if distance > to_destination:
			break
		var probe := ship.position + ahead * distance
		if World.is_blocked(probe):
			land_ahead = true
			break

	# Land, the destination and the next mark are all places a decision is due.
	var hazard := minf(World.distance_to_land(ship.position), ship.position.distance_to(target_point()))
	hazard = minf(hazard, to_destination)
	var target := TimeCompression.target_scale(rudder != 0.0 or trim != 0.0, in_irons, land_ahead, hazard)
	time_scale = TimeCompression.approach(time_scale, target, delta)

	var dt := delta * GAME_SECONDS_PER_REAL_SECOND * time_scale
	ship.step(dt, rudder, wind_from, wind_kn)
	passage_seconds += dt

	if World.is_blocked(ship.position):
		var off_chart := not World.in_bounds(ship.position)
		ship.position = last_safe_position
		ship.speed_kn = 0.0
		ship.heading = wrapf(ship.heading + PI, 0.0, TAU)
		if off_chart:
			_show_notice("That way lies the open ocean, and she is no ocean ship. Turned back.", 6.0)
		else:
			passage_seconds += AGROUND_PENALTY_S
			_show_notice("Ran aground! Lost 30 minutes getting her off. Steer back to open water.", 6.0)
	else:
		last_safe_position = ship.position
		if ship.position.distance_to(track[track.size() - 1]) > TRACK_SPACING:
			track.append(ship.position)

	_advance_marks()
	if ship.position.distance_to(dest_pos) < DOCK_RADIUS:
		_arrive()


func _set_sail() -> void:
	var from_pos := World.port_position(current_port)
	next_mark = 0
	_apply_wind(0.0)
	announced_wind_from = wind_from
	planned_hours = plan_hours()
	passage_par = route_par()
	track = [from_pos]
	var bearing := SailingModel.vector_to_bearing(target_point() - from_pos)
	# If the first leg is straight upwind, start on the nearer tack instead.
	var off_wind := wrapf(bearing - wind_from, -PI, PI)
	if absf(off_wind) < deg_to_rad(55.0):
		var side := 1.0 if off_wind >= 0.0 else -1.0
		bearing = wrapf(wind_from + side * deg_to_rad(55.0), 0.0, TAU)

	ship.position = from_pos
	ship.heading = bearing
	ship.speed_kn = 2.0
	ship.hull_speed_kn = hull_speed()
	last_safe_position = from_pos
	passage_seconds = 0.0
	time_scale = 1.0
	notice_until = 0.0
	mode = Mode.SAILING
	port_panel.visible = false
	chart.visible = false
	log_screen.visible = false
	ship.sheet_deg = SailingModel.ideal_sheet_deg(ship.true_wind_angle_deg(wind_from))
	_show_sailing_controls(true)


func _arrive() -> void:
	var hours := passage_seconds / 3600.0
	var par := passage_par
	var distance_nm := route_distance_nm()
	var key := Trade.route_key(current_port, destination)
	var lines: Array[String] = []

	track.append(World.port_position(destination))
	var sailed := Track.simplify(track, 25.0)
	var is_record := not best_times.has(key) or hours < float(best_times[key])
	var arrival := "Arrived at %s in %s." % [World.port_name(destination), _format_time(passage_seconds)]
	if is_record:
		best_times[key] = hours
		record_tracks[key] = sailed
		arrival += " New best passage! Her course is saved in the log."
	lines.append(arrival)
	var difference := absf(hours - planned_hours)
	if difference < 0.1:
		lines.append("Right on your plan of %s." % format_hours(planned_hours))
	else:
		lines.append("Your plan said %s: you were %s %s." % [format_hours(planned_hours), format_hours(difference),
			"faster" if hours < planned_hours else "slower"])

	var total := 0
	for good_id: String in cargo:
		var units: int = cargo[good_id]
		if units <= 0:
			continue
		var price := Trade.sale_price(good_id, hours, par, distance_nm)
		var good: Dictionary = Trade.GOODS[good_id]
		var condition := ""
		if good["perishable"]:
			var multiplier := Trade.freshness_multiplier(hours, par)
			if multiplier >= 1.3:
				condition = " (arrived fresh: premium price)"
			elif multiplier >= 1.0:
				condition = " (good condition)"
			else:
				condition = " (past its best: sold cheap)"
		lines.append("Sold %d %s at $%d each%s." % [units, good["name"], price, condition])
		total += units * price
	if total > 0:
		lines.append("Takings: $%d." % total)
	else:
		lines.append("You arrived with an empty hold.")
	money += total
	ship_log.push_front({
		"from": current_port,
		"to": destination,
		"hours": hours,
		"wind_deg": forecast["from_deg"],
		"wind_kn": forecast["kn"],
		"takings": total,
		"record": is_record,
		"track": sailed,
	})
	if ship_log.size() > MAX_LOG_ENTRIES:
		ship_log.resize(MAX_LOG_ENTRIES)
	_enter_port(destination, "\n".join(lines))


# --- Port --------------------------------------------------------------------

func _enter_port(port: String, report: String) -> void:
	mode = Mode.PORT
	# By default the next trip is back the way she came.
	var came_from := current_port
	current_port = port
	destination = came_from if came_from != port else World.destinations(port)[0]
	cargo = {}
	plan = _points(plans.get(Trade.route_key(current_port, destination), []))
	next_mark = 0
	forecast = Weather.roll(rng)
	_apply_wind(0.0)
	ship.position = World.port_position(port)
	ship.speed_kn = 0.0
	time_scale = 1.0
	land_ahead = false
	if money < MINIMUM_STAKE:
		money = MINIMUM_STAKE
		report += "\nThe harbourmaster advances you enough to buy a small cargo."
	port_title.text = World.port_name(port)
	port_report.text = report
	_rebuild_goods_rows()
	_refresh_port_panel()
	port_panel.visible = true
	chart.visible = false
	log_screen.visible = false
	_show_sailing_controls(false)
	_save_game()


## Pick the next port in the list as the destination.
func _cycle_destination() -> void:
	var options := World.destinations(current_port)
	destination = options[(options.find(destination) + 1) % options.size()]
	plan = _points(plans.get(Trade.route_key(current_port, destination), []))
	next_mark = 0
	_refresh_port_panel()


func _cargo_units() -> int:
	var units := 0
	for good_id: String in cargo:
		units += int(cargo[good_id])
	return units


func _change_cargo(good_id: String, amount: int) -> void:
	var price: int = Trade.GOODS[good_id]["buy"]
	var held: int = cargo.get(good_id, 0)
	if amount > 0:
		var space := Trade.hold_capacity(hold_level) - _cargo_units()
		amount = mini(amount, mini(space, money / price))
	else:
		amount = -mini(-amount, held)
	cargo[good_id] = held + amount
	money -= amount * price
	_refresh_port_panel()


func _buy_upgrade(kind: String) -> void:
	var level := hold_level if kind == "hold" else sail_level
	var cost := Trade.upgrade_cost(kind, level)
	if cost < 0 or money < cost:
		return
	money -= cost
	if kind == "hold":
		hold_level += 1
	else:
		sail_level += 1
	_refresh_port_panel()
	_save_game()


func _upgrade_text(label: String, kind: String, level: int) -> String:
	var cost := Trade.upgrade_cost(kind, level)
	if cost < 0:
		return "%s: fully upgraded" % label
	return "%s  $%d" % [label, cost]


func _refresh_port_panel() -> void:
	port_money.text = "Money: $%d     Hold: %d / %d" % [money, _cargo_units(), Trade.hold_capacity(hold_level)]
	plan_label.text = "Wind today: %s, and it will shift at sea. %s" % [forecast_text(), plan_summary(false)]
	for good_id: String in goods_count_labels:
		var count_label: Label = goods_count_labels[good_id]
		count_label.text = str(int(cargo.get(good_id, 0)))
	hold_button.text = _upgrade_text("Bigger hold (+%d)" % Trade.HOLD_PER_LEVEL, "hold", hold_level)
	hold_button.disabled = Trade.upgrade_cost("hold", hold_level) < 0 or money < Trade.upgrade_cost("hold", hold_level)
	sails_button.text = _upgrade_text("Better sails (+6% speed)", "sails", sail_level)
	sails_button.disabled = Trade.upgrade_cost("sails", sail_level) < 0 or money < Trade.upgrade_cost("sails", sail_level)
	var key := Trade.route_key(current_port, destination)
	var record := "no passage yet"
	if best_times.has(key):
		record = "best " + _format_time(float(best_times[key]) * 3600.0)
	sail_button.text = "Set sail for %s  (%s)" % [World.port_name(destination), record]
	destination_button.text = "To: %s, %d nm (change)" % [World.port_name(destination), roundi(route_distance_nm())]


func _rebuild_goods_rows() -> void:
	for child in goods_box.get_children():
		child.queue_free()
	goods_count_labels.clear()
	for good_id in Trade.goods_sold_at(current_port):
		var good: Dictionary = Trade.GOODS[good_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var kind := "spoils: pays more for a fast passage" if good["perishable"] else "keeps: small steady profit"
		var name_label := Label.new()
		name_label.text = "%s  $%d  (%s)" % [good["name"], good["buy"], kind]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(_make_button("-", _change_cargo.bind(good_id, -1), 60))
		var count_label := Label.new()
		count_label.custom_minimum_size = Vector2(44, 0)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(count_label)
		goods_count_labels[good_id] = count_label
		row.add_child(_make_button("+", _change_cargo.bind(good_id, 1), 60))
		row.add_child(_make_button("Fill", _change_cargo.bind(good_id, 999), 90))
		goods_box.add_child(row)


# --- UI ----------------------------------------------------------------------

func _make_button(text: String, action: Callable, min_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 56)
	if action.is_valid():
		button.pressed.connect(action)
	return button


func _make_helm_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 72)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _build_ui() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(0.75, 0.75)
	add_child(camera)

	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 24
	root.theme = ui_theme
	layer.add_child(root)

	overlay = Overlay.new()
	overlay.game = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	status_label = Label.new()
	status_label.position = Vector2(20, 12)
	root.add_child(status_label)

	passage_label = Label.new()
	passage_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	passage_label.offset_left = -820
	passage_label.offset_right = -20
	passage_label.offset_top = 12
	passage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	passage_label.add_theme_font_size_override("font_size", 20)
	root.add_child(passage_label)

	hint_panel = PanelContainer.new()
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint_panel.offset_left = -330
	hint_panel.offset_right = 330
	hint_panel.offset_top = 64
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label = Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.custom_minimum_size = Vector2(640, 0)
	hint_panel.add_child(hint_label)
	root.add_child(hint_panel)

	left_button = _make_helm_button("<")
	left_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left_button.offset_left = 30
	left_button.offset_right = 200
	left_button.offset_top = -200
	left_button.offset_bottom = -30
	root.add_child(left_button)

	right_button = _make_helm_button(">")
	right_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right_button.offset_left = -200
	right_button.offset_right = -30
	right_button.offset_top = -200
	right_button.offset_bottom = -30
	root.add_child(right_button)

	# Sail trim: a switch between automatic and by hand, and the two sheet buttons.
	trim_button = _make_button("", _toggle_trim, 170)
	trim_button.focus_mode = Control.FOCUS_NONE
	trim_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	trim_button.offset_left = 30
	trim_button.offset_right = 200
	trim_button.offset_top = -366
	trim_button.offset_bottom = -306
	trim_button.add_theme_font_size_override("font_size", 20)
	root.add_child(trim_button)

	haul_button = _make_button("Haul in", Callable(), 170)
	haul_button.focus_mode = Control.FOCUS_NONE
	haul_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	haul_button.offset_left = 30
	haul_button.offset_right = 200
	haul_button.offset_top = -292
	haul_button.offset_bottom = -214
	root.add_child(haul_button)

	ease_button = _make_button("Ease out", Callable(), 170)
	ease_button.focus_mode = Control.FOCUS_NONE
	ease_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ease_button.offset_left = -200
	ease_button.offset_right = -30
	ease_button.offset_top = -292
	ease_button.offset_bottom = -214
	root.add_child(ease_button)

	port_panel = PanelContainer.new()
	port_panel.set_anchors_preset(Control.PRESET_CENTER)
	port_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	port_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	port_panel.custom_minimum_size = Vector2(860, 0)
	root.add_child(port_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	port_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	port_title = Label.new()
	port_title.add_theme_font_size_override("font_size", 34)
	box.add_child(port_title)
	port_report = Label.new()
	port_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	port_report.custom_minimum_size = Vector2(810, 0)
	port_report.add_theme_font_size_override("font_size", 20)
	box.add_child(port_report)
	box.add_child(HSeparator.new())
	port_money = Label.new()
	box.add_child(port_money)
	goods_box = VBoxContainer.new()
	goods_box.add_theme_constant_override("separation", 8)
	box.add_child(goods_box)
	box.add_child(HSeparator.new())

	var plan_row := HBoxContainer.new()
	plan_row.add_theme_constant_override("separation", 12)
	plan_label = Label.new()
	plan_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plan_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plan_label.add_theme_font_size_override("font_size", 20)
	plan_row.add_child(plan_label)
	plan_row.add_child(_make_button("Plan route", open_chart, 150))
	plan_row.add_child(_make_button("Ship's log", open_log, 150))
	box.add_child(plan_row)

	var upgrades := HBoxContainer.new()
	upgrades.add_theme_constant_override("separation", 12)
	hold_button = _make_button("", _buy_upgrade.bind("hold"), 0)
	hold_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sails_button = _make_button("", _buy_upgrade.bind("sails"), 0)
	sails_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades.add_child(hold_button)
	upgrades.add_child(sails_button)
	box.add_child(upgrades)
	var departure := HBoxContainer.new()
	departure.add_theme_constant_override("separation", 12)
	destination_button = _make_button("", _cycle_destination, 330)
	destination_button.custom_minimum_size = Vector2(330, 64)
	departure.add_child(destination_button)
	sail_button = _make_button("", _set_sail, 0)
	sail_button.custom_minimum_size = Vector2(0, 64)
	sail_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	departure.add_child(sail_button)
	box.add_child(departure)

	chart = Chart.new()
	chart.setup(self)
	chart.visible = false
	root.add_child(chart)

	log_screen = LogScreen.new()
	log_screen.setup(self)
	log_screen.visible = false
	root.add_child(log_screen)


func _show_notice(text: String, seconds: float) -> void:
	notice = text
	notice_until = anim_time + seconds


func _current_hint() -> String:
	if mode != Mode.SAILING:
		return ""
	if anim_time < notice_until:
		return notice
	if land_ahead:
		return "Land ahead! Turn away."
	if _in_no_go():
		return "Sails flapping! You can't sail straight into the wind. Steer out of the red zone."
	if passage_seconds < 1200.0:
		return "Hold < or > to steer. The gold arrow points to %s." % target_name()
	var to_target := SailingModel.vector_to_bearing(target_point() - ship.position)
	if not SailingModel.can_lay(SailingModel.true_wind_angle_deg(to_target, wind_from)):
		return "%s is upwind. Zig-zag towards it, keeping just outside the red zone." % target_name().capitalize()
	return ""


func _format_time(seconds: float) -> String:
	var minutes := int(seconds / 60.0)
	return "%dh %02dm" % [minutes / 60, minutes % 60]


func _update_hud() -> void:
	var sailing := mode == Mode.SAILING
	status_label.visible = sailing
	passage_label.visible = sailing
	var hint := _current_hint()
	hint_panel.visible = hint != ""
	hint_label.text = hint
	if not sailing:
		return
	var parts: Array[String] = []
	for good_id: String in cargo:
		if int(cargo[good_id]) > 0:
			parts.append("%d %s" % [cargo[good_id], Trade.GOODS[good_id]["name"]])
	var cargo_text := ", ".join(parts) if not parts.is_empty() else "empty"
	status_label.text = "$%d   Cargo: %s" % [money, cargo_text]
	var remaining := RoutePlan.total_hours(estimate(route_points(ship.position, next_mark), false))
	var projected := passage_seconds / 3600.0 + remaining
	passage_label.text = "Sailed %s   On course for %s (plan %s)   Time x%d" % [
		_format_time(passage_seconds), format_hours(projected), format_hours(planned_hours), roundi(time_scale)]


# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	_draw_waves()
	# Only the land near the ship is drawn.
	var view_size := get_viewport_rect().size / camera.zoom
	var view := Rect2(ship.position - view_size / 2.0, view_size).grow(40.0)
	var triangles := World.triangles()
	for i in range(0, triangles.size(), 3):
		var a := triangles[i]
		var b := triangles[i + 1]
		var c := triangles[i + 2]
		var bounds := Rect2(a, Vector2.ZERO).expand(b).expand(c)
		if bounds.intersects(view):
			draw_colored_polygon(PackedVector2Array([a, b, c]), LAND_FILL)
	for polygon in World.land():
		for i in polygon.size():
			var from := polygon[i]
			var to := polygon[(i + 1) % polygon.size()]
			if Rect2(from, Vector2.ZERO).expand(to).grow(10.0).intersects(view):
				draw_line(from, to, LAND_EDGE, 10.0)
	_draw_ports()
	if mode == Mode.SAILING:
		_draw_record()
		_draw_plan()
		_draw_ship()


func _draw_waves() -> void:
	var view := get_viewport_rect().size / camera.zoom
	var top_left := ship.position - view / 2.0
	var spacing := 180
	var across := SailingModel.bearing_to_vector(wind_from + PI / 2.0)
	var first_x := int(floor(top_left.x / spacing))
	var first_y := int(floor(top_left.y / spacing))
	for ix in range(first_x, first_x + int(view.x / spacing) + 2):
		for iy in range(first_y, first_y + int(view.y / spacing) + 2):
			var seed_value := posmod(hash(Vector2i(ix, iy)), 8100)
			var p := Vector2(ix * spacing + seed_value % 90, iy * spacing + seed_value / 90)
			draw_line(p - across * 11.0, p + across * 11.0, Color(1, 1, 1, 0.16), 2.0)


func _draw_ports() -> void:
	var font := ThemeDB.fallback_font
	for port: String in World.PORTS:
		var p := World.port_position(port)
		if mode == Mode.SAILING and port == destination:
			draw_arc(p, DOCK_RADIUS, 0.0, TAU, 48, GOLD, 4.0)
		draw_circle(p, 26.0, Color("7a5230"))
		draw_circle(p, 14.0, Color("f4ecd8"))
		draw_string(font, p + Vector2(-120, -44), World.port_name(port), HORIZONTAL_ALIGNMENT_CENTER, 240, 30, Color.WHITE)


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
		draw_arc(plan[i], MARK_RADIUS, 0.0, TAU, 48, Color(colour, colour.a * 0.5), 3.0)
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

	draw_set_transform(ship.position, ship.heading, Vector2.ONE)
	var hull := PackedVector2Array([Vector2(0, -36), Vector2(11, -14), Vector2(12, 18), Vector2(7, 30),
		Vector2(-7, 30), Vector2(-12, 18), Vector2(-11, -14)])
	draw_colored_polygon(hull, Color("6b4423"))
	hull.append(hull[0])
	draw_polyline(hull, Color("2e1c0d"), 2.0)
	# The sail swings out to the downwind side, and flaps in the no-go zone.
	var ideal_sheet := SailingModel.ideal_sheet_deg(twa)
	var sheet := deg_to_rad(ship.sheet_deg if ship.manual_trim else ideal_sheet)
	if ship.manual_trim and ship.sheet_deg > ideal_sheet + 15.0:
		# Eased too far: the sail spills the wind and flutters.
		sheet += sin(anim_time * 18.0) * 0.1
	if no_go:
		sheet = deg_to_rad(6.0) + sin(anim_time * 18.0) * 0.14
	var side := 1.0 if side_angle >= 0.0 else -1.0
	var mast := Vector2(0, -10)
	draw_line(mast, mast + Vector2(0, 1).rotated(sheet * side) * 42.0, Color.WHITE, 6.0)
	draw_circle(mast, 4.0, Color("2e1c0d"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Screen-space extras: wind dial, minimap and the speed panel.
class Overlay extends Control:
	var game

	func _draw() -> void:
		if not game.is_sailing():
			return
		var font := ThemeDB.fallback_font
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
		draw_string(font, Vector2(4, 214), "Wind %s %d kn" % [Weather.compass_name(rad_to_deg(game.wind_from)), roundi(game.wind_kn)],
			HORIZONTAL_ALIGNMENT_CENTER, 160, 22, Color.WHITE)

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
		var target: Vector2 = game.target_point()
		draw_circle(origin + target * map_scale, 4.0, GOLD)
		var ship_at: Vector2 = origin + game.ship.position * map_scale
		var bow: Vector2 = SailingModel.bearing_to_vector(game.ship.heading)
		draw_line(ship_at, ship_at + bow * 14.0, Color.WHITE, 2.0)
		draw_circle(ship_at, 4.0, Color("ff5a4a"))
		draw_rect(Rect2(origin, map_size), Color(1, 1, 1, 0.6), false, 2.0)

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

		draw_string(font, Vector2(x, y + 78.0), "%s: wind %d° off the bow" % [SailingModel.point_of_sail(twa), roundi(twa)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		draw_string(font, Vector2(x, y + 106.0), "This heading is worth %.1f kn (her best is %.1f)" % [worth, best],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

		var course: float = SailingModel.vector_to_bearing(game.ship.velocity) if speed > 0.05 else heading
		var made_good: float = SailingModel.vmg_kn(speed, course, SailingModel.vector_to_bearing(to_target))
		var progress := "Towards %s: %.1f kn" % [game.target_name(), made_good]
		if made_good < 0.0:
			progress = "Moving away from %s" % game.target_name()
		draw_string(font, Vector2(x, y + 134.0), progress, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD)

		var tip: String = SailingModel.point_of_sail_tip(twa)
		if not SailingModel.in_no_go(twa):
			if speed < worth * 0.8:
				tip = "Picking up speed. Every turn costs some, so turn only when you need to."
			elif speed > worth * 1.15:
				tip = "Slowing down: this heading is worth less than the last one."
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


# --- Saving ------------------------------------------------------------------

func _save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	var saved_plans := {}
	for key: String in plans:
		saved_plans[key] = _pack(plans[key])
	var saved_records := {}
	for key: String in record_tracks:
		saved_records[key] = _pack(record_tracks[key])
	var saved_log: Array = []
	for entry: Dictionary in ship_log:
		var saved_entry := entry.duplicate()
		saved_entry["track"] = _pack(entry["track"])
		saved_log.append(saved_entry)
	file.store_string(JSON.stringify({
		"money": money,
		"port": current_port,
		"hold_level": hold_level,
		"sail_level": sail_level,
		"best_times": best_times,
		"plans": saved_plans,
		"manual_trim": ship.manual_trim,
		"record_tracks": saved_records,
		"ship_log": saved_log,
	}))


## Points as [[x, y], ...] whole numbers for the save file.
func _pack(points: Array) -> Array:
	var packed: Array = []
	for point: Vector2 in points:
		packed.append([roundi(point.x), roundi(point.y)])
	return packed


## The reverse of _pack, dropping anything malformed or off the water.
func _unpack(entries: Variant, limit: int) -> Array:
	var points: Array = []
	if typeof(entries) != TYPE_ARRAY:
		return points
	for entry: Variant in entries:
		if typeof(entry) == TYPE_ARRAY and entry.size() == 2 and points.size() < limit:
			var point := Vector2(float(entry[0]), float(entry[1]))
			if not World.is_blocked(point):
				points.append(point)
	return points


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	money = int(data.get("money", STARTING_MONEY))
	hold_level = clampi(int(data.get("hold_level", 0)), 0, Trade.MAX_UPGRADE_LEVEL)
	sail_level = clampi(int(data.get("sail_level", 0)), 0, Trade.MAX_UPGRADE_LEVEL)
	var port: String = str(data.get("port", "melbourne"))
	current_port = port if World.PORTS.has(port) else "melbourne"
	ship.manual_trim = bool(data.get("manual_trim", false))
	var times: Variant = data.get("best_times", {})
	if typeof(times) == TYPE_DICTIONARY:
		best_times = times
	var saved_plans: Variant = data.get("plans", {})
	if typeof(saved_plans) == TYPE_DICTIONARY:
		for key: String in saved_plans:
			plans[key] = _unpack(saved_plans[key], MAX_MARKS)
	var saved_records: Variant = data.get("record_tracks", {})
	if typeof(saved_records) == TYPE_DICTIONARY:
		for key: String in saved_records:
			record_tracks[key] = _unpack(saved_records[key], 500)
	var saved_log: Variant = data.get("ship_log", [])
	if typeof(saved_log) == TYPE_ARRAY:
		for saved_entry: Variant in saved_log:
			if typeof(saved_entry) != TYPE_DICTIONARY or ship_log.size() >= MAX_LOG_ENTRIES:
				continue
			var from_port: String = str(saved_entry.get("from", ""))
			var to_port: String = str(saved_entry.get("to", ""))
			if not World.PORTS.has(from_port) or not World.PORTS.has(to_port):
				continue
			ship_log.append({
				"from": from_port,
				"to": to_port,
				"hours": float(saved_entry.get("hours", 0.0)),
				"wind_deg": float(saved_entry.get("wind_deg", 0.0)),
				"wind_kn": float(saved_entry.get("wind_kn", 0.0)),
				"takings": int(saved_entry.get("takings", 0)),
				"record": bool(saved_entry.get("record", false)),
				"track": _unpack(saved_entry.get("track", []), 500),
			})
