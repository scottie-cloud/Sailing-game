extends RefCounted
## The rules for charters. The charters themselves are in data/charters.gd.
## Carry enough of the named cargo between the two ports inside the time
## allowed and the charterer pays a bonus on top of the sale.

const Charters = preload("res://data/charters.gd")
const CONTRACTS: Array = Charters.CHARTERS


static func offers_at(port: String) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for contract: Dictionary in CONTRACTS:
		if contract["from"] == port:
			offers.append(contract)
	return offers


## The charter with this id, or an empty dictionary.
static func by_id(id: String) -> Dictionary:
	for contract: Dictionary in CONTRACTS:
		if contract["id"] == id:
			return contract
	return {}


## A small ship is asked for a full hold, not more than she can carry.
static func required_units(contract: Dictionary, capacity: int) -> int:
	var units: int = contract["units"]
	return mini(units, capacity)


static func deadline_hours(contract: Dictionary, par: float) -> float:
	var factor: float = contract["deadline_factor"]
	return par * factor


static func bonus(contract: Dictionary, capacity: int) -> int:
	var per_unit: int = contract["bonus_per_unit"]
	return required_units(contract, capacity) * per_unit


static func is_met(contract: Dictionary, from_port: String, to_port: String, units_carried: int, capacity: int, hours: float, par: float) -> bool:
	if contract["from"] != from_port or contract["to"] != to_port:
		return false
	return units_carried >= required_units(contract, capacity) and hours <= deadline_hours(contract, par)
