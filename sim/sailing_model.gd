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

## A reefed sail is smaller: it feels this fraction of the wind.
const REEF_WIND_FACTOR := 0.7
## More wind than this in the sail and the boat is overpowered.
const OVERPOWERED_KN := 20.0

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


## A course this far off the wind can be sailed directly. Leeway means the
## bow has to point a few degrees closer to the wind than the course.
static func can_lay(course_twa_deg: float) -> bool:
	return course_twa_deg >= NO_GO_DEG + leeway_deg(NO_GO_DEG)


## The fastest the boat goes on any heading in this wind.
static func best_speed_kn(wind_kn: float, hull_speed_kn: float, trim: float) -> float:
	return wind_factor(wind_kn) * hull_speed_kn * trim


## Best progress straight upwind when zig-zagging.
static func best_upwind_vmg_kn(wind_kn: float, hull_speed_kn: float, trim: float) -> float:
	var best := 0.0
	for angle in range(int(NO_GO_DEG), 91):
		var speed := target_speed_kn(float(angle), wind_kn, hull_speed_kn, trim)
		best = maxf(best, speed * cos(deg_to_rad(float(angle))))
	return best


static func point_of_sail(twa_deg: float) -> String:
	if twa_deg < NO_GO_DEG:
		return "Head to wind"
	if twa_deg < 55.0:
		return "Close-hauled"
	if twa_deg < 80.0:
		return "Close reach"
	if twa_deg < 105.0:
		return "Beam reach"
	if twa_deg < 150.0:
		return "Broad reach"
	return "Running"


static func point_of_sail_tip(twa_deg: float) -> String:
	if twa_deg < NO_GO_DEG:
		return "Too close to the wind: the sail can't fill. Turn away."
	if twa_deg < 55.0:
		return "As close to the wind as she goes: slow but gaining."
	if twa_deg < 80.0:
		return "Good speed while still working upwind."
	if twa_deg < 105.0:
		return "Wind on the side: fast and easy."
	if twa_deg < 150.0:
		return "Wind over the back corner: her fastest heading."
	return "Wind dead behind: steady, but slower than a broad reach."


## The wind the sail has to cope with: less when reefed.
static func sail_wind_kn(wind_kn: float, reefed: bool) -> float:
	return wind_kn * REEF_WIND_FACTOR if reefed else wind_kn


static func is_overpowered(wind_kn: float, reefed: bool) -> bool:
	return sail_wind_kn(wind_kn, reefed) > OVERPOWERED_KN
