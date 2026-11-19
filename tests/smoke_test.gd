extends SceneTree
## Loads the real game scene and plays one voyage: buy cargo, set sail,
## sail for a moment, then arrive and sell.
## Run with: godot --headless --path . -s tests/smoke_test.gd

const Trade = preload("res://sim/trade.gd")
const World = preload("res://game/world.gd")

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
	check(game._cargo_units() <= Trade.hold_capacity(game.hold_level), "cargo fits the hold")
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
	tap.position = game.chart.to_screen(Vector2(3500, 1200))
	game.chart._gui_input(tap)
	check(game.plan.size() == 1, "tapping the water adds a mark")
	check(game.plan[0].distance_to(Vector2(3500, 1200)) < 5.0, "the mark lands where the chart was tapped")
	game.chart.add_mark(Vector2(3500, 1750))
	check(game.plan.size() == 1, "a mark cannot be placed on land")
	game.chart.add_mark(Vector2(2000, 2400))
	game.chart.undo()
	check(game.plan.size() == 1, "undo removes the last mark")
	check(game.chart.summary.text.contains("Route plan"), "the chart shows a plan summary")
	await _frames(3)
	game.close_chart()
	check(game.port_panel.visible and not game.chart.visible, "closing the chart returns to the port screen")

	game._set_sail()
	check(game.planned_hours > 0.0, "setting sail records the planned passage time")
	check(game.target_point().distance_to(Vector2(3500, 1200)) < 5.0, "the first target is the planned mark")
	check(game.target_name() == "mark 1", "the first target is named as a mark")
	await _frames(90)
	check(game.is_sailing(), "the ship is under way after setting sail")
	check(game.passage_seconds > 0.0, "passage time advances")
	check(game.ship.speed_kn > 0.5, "the ship is moving")
	check(not World.is_land(game.ship.position), "the ship leaves port into open water")

	# Round the mark: the target moves on to the destination.
	game.ship.position = Vector2(3500, 1200) + Vector2(60, 0)
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
	var course: Array[Vector2] = [dest_pos, Vector2(5000, 1200), Vector2(3500, 1200), World.port_position(origin)]
	game.follow_track(course)
	check(game.plan.size() == 2 and game.plan[0].distance_to(Vector2(5000, 1200)) < 5.0, "following a course plans its turning points")
	check(game.forecast_text() != "", "the port shows a wind forecast")
	check(game.route_par() > 0.0, "the route has a par time for the day's wind")

	print("smoke: %d failures" % failures)
	quit(1 if failures > 0 else 0)
