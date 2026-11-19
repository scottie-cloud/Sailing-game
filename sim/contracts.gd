extends RefCounted
## Charters: paid jobs drawn from the trading history of Port Phillip Bay.
## Carry enough of the named cargo between the two ports inside the time
## allowed and the charterer pays a bonus on top of the sale.

const CONTRACTS := [
	{"id": "wool_clip", "title": "The wool clip", "from": "geelong", "to": "melbourne", "good": "wool",
		"units": 20, "deadline_factor": 1.1, "bonus_per_unit": 8,
		"story": "From the 1840s the wool of the Western District came down to Geelong and went on by water. The season's clip is on the wharf and the ships for London are loading."},
	{"id": "diggings", "title": "Tools for the diggings", "from": "melbourne", "to": "geelong", "good": "tools",
		"units": 15, "deadline_factor": 1.1, "bonus_per_unit": 8,
		"story": "Gold was found near Ballarat in 1851, and Geelong was the nearest port to the diggings. Every man heading inland wants a pick and a shovel."},
	{"id": "couta", "title": "First boat to market", "from": "queenscliff", "to": "melbourne", "good": "fish",
		"units": 10, "deadline_factor": 0.95, "bonus_per_unit": 10,
		"story": "The couta boats of Queenscliff fished outside the Heads and raced each other home, because the first catch landed fetched the best price. Get this catch to market while it is fresh."},
	{"id": "lime", "title": "Lime for a growing city", "from": "queenscliff", "to": "melbourne", "good": "lime",
		"units": 15, "deadline_factor": 1.15, "bonus_per_unit": 7,
		"story": "Early Melbourne was built with mortar made from lime burnt in kilns on the shores near the Heads and carried up the bay in small craft."},
	{"id": "firewood", "title": "Timber for the city", "from": "mornington", "to": "melbourne", "good": "timber",
		"units": 15, "deadline_factor": 1.15, "bonus_per_unit": 7,
		"story": "The forests of the Mornington Peninsula were cut for Melbourne's building timber and firewood and shipped from the piers along the bay."},
	{"id": "onions", "title": "The Bellarine harvest", "from": "barwon", "to": "melbourne", "good": "onions",
		"units": 15, "deadline_factor": 1.1, "bonus_per_unit": 10,
		"story": "The Bellarine Peninsula's farms grew onions and potatoes for the Melbourne market. This load has to go out through the Rip, so mind the tide."},
	{"id": "papers", "title": "The latest news", "from": "melbourne", "to": "queenscliff", "good": "newspapers",
		"units": 10, "deadline_factor": 0.95, "bonus_per_unit": 9,
		"story": "News is worth most while it is new. The Melbourne papers are off the press and the pilots at the Heads are waiting for them."},
]


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
