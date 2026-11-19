extends RefCounted
## Draws the ship from above: hull, deck, masts and sails. The caller sets
## the canvas transform to the ship's position, heading and size first, so
## the bow points up the screen (-y) and starboard is +x.

const HULL := Color("4a2d16")
const DECK := Color("c9a26b")
const SAIL := Color("f6efdc")
const SPAR := Color("2e1c0d")

## Each mast: where it stands along the deck, its boom length, and whether
## a headsail is set forward of it.
const RIGS := {
	"cutter": [{"y": -10.0, "boom": 40.0, "jib": true}],
	"ketch": [{"y": -14.0, "boom": 36.0, "jib": true}, {"y": 16.0, "boom": 22.0, "jib": false}],
	"schooner": [{"y": -18.0, "boom": 28.0, "jib": true}, {"y": 6.0, "boom": 36.0, "jib": false}],
}

const HULL_SHAPE: Array[Vector2] = [Vector2(0, -38), Vector2(8, -24), Vector2(12, -6), Vector2(12, 16),
	Vector2(8, 30), Vector2(-8, 30), Vector2(-12, 16), Vector2(-12, -6), Vector2(-8, -24)]


static func _scaled(points: Array[Vector2], factor: float, offset: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(point * factor + offset)
	return result


## sheet: boom angle off the centreline in radians. side: +1 with the wind on
## starboard (sails out to port), -1 with it on port. flutter: extra wobble
## in radians when the sail is not drawing.
static func draw_top_down(canvas: CanvasItem, ship_id: String, sheet: float, side: float, flutter: float) -> void:
	canvas.draw_colored_polygon(_scaled(HULL_SHAPE, 1.0, Vector2(5, 7)), Color(0, 0, 0, 0.22))
	canvas.draw_colored_polygon(_scaled(HULL_SHAPE, 1.0, Vector2.ZERO), HULL)
	canvas.draw_colored_polygon(_scaled(HULL_SHAPE, 0.78, Vector2(0, -1)), DECK)
	# Leeward is the side the sails swing out to.
	var leeward := Vector2(-side, 0.0)
	var rig: Array = RIGS.get(ship_id, RIGS["cutter"])
	for entry: Dictionary in rig:
		var mast_y: float = entry["y"]
		var boom: float = entry["boom"]
		var mast := Vector2(0.0, mast_y)
		if entry["jib"]:
			var clew := mast + leeward * (4.0 + 11.0 * sin(sheet)) + Vector2(0.0, 3.0 + flutter * 20.0)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, -36), clew, mast + Vector2(0, -2)]), Color(SAIL, 0.92))
		var boom_end := mast + Vector2(0, 1).rotated((sheet + flutter) * side) * boom
		var across := (boom_end - mast).orthogonal().normalized()
		if across.dot(leeward) < 0.0:
			across = -across
		var belly := mast.lerp(boom_end, 0.55) + across * boom * 0.2
		canvas.draw_colored_polygon(PackedVector2Array([mast, belly, boom_end]), SAIL)
		canvas.draw_line(mast, boom_end, SPAR, 2.0)
		canvas.draw_circle(mast, 3.0, SPAR)
