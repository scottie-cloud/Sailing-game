extends RefCounted
## The path a ship actually sailed, boiled down to its corners so it can be
## stored in the log and followed again as a route plan.


## Drops points that lie within tolerance of the line between their
## neighbours (Ramer-Douglas-Peucker). The first and last points are kept.
static func simplify(points: Array[Vector2], tolerance: float) -> Array[Vector2]:
	var count := points.size()
	if count < 3:
		return points.duplicate()
	var keep: Array[bool] = []
	keep.resize(count)
	keep.fill(false)
	keep[0] = true
	keep[count - 1] = true
	var spans: Array[Vector2i] = [Vector2i(0, count - 1)]
	while not spans.is_empty():
		var span: Vector2i = spans.pop_back()
		var worst := -1
		var worst_distance := tolerance
		for i in range(span.x + 1, span.y):
			var nearest := Geometry2D.get_closest_point_to_segment(points[i], points[span.x], points[span.y])
			var distance := points[i].distance_to(nearest)
			if distance > worst_distance:
				worst_distance = distance
				worst = i
		if worst >= 0:
			keep[worst] = true
			spans.append(Vector2i(span.x, worst))
			spans.append(Vector2i(worst, span.y))
	var result: Array[Vector2] = []
	for i in count:
		if keep[i]:
			result.append(points[i])
	return result


## The turning points of a track, without its start and end, cut down to at
## most max_marks so it can be used as a route plan.
static func to_marks(points: Array[Vector2], max_marks: int) -> Array[Vector2]:
	var tolerance := 40.0
	var simplified := simplify(points, tolerance)
	while simplified.size() - 2 > max_marks:
		tolerance *= 1.5
		simplified = simplify(points, tolerance)
	var marks: Array[Vector2] = []
	for i in range(1, simplified.size() - 1):
		marks.append(simplified[i])
	return marks
