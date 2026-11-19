extends RefCounted
## Pure sailing maths: no nodes, no engine state. Unit tested in tests/.
##
## Angles are compass bearings in radians: 0 = north (up the screen),
## clockwise positive. "Wind from" is the bearing the wind blows FROM.
## TWA = true wind angle: how far the bow points away from the wind,
## 0 (straight into it) to 180 (wind dead astern).

## Closer to the wind than this and the sails just flap.
const NO_GO_DEG := 40.0

## Stage 1 sails trim themselves, but not perfectly. Manual trim (stage 2)
## can reach 1.0, which is how skill turns into speed.
const AUTO_TRIM_EFFICIENCY := 0.85

## Wind strength at which the boat reaches its full polar speed.
const FULL_POWER_WIND_KN := 12.0

## Speed polar for a small fore-and-aft boat: fraction of hull speed by TWA.
const POLAR_ANGLES: Array[float] = [0.0, 30.0, 40.0, 50.0, 60.0, 90.0, 120.0, 150.0, 180.0]
const POLAR_FRACTIONS: Array[float] = [0.0, 0.05, 0.30, 0.55, 0.70, 0.90, 1.0, 0.86, 0.72]


static func bearing_to_vector(bearing: float) -> Vector2:
	return Vector2(sin(bearing), -cos(bearing))


static func vector_to_bearing(v: Vector2) -> float:
	return wrapf(atan2(v.x, -v.y), 0.0, TAU)


## Positive = wind on the starboard (right) side, negative = port.
static func signed_wind_angle(heading: float, wind_from: float) -> float:
	return wrapf(wind_from - heading, -PI, PI)


static func true_wind_angle_deg(heading: float, wind_from: float) -> float:
	return absf(rad_to_deg(signed_wind_angle(heading, wind_from)))


static func in_no_go(twa_deg: float) -> bool:
	return twa_deg < NO_GO_DEG


static func polar_fraction(twa_deg: float) -> float:
	var a := clampf(absf(twa_deg), 0.0, 180.0)
	for i in range(1, POLAR_ANGLES.size()):
		if a <= POLAR_ANGLES[i]:
			var t := inverse_lerp(POLAR_ANGLES[i - 1], POLAR_ANGLES[i], a)
			return lerpf(POLAR_FRACTIONS[i - 1], POLAR_FRACTIONS[i], t)
	return POLAR_FRACTIONS[POLAR_FRACTIONS.size() - 1]


static func wind_factor(wind_kn: float) -> float:
	return clampf(wind_kn / FULL_POWER_WIND_KN, 0.0, 1.15)


## The speed the boat settles at on this point of sail.
static func target_speed_kn(twa_deg: float, wind_kn: float, hull_speed_kn: float, trim_efficiency: float) -> float:
	return polar_fraction(twa_deg) * wind_factor(wind_kn) * hull_speed_kn * trim_efficiency


## Best boom angle off the centreline: sheeted in tight upwind, eased out downwind.
static func ideal_sheet_deg(twa_deg: float) -> float:
	return clampf(twa_deg * 0.5, 10.0, 85.0)


## Stage 2 hook: 1.0 with the sheet at the ideal angle, falling off as it is mis-set.
static func trim_efficiency(sheet_deg: float, twa_deg: float) -> float:
	var error := absf(sheet_deg - ideal_sheet_deg(twa_deg))
	return 1.0 - clampf(error / 45.0, 0.0, 1.0) * 0.6


## Sideways slip: worst close-hauled, none once the wind is well aft.
static func leeway_deg(twa_deg: float) -> float:
	return lerpf(6.0, 0.0, clampf(inverse_lerp(50.0, 120.0, twa_deg), 0.0, 1.0))


## Speed made good towards a target bearing.
static func vmg_kn(speed_kn: float, course: float, target_bearing: float) -> float:
	return speed_kn * cos(wrapf(target_bearing - course, -PI, PI))
