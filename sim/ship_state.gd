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
## Pixels per game second, including leeway.
var velocity := Vector2.ZERO


func step(dt: float, rudder: float, wind_from: float, wind_kn: float) -> void:
	var steerage := lerpf(MIN_STEERAGE, 1.0, clampf(speed_kn / hull_speed_kn, 0.0, 1.0))
	var turn := deg_to_rad(TURN_RATE_DEG_PER_MIN) / 60.0 * clampf(rudder, -1.0, 1.0) * steerage * dt
	heading = wrapf(heading + turn, 0.0, TAU)

	var side_angle := SailingModel.signed_wind_angle(heading, wind_from)
	var twa := absf(rad_to_deg(side_angle))
	var target := SailingModel.target_speed_kn(twa, wind_kn, hull_speed_kn, trim_efficiency)
	speed_kn = lerpf(target, speed_kn, exp(-dt / SPEED_TAU_S))

	# Leeway pushes the boat away from the wind.
	var leeway := deg_to_rad(SailingModel.leeway_deg(twa)) * signf(side_angle)
	velocity = SailingModel.bearing_to_vector(heading - leeway) * speed_kn * PX_PER_NM / 3600.0
	position += velocity * dt


func true_wind_angle_deg(wind_from: float) -> float:
	return SailingModel.true_wind_angle_deg(heading, wind_from)
