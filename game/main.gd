extends Node2D
## The game itself: its state, and what happens in port and under sail.
## Rules are in sim/, content in data/, and the views and screens in the
## other files of game/.

const SailingModel = preload("res://sim/sailing_model.gd")
const ShipState = preload("res://sim/ship_state.gd")
const Trade = preload("res://sim/trade.gd")
const TimeCompression = preload("res://sim/time_compression.gd")
const RoutePlan = preload("res://sim/route_plan.gd")
const Weather = preload("res://sim/weather.gd")
const Track = preload("res://sim/track.gd")
const Tide = preload("res://sim/tide.gd")
const Shipyard = preload("res://sim/shipyard.gd")
const Market = preload("res://sim/market.gd")
const Contracts = preload("res://sim/contracts.gd")
const World = preload("res://game/world.gd")
const Chart = preload("res://game/chart.gd")
const LogScreen = preload("res://game/log_screen.gd")
const ListScreen = preload("res://game/list_screen.gd")
const DeckView = preload("res://game/deck_view.gd")
const Hud = preload("res://game/hud.gd")
const SeaView = preload("res://game/sea_view.gd")
const SaveGame = preload("res://game/save_game.gd")
const Ui = preload("res://game/ui_builder.gd")
const Palette = preload("res://game/palette.gd")
const Sound = preload("res://game/sound.gd")

## At 1x, one real second is one game minute.
const GAME_SECONDS_PER_REAL_SECOND := 60.0
const DOCK_RADIUS := 170.0
## How fast the sheet runs in or out while a trim button is held (degrees a second).
const SHEET_RATE_DEG := 30.0
## A squall is announced when its edge is this close (px).
const SQUALL_WARNING_DISTANCE := 1800.0
## A light is pointed out when the ship passes this close (px: two miles).
const LIGHT_NOTICE_DISTANCE := 800.0
const REPAIR_COST := 30
## The game clock starts at eight in the morning.
const START_HOUR := 8.0
const WAKE_POINTS := 44
const WAKE_SPACING := 14.0
## Hours spent in port unloading and loading.
const TURNAROUND_HOURS := 1.0
## How close the ship has to pass a planned mark to count as rounding it.
const MARK_RADIUS := 200.0
const MAX_MARKS := 12
## A point is added to the sailed track every time the ship moves this far.
const TRACK_SPACING := 120.0
const MAX_LOG_ENTRIES := 30
const BASE_HULL_SPEED_KN := 7.0
const AGROUND_PENALTY_S := 1800.0
const STARTING_MONEY := 100
const MINIMUM_STAKE := 40

enum Mode { PORT, SAILING }

var ship := ShipState.new()
var mode := Mode.PORT
var wind_from := deg_to_rad(World.WIND_FROM_DEG)
var wind_kn := World.WIND_KN
var rng := RandomNumberGenerator.new()
## Today's wind as forecast in port. Under sail the real wind drifts from it.
var forecast := {}
var passage_par := 0.0
## Hours since the game began: sets the state of the tide.
var clock_hours := 0.0
var paused := false
## How deep in a squall the ship is, 0 to 1, and which squalls have been announced.
var squall_strength := 0.0
var announced_squalls := {}
var announced_damage := false
## Lights already pointed out on this passage.
var announced_lights := {}
var announced_wind_from := 0.0
var time_scale := 1.0
var passage_seconds := 0.0
var current_port := "melbourne"
var destination := "geelong"
var money := STARTING_MONEY
var cargo := {}
var ship_id := "cutter"
var upgrade_levels := {"hold": 0, "sails": 0, "keel": 0, "rigging": 0}
## Cargo recently landed at each port ("port:good" -> units): it depresses the price.
var glut := {}
## The charter taken on, if any, and how many times each has been completed.
var active_contract := ""
var completed_contracts := {}
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
## Distance from the ship to the nearest land, refreshed a few times a second.
var land_distance := -1.0
var last_safe_position := Vector2.ZERO
var anim_time := 0.0
var notice := ""
var notice_until := 0.0

var camera: Camera2D
var overlay: Hud
var sea_view: SeaView
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
var goods_name_labels := {}
var shipyard_screen: ListScreen
var contracts_screen: ListScreen
var sail_button: Button
var destination_button: Button
var trim_button: Button
var haul_button: Button
var ease_button: Button
var reef_button: Button
var pause_button: Button
var view_button: Button
var sound_button: Button
var sound: Sound
var deck_view: DeckView
## True when the player has chosen the view from the deck.
var deck_mode := false
var sound_muted := false
## Recent positions, oldest first, for drawing the wake.
var wake: Array[Vector2] = []


func _ready() -> void:
	RenderingServer.set_default_clear_color(Palette.SEA)
	rng.randomize()
	_load_game()
	sea_view = SeaView.new()
	sea_view.game = self
	add_child(sea_view)
	Ui.build(self)
	sound = Sound.new()
	add_child(sound)
	sound.setup(self)
	sound.set_muted(sound_muted)
	_enter_port(current_port, "Welcome aboard. Buy cargo here, choose where to take it and sell it there.\nFresh cargo pays more the faster you arrive.")


func is_sailing() -> bool:
	return mode == Mode.SAILING


func _process(delta: float) -> void:
	anim_time += delta
	if mode == Mode.SAILING and not paused:
		_sail(delta)
	camera.position = ship.position
	_update_hud()
	sea_view.queue_redraw()
	overlay.queue_redraw()


# --- Route planning ----------------------------------------------------------

func hull_speed() -> float:
	return Shipyard.hull_speed_kn(ship_id, upgrade_level("sails"))


func upgrade_level(kind: String) -> int:
	return int(upgrade_levels.get(kind, 0))


func hold_capacity() -> int:
	return Shipyard.hold_capacity(ship_id, upgrade_level("hold"))


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
		text += " %d red leg%s zig-zagging into the wind." % [upwind, " needs" if upwind == 1 else "s need"]
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


# --- Market, shipyard and charters -------------------------------------------

## Everything that scales a cargo's price at a port: the route's premium,
## whether the port wants it, and how much has been landed there lately.
func market_factor(good_id: String, port: String) -> float:
	var landed: float = glut.get(Market.key(port, good_id), 0.0)
	return World.route_premium(current_port, port) * Market.demand_factor(good_id, port) * Market.glut_factor(landed)


## What a unit should fetch at the destination after a passage on par.
func expected_price(good_id: String) -> int:
	var par := route_par()
	return Trade.sale_price(good_id, par, par, route_distance_nm(), market_factor(good_id, destination))


## Move the clock on: the tide turns and glutted markets recover.
func _advance_clock(hours: float) -> void:
	clock_hours += hours
	for key: String in glut:
		glut[key] = Market.recovered(glut[key], hours)


func close_screens() -> void:
	shipyard_screen.visible = false
	contracts_screen.visible = false
	port_panel.visible = true
	_refresh_port_panel()


func open_shipyard() -> void:
	port_panel.visible = false
	shipyard_screen.visible = true
	_refresh_shipyard()


func _refresh_shipyard() -> void:
	var entries: Array[Dictionary] = []
	for id in Shipyard.SHIP_ORDER:
		var info: Dictionary = Shipyard.SHIPS[id]
		var text := "%s: hold %d, top speed %.1f kn. %s" % [info["name"], info["hold"], info["hull_speed"], info["blurb"]]
		if id == ship_id:
			entries.append({"text": text + " This is your ship."})
			continue
		var cost := Shipyard.ship_cost(ship_id, id)
		var button := "Buy $%d" % cost if cost >= 0 else "Swap, get $%d" % -cost
		entries.append({"text": text, "button": button, "action": _buy_ship.bind(id), "disabled": money < cost or _cargo_units() > 0})
	for kind in Shipyard.UPGRADE_ORDER:
		var info: Dictionary = Shipyard.UPGRADES[kind]
		var level := upgrade_level(kind)
		var cost := Shipyard.upgrade_cost(kind, level)
		var text := "%s (%s): level %d of %d." % [info["name"], info["effect"], level, info["max"]]
		if cost < 0:
			entries.append({"text": text + " Fully fitted."})
		else:
			entries.append({"text": text, "button": "Fit $%d" % cost, "action": _buy_upgrade.bind(kind), "disabled": money < cost})
	var note := "You have $%d. Upgrades stay with you when you change ship." % money
	if _cargo_units() > 0:
		note += " Unload your cargo before changing ship."
	shipyard_screen.show_rows(note, entries)


func _buy_ship(id: String) -> void:
	var cost := Shipyard.ship_cost(ship_id, id)
	if money < cost or _cargo_units() > 0:
		return
	money -= cost
	ship_id = id
	_refresh_shipyard()
	_save_game()


func open_contracts() -> void:
	port_panel.visible = false
	contracts_screen.visible = true
	_refresh_contracts()


func _contract_terms(contract: Dictionary) -> String:
	var good: Dictionary = Trade.GOODS[contract["good"]]
	return "Carry %d %s to %s for a bonus of $%d." % [Contracts.required_units(contract, hold_capacity()),
		good["name"], World.port_name(contract["to"]), Contracts.bonus(contract, hold_capacity())]


func _refresh_contracts() -> void:
	var entries: Array[Dictionary] = []
	for contract in Contracts.offers_at(current_port):
		var id: String = contract["id"]
		var done := int(completed_contracts.get(id, 0))
		var text := "%s. %s %s" % [contract["title"], contract["story"], _contract_terms(contract)]
		if done > 0:
			text += " Completed %d time%s." % [done, "" if done == 1 else "s"]
		if id == active_contract:
			entries.append({"text": text + " You have taken this charter.", "button": "Give up", "action": _accept_contract.bind("")})
		else:
			entries.append({"text": text, "button": "Accept", "action": _accept_contract.bind(id)})
	var note := "Jobs drawn from the trading history of the bay. The time allowed is set by the day's wind when you sail."
	if entries.is_empty():
		note = "No charters are offered at this port today."
	contracts_screen.show_rows(note, entries)


## Take on a charter (or give it up with an empty id). The destination is set to match.
func _accept_contract(id: String) -> void:
	active_contract = id
	if id != "":
		var contract := Contracts.by_id(id)
		destination = contract["to"]
		plan = _points(plans.get(Trade.route_key(current_port, destination), []))
		next_mark = 0
	_refresh_contracts()
	_save_game()


## The charter in hand, if it starts at this port: otherwise an empty dictionary.
func _current_contract() -> Dictionary:
	var contract := Contracts.by_id(active_contract)
	if contract.is_empty() or contract["from"] != current_port:
		return {}
	return contract


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
	var now := Weather.wind_at(forecast, game_seconds, ship.position, World.SIZE)
	wind_from = now["from"]
	wind_kn = now["kn"]
	squall_strength = now["squall"]


## The time on the tide clock, including the passage so far.
func now_hours() -> float:
	return clock_hours + (passage_seconds / 3600.0 if mode == Mode.SAILING else 0.0)


func tide_text() -> String:
	return "Tide at the Heads: %s, turns in %s" % [Tide.describe(now_hours()), format_hours(Tide.hours_to_turn(now_hours()))]


## Squalls as {"centre", "radius"} at a time this many hours into the passage.
func squalls_at(hours: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var squalls: Array = forecast.get("squalls", [])
	for squall: Dictionary in squalls:
		result.append({"centre": Weather.squall_centre(forecast, squall, hours, World.SIZE), "radius": squall["radius"]})
	return result


## Wait in port for the tide. The wind forecast stays as it is.
func wait_hour() -> void:
	_advance_clock(1.0)
	_refresh_port_panel()
	_save_game()


## Hour of the day, 0 to 24.
func hour_of_day() -> float:
	return fposmod(START_HOUR + now_hours(), 24.0)


## 1 in full daylight, falling to 0 in the middle of the night.
func daylight() -> float:
	var hour := hour_of_day()
	return clampf(minf(hour - 5.0, 20.0 - hour) / 1.5, 0.0, 1.0)


func clock_text() -> String:
	var hour := hour_of_day()
	return "Day %d, %02d:%02d" % [int((START_HOUR + now_hours()) / 24.0) + 1, int(hour), int(fposmod(hour, 1.0) * 60.0)]


func _toggle_view() -> void:
	deck_mode = not deck_mode
	_show_sailing_controls(mode == Mode.SAILING)
	_save_game()


func _toggle_sound() -> void:
	sound_muted = not sound_muted
	sound.set_muted(sound_muted)
	_show_sailing_controls(mode == Mode.SAILING)
	_save_game()


## True when a sail is shaking instead of drawing: head to wind, or eased too far.
func is_flapping() -> bool:
	if mode != Mode.SAILING:
		return false
	var twa := ship.true_wind_angle_deg(wind_from)
	if SailingModel.in_no_go(twa):
		return true
	return ship.manual_trim and ship.sheet_deg > SailingModel.ideal_sheet_deg(twa) + 15.0


func _toggle_pause() -> void:
	paused = not paused
	pause_button.text = "Resume" if paused else "Pause"


func _toggle_reef() -> void:
	ship.reefed = not ship.reefed
	_show_sailing_controls(mode == Mode.SAILING)


## Warn of a squall before it arrives, and of damage when it happens.
func _watch_weather() -> void:
	var squalls := squalls_at(passage_seconds / 3600.0)
	for i in squalls.size():
		var centre: Vector2 = squalls[i]["centre"]
		var radius: float = squalls[i]["radius"]
		if not announced_squalls.has(i) and ship.position.distance_to(centre) < radius + SQUALL_WARNING_DISTANCE:
			announced_squalls[i] = true
			time_scale = 1.0
			var bearing := SailingModel.vector_to_bearing(centre - ship.position)
			_show_notice("Squall coming from the %s! Reef before it hits, or risk a split sail." % Weather.compass_name(rad_to_deg(bearing)), 7.0)
	# Passing a light for the first time: say what it is.
	for index in World.LIGHTS.size():
		var light: Dictionary = World.LIGHTS[index]
		if not announced_lights.has(index) and ship.position.distance_to(World.feature_position(light)) < LIGHT_NOTICE_DISTANCE:
			announced_lights[index] = true
			if anim_time >= notice_until:
				_show_notice("%s. %s" % [World.light_label(light), light["note"]], 9.0)
	if ship.damaged and not announced_damage:
		announced_damage = true
		time_scale = 1.0
		_show_notice("A sail has split! She is slower until it is repaired in port.", 7.0)


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
	reef_button.visible = sailing
	reef_button.text = "Reefed: undo" if ship.reefed else "Reef sail"
	pause_button.visible = sailing
	view_button.visible = sailing
	sound_button.visible = sailing
	sound_button.text = "Sound: off" if sound_muted else "Sound: on"
	view_button.text = "Top" if deck_mode else "Deck"
	deck_view.visible = sailing and deck_mode
	pause_button.text = "Resume" if paused else "Pause"


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
	# Measuring to the coast is the costly part, so it is done a few times a second.
	if Engine.get_process_frames() % 8 == 0 or land_distance < 0.0:
		land_distance = World.distance_to_land(ship.position)
	var hazard := minf(land_distance, ship.position.distance_to(target_point()))
	hazard = minf(hazard, to_destination)
	_watch_weather()
	var target := TimeCompression.target_scale(rudder != 0.0 or trim != 0.0, in_irons or ship.overpowered, land_ahead, hazard)
	time_scale = TimeCompression.approach(time_scale, target, delta)

	var dt := delta * GAME_SECONDS_PER_REAL_SECOND * time_scale
	ship.step(dt, rudder, wind_from, wind_kn, World.current_kn(ship.position, now_hours()))
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
		if wake.is_empty() or ship.position.distance_to(wake[wake.size() - 1]) > WAKE_SPACING:
			wake.append(ship.position)
			if wake.size() > WAKE_POINTS:
				wake.pop_front()

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
	land_distance = -1.0
	wake.clear()
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
	ship.turn_factor = Shipyard.turn_factor(ship_id)
	ship.leeway_factor = Shipyard.leeway_factor(upgrade_level("keel"))
	ship.strain_limit_s = Shipyard.strain_limit_s(ship_id, upgrade_level("rigging"))
	last_safe_position = from_pos
	passage_seconds = 0.0
	time_scale = 1.0
	notice_until = 0.0
	mode = Mode.SAILING
	port_panel.visible = false
	chart.visible = false
	log_screen.visible = false
	shipyard_screen.visible = false
	contracts_screen.visible = false
	ship.sheet_deg = SailingModel.ideal_sheet_deg(ship.true_wind_angle_deg(wind_from))
	ship.reefed = false
	ship.strain_s = 0.0
	paused = false
	announced_squalls = {}
	announced_lights = {}
	announced_damage = ship.damaged
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
		var price := Trade.sale_price(good_id, hours, par, distance_nm, market_factor(good_id, destination))
		var good: Dictionary = Trade.GOODS[good_id]
		var glut_key := Market.key(destination, good_id)
		var landed: float = glut.get(glut_key, 0.0)
		glut[glut_key] = landed + units
		var condition := ""
		if good["perishable"]:
			var multiplier := Trade.freshness_multiplier(hours, par)
			if multiplier >= 1.3:
				condition = " (arrived fresh: premium price)"
			elif multiplier >= 1.0:
				condition = " (good condition)"
			else:
				condition = " (past its best: sold cheap)"
		var market_note := ""
		if Market.is_wanted(good_id, destination):
			market_note += " In demand here."
		if Market.glut_factor(landed) < 0.95:
			market_note += " The market is glutted."
		lines.append("Sold %d %s at $%d each%s.%s" % [units, good["name"], price, condition, market_note])
		total += units * price
	if total > 0:
		lines.append("Takings: $%d." % total)
	else:
		lines.append("You arrived with an empty hold.")
	var contract := _current_contract()
	if not contract.is_empty():
		var carried := int(cargo.get(contract["good"], 0))
		if Contracts.is_met(contract, current_port, destination, carried, hold_capacity(), hours, par):
			var reward := Contracts.bonus(contract, hold_capacity())
			total += reward
			completed_contracts[contract["id"]] = int(completed_contracts.get(contract["id"], 0)) + 1
			lines.append("Charter fulfilled: %s. Bonus $%d." % [contract["title"], reward])
		elif contract["to"] == destination:
			lines.append("Charter missed: %s. No bonus this time." % contract["title"])
		active_contract = ""
	money += total
	sound.ring_bell()
	if ship.damaged:
		var repair := mini(REPAIR_COST, money)
		money -= repair
		ship.damaged = false
		lines.append("The split sail was repaired for $%d." % repair)
	_advance_clock(hours + TURNAROUND_HOURS)
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
	shipyard_screen.visible = false
	contracts_screen.visible = false
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
		var space := hold_capacity() - _cargo_units()
		amount = mini(amount, mini(space, money / price))
	else:
		amount = -mini(-amount, held)
	cargo[good_id] = held + amount
	money -= amount * price
	_refresh_port_panel()


func _buy_upgrade(kind: String) -> void:
	var cost := Shipyard.upgrade_cost(kind, upgrade_level(kind))
	if cost < 0 or money < cost:
		return
	money -= cost
	upgrade_levels[kind] = upgrade_level(kind) + 1
	_refresh_shipyard()
	_save_game()


func _refresh_port_panel() -> void:
	var ship_name: String = Shipyard.SHIPS[ship_id]["name"]
	port_money.text = "Money: $%d     %s, hold %d / %d" % [money, ship_name, _cargo_units(), hold_capacity()]
	plan_label.text = "Wind today: %s, shifting at sea. %s" % [forecast_text(), plan_summary(false)]
	var contract := _current_contract()
	if not contract.is_empty():
		plan_label.text += " Charter: %s %s" % [contract["title"].to_lower(), _contract_terms(contract)]
	for good_id: String in goods_name_labels:
		var good: Dictionary = Trade.GOODS[good_id]
		var notes := "spoils" if good["perishable"] else "keeps"
		if Market.is_wanted(good_id, destination):
			notes += ", in demand"
		var name_label: Label = goods_name_labels[good_id]
		name_label.text = "%s $%d. About $%d in %s (%s)" % [good["name"], good["buy"], expected_price(good_id),
			World.port_name(destination), notes]
	for good_id: String in goods_count_labels:
		var count_label: Label = goods_count_labels[good_id]
		count_label.text = str(int(cargo.get(good_id, 0)))
	var key := Trade.route_key(current_port, destination)
	var record := "no passage yet"
	if best_times.has(key):
		record = "best " + _format_time(float(best_times[key]) * 3600.0)
	sail_button.text = "Set sail for %s  (%s)" % [World.port_name(destination), record]
	var premium := World.route_premium(current_port, destination)
	var bonus := ", pays +%d%%" % roundi((premium - 1.0) * 100.0) if premium > 1.0 else ""
	destination_button.text = "To: %s, %d nm%s (change)" % [World.port_name(destination), roundi(route_distance_nm()), bonus]


func _rebuild_goods_rows() -> void:
	for child in goods_box.get_children():
		child.queue_free()
	goods_count_labels.clear()
	goods_name_labels.clear()
	for good_id in Trade.goods_sold_at(current_port):
		var good: Dictionary = Trade.GOODS[good_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_label := Label.new()
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size = Vector2(420, 0)
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		goods_name_labels[good_id] = name_label
		row.add_child(Ui.make_button("-", _change_cargo.bind(good_id, -1), 60))
		var count_label := Label.new()
		count_label.custom_minimum_size = Vector2(44, 0)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(count_label)
		goods_count_labels[good_id] = count_label
		row.add_child(Ui.make_button("+", _change_cargo.bind(good_id, 1), 60))
		row.add_child(Ui.make_button("Fill", _change_cargo.bind(good_id, 999), 90))
		goods_box.add_child(row)


# --- UI ----------------------------------------------------------------------

func _show_notice(text: String, seconds: float) -> void:
	notice = text
	notice_until = anim_time + seconds


func _current_hint() -> String:
	if mode != Mode.SAILING:
		return ""
	if paused:
		return "Paused. Tap Resume to sail on."
	if anim_time < notice_until:
		return notice
	if ship.overpowered:
		return "Too much sail for this wind! Reef, or a sail will split."
	if land_ahead:
		return "Land ahead! Turn away."
	if _in_no_go():
		return "Sails flapping! You can't sail straight into the wind. Steer out of the red zone."
	if passage_seconds < 1200.0:
		if deck_mode:
			return "Hold < or > to steer. Bring the gold MARK pointer to the middle of the compass."
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
	status_label.text = "%s   $%d   Cargo: %s" % [clock_text(), money, cargo_text]
	var remaining := RoutePlan.total_hours(estimate(route_points(ship.position, next_mark), false))
	var projected := passage_seconds / 3600.0 + remaining
	passage_label.text = "Sailed %s   On course for %s (plan %s)   Time x%d" % [
		_format_time(passage_seconds), format_hours(projected), format_hours(planned_hours), roundi(time_scale)]


# --- Saving ------------------------------------------------------------------

func _save_game() -> void:
	SaveGame.save(self)


func _load_game() -> void:
	SaveGame.load_into(self)
