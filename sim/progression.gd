extends RefCounted
## The learning ladder. Steering and sail trim are playable; the later stages
## are listed so features can be gated on them as they are built.

enum Stage { STEERING, SAIL_TRIM, WEATHER, ROUTE_PLANNING, SQUARE_RIG }

const CURRENT := Stage.SAIL_TRIM


static func unlocked(stage: Stage) -> bool:
	return stage <= CURRENT
