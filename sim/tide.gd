extends RefCounted
## The tide. It floods into the bay and ebbs out again on a 12.4 hour cycle.
## The stream is fierce in the narrow entrance (the Rip) and gentle elsewhere,
## so the entrance is easy with the tide and hard work against it.

const SailingModel = preload("res://sim/sailing_model.gd")

const CYCLE_HOURS := 12.4
## Strongest stream in the entrance at mid-tide.
const RIP_PEAK_KN := 3.0
## How far (px) the strong stream reaches from the middle of the entrance.
const RIP_REACH := 2200.0
## The gentle set felt across the rest of the bay.
const BAY_PEAK_KN := 0.3
const BAY_REACH := 9000.0
## Below this fraction of full strength the tide counts as slack water.
const SLACK := 0.2
## How far the water rises from low to high, in metres.
const RANGE_M := 0.9


## +1 at full flood (into the bay), -1 at full ebb, 0 at slack water.
static func phase(clock_hours: float) -> float:
	return sin(TAU * clock_hours / CYCLE_HOURS)


## Height of the water above low water, in metres. It rises while the tide
## floods and falls while it ebbs.
static func height_m(clock_hours: float) -> float:
	return RANGE_M / 2.0 * (1.0 - cos(TAU * clock_hours / CYCLE_HOURS))


## Peak stream (knots) this far from the middle of the entrance.
static func peak_kn(distance: float) -> float:
	return RIP_PEAK_KN * exp(-pow(distance / RIP_REACH, 2.0)) + BAY_PEAK_KN * exp(-pow(distance / BAY_REACH, 2.0))


## The stream at a position, in knots, as a vector on the chart.
static func current_kn(position: Vector2, clock_hours: float, rip_centre: Vector2, flood_bearing: float) -> Vector2:
	var strength := peak_kn(position.distance_to(rip_centre)) * phase(clock_hours)
	return SailingModel.bearing_to_vector(flood_bearing) * strength


## Hours until the stream next turns.
static func hours_to_turn(clock_hours: float) -> float:
	var half := CYCLE_HOURS / 2.0
	return half - fposmod(clock_hours, half)


static func describe(clock_hours: float) -> String:
	var now := phase(clock_hours)
	if absf(now) < SLACK:
		return "slack water"
	return "flooding in" if now > 0.0 else "ebbing out"
