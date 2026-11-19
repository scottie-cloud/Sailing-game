extends RefCounted
## The learning ladder. Only STEERING is playable so far; the later stages
## are listed so features can be gated on them as they are built.

enum Stage { STEERING, SAIL_TRIM, WEATHER, ROUTE_PLANNING, SQUARE_RIG }

const CURRENT := Stage.STEERING


static func unlocked(stage: Stage) -> bool:
	return stage <= CURRENT
