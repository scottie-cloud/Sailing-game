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

	game._set_sail()
	await _frames(90)
	check(game.is_sailing(), "the ship is under way after setting sail")
	check(game.passage_seconds > 0.0, "passage time advances")
	check(game.ship.speed_kn > 0.5, "the ship is moving")
	check(not World.is_land(game.ship.position), "the ship leaves port into open water")

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

	print("smoke: %d failures" % failures)
	quit(1 if failures > 0 else 0)
