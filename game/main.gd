extends Node2D
## Stage 1 prototype: steer a small boat between two ports, sell cargo,
## buy upgrades. Everything visual is drawn in code; the rules live in sim/.

const SailingModel = preload("res://sim/sailing_model.gd")
const ShipState = preload("res://sim/ship_state.gd")
const Trade = preload("res://sim/trade.gd")
const TimeCompression = preload("res://sim/time_compression.gd")
const World = preload("res://game/world.gd")

const SAVE_PATH := "user://save.json"
## At 1x, one real second is one game minute.
const GAME_SECONDS_PER_REAL_SECOND := 60.0
const DOCK_RADIUS := 170.0
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
var time_scale := 1.0
var passage_seconds := 0.0
var current_port := "haven"
var destination := "eastpoint"
var money := STARTING_MONEY
var cargo := {}
var hold_level := 0
var sail_level := 0
var best_times := {}

var land_ahead := false
var last_safe_position := Vector2.ZERO
var anim_time := 0.0
var notice := ""
var notice_until := 0.0

var camera: Camera2D
var overlay: Overlay
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
var goods_box: VBoxContainer
var goods_count_labels := {}
var hold_button: Button
var sails_button: Button
var sail_button: Button


func _ready() -> void:
	RenderingServer.set_default_clear_color(SEA)
	_load_game()
	_build_ui()
	_enter_port(current_port, "Welcome aboard. Buy cargo here, sail it to %s and sell it.\nFresh cargo pays more the faster you arrive." % World.port_name(World.other_port(current_port)))


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


# --- Sailing -----------------------------------------------------------------

func _rudder_input() -> float:
	var rudder := 0.0
	if left_button.is_pressed() or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		rudder -= 1.0
	if right_button.is_pressed() or Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		rudder += 1.0
	return rudder


func _in_no_go() -> bool:
	return SailingModel.in_no_go(ship.true_wind_angle_deg(wind_from))


func _sail(delta: float) -> void:
	var rudder := _rudder_input()
	var dest_pos := World.port_position(destination)
	var in_irons := _in_no_go() and ship.speed_kn < 1.5

	land_ahead = false
	var ahead := SailingModel.bearing_to_vector(ship.heading)
	var to_destination := ship.position.distance_to(dest_pos)
	for distance: float in [150.0, 300.0, 450.0, 600.0]:
		# The shore behind the port we are heading for is not a hazard.
		if distance > to_destination:
			break
		var probe := ship.position + ahead * distance
		if World.is_land(probe):
			land_ahead = true
			break

	var hazard := minf(World.distance_to_land(ship.position), ship.position.distance_to(dest_pos))
	var target := TimeCompression.target_scale(rudder != 0.0, in_irons, land_ahead, hazard)
	time_scale = TimeCompression.approach(time_scale, target, delta)

	var dt := delta * GAME_SECONDS_PER_REAL_SECOND * time_scale
	ship.step(dt, rudder, wind_from, wind_kn)
	passage_seconds += dt

	if World.is_land(ship.position):
		ship.position = last_safe_position
		ship.speed_kn = 0.0
		ship.heading = wrapf(ship.heading + PI, 0.0, TAU)
		passage_seconds += AGROUND_PENALTY_S
		_show_notice("Ran aground! Lost 30 minutes getting her off. Steer back to open water.", 6.0)
	else:
		last_safe_position = ship.position

	if ship.position.distance_to(dest_pos) < DOCK_RADIUS:
		_arrive()


func _set_sail() -> void:
	var from_pos := World.port_position(current_port)
	var bearing := SailingModel.vector_to_bearing(World.port_position(destination) - from_pos)
	# If the destination is straight upwind, start on the nearer tack instead.
	var off_wind := wrapf(bearing - wind_from, -PI, PI)
	if absf(off_wind) < deg_to_rad(55.0):
		var side := 1.0 if off_wind >= 0.0 else -1.0
		bearing = wrapf(wind_from + side * deg_to_rad(55.0), 0.0, TAU)

	ship.position = from_pos
	ship.heading = bearing
	ship.speed_kn = 2.0
	ship.hull_speed_kn = BASE_HULL_SPEED_KN * Trade.sail_bonus(sail_level)
	last_safe_position = from_pos
	passage_seconds = 0.0
	time_scale = 1.0
	notice_until = 0.0
	mode = Mode.SAILING
	port_panel.visible = false
	left_button.visible = true
	right_button.visible = true


func _arrive() -> void:
	var hours := passage_seconds / 3600.0
	var par := Trade.par_hours(current_port, destination)
	var key := Trade.route_key(current_port, destination)
	var lines: Array[String] = []

	var arrival := "Arrived at %s in %s." % [World.port_name(destination), _format_time(passage_seconds)]
	if not best_times.has(key) or hours < float(best_times[key]):
		best_times[key] = hours
		arrival += " New best passage!"
	lines.append(arrival)

	var total := 0
	for good_id: String in cargo:
		var units: int = cargo[good_id]
		if units <= 0:
			continue
		var price := Trade.sale_price(good_id, hours, par)
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
	_enter_port(destination, "\n".join(lines))


# --- Port --------------------------------------------------------------------

func _enter_port(port: String, report: String) -> void:
	mode = Mode.PORT
	current_port = port
	destination = World.other_port(port)
	cargo = {}
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
	left_button.visible = false
	right_button.visible = false
	_save_game()


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
	passage_label.offset_left = -620
	passage_label.offset_right = -20
	passage_label.offset_top = 12
	passage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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

	port_panel = PanelContainer.new()
	port_panel.set_anchors_preset(Control.PRESET_CENTER)
	port_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	port_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	port_panel.custom_minimum_size = Vector2(820, 0)
	root.add_child(port_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	port_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	port_title = Label.new()
	port_title.add_theme_font_size_override("font_size", 36)
	box.add_child(port_title)
	port_report = Label.new()
	port_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	port_report.custom_minimum_size = Vector2(770, 0)
	box.add_child(port_report)
	box.add_child(HSeparator.new())
	port_money = Label.new()
	box.add_child(port_money)
	goods_box = VBoxContainer.new()
	goods_box.add_theme_constant_override("separation", 8)
	box.add_child(goods_box)
	box.add_child(HSeparator.new())
	var upgrades := HBoxContainer.new()
	upgrades.add_theme_constant_override("separation", 12)
	hold_button = _make_button("", _buy_upgrade.bind("hold"), 0)
	hold_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sails_button = _make_button("", _buy_upgrade.bind("sails"), 0)
	sails_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades.add_child(hold_button)
	upgrades.add_child(sails_button)
	box.add_child(upgrades)
	sail_button = _make_button("", _set_sail, 0)
	sail_button.custom_minimum_size = Vector2(0, 72)
	box.add_child(sail_button)


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
	var dest_name := World.port_name(destination)
	if passage_seconds < 1200.0:
		return "Hold < or > to steer. The gold arrow points to %s." % dest_name
	var to_dest := SailingModel.vector_to_bearing(World.port_position(destination) - ship.position)
	if SailingModel.in_no_go(SailingModel.true_wind_angle_deg(to_dest, wind_from)):
		return "%s is upwind. Zig-zag towards it, keeping just outside the red zone." % dest_name
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
	passage_label.text = "%.1f kn   Passage %s   Time x%d" % [ship.speed_kn, _format_time(passage_seconds), roundi(time_scale)]


# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	_draw_waves()
	for polygon in World.land():
		draw_colored_polygon(polygon, LAND_FILL)
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline, LAND_EDGE, 10.0)
	_draw_ports()
	if mode == Mode.SAILING:
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

	# Gold arrow towards the destination.
	var to_dest := World.port_position(destination) - ship.position
	var direction := to_dest.normalized()
	var tip := ship.position + direction * 250.0
	var base := ship.position + direction * 215.0
	var wing := direction.orthogonal() * 16.0
	draw_colored_polygon(PackedVector2Array([tip, base + wing, base - wing]), GOLD)
	draw_string(ThemeDB.fallback_font, tip + direction * 34.0 + Vector2(-60, 8),
		"%.1f nm" % (to_dest.length() / ShipState.PX_PER_NM), HORIZONTAL_ALIGNMENT_CENTER, 120, 22, GOLD)

	draw_set_transform(ship.position, ship.heading, Vector2.ONE)
	var hull := PackedVector2Array([Vector2(0, -36), Vector2(11, -14), Vector2(12, 18), Vector2(7, 30),
		Vector2(-7, 30), Vector2(-12, 18), Vector2(-11, -14)])
	draw_colored_polygon(hull, Color("6b4423"))
	hull.append(hull[0])
	draw_polyline(hull, Color("2e1c0d"), 2.0)
	# The sail swings out to the downwind side, and flaps in the no-go zone.
	var sheet := deg_to_rad(SailingModel.ideal_sheet_deg(twa))
	if no_go:
		sheet = deg_to_rad(6.0) + sin(anim_time * 18.0) * 0.14
	var side := 1.0 if side_angle >= 0.0 else -1.0
	var mast := Vector2(0, -10)
	draw_line(mast, mast + Vector2(0, 1).rotated(sheet * side) * 42.0, Color.WHITE, 6.0)
	draw_circle(mast, 4.0, Color("2e1c0d"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Screen-space extras: wind dial and minimap.
class Overlay extends Control:
	var game

	func _draw() -> void:
		if not game.is_sailing():
			return
		var font := ThemeDB.fallback_font

		var centre := Vector2(84, 128)
		draw_circle(centre, 56.0, Color(0, 0, 0, 0.35))
		var blowing_to: Vector2 = SailingModel.bearing_to_vector(game.wind_from + PI)
		var head := centre + blowing_to * 40.0
		draw_line(centre - blowing_to * 40.0, head, Color.WHITE, 5.0)
		var barb := blowing_to.orthogonal() * 11.0
		draw_colored_polygon(PackedVector2Array([head + blowing_to * 12.0, head - blowing_to * 8.0 + barb, head - blowing_to * 8.0 - barb]), Color.WHITE)
		draw_string(font, Vector2(14, 214), "Wind %d kn" % roundi(game.wind_kn), HORIZONTAL_ALIGNMENT_CENTER, 140, 22, Color.WHITE)

		var map_scale := 0.04
		var map_size: Vector2 = World.SIZE * map_scale
		var origin := Vector2(size.x - map_size.x - 20.0, 56.0)
		draw_rect(Rect2(origin, map_size), Color(0.05, 0.2, 0.32, 0.85))
		for polygon in World.land():
			var points := PackedVector2Array()
			for point in polygon:
				var q: Vector2 = origin + point * map_scale
				points.append(Vector2(clampf(q.x, origin.x, origin.x + map_size.x), clampf(q.y, origin.y, origin.y + map_size.y)))
			draw_colored_polygon(points, LAND_FILL)
		for port: String in World.PORTS:
			var colour := GOLD if port == game.destination else Color.WHITE
			draw_circle(origin + World.port_position(port) * map_scale, 5.0, colour)
		var ship_at: Vector2 = origin + game.ship.position * map_scale
		var bow: Vector2 = SailingModel.bearing_to_vector(game.ship.heading)
		draw_line(ship_at, ship_at + bow * 14.0, Color.WHITE, 2.0)
		draw_circle(ship_at, 4.0, Color("ff5a4a"))
		draw_rect(Rect2(origin, map_size), Color(1, 1, 1, 0.6), false, 2.0)


# --- Saving ------------------------------------------------------------------

func _save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"money": money,
		"port": current_port,
		"hold_level": hold_level,
		"sail_level": sail_level,
		"best_times": best_times,
	}))


func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	money = int(data.get("money", STARTING_MONEY))
	hold_level = clampi(int(data.get("hold_level", 0)), 0, Trade.MAX_UPGRADE_LEVEL)
	sail_level = clampi(int(data.get("sail_level", 0)), 0, Trade.MAX_UPGRADE_LEVEL)
	var port: String = str(data.get("port", "haven"))
	current_port = port if World.PORTS.has(port) else "haven"
	var times: Variant = data.get("best_times", {})
	if typeof(times) == TYPE_DICTIONARY:
		best_times = times
