extends RefCounted
## Arriving in port. A ship either comes alongside the pier, where her speed
## decides how the landing goes, or anchors off and has her cargo taken
## ashore by boat, which is safe but slow.

enum Landing { CLEAN, HARD, STRUCK, ANCHORED }

## At or under this speed she comes alongside cleanly.
const CLEAN_KN := 2.0
## Over this speed she strikes the pier.
const STRUCK_KN := 4.0
## Coming in hard: a bill that grows with the speed, and a quarter of an hour lost.
const HARD_COST_PER_KN := 6.0
const HARD_DELAY_S := 900.0
## Striking the pier: repairs, and an hour lost.
const STRUCK_COST := 40
const STRUCK_DELAY_S := 3600.0
## Anchoring off: an hour for the boats, and a fee for each unit they carry.
const ANCHOR_DELAY_S := 3600.0
const LIGHTERAGE_PER_UNIT := 1


static func grade(speed_kn: float) -> Landing:
	if speed_kn <= CLEAN_KN:
		return Landing.CLEAN
	if speed_kn <= STRUCK_KN:
		return Landing.HARD
	return Landing.STRUCK


## How a landing at the pier turns out: {"landing", "cost", "delay_s", "text"}.
static func alongside(speed_kn: float) -> Dictionary:
	match grade(speed_kn):
		Landing.CLEAN:
			return {"landing": Landing.CLEAN, "cost": 0, "delay_s": 0.0,
				"text": "She came alongside at %.1f kn and was made fast without a scrape." % speed_kn}
		Landing.HARD:
			var cost := roundi((speed_kn - CLEAN_KN) * HARD_COST_PER_KN)
			return {"landing": Landing.HARD, "cost": cost, "delay_s": HARD_DELAY_S,
				"text": "She came in hard at %.1f kn. $%d for the damage to the pier, and a quarter of an hour lost." % [speed_kn, cost]}
	return {"landing": Landing.STRUCK, "cost": STRUCK_COST, "delay_s": STRUCK_DELAY_S,
		"text": "She struck the pier at %.1f kn. $%d for repairs, and an hour lost." % [speed_kn, STRUCK_COST]}


## How anchoring off turns out, with this many units of cargo to bring ashore.
static func anchored(units: int) -> Dictionary:
	var cost := units * LIGHTERAGE_PER_UNIT
	var text := "She anchored off and the cargo came ashore by boat: an hour, and $%d for the lighters." % cost
	if units <= 0:
		text = "She anchored off and you were rowed ashore: an hour lost."
	return {"landing": Landing.ANCHORED, "cost": cost, "delay_s": ANCHOR_DELAY_S, "text": text}
