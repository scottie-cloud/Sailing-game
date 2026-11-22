extends RefCounted
## The rules for shallow water: how deep a ship sits, how much water the
## tide puts over a shoal, and whether she floats. The shoals themselves are
## in data/shoals.gd.

## A shoal's standing for a given ship.
enum Passage { ALWAYS, ON_THE_TIDE, NEVER }


## How deep she sits: more with cargo aboard. load_fraction is 0 (empty) to 1 (full).
static func draught_m(light: float, laden_extra: float, load_fraction: float) -> float:
	return light + laden_extra * clampf(load_fraction, 0.0, 1.0)


## Water over a shoal: its depth at low water plus the height of the tide.
static func depth_m(low_water_depth: float, tide_height: float) -> float:
	return low_water_depth + tide_height


## She needs more water than she draws.
static func can_float(depth: float, draught: float) -> bool:
	return depth > draught


## Whether a ship of this draught can cross a shoal at any tide, only with
## enough tide, or not at all.
static func passage(low_water_depth: float, draught: float, tide_range: float) -> Passage:
	if can_float(low_water_depth, draught):
		return Passage.ALWAYS
	if can_float(low_water_depth + tide_range, draught):
		return Passage.ON_THE_TIDE
	return Passage.NEVER
