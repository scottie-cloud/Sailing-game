extends RefCounted
## Passage estimates for a planned route: a list of points joined by legs.
## A leg that points too close to the wind cannot be sailed directly, so it
## is costed as a zig-zag at the boat's best upwind progress.

const SailingModel = preload("res://sim/sailing_model.gd")
const ShipState = preload("res://sim/ship_state.gd")

## Extra time allowed for the speed lost in each tack of a zig-zag.
const TACK_PENALTY := 1.1


static func leg(from: Vector2, to: Vector2, wind_from: float, wind_kn: float, hull_speed_kn: float, trim: float) -> Dictionary:
	var offset: Vector2 = to - from
	var distance_nm: float = offset.length() / ShipState.PX_PER_NM
	var bearing: float = SailingModel.vector_to_bearing(offset)
	var twa: float = SailingModel.true_wind_angle_deg(bearing, wind_from)
	var direct: bool = SailingModel.can_lay(twa)
	var speed := 0.0
	if direct:
		# The bow points a little closer to the wind than the course made good.
		var heading_twa: float = twa - SailingModel.leeway_deg(twa)
		speed = SailingModel.target_speed_kn(heading_twa, wind_kn, hull_speed_kn, trim)
	else:
		var vmg: float = SailingModel.best_upwind_vmg_kn(wind_kn, hull_speed_kn, trim)
		speed = vmg / (cos(deg_to_rad(twa)) * TACK_PENALTY)
	var hours := 0.0
	if distance_nm > 0.0:
		hours = distance_nm / speed if speed > 0.0 else INF
	return {
		"from": from,
		"to": to,
		"distance_nm": distance_nm,
		"bearing": bearing,
		"twa_deg": twa,
		"direct": direct,
		"speed_kn": speed,
		"hours": hours,
	}


static func legs(points: Array[Vector2], wind_from: float, wind_kn: float, hull_speed_kn: float, trim: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(1, points.size()):
		result.append(leg(points[i - 1], points[i], wind_from, wind_kn, hull_speed_kn, trim))
	return result


static func total_hours(route_legs: Array[Dictionary]) -> float:
	var total := 0.0
	for route_leg in route_legs:
		var hours: float = route_leg["hours"]
		total += hours
	return total
