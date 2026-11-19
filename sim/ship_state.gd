extends RefCounted
## One ship's motion. step() takes GAME seconds, so time compression is
## just the caller passing a bigger dt.

const SailingModel = preload("res://sim/sailing_model.gd")

const PX_PER_NM := 400.0
## Turn rate at full speed, degrees per game minute.
const TURN_RATE_DEG_PER_MIN := 50.0
## A stopped boat can still turn a little, so you can always get out of irons.
const MIN_STEERAGE := 0.35
## How quickly speed settles on a new point of sail (game seconds).
const SPEED_TAU_S := 300.0

var position := Vector2.ZERO
var heading := 0.0
var speed_kn := 0.0
var hull_speed_kn := 7.0
var trim_efficiency := SailingModel.AUTO_TRIM_EFFICIENCY
## With manual trim the player sets the sheet: the boom's angle off the
## centreline. Set well it beats the automatic trim; set badly it is slower.
var manual_trim := false
var sheet_deg := 45.0
## Reefed, the sail is smaller: slower in ordinary wind, safe in a blow.
var reefed := false
## Too much wind for the sail she is carrying.
var overpowered := false
## Seconds spent overpowered. Past the limit, a sail splits.
var strain_s := 0.0
## A split sail: slower until repaired in port.
var damaged := false
## Pixels per game second over the ground, including leeway and current.
var velocity := Vector2.ZERO

## Set from the ship and her upgrades: how readily she turns, how much she
## slips sideways, and how long she stands being overpowered.
var turn_factor := 1.0
var leeway_factor := 1.0
var strain_limit_s := 1200.0

const OVERPOWERED_SPEED_FACTOR := 0.8
const DAMAGED_SPEED_FACTOR := 0.7


func step(dt: float, rudder: float, wind_from: float, wind_kn: float, current_kn: Vector2 = Vector2.ZERO) -> void:
	var steerage := lerpf(MIN_STEERAGE, 1.0, clampf(speed_kn / hull_speed_kn, 0.0, 1.0))
	var turn := deg_to_rad(TURN_RATE_DEG_PER_MIN) / 60.0 * clampf(rudder, -1.0, 1.0) * steerage * turn_factor * dt
	heading = wrapf(heading + turn, 0.0, TAU)

	var side_angle := SailingModel.signed_wind_angle(heading, wind_from)
	var twa := absf(rad_to_deg(side_angle))
	if manual_trim:
		trim_efficiency = SailingModel.trim_efficiency(sheet_deg, twa)
	else:
		trim_efficiency = SailingModel.AUTO_TRIM_EFFICIENCY
	overpowered = SailingModel.is_overpowered(wind_kn, reefed)
	var target := SailingModel.target_speed_kn(twa, SailingModel.sail_wind_kn(wind_kn, reefed), hull_speed_kn, trim_efficiency)
	if overpowered:
		# Laid over on her side, she goes slower and slides sideways.
		target *= OVERPOWERED_SPEED_FACTOR
		strain_s += dt
		if strain_s > strain_limit_s:
			damaged = true
	else:
		strain_s = maxf(0.0, strain_s - dt)
	if damaged:
		target *= DAMAGED_SPEED_FACTOR
	speed_kn = lerpf(target, speed_kn, exp(-dt / SPEED_TAU_S))

	# Leeway pushes the boat away from the wind; the current carries her bodily.
	var leeway := deg_to_rad(SailingModel.leeway_deg(twa)) * signf(side_angle) * leeway_factor * (2.0 if overpowered else 1.0)
	velocity = (SailingModel.bearing_to_vector(heading - leeway) * speed_kn + current_kn) * PX_PER_NM / 3600.0
	position += velocity * dt


## Speed over the ground in knots: through the water, plus or minus the current.
func ground_speed_kn() -> float:
	return velocity.length() * 3600.0 / PX_PER_NM


func true_wind_angle_deg(wind_from: float) -> float:
	return SailingModel.true_wind_angle_deg(heading, wind_from)
