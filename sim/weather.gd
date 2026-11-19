extends RefCounted
## Wind. Each day in port gets a forecast: a direction and strength rolled
## around the prevailing breeze. Under sail the real wind drifts away from
## the forecast and back, so a plan made in port needs adjusting at sea.

const PREVAILING_DEG := 225.0
## The day's wind can come from any direction, but most often from near the
## prevailing one.
const DIRECTION_SPREAD_DEG := 180.0
const MIN_KN := 8.0
const MAX_KN := 16.0
## The most the wind swings away from the forecast during a passage.
const MAX_SHIFT_DEG := 20.0
const MAX_STRENGTH_CHANGE_KN := 3.0

## Squalls travel with the wind at this speed (px per hour: 15 knots).
const SQUALL_SPEED := 6000.0
## A squall starts this far upwind of the middle of the chart.
const SQUALL_RUN_UP := 10000.0
## Inside a squall the wind veers by up to this much.
const SQUALL_VEER_DEG := 15.0

const COMPASS: Array[String] = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
	"S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]


static func roll(rng: RandomNumberGenerator) -> Dictionary:
	# Two rolls added together favour directions near the prevailing wind.
	var offset := (rng.randf() + rng.randf() - 1.0) * DIRECTION_SPREAD_DEG
	# Most days bring no squall or one; some bring two.
	var squalls: Array = []
	var chance := rng.randf()
	var count := 0 if chance < 0.4 else (1 if chance < 0.8 else 2)
	for i in count:
		squalls.append({
			"delay_hours": rng.randf_range(0.5, 7.0),
			"offset": rng.randf_range(-0.4, 0.4),
			"extra_kn": rng.randf_range(8.0, 12.0),
			"radius": rng.randf_range(1800.0, 2800.0),
		})
	return {
		"squalls": squalls,
		"from_deg": wrapf(PREVAILING_DEG + offset, 0.0, 360.0),
		"kn": float(roundi(rng.randf_range(MIN_KN, MAX_KN))),
		"slow_phase": rng.randf() * TAU,
		"slow_hours": rng.randf_range(2.5, 4.0),
		"quick_phase": rng.randf() * TAU,
		"quick_hours": rng.randf_range(0.8, 1.5),
		"strength_phase": rng.randf() * TAU,
		"strength_hours": rng.randf_range(1.5, 3.0),
	}


## A slow swing and a quicker wobble, both zero at the moment of leaving port.
static func _drift(phase: float, period_hours: float, hours: float) -> float:
	return (sin(phase + TAU * hours / period_hours) - sin(phase)) / 2.0


## Where a squall is this many hours after leaving port. It crosses the chart
## in a straight line, travelling with the forecast wind.
static func squall_centre(forecast: Dictionary, squall: Dictionary, hours: float, map_size: Vector2) -> Vector2:
	var from_deg: float = forecast["from_deg"]
	var downwind := Vector2(sin(deg_to_rad(from_deg + 180.0)), -cos(deg_to_rad(from_deg + 180.0)))
	var offset: float = squall["offset"]
	var delay: float = squall["delay_hours"]
	var line_point := map_size / 2.0 + downwind.orthogonal() * offset * map_size.x
	return line_point + downwind * (SQUALL_SPEED * (hours - delay) - SQUALL_RUN_UP)


## 1 in the heart of a squall, fading to 0 at its edge.
static func squall_strength(distance: float, radius: float) -> float:
	return 1.0 - smoothstep(radius * 0.6, radius, distance)


## The wind this long after leaving port: {"from": radians, "kn": knots,
## "squall": 0 to 1}. Squalls are only felt when a position is given.
static func wind_at(forecast: Dictionary, game_seconds: float, position: Vector2 = Vector2.INF, map_size: Vector2 = Vector2.ZERO) -> Dictionary:
	var hours := game_seconds / 3600.0
	var slow: float = _drift(forecast["slow_phase"], forecast["slow_hours"], hours)
	var quick: float = _drift(forecast["quick_phase"], forecast["quick_hours"], hours)
	var shift := MAX_SHIFT_DEG * (0.75 * slow + 0.25 * quick)
	var change: float = MAX_STRENGTH_CHANGE_KN * _drift(forecast["strength_phase"], forecast["strength_hours"], hours)
	var from_deg: float = forecast["from_deg"]
	var base_kn: float = forecast["kn"]
	var squall := 0.0
	var extra_kn := 0.0
	if position != Vector2.INF:
		var squalls: Array = forecast.get("squalls", [])
		for entry: Dictionary in squalls:
			var radius: float = entry["radius"]
			var strength := squall_strength(position.distance_to(squall_centre(forecast, entry, hours, map_size)), radius)
			var entry_kn: float = entry["extra_kn"]
			extra_kn = maxf(extra_kn, entry_kn * strength)
			squall = maxf(squall, strength)
	return {
		"from": deg_to_rad(wrapf(from_deg + shift + SQUALL_VEER_DEG * squall, 0.0, 360.0)),
		"kn": base_kn + change + extra_kn,
		"squall": squall,
	}


static func compass_name(degrees: float) -> String:
	return COMPASS[posmod(roundi(degrees / 22.5), 16)]


static func describe(forecast: Dictionary) -> String:
	var from_deg: float = forecast["from_deg"]
	var kn: float = forecast["kn"]
	var squalls: Array = forecast.get("squalls", [])
	var text := "%s %d kn" % [compass_name(from_deg), roundi(kn)]
	if squalls.size() == 1:
		text += ", a squall about"
	elif squalls.size() > 1:
		text += ", squalls about"
	return text
