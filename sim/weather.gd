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

const COMPASS: Array[String] = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
	"S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]


static func roll(rng: RandomNumberGenerator) -> Dictionary:
	# Two rolls added together favour directions near the prevailing wind.
	var offset := (rng.randf() + rng.randf() - 1.0) * DIRECTION_SPREAD_DEG
	return {
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


## The wind this long after leaving port: {"from": radians, "kn": knots}.
static func wind_at(forecast: Dictionary, game_seconds: float) -> Dictionary:
	var hours := game_seconds / 3600.0
	var slow: float = _drift(forecast["slow_phase"], forecast["slow_hours"], hours)
	var quick: float = _drift(forecast["quick_phase"], forecast["quick_hours"], hours)
	var shift := MAX_SHIFT_DEG * (0.75 * slow + 0.25 * quick)
	var change: float = MAX_STRENGTH_CHANGE_KN * _drift(forecast["strength_phase"], forecast["strength_hours"], hours)
	var from_deg: float = forecast["from_deg"]
	var base_kn: float = forecast["kn"]
	return {
		"from": deg_to_rad(wrapf(from_deg + shift, 0.0, 360.0)),
		"kn": base_kn + change,
	}


static func compass_name(degrees: float) -> String:
	return COMPASS[posmod(roundi(degrees / 22.5), 16)]


static func describe(forecast: Dictionary) -> String:
	var from_deg: float = forecast["from_deg"]
	var kn: float = forecast["kn"]
	return "%s %d kn" % [compass_name(from_deg), roundi(kn)]
