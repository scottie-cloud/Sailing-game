extends RefCounted
## The stage 1 map: one enclosed bay, two ports, an island on the direct line.
## 400 px = 1 nautical mile.

const SIZE := Vector2(7200, 3600)

const PORTS := {
	"haven": {"name": "Port Haven", "position": Vector2(640, 1900)},
	"eastpoint": {"name": "Eastpoint", "position": Vector2(6640, 1500)},
}

## Steady breeze from the east-north-east, so Haven to Eastpoint is upwind.
const WIND_FROM_DEG := 70.0
const WIND_KN := 12.0

const _LAND_POINTS := [
	# West shore
	[Vector2(-400, -400), Vector2(450, -400), Vector2(520, 900), Vector2(400, 1500),
		Vector2(430, 2300), Vector2(560, 3000), Vector2(450, 4000), Vector2(-400, 4000)],
	# East shore
	[Vector2(7600, -400), Vector2(7600, 4000), Vector2(6800, 4000), Vector2(6900, 3000),
		Vector2(6850, 2000), Vector2(6880, 1200), Vector2(6780, 500), Vector2(6850, -400)],
	# North shore
	[Vector2(-400, -400), Vector2(7600, -400), Vector2(7600, 450), Vector2(6800, 560),
		Vector2(6000, 430), Vector2(5000, 640), Vector2(4000, 470), Vector2(3000, 700),
		Vector2(2000, 520), Vector2(1000, 650), Vector2(0, 560), Vector2(-400, 560)],
	# South shore
	[Vector2(-400, 4000), Vector2(-400, 3050), Vector2(0, 3050), Vector2(1000, 2950),
		Vector2(2000, 3130), Vector2(3000, 2900), Vector2(4000, 3100), Vector2(5000, 2880),
		Vector2(6000, 3120), Vector2(6800, 3000), Vector2(7600, 3050), Vector2(7600, 4000)],
	# Island
	[Vector2(3250, 1700), Vector2(3400, 1580), Vector2(3650, 1600), Vector2(3800, 1750),
		Vector2(3700, 1900), Vector2(3450, 1930), Vector2(3300, 1850)],
]

static var _land_cache: Array[PackedVector2Array] = []


static func land() -> Array[PackedVector2Array]:
	if _land_cache.is_empty():
		for points: Array in _LAND_POINTS:
			_land_cache.append(PackedVector2Array(points))
	return _land_cache


static func port_position(port: String) -> Vector2:
	return PORTS[port]["position"]


static func port_name(port: String) -> String:
	return PORTS[port]["name"]


static func other_port(port: String) -> String:
	return "eastpoint" if port == "haven" else "haven"


static func is_land(p: Vector2) -> bool:
	for polygon in land():
		if Geometry2D.is_point_in_polygon(p, polygon):
			return true
	return false


static func distance_to_land(p: Vector2) -> float:
	if is_land(p):
		return 0.0
	var best := INF
	for polygon in land():
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


static func in_bounds(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, SIZE).has_point(p)


## True if the straight line from a to b touches land.
static func segment_crosses_land(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, int(ceil(a.distance_to(b) / 40.0)))
	for i in steps + 1:
		if is_land(a.lerp(b, float(i) / steps)):
			return true
	return false
