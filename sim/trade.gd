extends RefCounted
## The rules for cargo prices. The cargoes themselves are in data/goods.gd.
## Perishable cargo is what makes speed pay:
## it sells for a premium after a fast passage and at a loss after a slow one.
## Every cargo is worth more the further it has been carried.

const Goods = preload("res://data/goods.gd")
const GOODS: Dictionary = Goods.GOODS

## Par for a passage is this multiple of the pilot-route estimate in the
## day's forecast wind: room for the tacks and a beginner's helm.
const PAR_FACTOR := 1.2

const FAST_FRACTION := 0.85
const SLOW_FRACTION := 1.75
const FAST_MULTIPLIER := 1.5
const SLOW_MULTIPLIER := 0.5


static func route_key(from_port: String, to_port: String) -> String:
	return "%s>%s" % [from_port, to_port]


static func par_from_estimate(route_hours: float) -> float:
	return route_hours * PAR_FACTOR


static func goods_sold_at(port: String) -> Array[String]:
	var ids: Array[String] = []
	for id: String in GOODS:
		if GOODS[id]["origin"] == port:
			ids.append(id)
	return ids


## 1.5 for a fast passage, sliding down to 0.5 for a slow one.
static func freshness_multiplier(hours: float, par: float) -> float:
	var t := clampf(inverse_lerp(par * FAST_FRACTION, par * SLOW_FRACTION, hours), 0.0, 1.0)
	return lerpf(FAST_MULTIPLIER, SLOW_MULTIPLIER, t)


## What a unit is worth at a port this far away, before freshness.
static func base_sale_price(good_id: String, distance_nm: float) -> float:
	var good: Dictionary = GOODS[good_id]
	var buy: float = good["buy"]
	if good["perishable"]:
		return buy * (1.2 + 0.02 * distance_nm)
	return buy * (1.15 + 0.01 * distance_nm)


## Price per unit at the destination. Trade with a hard-to-reach port is
## scarce, so it pays a premium (1.0 = none).
static func sale_price(good_id: String, hours: float, par: float, distance_nm: float, premium: float = 1.0) -> int:
	var base := base_sale_price(good_id, distance_nm) * premium
	if GOODS[good_id]["perishable"]:
		return roundi(base * freshness_multiplier(hours, par))
	return roundi(base)


## Arrive inside this many hours and perishable cargo still earns a premium.
static func premium_hours(par: float) -> float:
	return par * lerpf(FAST_FRACTION, SLOW_FRACTION, 0.2)
