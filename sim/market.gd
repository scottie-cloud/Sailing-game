extends RefCounted
## Supply and demand. Some ports want particular goods and pay more for
## them. Landing a lot of one cargo gluts the market: the price falls and
## recovers slowly, so the same run pays less each time it is repeated with a
## big hold.

const Goods = preload("res://data/goods.gd")
const WANTED_FACTOR := 1.25

## Each unit already on the market knocks this much off the price.
const GLUT_SLOPE := 0.01
const GLUT_FLOOR := 0.6
## Units of glut the market absorbs each hour.
const RECOVERY_PER_HOUR := 0.5


static func key(port: String, good_id: String) -> String:
	return "%s:%s" % [port, good_id]


static func is_wanted(good_id: String, port: String) -> bool:
	if not Goods.GOODS.has(good_id):
		return false
	var ports: Array = Goods.GOODS[good_id].get("wanted_at", [])
	return ports.has(port)


static func demand_factor(good_id: String, port: String) -> float:
	return WANTED_FACTOR if is_wanted(good_id, port) else 1.0


static func glut_factor(glut: float) -> float:
	return maxf(GLUT_FLOOR, 1.0 - GLUT_SLOPE * maxf(glut, 0.0))


static func recovered(glut: float, hours: float) -> float:
	return maxf(0.0, glut - RECOVERY_PER_HOUR * hours)
