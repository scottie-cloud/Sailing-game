extends RefCounted
## Cargo, prices and ship upgrades. Perishable cargo is what makes speed pay:
## it sells for a premium after a fast passage and at a loss after a slow one.
## Every cargo is worth more the further it has been carried.

const GOODS := {
	"newspapers": {"name": "Newspapers", "origin": "melbourne", "perishable": true, "buy": 8},
	"tools": {"name": "Tools", "origin": "melbourne", "perishable": false, "buy": 10},
	"butter": {"name": "Butter", "origin": "geelong", "perishable": true, "buy": 9},
	"wool": {"name": "Wool", "origin": "geelong", "perishable": false, "buy": 10},
	"fish": {"name": "Fresh fish", "origin": "queenscliff", "perishable": true, "buy": 8},
	"rope": {"name": "Rope", "origin": "queenscliff", "perishable": false, "buy": 10},
	"fruit": {"name": "Fruit", "origin": "mornington", "perishable": true, "buy": 9},
	"timber": {"name": "Timber", "origin": "mornington", "perishable": false, "buy": 10},
}

## Par for a passage is this multiple of the pilot-route estimate in the
## day's forecast wind: room for the tacks and a beginner's helm.
const PAR_FACTOR := 1.2

const FAST_FRACTION := 0.85
const SLOW_FRACTION := 1.75
const FAST_MULTIPLIER := 1.5
const SLOW_MULTIPLIER := 0.5

const BASE_HOLD := 10
const HOLD_PER_LEVEL := 5
const SAIL_BONUS_PER_LEVEL := 0.06
const MAX_UPGRADE_LEVEL := 3
const UPGRADE_BASE_COST := {"hold": 150, "sails": 200}


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


## Price per unit at the destination.
static func sale_price(good_id: String, hours: float, par: float, distance_nm: float) -> int:
	var base := base_sale_price(good_id, distance_nm)
	if GOODS[good_id]["perishable"]:
		return roundi(base * freshness_multiplier(hours, par))
	return roundi(base)


static func hold_capacity(level: int) -> int:
	return BASE_HOLD + HOLD_PER_LEVEL * level


static func sail_bonus(level: int) -> float:
	return 1.0 + SAIL_BONUS_PER_LEVEL * level


## Cost of the next level, or -1 when maxed out.
static func upgrade_cost(kind: String, level: int) -> int:
	if level >= MAX_UPGRADE_LEVEL:
		return -1
	var base: float = UPGRADE_BASE_COST[kind]
	return roundi(base * pow(1.6, level))


## Arrive inside this many hours and perishable cargo still earns a premium.
static func premium_hours(par: float) -> float:
	return par * lerpf(FAST_FRACTION, SLOW_FRACTION, 0.2)
