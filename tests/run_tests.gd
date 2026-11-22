extends SceneTree
## Headless tests for the rules in sim/ and the map.
## Run with: godot --headless --path . -s tests/run_tests.gd

const SailingModel = preload("res://sim/sailing_model.gd")
const ShipState = preload("res://sim/ship_state.gd")
const Trade = preload("res://sim/trade.gd")
const TimeCompression = preload("res://sim/time_compression.gd")
const RoutePlan = preload("res://sim/route_plan.gd")
const Track = preload("res://sim/track.gd")
const Weather = preload("res://sim/weather.gd")
const Tide = preload("res://sim/tide.gd")
const Shipyard = preload("res://sim/shipyard.gd")
const Market = preload("res://sim/market.gd")
const Contracts = preload("res://sim/contracts.gd")
const SoundMix = preload("res://sim/sound_mix.gd")
const World = preload("res://game/world.gd")

const NORTH := 0.0
const EAST := PI / 2.0

var failures := 0
var checks := 0


func check(condition: bool, what: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", what)


func near(a: float, b: float, tolerance: float = 0.001) -> bool:
	return absf(a - b) <= tolerance


func _init() -> void:
	test_bearings()
	test_polar()
	test_trim_and_leeway()
	test_ship_motion()
	test_trade()
	test_time_compression()
	test_world()
	test_speed_explanations()
	test_route_plan()
	test_track()
	test_weather()
	test_tide()
	test_heavy_weather()
	test_shipyard()
	test_market_and_charters()
	test_data()
	test_sound_mix()
	test_chart()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_bearings() -> void:
	check(SailingModel.bearing_to_vector(NORTH).is_equal_approx(Vector2(0, -1)), "north points up the screen")
	check(SailingModel.bearing_to_vector(EAST).is_equal_approx(Vector2(1, 0)), "east points right")
	check(near(SailingModel.vector_to_bearing(Vector2(1, 0)), EAST), "vector to bearing round trip")
	check(near(SailingModel.signed_wind_angle(NORTH, EAST), PI / 2.0), "wind from the east is on the starboard side heading north")
	check(near(SailingModel.signed_wind_angle(NORTH, -EAST), -PI / 2.0), "wind from the west is on the port side heading north")
	check(near(SailingModel.true_wind_angle_deg(deg_to_rad(350.0), deg_to_rad(10.0)), 20.0), "wind angle wraps through north")


func test_polar() -> void:
	check(near(SailingModel.polar_fraction(0.0), 0.0), "no drive pointing straight into the wind")
	check(near(SailingModel.polar_fraction(120.0), 1.0), "fastest on a broad reach")
	check(SailingModel.polar_fraction(180.0) < SailingModel.polar_fraction(120.0), "a dead run is slower than a broad reach")
	var previous := -1.0
	var rising := true
	for angle in range(0, 121, 5):
		var fraction := SailingModel.polar_fraction(float(angle))
		rising = rising and fraction >= previous
		previous = fraction
	check(rising, "speed rises steadily from head to wind round to a broad reach")
	check(SailingModel.in_no_go(30.0), "30 degrees off the wind is in the no-go zone")
	check(not SailingModel.in_no_go(50.0), "50 degrees off the wind is sailable")
	check(SailingModel.target_speed_kn(90.0, 6.0, 7.0, 1.0) < SailingModel.target_speed_kn(90.0, 12.0, 7.0, 1.0), "less wind means less speed")
	check(SailingModel.target_speed_kn(120.0, 40.0, 7.0, 1.0) <= 7.0 * 1.15 + 0.001, "strong wind cannot push far past hull speed")


func test_trim_and_leeway() -> void:
	check(near(SailingModel.trim_efficiency(SailingModel.ideal_sheet_deg(90.0), 90.0), 1.0), "ideal trim is fully efficient")
	check(SailingModel.trim_efficiency(10.0, 150.0) < 0.7, "sheeted in hard on a run is badly trimmed")
	check(SailingModel.AUTO_TRIM_EFFICIENCY < 1.0, "auto trim leaves room for skilled manual trim")
	check(SailingModel.ideal_sheet_deg(45.0) < SailingModel.ideal_sheet_deg(150.0), "sails are eased further out downwind")
	check(SailingModel.leeway_deg(45.0) > SailingModel.leeway_deg(90.0), "more leeway close-hauled than reaching")
	check(near(SailingModel.leeway_deg(170.0), 0.0), "no leeway running downwind")
	check(near(SailingModel.vmg_kn(6.0, NORTH, EAST), 0.0), "no progress towards a target abeam")


func test_ship_motion() -> void:
	# Beam reach: heading north, wind from the east.
	var ship := ShipState.new()
	for i in 3600:
		ship.step(1.0, 0.0, EAST, 12.0)
	var expected := SailingModel.target_speed_kn(90.0, 12.0, ship.hull_speed_kn, ship.trim_efficiency)
	check(near(ship.speed_kn, expected, 0.01), "ship settles at the polar speed")
	check(ship.position.y < -1500.0, "ship makes ground north on a beam reach")
	check(ship.position.x < 0.0, "leeway pushes the ship away from the wind")

	var early := ShipState.new()
	early.step(60.0, 0.0, EAST, 12.0)
	check(early.speed_kn > 0.0 and early.speed_kn < expected * 0.5, "ship takes time to build speed")

	# Head to wind: the boat stops.
	var stalled := ShipState.new()
	stalled.speed_kn = 5.0
	for i in 3600:
		stalled.step(1.0, 0.0, NORTH, 12.0)
	check(stalled.speed_kn < 0.05, "ship stops when pointed into the wind")
	for i in 240:
		stalled.step(1.0, 1.0, NORTH, 12.0)
	check(not SailingModel.in_no_go(stalled.true_wind_angle_deg(NORTH)), "a stopped ship can still turn out of irons")

	var turning := ShipState.new()
	turning.speed_kn = 5.0
	turning.step(10.0, 1.0, deg_to_rad(200.0), 12.0)
	check(turning.heading > 0.0 and turning.heading < PI, "right rudder turns clockwise")

	# Hand trim: set well it beats the automatic trim, set badly it is slower.
	var auto := ShipState.new()
	var well_set := ShipState.new()
	well_set.manual_trim = true
	well_set.sheet_deg = SailingModel.ideal_sheet_deg(90.0)
	var badly_set := ShipState.new()
	badly_set.manual_trim = true
	badly_set.sheet_deg = 10.0
	for i in 3600:
		auto.step(1.0, 0.0, EAST, 12.0)
		well_set.step(1.0, 0.0, EAST, 12.0)
		badly_set.step(1.0, 0.0, EAST, 12.0)
	check(well_set.speed_kn > auto.speed_kn * 1.1, "well-set hand trim is faster than automatic trim")
	check(badly_set.speed_kn < auto.speed_kn, "badly set hand trim is slower than automatic trim")
	check(near(well_set.trim_efficiency, 1.0) and near(auto.trim_efficiency, SailingModel.AUTO_TRIM_EFFICIENCY), "trim efficiency is reported")

	# Time compression must not change the outcome much.
	var fine := ShipState.new()
	var coarse := ShipState.new()
	for i in 3600:
		fine.step(1.0, 0.0, EAST, 12.0)
	for i in 600:
		coarse.step(6.0, 0.0, EAST, 12.0)
	check(fine.position.distance_to(coarse.position) < 40.0, "6x time steps land in nearly the same place")


func test_trade() -> void:
	var par := 9.0
	var fast := Trade.sale_price("fish", par * 0.8, par, 15.0)
	var on_par := Trade.sale_price("fish", par, par, 15.0)
	var slow := Trade.sale_price("fish", par * 2.0, par, 15.0)
	var cost: int = Trade.GOODS["fish"]["buy"]
	check(fast > on_par and on_par > slow, "perishable cargo pays more the faster it arrives")
	check(on_par > cost, "a par passage with perishables is profitable")
	check(slow < cost, "a slow passage with perishables loses money")
	check(Trade.sale_price("timber", par * 0.5, par, 15.0) == Trade.sale_price("timber", par * 3.0, par, 15.0), "durable cargo ignores passage time")
	check(Trade.sale_price("timber", par, par, 15.0) > int(Trade.GOODS["timber"]["buy"]), "durable cargo makes a small profit")
	check(fast - cost > Trade.sale_price("timber", par, par, 15.0) - int(Trade.GOODS["timber"]["buy"]), "a fast perishable run beats the safe cargo")
	var two_each := true
	for port: String in World.PORTS:
		two_each = two_each and Trade.goods_sold_at(port).size() == 2
	check(two_each, "each port sells two goods")
	check(Trade.sale_price("timber", par, par, 30.0) > Trade.sale_price("timber", par, par, 15.0), "cargo is worth more the further it is carried")
	check(Trade.sale_price("fish", par, par, 30.0) > Trade.sale_price("fish", par, par, 15.0), "perishables are worth more over distance too")


func test_time_compression() -> void:
	var open_water := 5000.0
	check(near(TimeCompression.target_scale(false, false, false, open_water), TimeCompression.MAX_SCALE), "open water runs at full compression")
	check(near(TimeCompression.target_scale(true, false, false, open_water), 1.0), "steering drops to normal time")
	check(near(TimeCompression.target_scale(false, true, false, open_water), 1.0), "being in irons drops to normal time")
	check(near(TimeCompression.target_scale(false, false, true, open_water), 1.0), "land ahead drops to normal time")
	check(near(TimeCompression.target_scale(false, false, false, 100.0), 1.0), "close to a hazard runs at normal time")
	var slowing := 6.0 - TimeCompression.approach(6.0, 1.0, 0.1)
	var speeding := TimeCompression.approach(1.0, 6.0, 0.1) - 1.0
	check(slowing > speeding, "time slows down faster than it speeds up")
	check(near(TimeCompression.approach(1.2, 1.0, 1.0), 1.0), "compression never overshoots its target")


func test_world() -> void:
	var water := Vector2(11000, 8000)
	var inland := Vector2(2000, 2000)
	check(not World.is_land(water) and World.is_land(inland), "the middle of the bay is water and the north-west is land")
	check(World.is_blocked(Vector2(-10, 100)) and World.is_blocked(inland) and not World.is_blocked(water), "land and off-chart are both blocked")
	check(World.distance_to_land(water) > 2000.0, "the middle of the bay is well clear of land")
	check(World.triangles().size() % 3 == 0 and World.triangles().size() > 0, "the land is cut into triangles")

	# The map is to scale: Melbourne sits where Williamstown really is.
	var williamstown := World.lonlat_to_px(144.90, -37.87)
	check(World.port_position("melbourne").distance_to(williamstown) < 1200.0, "Melbourne is within three miles of its real position")
	check(near(World.lonlat_to_px(144.30, -37.78).length(), 0.0, 1.0), "the chart's top-left corner is its north-west limit")

	var roomy := true
	var routes_ok := true
	for port: String in World.PORTS:
		var position := World.port_position(port)
		roomy = roomy and not World.is_blocked(position) and World.distance_to_land(position) > 200.0
		check(World.destinations(port).size() == World.PORTS.size() - 1 and not World.destinations(port).has(port), "every other port is a destination")
		for other in World.destinations(port):
			var route := World.pilot_route(port, other)
			var straight := position.distance_to(World.port_position(other)) / 400.0
			routes_ok = routes_ok and route.size() >= 2 and route[0] == position and route[route.size() - 1] == World.port_position(other)
			routes_ok = routes_ok and World.route_length_nm(route) >= straight - 0.01 and World.route_length_nm(route) < straight * 5.0
			for i in range(1, route.size()):
				routes_ok = routes_ok and not World.segment_crosses_land(route[i - 1], route[i], 100.0)
	check(roomy, "every port is in the water with room to dock")
	check(routes_ok, "every pair of ports has a pilot route that stays off the land")

	var geelong := World.port_position("geelong")
	var queenscliff := World.port_position("queenscliff")
	check(World.segment_crosses_land(geelong, queenscliff), "the straight line from Geelong to Queenscliff crosses the Bellarine Peninsula")
	var around := World.pilot_route("geelong", "queenscliff")
	check(around.size() > 2, "the pilot route from Geelong to Queenscliff goes around the peninsula")
	check(World.route_length_nm(around) > geelong.distance_to(queenscliff) / 400.0 * 1.3, "going around is a good deal further than the straight line")
	check(World.pilot_route("geelong", "queenscliff") == around, "pilot routes are repeatable")


func test_speed_explanations() -> void:
	check(SailingModel.point_of_sail(10.0) == "Head to wind", "pointing at the wind is named head to wind")
	check(SailingModel.point_of_sail(45.0) == "Close-hauled", "45 degrees is close-hauled")
	check(SailingModel.point_of_sail(90.0) == "Beam reach", "90 degrees is a beam reach")
	check(SailingModel.point_of_sail(130.0) == "Broad reach", "130 degrees is a broad reach")
	check(SailingModel.point_of_sail(175.0) == "Running", "175 degrees is running")
	check(SailingModel.point_of_sail_tip(90.0) != SailingModel.point_of_sail_tip(175.0), "each point of sail has its own tip")
	var best := SailingModel.best_speed_kn(12.0, 7.0, 0.85)
	check(near(best, SailingModel.target_speed_kn(120.0, 12.0, 7.0, 0.85)), "best speed is the broad reach speed")
	var vmg := SailingModel.best_upwind_vmg_kn(12.0, 7.0, 0.85)
	check(vmg > 0.0 and vmg < SailingModel.target_speed_kn(60.0, 12.0, 7.0, 0.85), "upwind progress is slower than boat speed")
	check(not SailingModel.can_lay(42.0), "a course just outside the no-go zone still cannot be laid because of leeway")
	check(SailingModel.can_lay(50.0), "a course 50 degrees off the wind can be laid")
	check(Trade.premium_hours(9.0) > 9.0 * Trade.FAST_FRACTION and Trade.premium_hours(9.0) < 9.0 * Trade.SLOW_FRACTION, "premium deadline sits between fast and slow")
	check(Trade.freshness_multiplier(Trade.premium_hours(9.0) - 0.01, 9.0) >= 1.3, "arriving inside the premium deadline earns the premium")


func test_route_plan() -> void:
	var wind_from := deg_to_rad(World.WIND_FROM_DEG)
	var start := Vector2(1000, 1000)
	# 4 nautical miles on a beam reach.
	var across := SailingModel.bearing_to_vector(wind_from + PI / 2.0) * 1600.0
	var reach := RoutePlan.leg(start, start + across, wind_from, 12.0, 7.0, 0.85)
	check(near(reach["distance_nm"], 4.0, 0.01), "leg distance is in nautical miles")
	check(reach["direct"], "a beam reach leg can be sailed directly")
	check(near(reach["hours"], 4.0 / float(reach["speed_kn"]), 0.001), "leg time is distance over speed")

	# The same distance straight upwind has to be zig-zagged and takes longer.
	var upwind_offset := SailingModel.bearing_to_vector(wind_from) * 1600.0
	var beat := RoutePlan.leg(start, start + upwind_offset, wind_from, 12.0, 7.0, 0.85)
	check(not beat["direct"], "a leg straight upwind cannot be sailed directly")
	check(float(beat["hours"]) > float(reach["hours"]) * 2.0, "beating upwind takes much longer than reaching")

	# Sailing the zig-zag as two planned legs should roughly match the estimate.
	var tack_angle := deg_to_rad(55.0)
	var half := 800.0 / cos(tack_angle)
	var corner := start + SailingModel.bearing_to_vector(wind_from + tack_angle) * half
	var points: Array[Vector2] = [start, corner, start + upwind_offset]
	var zigzag := RoutePlan.legs(points, wind_from, 12.0, 7.0, 0.85)
	check(zigzag.size() == 2 and zigzag[0]["direct"] and zigzag[1]["direct"], "a planned zig-zag is two sailable legs")
	var planned := RoutePlan.total_hours(zigzag)
	check(absf(planned - float(beat["hours"])) < float(beat["hours"]) * 0.35, "planned zig-zag and the upwind estimate roughly agree")

	var faster := RoutePlan.leg(start, start + across, wind_from, 12.0, Shipyard.hull_speed_kn("cutter", 2), 0.85)
	check(float(faster["hours"]) < float(reach["hours"]), "better sails shorten the estimate")
	check(near(RoutePlan.leg(start, start, wind_from, 12.0, 7.0, 0.85)["hours"], 0.0), "a zero-length leg takes no time")

	check(not World.segment_crosses_land(Vector2(10000, 7000), Vector2(13000, 9000)), "a line across open water is clear")
	check(World.segment_crosses_land(Vector2(11000, 8000), Vector2(11000, -500)), "a line off the chart is not clear")


func test_track() -> void:
	# A dog-leg with small wobbles along each straight.
	var sailed: Array[Vector2] = []
	for i in 11:
		sailed.append(Vector2(i * 100.0, (i % 2) * 6.0))
	for i in range(1, 11):
		sailed.append(Vector2(1000.0 + (i % 2) * 6.0, i * 100.0))
	var simplified := Track.simplify(sailed, 25.0)
	check(simplified.size() == 3, "a wobbly dog-leg simplifies to start, corner and end")
	check(simplified[0] == sailed[0] and simplified[2] == sailed[sailed.size() - 1], "simplifying keeps the start and end")
	check(simplified[1].distance_to(Vector2(1000, 0)) < 20.0, "simplifying keeps the corner")
	var marks := Track.to_marks(sailed, 12)
	check(marks.size() == 1 and marks[0].distance_to(Vector2(1000, 0)) < 20.0, "a dog-leg becomes one mark at the corner")

	var two: Array[Vector2] = [Vector2.ZERO, Vector2(500, 0)]
	check(Track.simplify(two, 25.0).size() == 2 and Track.to_marks(two, 12).is_empty(), "a straight run has no marks")

	# A long zig-zag has more corners than marks allowed; it is cut down to fit.
	var zigzag: Array[Vector2] = []
	for i in 41:
		zigzag.append(Vector2(i * 150.0, (i % 2) * 300.0 + i * 5.0))
	var limited := Track.to_marks(zigzag, 12)
	check(limited.size() <= 12, "marks are limited to the maximum")


func test_weather() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var first := Weather.roll(rng)
	rng.seed = 12345
	var again := Weather.roll(rng)
	check(first["from_deg"] == again["from_deg"] and first["kn"] == again["kn"], "the same seed gives the same forecast")

	var in_range := true
	var directions_differ := false
	var shifts := false
	var bounded := true
	for i in 200:
		var forecast := Weather.roll(rng)
		var from_deg: float = forecast["from_deg"]
		var kn: float = forecast["kn"]
		var off_prevailing := absf(wrapf(from_deg - Weather.PREVAILING_DEG, -180.0, 180.0))
		in_range = in_range and off_prevailing <= Weather.DIRECTION_SPREAD_DEG + 0.01 and kn >= Weather.MIN_KN and kn <= Weather.MAX_KN
		directions_differ = directions_differ or absf(from_deg - float(first["from_deg"])) > 20.0
		var start := Weather.wind_at(forecast, 0.0)
		check(near(start["from"], deg_to_rad(from_deg), 0.0001) and near(start["kn"], kn, 0.0001), "the wind on leaving port matches the forecast")
		for hour in range(1, 13):
			var later := Weather.wind_at(forecast, hour * 3600.0)
			var shift := absf(rad_to_deg(wrapf(float(later["from"]) - deg_to_rad(from_deg), -PI, PI)))
			bounded = bounded and shift <= Weather.MAX_SHIFT_DEG + 0.01
			bounded = bounded and absf(float(later["kn"]) - kn) <= Weather.MAX_STRENGTH_CHANGE_KN + 0.01
			shifts = shifts or shift > 5.0
	check(in_range, "forecasts stay within the allowed direction and strength")
	check(directions_differ, "forecasts differ from day to day")
	check(shifts, "the wind shifts during a passage")
	check(bounded, "wind shifts stay within their limits")

	check(Weather.compass_name(0.0) == "N" and Weather.compass_name(90.0) == "E", "compass names for north and east")
	check(Weather.compass_name(70.0) == "ENE" and Weather.compass_name(350.0) == "N", "compass names round to the nearest point")
	check(Weather.describe({"from_deg": 225.0, "kn": 11.0}) == "SW 11 kn", "a forecast reads as direction and strength")
	check(near(Trade.par_from_estimate(5.0), 5.0 * Trade.PAR_FACTOR), "par is a multiple of the direct estimate")


func test_tide() -> void:
	var rip := World.RIP_CENTRE
	var flood := deg_to_rad(World.FLOOD_BEARING_DEG)
	var quarter := Tide.CYCLE_HOURS / 4.0
	check(near(Tide.phase(0.0), 0.0) and near(Tide.phase(quarter), 1.0) and near(Tide.phase(quarter * 3.0), -1.0), "the tide runs from slack to flood to ebb")
	check(near(Tide.peak_kn(0.0), Tide.RIP_PEAK_KN + Tide.BAY_PEAK_KN), "the stream is strongest in the middle of the Rip")
	check(Tide.peak_kn(8000.0) < 0.5, "the stream is gentle in the open bay")
	var flooding := Tide.current_kn(rip, quarter, rip, flood)
	var ebbing := Tide.current_kn(rip, quarter * 3.0, rip, flood)
	check(flooding.normalized().is_equal_approx(SailingModel.bearing_to_vector(flood)), "the flood runs into the bay")
	check(flooding.is_equal_approx(-ebbing), "the ebb runs the other way at the same strength")
	check(Tide.current_kn(rip, 0.0, rip, flood).length() < 0.01, "there is no stream at slack water")
	check(near(Tide.hours_to_turn(0.0), Tide.CYCLE_HOURS / 2.0) and near(Tide.hours_to_turn(quarter), quarter), "time to the next turn of the tide")
	check(Tide.describe(quarter) == "flooding in" and Tide.describe(quarter * 3.0) == "ebbing out" and Tide.describe(0.0) == "slack water", "the tide is described in words")
	check(World.current_kn(rip, quarter).length() > World.current_kn(Vector2(11000, 6000), quarter).length() * 5.0, "the Rip runs far harder than the bay")
	check(not World.is_blocked(rip), "the middle of the Rip is open water")

	# A current carries the ship over the ground without changing her speed through the water.
	var still := ShipState.new()
	var carried := ShipState.new()
	for i in 3600:
		still.step(1.0, 0.0, EAST, 12.0)
		carried.step(1.0, 0.0, EAST, 12.0, Vector2(0, -2.0))
	check(near(still.speed_kn, carried.speed_kn), "a current does not change speed through the water")
	check(near(carried.ground_speed_kn(), still.ground_speed_kn() + 2.0, 0.1), "a fair current adds to speed over the ground")
	check(carried.position.y < still.position.y - 700.0, "a fair current carries her further")

	check(World.port_premium("barwon") > 1.0 and near(World.port_premium("melbourne"), 1.0), "only the ocean port pays a premium")
	check(near(World.route_premium("melbourne", "barwon"), World.port_premium("barwon")) and near(World.route_premium("barwon", "geelong"), World.port_premium("barwon")), "the premium applies both ways")
	check(Trade.sale_price("timber", 9.0, 9.0, 15.0, 1.4) > Trade.sale_price("timber", 9.0, 9.0, 15.0), "a premium raises the price")
	check(Trade.goods_sold_at("barwon").size() == 2, "the ocean port sells two goods")


func test_heavy_weather() -> void:
	check(not SailingModel.is_overpowered(12.0, false) and SailingModel.is_overpowered(24.0, false), "full sail is overpowered in a strong wind")
	check(not SailingModel.is_overpowered(24.0, true), "a reefed sail copes with a strong wind")

	var full := ShipState.new()
	var reefed := ShipState.new()
	reefed.reefed = true
	for i in 1800:
		full.step(1.0, 0.0, EAST, 12.0)
		reefed.step(1.0, 0.0, EAST, 12.0)
	check(reefed.speed_kn < full.speed_kn * 0.8, "reefing costs speed in ordinary wind")
	check(not full.overpowered and not full.damaged, "ordinary wind does no harm under full sail")

	var pressed := ShipState.new()
	var snug := ShipState.new()
	snug.reefed = true
	for i in 600:
		pressed.step(1.0, 0.0, EAST, 24.0)
		snug.step(1.0, 0.0, EAST, 24.0)
	check(pressed.overpowered and not pressed.damaged, "a short blow under full sail strains her but does no damage yet")
	check(snug.speed_kn > pressed.speed_kn, "reefed, she is faster than an overpowered ship in a blow")
	for i in 900:
		pressed.step(1.0, 0.0, EAST, 24.0)
		snug.step(1.0, 0.0, EAST, 24.0)
	check(pressed.damaged, "staying overpowered too long splits a sail")
	check(not snug.damaged and not snug.overpowered, "the reefed ship comes through unharmed")
	var before := pressed.speed_kn
	for i in 3600:
		pressed.step(1.0, 0.0, EAST, 12.0)
		full.step(1.0, 0.0, EAST, 12.0)
	check(pressed.speed_kn < full.speed_kn * 0.8 and before > 0.0, "a split sail leaves her slow even after the wind eases")

	# Squalls: stronger wind inside, forecast wind outside, and they move downwind.
	var map_size := World.SIZE
	var forecast := {"from_deg": 270.0, "kn": 12.0, "slow_phase": 0.0, "slow_hours": 3.0, "quick_phase": 0.0,
		"quick_hours": 1.0, "strength_phase": 0.0, "strength_hours": 2.0,
		"squalls": [{"delay_hours": 1.0, "offset": 0.0, "extra_kn": 10.0, "radius": 2000.0}]}
	var squall: Dictionary = forecast["squalls"][0]
	var at_start := Weather.squall_centre(forecast, squall, 1.0, map_size)
	var later := Weather.squall_centre(forecast, squall, 2.0, map_size)
	check(near(later.x - at_start.x, Weather.SQUALL_SPEED, 1.0) and near(later.y, at_start.y, 1.0), "a squall in a westerly travels east at its speed")
	var inside := Weather.wind_at(forecast, 7200.0, later, map_size)
	var outside := Weather.wind_at(forecast, 7200.0, later + Vector2(0, 5000), map_size)
	check(near(float(inside["kn"]) - float(outside["kn"]), 10.0, 0.01) and near(inside["squall"], 1.0), "the wind is stronger in the heart of a squall")
	check(near(outside["squall"], 0.0), "outside the squall the wind is as forecast")
	check(near(Weather.squall_strength(0.0, 2000.0), 1.0) and near(Weather.squall_strength(2000.0, 2000.0), 0.0), "a squall fades out at its edge")
	check(Weather.describe(forecast).contains("squall"), "the forecast mentions squalls")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var with_squalls := 0
	for i in 100:
		var rolled: Array = Weather.roll(rng)["squalls"]
		with_squalls += 1 if not rolled.is_empty() else 0
		check(rolled.size() <= 2, "at most two squalls a day")
	check(with_squalls > 30 and with_squalls < 90, "some days have squalls and some do not")


func test_shipyard() -> void:
	check(Shipyard.hold_capacity("cutter", 0) == 10 and Shipyard.hold_capacity("cutter", 1) == 15, "the hold upgrade adds capacity")
	check(Shipyard.hold_capacity("ketch", 0) > Shipyard.hold_capacity("cutter", 3), "a ketch out-carries a fully upgraded cutter")
	check(near(Shipyard.hull_speed_kn("cutter", 0), 7.0) and Shipyard.hull_speed_kn("cutter", 2) > 7.0, "better sails add speed")
	check(Shipyard.hull_speed_kn("schooner", 0) > Shipyard.hull_speed_kn("ketch", 0), "bigger ships are faster")
	check(Shipyard.turn_factor("schooner") < Shipyard.turn_factor("ketch") and Shipyard.turn_factor("ketch") < Shipyard.turn_factor("cutter"), "bigger ships turn more slowly")
	check(Shipyard.upgrade_cost("hold", 1) > Shipyard.upgrade_cost("hold", 0), "upgrades get dearer")
	var capped := true
	for kind in Shipyard.UPGRADE_ORDER:
		capped = capped and Shipyard.upgrade_cost(kind, Shipyard.max_level(kind)) == -1 and Shipyard.upgrade_cost(kind, 0) > 0
	check(capped and Shipyard.UPGRADE_ORDER.size() == Shipyard.UPGRADES.size(), "every upgrade has a price and a top level")
	check(Shipyard.ship_cost("cutter", "ketch") == 700, "the first new ship costs its full price")
	check(Shipyard.ship_cost("ketch", "schooner") == 1850, "the old ship is traded in at half price")
	check(Shipyard.ship_cost("schooner", "cutter") < 0, "trading down pays money back")
	check(near(Shipyard.leeway_factor(0), 1.0) and near(Shipyard.leeway_factor(2), 0.5625), "a deeper keel cuts sideways slip")
	check(Shipyard.strain_limit_s("cutter", 2) > Shipyard.strain_limit_s("cutter", 0) * 1.9, "stronger rigging stands a blow longer")
	check(Shipyard.SHIP_ORDER.size() == Shipyard.SHIPS.size() and Shipyard.SHIP_ORDER[0] == "cutter", "the ships are listed from smallest to largest")

	# The ship's qualities change how she sails.
	var plain := ShipState.new()
	var deep_keel := ShipState.new()
	deep_keel.leeway_factor = 0.5
	for i in 1800:
		plain.step(1.0, 0.0, EAST, 12.0)
		deep_keel.step(1.0, 0.0, EAST, 12.0)
	check(absf(deep_keel.position.x) < absf(plain.position.x) * 0.6, "a deeper keel slips sideways less")
	var handy := ShipState.new()
	var heavy := ShipState.new()
	heavy.turn_factor = 0.65
	handy.speed_kn = 5.0
	heavy.speed_kn = 5.0
	handy.step(10.0, 1.0, deg_to_rad(200.0), 12.0)
	heavy.step(10.0, 1.0, deg_to_rad(200.0), 12.0)
	check(heavy.heading < handy.heading * 0.7 and heavy.heading > 0.0, "a bigger ship turns more slowly")
	var tough := ShipState.new()
	tough.strain_limit_s = 3000.0
	for i in 1500:
		tough.step(1.0, 0.0, EAST, 24.0)
	check(tough.overpowered and not tough.damaged, "stronger rigging has not split where the standard rig would")


func test_market_and_charters() -> void:
	check(near(Market.demand_factor("wool", "melbourne"), Market.WANTED_FACTOR) and near(Market.demand_factor("wool", "mornington"), 1.0), "a port pays more for what it wants")
	check(near(Market.glut_factor(0.0), 1.0) and Market.glut_factor(20.0) < 1.0, "landing cargo lowers the price")
	check(near(Market.glut_factor(1000.0), Market.GLUT_FLOOR), "a glutted market has a floor price")
	check(near(Market.recovered(10.0, 4.0), 8.0) and near(Market.recovered(1.0, 100.0), 0.0), "the market recovers with time")
	var goods_known := true
	for good_id: String in Trade.GOODS:
		var good: Dictionary = Trade.GOODS[good_id]
		goods_known = goods_known and World.PORTS.has(good["origin"]) and int(good["buy"]) > 0 and good["name"] != ""
		for port: String in good["wanted_at"]:
			goods_known = goods_known and World.PORTS.has(port) and good["origin"] != port and Market.is_wanted(good_id, port)
	check(goods_known, "every cargo is sold at a real port and wanted somewhere else")
	check(not Market.is_wanted("no such cargo", "melbourne"), "an unknown cargo is wanted nowhere")
	check(Market.key("geelong", "wool") == "geelong:wool", "market entries are keyed by port and cargo")

	var consistent := true
	var ids := {}
	for contract: Dictionary in Contracts.CONTRACTS:
		ids[contract["id"]] = true
		consistent = consistent and World.PORTS.has(contract["from"]) and World.PORTS.has(contract["to"]) and contract["from"] != contract["to"]
		consistent = consistent and Trade.GOODS.has(contract["good"]) and Trade.GOODS[contract["good"]]["origin"] == contract["from"]
		consistent = consistent and Contracts.by_id(contract["id"]) == contract
	check(consistent, "every charter names real ports and a cargo sold where it starts")
	check(ids.size() == Contracts.CONTRACTS.size(), "charter ids are unique")
	check(Contracts.by_id("no such charter").is_empty(), "an unknown charter id gives nothing")
	check(Contracts.offers_at("geelong").size() == 1 and Contracts.offers_at("melbourne").size() == 2, "charters are offered where they start")

	var wool := Contracts.by_id("wool_clip")
	check(Contracts.required_units(wool, 10) == 10 and Contracts.required_units(wool, 45) == 20, "a small ship is asked for a full hold, a big one for the whole order")
	check(Contracts.bonus(wool, 45) > Contracts.bonus(wool, 10), "a bigger delivery earns a bigger bonus")
	var deadline := Contracts.deadline_hours(wool, 8.0)
	check(Contracts.is_met(wool, "geelong", "melbourne", 10, 10, deadline - 0.1, 8.0), "enough cargo on time fulfils the charter")
	check(not Contracts.is_met(wool, "geelong", "melbourne", 10, 10, deadline + 0.1, 8.0), "arriving late misses the charter")
	check(not Contracts.is_met(wool, "geelong", "melbourne", 9, 10, 1.0, 8.0), "too little cargo misses the charter")
	check(not Contracts.is_met(wool, "geelong", "mornington", 10, 10, 1.0, 8.0), "the wrong port misses the charter")


## The lists in data/ are meant to be edited by hand, so check they hold together.
func test_data() -> void:
	var ports_ok := true
	for port: String in World.PORTS:
		var info: Dictionary = World.PORTS[port]
		ports_ok = ports_ok and info.has("name") and info.has("lon") and info.has("lat")
		var real := World.lonlat_to_px(info["lon"], info["lat"])
		ports_ok = ports_ok and World.in_bounds(real)
		# Placed in the nearest roomy water, which should be close to the real spot.
		ports_ok = ports_ok and World.port_position(port).distance_to(real) < 1600.0
		ports_ok = ports_ok and World.distance_to_land(World.port_position(port)) >= World.PORT_CLEARANCE - 1.0
		ports_ok = ports_ok and World.port_premium(port) >= 1.0
		ports_ok = ports_ok and not Trade.goods_sold_at(port).is_empty()
	check(ports_ok, "every port has a name and a real position on the chart, sits in roomy water, and sells something")
	check(World.port_position("melbourne") == World.port_position("melbourne"), "a port stays where it was put")

	var ships_ok := Shipyard.SHIP_ORDER.size() == Shipyard.SHIPS.size()
	var last_hold := 0
	for id in Shipyard.SHIP_ORDER:
		var ship: Dictionary = Shipyard.SHIPS[id]
		for field: String in ["name", "price", "hold", "hull_speed", "turn", "strain_limit", "size", "blurb", "rig"]:
			ships_ok = ships_ok and ship.has(field)
		var rig: Array = ship["rig"]
		ships_ok = ships_ok and not rig.is_empty() and int(ship["hold"]) > last_hold
		for mast: Dictionary in rig:
			ships_ok = ships_ok and mast.has("y") and mast.has("boom") and mast.has("jib")
		last_hold = ship["hold"]
	check(ships_ok, "every ship is fully described and each carries more than the last")
	check(Shipyard.SHIPS[Shipyard.SHIP_ORDER[0]]["price"] == 0, "the first ship is free: it is the one you start with")


func test_sound_mix() -> void:
	var breeze := SoundMix.levels(true, false, 10.0, 4.0, false, 0.0)
	var gale := SoundMix.levels(true, false, 26.0, 4.0, false, 0.0)
	check(gale["wind"] > breeze["wind"] and breeze["wind"] > 0.0, "more wind is louder")
	var slow := SoundMix.levels(true, false, 12.0, 1.0, false, 0.0)
	var fast := SoundMix.levels(true, false, 12.0, 7.0, false, 0.0)
	check(fast["water"] > slow["water"] * 3.0, "water along the hull grows with speed")
	check(near(SoundMix.levels(true, false, 12.0, 0.0, false, 0.0)["water"], 0.0), "a stopped ship makes no wash")
	check(near(breeze["flap"], 0.0) and SoundMix.levels(true, false, 10.0, 1.0, true, 0.0)["flap"] > 0.2, "a sail only flaps when it is not drawing")
	check(near(breeze["rain"], 0.0) and SoundMix.levels(true, false, 20.0, 4.0, false, 1.0)["rain"] > 0.5, "rain is heard in a squall")
	var in_port := SoundMix.levels(false, false, 20.0, 5.0, true, 1.0)
	check(near(in_port["wind"], SoundMix.PORT_WIND) and near(in_port["water"], 0.0) and near(in_port["flap"], 0.0) and near(in_port["rain"], 0.0), "in port there is only a breeze")
	var paused := SoundMix.levels(true, true, 20.0, 5.0, true, 1.0)
	var silent := true
	var in_range := true
	for sound: String in paused:
		silent = silent and near(paused[sound], 0.0)
		in_range = in_range and gale[sound] >= 0.0 and gale[sound] <= 1.0
	check(silent, "a paused game is silent")
	check(in_range, "levels stay between 0 and 1")
	check(near(SoundMix.to_db(0.0), SoundMix.SILENT_DB) and near(SoundMix.to_db(1.0), 0.0) and SoundMix.to_db(0.5) < 0.0, "levels convert to decibels")


## The detailed coastline, the shortcuts that keep it fast, and what is marked on it.
func test_chart() -> void:
	# The coarse grid must agree with the coastline itself.
	var agrees := true
	var shore_squares := 0
	for i in 400:
		var seed_value := posmod(hash(i * 7919), 1000000)
		var p := Vector2(seed_value % int(World.SIZE.x), (seed_value / 7) % int(World.SIZE.y))
		var exact := false
		for polygon in World.land():
			exact = exact or Geometry2D.is_point_in_polygon(p, polygon)
		agrees = agrees and World.is_land(p) == exact
		shore_squares += 1 if World.cell_state(p) == 2 else 0
	check(agrees, "the quick land test agrees with the coastline at 400 scattered points")
	check(shore_squares > 0 and shore_squares < 100, "only a few of those points are near the shore")
	check(World.cell_state(Vector2(-50, 100)) == 0 and not World.is_land(Vector2(-50, 100)), "off the chart is not land")

	# Asking for the coast near a spot must not miss the nearest stretch.
	var distances_ok := true
	for p: Vector2 in [Vector2(11000, 8000), Vector2(9000, 7000), Vector2(6350, 12470), Vector2(1800, 8500), Vector2(12500, 3500), Vector2(4000, 14000)]:
		if World.is_blocked(p):
			continue
		var brute := minf(minf(p.x, World.SIZE.x - p.x), minf(p.y, World.SIZE.y - p.y))
		for polygon in World.land():
			for i in polygon.size():
				brute = minf(brute, p.distance_to(Geometry2D.get_closest_point_to_segment(p, polygon[i], polygon[(i + 1) % polygon.size()])))
		distances_ok = distances_ok and near(World.distance_to_land(p), brute, 0.01)
	check(distances_ok, "distance to land matches a full search of the coastline")
	var by_the_heads := Rect2(5500, 11500, 2000, 2000)
	check(World.edges_near(by_the_heads).size() > 20 and World.edges_near(by_the_heads).size() < 800, "only the nearby coast is returned for a view")
	check(World.triangles_near(by_the_heads).size() > 5, "nearby land triangles are found")
	check(World.edges_near(Rect2(10500, 7500, 300, 300)).is_empty(), "the middle of the bay has no coast nearby")
	check(World.minimap_texture().get_width() > 100, "the minimap picture is made")

	# The Rip is open water, with the bay up-tide of it and the ocean down-tide.
	var flood := SailingModel.bearing_to_vector(deg_to_rad(World.FLOOD_BEARING_DEG))
	check(not World.is_blocked(World.RIP_CENTRE) and World.distance_to_land(World.RIP_CENTRE) > 150.0, "the middle of the Rip is clear water")
	check(not World.is_blocked(World.RIP_CENTRE + flood * 1500.0) and not World.is_blocked(World.RIP_CENTRE - flood * 1500.0), "the tide runs through the Rip in open water both ways")
	check(not World.segment_crosses_land(World.RIP_CENTRE - flood * 1200.0, World.RIP_CENTRE + flood * 1200.0), "a ship can sail straight through the Rip along the tide")

	# The detail a chart should show.
	check(World.is_land(World.lonlat_to_px(144.765, -38.272)) or World.distance_to_land(World.lonlat_to_px(144.765, -38.272)) < 400.0, "the Mud Islands are on the chart")
	check(World.land().size() >= 2, "the chart has islands as well as the mainland")
	check(not World.is_land(World.lonlat_to_px(144.671, -38.234)), "Swan Bay is water")

	var places_ok := true
	for place: Dictionary in World.PLACES:
		places_ok = places_ok and place["name"] != "" and World.in_bounds(World.feature_position(place))
		places_ok = places_ok and (place["kind"] == "water" or place["kind"] == "land") and (int(place["rank"]) == 1 or int(place["rank"]) == 2)
		if place["kind"] == "water":
			places_ok = places_ok and not World.is_land(World.feature_position(place))
	check(places_ok, "every named place is on the chart, and waters are named on water")
	var lights_ok := true
	for light: Dictionary in World.LIGHTS:
		var at := World.feature_position(light)
		lights_ok = lights_ok and World.in_bounds(at) and int(light["year"]) > 1800 and int(light["year"]) < 1900 and light["note"] != ""
		# A light stands on the shore or on piles in the water, never far inland.
		lights_ok = lights_ok and (not World.is_land(at) or World.distance_to_land(at + Vector2(0, 0)) == 0.0)
	check(lights_ok and World.LIGHTS.size() >= 5, "every light is on the chart with a year and a note")
	check(World.light_label({"name": "Point Lonsdale", "year": 1863}) == "Point Lonsdale Light (1863)", "a light is labelled with its name and year")
	check(World.light_label({"name": "Eastern Light", "year": 1883}) == "Eastern Light (1883)", "a name that already says Light is left alone")
