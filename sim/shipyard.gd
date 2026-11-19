extends RefCounted
## Ships and upgrades. A bigger ship carries more and has a higher top speed
## but turns more slowly; upgrades carry over when you change ship.

const SHIPS := {
	"cutter": {"name": "Cutter", "price": 0, "hold": 10, "hull_speed": 7.0, "turn": 1.0, "strain_limit": 1200.0, "size": 1.0,
		"blurb": "One mast, quick to turn. A boat for learning the bay."},
	"ketch": {"name": "Ketch", "price": 700, "hold": 28, "hull_speed": 8.0, "turn": 0.8, "strain_limit": 1500.0, "size": 1.25,
		"blurb": "Two masts and more than twice the hold. A working coaster."},
	"schooner": {"name": "Schooner", "price": 2200, "hold": 45, "hull_speed": 9.5, "turn": 0.65, "strain_limit": 1800.0, "size": 1.5,
		"blurb": "Fast and roomy, but slow in stays: plan her turns."},
}
const SHIP_ORDER: Array[String] = ["cutter", "ketch", "schooner"]

const UPGRADES := {
	"hold": {"name": "Bigger hold", "effect": "+5 cargo", "cost": 150, "max": 3},
	"sails": {"name": "Better sails", "effect": "+6% speed", "cost": 200, "max": 3},
	"keel": {"name": "Deeper keel", "effect": "25% less sideways slip", "cost": 180, "max": 2},
	"rigging": {"name": "Stronger rigging", "effect": "stands a blow 50% longer", "cost": 160, "max": 2},
}
const UPGRADE_ORDER: Array[String] = ["hold", "sails", "keel", "rigging"]

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
