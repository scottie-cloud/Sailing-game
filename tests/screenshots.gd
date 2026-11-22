extends SceneTree
## Takes a screenshot of each screen so layouts can be checked by eye.
## Needs a display (CI runs it under xvfb with software rendering):
##   SCREENSHOT_DIR=/tmp/shots godot --path . --rendering-driver opengl3 -s tests/screenshots.gd

const World = preload("res://game/world.gd")
const Trade = preload("res://sim/trade.gd")

var out_dir := ""
var game: Node


func _initialize() -> void:
	_run()


func _settle(frames: int = 4) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw


func _shot(name: String) -> void:
	await _settle()
	var image := root.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	var result := image.save_png(path)
	print("screenshot ", path, " ", "ok" if result == OK else "failed")


func _run() -> void:
	out_dir = OS.get_environment("SCREENSHOT_DIR")
	if out_dir == "":
		out_dir = "user://screenshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Start from a fresh game so the pictures are comparable from run to run.
	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))

	var scene: PackedScene = load("res://game/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	# Let the game finish starting up before driving it.
	await _settle()
	game.rng.seed = 20
	game._enter_port("melbourne", "Welcome aboard. Buy cargo here, choose where to take it and sell it there.\nFresh cargo pays more the faster you arrive.")
	await _shot("01_port")

	game._change_cargo(Trade.goods_sold_at("melbourne")[0], 999)
	game.open_chart()
	await _shot("02_chart_straight_line")
	game.chart.use_pilot()
	game.chart.add_mark(Vector2(9000, 7000))
	await _shot("03_chart_with_plan")
	game.close_chart()

	game.open_contracts()
	await _shot("04_charters")
	game.close_screens()
	game.money = 3000
	game.open_shipyard()
	await _shot("05_shipyard")
	game.close_screens()
	game.open_log()
	await _shot("06_log_empty")
	game.close_log()
	await _shot("07_port_with_cargo")

	game._set_sail()
	await _settle(20)
	await _shot("08_sailing_leaving_port")
	game._toggle_trim()
	game.ship.sheet_deg = 20.0
	await _settle(10)
	await _shot("09_sailing_hand_trim")
	game.ship.position = Vector2(10500, 7500)
	game._toggle_reef()
	await _settle(30)
	await _shot("10_sailing_mid_bay")
	game._toggle_pause()
	await _shot("11_paused")
	game._toggle_pause()

	# Near the coast, to see land drawn in the main view.
	game.ship.position = World.port_position("mornington") + Vector2(-300, -200)
	await _settle(10)
	await _shot("12_sailing_near_land")

	# The view from the deck: close to a shore, in open water, and in a squall.
	game._toggle_view()
	game.ship.position = World.port_position("mornington") + Vector2(150, 0)
	game.ship.heading = deg_to_rad(80.0)
	await _settle(12)
	await _shot("15_deck_near_land")
	game.ship.position = Vector2(10500, 7500)
	game.ship.heading = deg_to_rad(250.0)
	await _settle(12)
	await _shot("16_deck_open_water")
	var hours: float = game.passage_seconds / 3600.0
	game.forecast["squalls"] = [{"delay_hours": hours - 1.667, "offset": 0.0, "extra_kn": 10.0, "radius": 2400.0}]
	game.ship.position = World.SIZE / 2.0
	await _settle(12)
	await _shot("17_deck_in_squall")
	game._toggle_view()
	await _settle(6)
	await _shot("18_top_down_in_squall")
	game.forecast["squalls"] = []

	# Chart detail: the Heads from above, then the Queenscliff lights from the deck at night.
	game.ship.position = World.port_position("queenscliff") + Vector2(-150, 250)
	game.ship.heading = deg_to_rad(200.0)
	await _settle(12)
	await _shot("19_sea_by_the_heads")
	game.ship.position = World.RIP_CENTRE
	await _settle(12)
	await _shot("20_sea_in_the_rip")
	game.clock_hours = 15.0
	game._toggle_view()
	game.ship.position = World.port_position("queenscliff") + Vector2(1200, -700)
	game.ship.heading = deg_to_rad(240.0)
	await _settle(12)
	await _shot("21_deck_lights_at_night")
	game._toggle_view()
	game.clock_hours = 0.0

	var destination: String = game.destination
	var dest_pos := World.port_position(destination)
	game.ship.position = dest_pos + (World.SIZE / 2.0 - dest_pos).normalized() * 100.0
	await _settle(10)
	await _shot("13_arrival_report")
	game.open_log()
	await _shot("14_log_with_entry")
	quit(0)
