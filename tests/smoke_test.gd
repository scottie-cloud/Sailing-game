extends SceneTree
## Loads the real game scene and plays one voyage: buy cargo, set sail,
## sail for a moment, then arrive and sell.
## Run with: godot --headless --path . -s tests/smoke_test.gd

const Trade = preload("res://sim/trade.gd")
const Contracts = preload("res://sim/contracts.gd")
const World = preload("res://game/world.gd")

## A mark in open water in the middle of the bay.
const MARK := Vector2(9000, 7000)

var failures := 0


func check(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	var scene: PackedScene = load("res://game/main.tscn")
	var game: Node = scene.instantiate()
	root.add_child(game)
	await _frames(5)
	check(not game.is_sailing(), "the game starts in port")

	var origin: String = game.current_port
	var good_id: String = Trade.goods_sold_at(origin)[0]
	game._change_cargo(good_id, 999)
	check(game._cargo_units() > 0, "cargo can be bought")
	check(game._cargo_units() <= game.hold_capacity(), "cargo fits the hold")
	check(game.money >= 0, "buying never overdraws")

	# Plan a route on the chart: one mark by tapping, one added directly.
	game.plan.clear()
	game.plan_changed()
	var straight_hours: float = game.plan_hours()
	check(straight_hours > 0.0 and straight_hours < 100.0, "the straight-line route has a time estimate")
	game.open_chart()
	await _frames(3)
	check(game.chart.visible and not game.port_panel.visible, "the chart opens over the port screen")
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = game.chart.to_screen(MARK)
	game.chart._gui_input(tap)
	check(game.plan.size() == 1, "tapping the water adds a mark")
	check(game.plan[0].distance_to(MARK) < 5.0, "the mark lands where the chart was tapped")
	game.chart.add_mark(Vector2(2000, 2000))
	check(game.plan.size() == 1, "a mark cannot be placed on land")
	game.chart.add_mark(Vector2(10000, 9000))
	game.chart.undo()
	check(game.plan.size() == 1, "undo removes the last mark")
	check(game.chart.summary.text.contains("Route plan"), "the chart shows a plan summary")
	await _frames(3)
	game.close_chart()
	check(game.port_panel.visible and not game.chart.visible, "closing the chart returns to the port screen")

	game._set_sail()
	check(game.planned_hours > 0.0, "setting sail records the planned passage time")
	check(game.target_point().distance_to(MARK) < 5.0, "the first target is the planned mark")
	check(game.target_name() == "mark 1", "the first target is named as a mark")
	await _frames(90)
	check(game.is_sailing(), "the ship is under way after setting sail")
	check(game.passage_seconds > 0.0, "passage time advances")
	check(game.ship.speed_kn > 0.5, "the ship is moving")
	check(not World.is_land(game.ship.position), "the ship leaves port into open water")

	# Round the mark: the target moves on to the destination.
	game.ship.position = MARK + Vector2(60, 0)
	await _frames(3)
	check(game.next_mark == 1, "passing close to a mark rounds it")
	check(game.target_point() == World.port_position(game.destination), "after the last mark the target is the destination")
	check(game.is_sailing(), "the ship is still under way after rounding the mark")

	# Skip the crossing: put the ship just off the destination.
	var destination: String = game.destination
	var dest_pos := World.port_position(destination)
	var money_before: int = game.money
	game.ship.position = dest_pos + (World.SIZE / 2.0 - dest_pos).normalized() * 100.0
	await _frames(5)
	check(not game.is_sailing(), "the ship docks at the destination")
	check(game.current_port == destination, "the ship is now at the destination port")
	check(game.money > money_before, "the cargo is sold on arrival")
	check(game.destination == origin, "the next destination is the port we came from")

	# The passage is in the ship's log, with its course saved as the record.
	check(game.ship_log.size() == 1, "the passage is written to the log")
	var entry: Dictionary = game.ship_log[0]
	check(entry["from"] == origin and entry["to"] == destination, "the log entry names the route")
	check(entry["record"], "a first passage is a record")
	check(entry["track"].size() >= 2, "the log entry keeps the course sailed")
	check(game.record_tracks.has(Trade.route_key(origin, destination)), "the record course is saved for the route")
	check(game.record_track().is_empty(), "there is no record yet for the return route")
	game.open_log()
	await _frames(3)
	check(game.log_screen.visible and game.log_screen.rows.get_child_count() == 1, "the log screen lists the passage")
	check(game.log_screen.entry_text(entry).contains("RECORD"), "the log marks the record passage")
	game.close_log()
	check(game.port_panel.visible, "closing the log returns to the port screen")

	# Following a logged course turns it into a plan.
	var course: Array[Vector2] = [dest_pos, Vector2(6000, 9000), Vector2(9000, 5000), World.port_position(origin)]
	game.follow_track(course)
	check(game.plan.size() == 2 and game.plan[0].distance_to(Vector2(6000, 9000)) < 5.0, "following a course plans its turning points")

	# The pilot's course goes on the chart as marks, and the destination can be changed.
	game.open_chart()
	game.chart.use_pilot()
	check(game.chart.summary.text.contains("Route plan"), "the pilot course gives a plan")
	game.close_chart()
	var first_choice: String = game.destination
	game._cycle_destination()
	check(game.destination != first_choice and game.destination != game.current_port, "the destination can be changed")
	check(game.route_distance_nm() > 5.0, "the new route has a sailing distance")
	check(game.route_par() > 0.0, "the new route has a par time")

	# Hand trim: the sheet buttons appear and the sheet starts where auto had it.
	game._set_sail()
	check(not game.haul_button.visible, "sheet buttons are hidden with automatic trim")
	game._toggle_trim()
	check(game.ship.manual_trim and game.haul_button.visible and game.ease_button.visible, "switching to hand trim shows the sheet buttons")
	await _frames(30)
	check(game.ship.trim_efficiency > 0.9, "the sail starts well set when taking over by hand")
	game.ship.sheet_deg = 90.0 if game.ship.sheet_deg < 45.0 else 5.0
	await _frames(5)
	check(game.ship.trim_efficiency < 0.85, "a badly set sheet is worse than automatic trim")
	game._toggle_trim()
	await _frames(5)
	check(not game.ship.manual_trim and not game.haul_button.visible, "switching back hides the sheet buttons")

	# The view from the deck can be switched on and off.
	check(game.view_button.visible and not game.deck_view.visible, "the chart view is the default")
	game._toggle_view()
	await _frames(8)
	check(game.deck_mode and game.deck_view.visible, "the deck view can be switched on")
	check(game.deck_view._land.size() == game.deck_view.COLUMNS, "the deck view scans for land in sight")
	game._toggle_view()
	check(not game.deck_view.visible, "and switched off again")
	check(game.clock_text().begins_with("Day "), "the time of day is shown")
	check(game.daylight() >= 0.0 and game.daylight() <= 1.0, "daylight is a fraction")

	# Sound: the loops are running, follow the ship, and can be switched off.
	var loops_ready := true
	for loop: String in game.sound.LOOPS:
		loops_ready = loops_ready and AudioServer.get_bus_index(game.sound.bus_name(loop)) >= 0
	check(loops_ready and game.sound.get_child_count() == game.sound.LOOPS.size() + 1, "each sound loop and the bell is set up")
	await _frames(30)
	check(game.sound.level("wind") > 0.0, "the wind is heard under sail")
	check(game.sound_button.visible and game.sound_button.text == "Sound: on", "the sound button shows under sail")
	game._toggle_sound()
	check(game.sound_muted and AudioServer.is_bus_mute(0) and game.sound_button.text == "Sound: off", "sound can be switched off")
	game._toggle_sound()
	check(not AudioServer.is_bus_mute(0), "and back on")
	check(not game.is_flapping() or game.sound.level("flap") >= 0.0, "a flapping sail can be asked about")

	# Pause stops the clock; reefing and the tide are available.
	check(game.pause_button.visible and game.reef_button.visible, "pause and reef buttons show under sail")
	game._toggle_pause()
	var paused_at: float = game.passage_seconds
	var paused_position: Vector2 = game.ship.position
	await _frames(20)
	check(game.passage_seconds == paused_at and game.ship.position == paused_position, "nothing moves while paused")
	game._toggle_pause()
	await _frames(20)
	check(game.passage_seconds > paused_at, "the passage carries on after resuming")
	game._toggle_reef()
	check(game.ship.reefed and game.reef_button.text.contains("Reefed"), "the sail can be reefed")
	game._toggle_reef()
	check(not game.ship.reefed, "the reef can be shaken out")
	check(game.tide_text().contains("Tide"), "the state of the tide is reported")
	check(game.squalls_at(0.0).size() <= 2, "the day's squalls can be listed")
	var clock: float = game.clock_hours
	game.wait_hour()
	check(game.clock_hours == clock + 1.0, "waiting an hour moves the tide clock on")
	check(game.is_sailing(), "the ship is still under way")
	check(game.forecast_text() != "", "the port shows a wind forecast")
	check(game.route_par() > 0.0, "the route has a par time for the day's wind")

	# Shallow water: the cutter floats over the West Sand, a schooner grounds on it.
	var sand: Vector2 = World.lonlat_to_px(144.775, -38.225)
	game.clock_hours = -game.passage_seconds / 3600.0
	check(game.tide_height() < 0.05 and game.draught() < 2.0, "it is low water and the cutter draws little")
	game.ship.position = sand
	await _frames(3)
	check(game.ship.position.distance_to(sand) < 200.0, "the cutter crosses the sand")
	var own_ship: String = game.ship_id
	game.ship_id = "schooner"
	var before_grounding: float = game.passage_seconds
	game.ship.position = sand
	await _frames(3)
	# Judged by the time lost, since another notice may have replaced the grounding one.
	check(game.passage_seconds - before_grounding >= game.AGROUND_PENALTY_S, "a schooner runs aground there at low water and loses time")
	check(game.passage_seconds - before_grounding < game.AGROUND_PENALTY_S * 2.0, "and only once")
	check(game.ship.position.distance_to(sand) > 1.0, "and is put back where she can float")
	check(World.depth_at(game.ship.position, game.tide_height()) > game.draught(), "with water under her")
	game.ship_id = own_ship
	game.clock_hours = 0.0

	# Finish the passage, then use the shipyard and take a charter.
	var second_port: String = game.destination
	var second_pos := World.port_position(second_port)
	game.ship.position = second_pos + (World.SIZE / 2.0 - second_pos).normalized() * 100.0
	await _frames(5)
	check(not game.is_sailing() and game.current_port == second_port, "the second passage ends in port")

	game.money = 5000
	game.open_shipyard()
	await _frames(3)
	check(game.shipyard_screen.visible and game.shipyard_screen.rows.get_child_count() == 7, "the shipyard lists three ships and four upgrades")
	game._buy_ship("ketch")
	check(game.ship_id == "ketch" and game.hold_capacity() == 28, "a bigger ship can be bought")
	game._buy_upgrade("keel")
	game._buy_upgrade("hold")
	check(game.upgrade_level("keel") == 1 and game.hold_capacity() == 33, "upgrades can be fitted")
	check(game.money < 5000, "the shipyard takes its money")
	game.close_screens()
	check(game.port_panel.visible and not game.shipyard_screen.visible, "closing the shipyard returns to the port screen")

	var offers := Contracts.offers_at(game.current_port)
	check(not offers.is_empty(), "this port offers a charter")
	game.open_contracts()
	await _frames(3)
	check(game.contracts_screen.rows.get_child_count() == offers.size(), "the charters screen lists the offers")
	var offer: Dictionary = offers[offers.size() - 1]
	game._accept_contract(offer["id"])
	check(game.active_contract == offer["id"] and game.destination == offer["to"], "accepting a charter sets the destination")
	game.close_screens()
	game._change_cargo(offer["good"], 999)
	check(game.expected_price(offer["good"]) > 0, "the port shows what the cargo should fetch")
	var money_before_charter: int = game.money
	game._set_sail()
	await _frames(5)
	check(game.ship.turn_factor < 1.0 and game.ship.leeway_factor < 1.0, "the new ship and keel change how she handles")
	var charter_pos := World.port_position(offer["to"])
	game.ship.position = charter_pos + (World.SIZE / 2.0 - charter_pos).normalized() * 100.0
	await _frames(5)
	check(not game.is_sailing(), "the charter passage ends in port")
	check(game.port_report.text.contains("Charter fulfilled"), "the charter is fulfilled on arrival")
	check(int(game.completed_contracts.get(offer["id"], 0)) == 1 and game.active_contract == "", "the charter is recorded and cleared")
	check(game.money > money_before_charter, "the charter and cargo pay")
	check(not game.glut.is_empty(), "the cargo landed is remembered by the market")

	print("smoke: %d failures" % failures)
	quit(1 if failures > 0 else 0)
