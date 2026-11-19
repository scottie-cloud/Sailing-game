extends RefCounted
## Time runs fast on open water and drops to normal whenever the player has
## something to decide: steering, stuck in irons, land ahead, or near a
## coast or the destination.

const MAX_SCALE := 6.0
## At or inside this distance (px) from a hazard, time is normal.
const SLOW_DISTANCE := 250.0
## At or beyond this distance, time is fully compressed.
const FAST_DISTANCE := 600.0
const DROP_RATE := 12.0
const RISE_RATE := 2.0


static func target_scale(steering: bool, in_irons: bool, land_ahead: bool, hazard_distance: float) -> float:
	if steering or in_irons or land_ahead:
		return 1.0
	var t := clampf(inverse_lerp(SLOW_DISTANCE, FAST_DISTANCE, hazard_distance), 0.0, 1.0)
	return lerpf(1.0, MAX_SCALE, t)


## Slow down almost at once, speed back up gently.
static func approach(current: float, target: float, real_dt: float) -> float:
	var rate := DROP_RATE if target < current else RISE_RATE
	return move_toward(current, target, rate * real_dt)
