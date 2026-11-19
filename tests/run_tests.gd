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
	var fast := Trade.sale_price("fish", par * 0.8, par)
	var on_par := Trade.sale_price("fish", par, par)
	var slow := Trade.sale_price("fish", par * 2.0, par)
	var cost: int = Trade.GOODS["fish"]["buy"]
	check(fast > on_par and on_par > slow, "perishable cargo pays more the faster it arrives")
	check(on_par > cost, "a par passage with perishables is profitable")
	check(slow < cost, "a slow passage with perishables loses money")
	check(Trade.sale_price("timber", par * 0.5, par) == Trade.sale_price("timber", par * 3.0, par), "durable cargo ignores passage time")
	check(Trade.sale_price("timber", par, par) > int(Trade.GOODS["timber"]["buy"]), "durable cargo makes a small profit")
	check(fast - cost > Trade.sale_price("timber", par, par) - int(Trade.GOODS["timber"]["buy"]), "a fast perishable run beats the safe cargo")
	check(Trade.goods_sold_at("haven").size() == 2 and Trade.goods_sold_at("eastpoint").size() == 2, "each port sells two goods")
	check(Trade.hold_capacity(1) > Trade.hold_capacity(0), "hold upgrade adds capacity")
	check(Trade.upgrade_cost("hold", 1) > Trade.upgrade_cost("hold", 0), "upgrades get dearer")
	check(Trade.upgrade_cost("sails", Trade.MAX_UPGRADE_LEVEL) == -1, "upgrades stop at the maximum level")
	check(Trade.sail_bonus(2) > Trade.sail_bonus(0), "sail upgrade adds speed")


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
	var haven := World.port_position("haven")
	var eastpoint := World.port_position("eastpoint")
	check(not World.is_land(haven) and not World.is_land(eastpoint), "ports are in the water")
	check(World.distance_to_land(haven) > 60.0 and World.distance_to_land(eastpoint) > 60.0, "ports have room to dock")
	check(World.is_land(Vector2(3500, 1750)), "the island is land")
	check(World.distance_to_land(Vector2(3500, 1200)) > 300.0, "there is a clear channel north of the island")
	check(World.other_port("haven") == "eastpoint" and World.other_port("eastpoint") == "haven", "the two ports are each other's destination")

	var crosses_island := false
	for i in 101:
		crosses_island = crosses_island or World.is_land(haven.lerp(eastpoint, i / 100.0))
	check(crosses_island, "the straight line between ports is blocked by the island")

	var wind_from := deg_to_rad(World.WIND_FROM_DEG)
	var outward := SailingModel.vector_to_bearing(eastpoint - haven)
	check(SailingModel.in_no_go(SailingModel.true_wind_angle_deg(outward, wind_from)), "Haven to Eastpoint is upwind, so it needs tacking")
	var homeward := SailingModel.vector_to_bearing(haven - eastpoint)
	check(SailingModel.true_wind_angle_deg(homeward, wind_from) > 120.0, "Eastpoint to Haven is a downwind run")


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

	var faster := RoutePlan.leg(start, start + across, wind_from, 12.0, 7.0 * Trade.sail_bonus(2), 0.85)
	check(float(faster["hours"]) < float(reach["hours"]), "better sails shorten the estimate")
	check(near(RoutePlan.leg(start, start, wind_from, 12.0, 7.0, 0.85)["hours"], 0.0), "a zero-length leg takes no time")

	var haven := World.port_position("haven")
	var eastpoint := World.port_position("eastpoint")
	check(World.segment_crosses_land(haven, eastpoint), "the direct route is flagged as crossing land")
	check(not World.segment_crosses_land(Vector2(1500, 1200), Vector2(5500, 1200)), "the north channel is clear")
	check(World.in_bounds(haven) and not World.in_bounds(Vector2(-10, 100)), "bounds check")


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
