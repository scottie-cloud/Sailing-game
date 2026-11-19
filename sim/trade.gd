extends RefCounted
## Cargo, prices and ship upgrades. Perishable cargo is what makes speed pay:
## it sells for a premium after a fast passage and at a loss after a slow one.

const GOODS := {
	"fish": {"name": "Fresh fish", "origin": "haven", "perishable": true, "buy": 8, "sell": 12},
	"timber": {"name": "Timber", "origin": "haven", "perishable": false, "buy": 10, "sell": 13},
	"fruit": {"name": "Fruit", "origin": "eastpoint", "perishable": true, "buy": 9, "sell": 13},
	"wool": {"name": "Wool", "origin": "eastpoint", "perishable": false, "buy": 10, "sell": 13},
}

## A competent stage 1 passage, in game hours. Haven to Eastpoint is upwind.
const PAR_HOURS := {"haven>eastpoint": 9.0, "eastpoint>haven": 3.6}

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


static func par_hours(from_port: String, to_port: String) -> float:
	return PAR_HOURS.get(route_key(from_port, to_port), 5.0)


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


## Price per unit at the destination.
static func sale_price(good_id: String, hours: float, par: float) -> int:
	var good: Dictionary = GOODS[good_id]
	var base: float = good["sell"]
	if good["perishable"]:
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
