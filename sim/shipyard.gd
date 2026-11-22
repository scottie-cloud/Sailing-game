extends RefCounted
## The rules for ships and upgrades. The ships and upgrades themselves are
## in data/ships.gd. A bigger ship carries more and has a higher top speed
## but turns more slowly; upgrades carry over when you change ship.

const Ships = preload("res://data/ships.gd")
const SHIPS: Dictionary = Ships.SHIPS
const SHIP_ORDER: Array[String] = Ships.SHIP_ORDER
const UPGRADES: Dictionary = Ships.UPGRADES
const UPGRADE_ORDER: Array[String] = Ships.UPGRADE_ORDER

const HOLD_PER_LEVEL := 5
const SAIL_BONUS_PER_LEVEL := 0.06
const KEEL_LEEWAY_FACTOR := 0.75
const RIGGING_BONUS_PER_LEVEL := 0.5
## A ship traded in is worth this fraction of its price.
const TRADE_IN := 0.5


static func max_level(kind: String) -> int:
	return UPGRADES[kind]["max"]


## Cost of the next level, or -1 when maxed out.
static func upgrade_cost(kind: String, level: int) -> int:
	if level >= max_level(kind):
		return -1
	var base: float = UPGRADES[kind]["cost"]
	return roundi(base * pow(1.6, level))


static func hold_capacity(ship_id: String, hold_level: int) -> int:
	var base: int = SHIPS[ship_id]["hold"]
	return base + HOLD_PER_LEVEL * hold_level


static func hull_speed_kn(ship_id: String, sail_level: int) -> float:
	var base: float = SHIPS[ship_id]["hull_speed"]
	return base * (1.0 + SAIL_BONUS_PER_LEVEL * sail_level)


static func leeway_factor(keel_level: int) -> float:
	return pow(KEEL_LEEWAY_FACTOR, keel_level)


static func strain_limit_s(ship_id: String, rigging_level: int) -> float:
	var base: float = SHIPS[ship_id]["strain_limit"]
	return base * (1.0 + RIGGING_BONUS_PER_LEVEL * rigging_level)


static func turn_factor(ship_id: String) -> float:
	return SHIPS[ship_id]["turn"]


## What it costs to change from one ship to another, after the trade-in.
static func ship_cost(current_id: String, wanted_id: String) -> int:
	var price: float = SHIPS[wanted_id]["price"]
	var old_price: float = SHIPS[current_id]["price"]
	return roundi(price - old_price * TRADE_IN)
