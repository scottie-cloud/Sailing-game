extends Control
## The view from the deck: sky, sea and horizon, with land showing only when
## it is close enough to see, and a compass strip to steer by. The world
## tilts as the ship heels; her own bow and sails stay put in front of you.

const SailingModel = preload("res://sim/sailing_model.gd")
const World = preload("res://game/world.gd")

const FOV := PI / 2.0
## On a clear day land can be made out this far off (px: 8 nautical miles).
const CLEAR_VISIBILITY := 3200.0
const SQUALL_VISIBILITY := 500.0
const METRES_PER_PX := 4.63
const EYE_HEIGHT_M := 3.0
## Land is drawn this many times taller than life, so a distant shore can be
## made out on a small screen.
const LAND_EXAGGERATION := 3.0
## Distance to the sea horizon from that height, in nautical miles.
const SEA_HORIZON_NM := 3.6
const COLUMNS := 72
const RAY_STEP := 80.0
## The sea rushes past this much faster than life, so speed can be felt.
const WAVE_SPEED_UP := 2.5
const WAVE_SPACING_M := 14.0
const WAVE_RANGE_M := 150.0

const SKY_TOP := Color("3f7fc4")
const SKY_LOW := Color("bfe0f2")
const NIGHT_TOP := Color("0a1226")
const NIGHT_LOW := Color("27375c")
const SEA_FAR := Color("2f7fa8")
const SEA_NEAR := Color("154d73")
const LAND := Color("4f7243")
const GOLD := Color("ffd24a")

var game
## Where the sea surface has scrolled to, in metres.
var water_m := Vector2.ZERO
## Per column of the view: x = distance to land in px (INF if none in sight), y = its height in metres.
var _land: Array[Vector2] = []
var _frame := 0


func setup(game_ref) -> void:
	game = game_ref
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(delta: float) -> void:
	if not visible or not game.is_sailing():
		return
	if not game.paused:
		water_m += SailingModel.bearing_to_vector(game.ship.heading) * game.ship.speed_kn * 0.514 * delta * WAVE_SPEED_UP
	_frame += 1
	if _frame % 3 == 0 or _land.is_empty():
		_scan_land()
	queue_redraw()


func visibility() -> float:
	return lerpf(CLEAR_VISIBILITY, SQUALL_VISIBILITY, game.squall_strength)


func _column_angle(index: float) -> float:
	# A little wider than the view, to cover the corners when the horizon tilts.
	return lerpf(-FOV * 0.62, FOV * 0.62, index / COLUMNS)


## Rolling hills: between about 18 and 70 metres high.
func _height_m(p: Vector2) -> float:
	return 44.0 + 26.0 * sin(p.x * 0.004) * cos(p.y * 0.005)


func _cast(origin: Vector2, bearing: float, limit: float) -> Vector2:
	var direction := SailingModel.bearing_to_vector(bearing)
	var distance := 60.0
	while distance <= limit:
		var p := origin + direction * distance
		if World.in_bounds(p) and World.is_land(p):
			# Step back to find the shoreline more exactly.
			var near := distance - RAY_STEP
			var far := distance
			for i in 3:
				var middle := (near + far) / 2.0
				if World.is_land(origin + direction * middle):
					far = middle
				else:
					near = middle
			return Vector2(far, _height_m(origin + direction * far))
		distance += RAY_STEP
	return Vector2(INF, 0.0)


func _scan_land() -> void:
	_land.resize(COLUMNS)
	var limit := visibility()
	for i in COLUMNS:
		_land[i] = _cast(game.ship.position, game.ship.heading + _column_angle(i + 0.5), limit)


## How many pixels tall something this high (m) looks at this distance (px),
## allowing for the curve of the earth hiding its foot.
func _apparent_height(height_m: float, distance: float, focal: float) -> float:
	var distance_nm := distance / 400.0
	var hidden := 0.0
	if distance_nm > SEA_HORIZON_NM:
		hidden = pow((distance_nm - SEA_HORIZON_NM) / 2.08, 2.0)
	return atan2(maxf(height_m - hidden, 0.0), distance * METRES_PER_PX) * focal


func _draw() -> void:
	if game == null or not game.is_sailing():
		return
	var w := size.x
	var h := size.y
	var horizon := h * 0.46
	var focal := (w / 2.0) / tan(FOV / 2.0)
	var heading: float = game.ship.heading
	var daylight: float = game.daylight()
	var gloom: float = game.squall_strength
	var side_angle := SailingModel.signed_wind_angle(heading, game.wind_from)
	var twa := absf(rad_to_deg(side_angle))
	var side := 1.0 if side_angle >= 0.0 else -1.0

	# She heels away from the wind, so the horizon tips the other way.
	var sail_wind: float = SailingModel.sail_wind_kn(game.wind_kn, game.ship.reefed)
	var heel := deg_to_rad(clampf(sail_wind * 0.6 * sin(deg_to_rad(twa)), 0.0, 16.0)) * side
	if SailingModel.in_no_go(twa):
		heel = 0.0
	draw_set_transform(Vector2(w / 2.0, horizon), heel, Vector2.ONE)

	var reach := w * 1.3
	var sky_top := NIGHT_TOP.lerp(SKY_TOP, daylight).lerp(Color("39424f"), gloom * 0.8)
	var sky_low := NIGHT_LOW.lerp(SKY_LOW, daylight).lerp(Color("7c8791"), gloom * 0.8)
	draw_polygon(PackedVector2Array([Vector2(-reach, -h), Vector2(reach, -h), Vector2(reach, 0), Vector2(-reach, 0)]),
		PackedColorArray([sky_top, sky_top, sky_low, sky_low]))
	_draw_clouds(heading, focal, daylight, gloom)

	var sea_far := SEA_FAR.lerp(sky_low, 0.35).darkened(0.5 * (1.0 - daylight))
	var sea_near := SEA_NEAR.darkened(0.5 * (1.0 - daylight) + 0.2 * gloom)
	draw_polygon(PackedVector2Array([Vector2(-reach, 0), Vector2(reach, 0), Vector2(reach, h), Vector2(-reach, h)]),
		PackedColorArray([sea_far, sea_far, sea_near, sea_near]))

	_draw_squall_clouds(heading, focal)
	_draw_land(focal, sky_low, daylight)
	_draw_landmarks(heading, focal)
	_draw_waves(heading, focal, h - horizon)
	if gloom > 0.3:
		_draw_rain(w, h, gloom, side)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_own_ship(w, h, twa, side)
	_draw_compass(w, heading)


func _draw_clouds(heading: float, focal: float, daylight: float, gloom: float) -> void:
	var colour := Color(1, 1, 1, 0.55).darkened(0.6 * (1.0 - daylight) + 0.4 * gloom)
	for i in 14:
		var seed_value := posmod(hash(i * 7919), 1000)
		var bearing := TAU * i / 14.0 + seed_value * 0.0004
		var offset := wrapf(bearing - heading, -PI, PI)
		if absf(offset) > FOV * 0.7:
			continue
		var x := tan(offset) * focal
		var y := -(50.0 + (seed_value % 170))
		var width := 70.0 + (seed_value % 60)
		draw_circle(Vector2(x - width * 0.45, y + 6.0), width * 0.28, colour)
		draw_circle(Vector2(x, y), width * 0.36, colour)
		draw_circle(Vector2(x + width * 0.45, y + 8.0), width * 0.26, colour)


## A squall shows as a dark mass on the horizon before it arrives.
func _draw_squall_clouds(heading: float, focal: float) -> void:
	for squall: Dictionary in game.squalls_at(game.passage_seconds / 3600.0):
		var centre: Vector2 = squall["centre"]
		var radius: float = squall["radius"]
		var to_squall: Vector2 = centre - game.ship.position
		var distance := to_squall.length()
		if distance < radius or distance > 12000.0:
			continue
		var offset := wrapf(SailingModel.vector_to_bearing(to_squall) - heading, -PI, PI)
		if absf(offset) > FOV * 0.7:
			continue
		var x := tan(offset) * focal
		var half_width := clampf(atan2(radius, distance) * focal, 30.0, 500.0)
		var height := clampf(half_width * 0.5, 24.0, 160.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x - half_width, 0), Vector2(x - half_width * 0.7, -height * 0.8),
			Vector2(x, -height), Vector2(x + half_width * 0.7, -height * 0.8), Vector2(x + half_width, 0)]), Color(0.16, 0.18, 0.24, 0.85))


func _draw_land(focal: float, haze: Color, daylight: float) -> void:
	if _land.size() != COLUMNS:
		return
	var limit := visibility()
	var colour := LAND.darkened(0.55 * (1.0 - daylight))
	for i in COLUMNS:
		var hit := _land[i]
		if hit.x == INF:
			continue
		# Average with the neighbours so the skyline is not jagged.
		var height := hit.y
		var count := 1.0
		for j: int in [i - 1, i + 1]:
			if j >= 0 and j < COLUMNS and _land[j].x != INF:
				height += _land[j].y
				count += 1.0
		var tall := _apparent_height(height / count * LAND_EXAGGERATION, hit.x, focal)
		if tall < 0.5:
			continue
		var left := tan(_column_angle(i)) * focal
		var right := tan(_column_angle(i + 1.0)) * focal
		var faded := clampf(hit.x / limit, 0.0, 1.0)
		var shade := colour.lerp(haze, faded * 0.85)
		shade.a = 1.0 - smoothstep(0.8, 1.0, faded)
		draw_rect(Rect2(left, -tall, right - left + 1.0, tall), shade)
		# A pale strip of beach where the land meets the water.
		if faded < 0.5:
			draw_rect(Rect2(left, -minf(tall * 0.12, 5.0), right - left + 1.0, minf(tall * 0.12, 5.0)), Color("e3d6a1").lerp(haze, faded))


## Ports show as a white tower with a name once they are in sight; the next
## mark shows as a gold flag when it is within three miles.
func _draw_landmarks(heading: float, focal: float) -> void:
	var font := ThemeDB.fallback_font
	var limit := visibility()
	for port: String in World.PORTS:
		var to_port: Vector2 = World.port_position(port) - game.ship.position
		var distance := to_port.length()
		var offset := wrapf(SailingModel.vector_to_bearing(to_port) - heading, -PI, PI)
		if distance > limit or distance < 30.0 or absf(offset) > FOV * 0.6:
			continue
		var x := tan(offset) * focal
		var tall := maxf(_apparent_height(30.0 * LAND_EXAGGERATION, distance, focal), 10.0)
		draw_rect(Rect2(x - 3.0, -tall, 6.0, tall), Color.WHITE)
		draw_rect(Rect2(x - 4.0, -tall - 4.0, 8.0, 4.0), Color("c0392b"))
		draw_string(font, Vector2(x - 100.0, -tall - 12.0), World.port_name(port), HORIZONTAL_ALIGNMENT_CENTER, 200, 20, Color.WHITE)
	var to_mark: Vector2 = game.target_point() - game.ship.position
	var mark_distance := to_mark.length()
	var mark_offset := wrapf(SailingModel.vector_to_bearing(to_mark) - heading, -PI, PI)
	if game.next_mark < game.plan.size() and mark_distance < 1200.0 and mark_distance > 30.0 and absf(mark_offset) < FOV * 0.6:
		var x := tan(mark_offset) * focal
		var y := EYE_HEIGHT_M * focal / (mark_distance * METRES_PER_PX)
		var tall := maxf(_apparent_height(8.0, mark_distance, focal), 10.0)
		draw_line(Vector2(x, y), Vector2(x, y - tall), GOLD, 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x, y - tall), Vector2(x + tall * 0.6, y - tall * 0.8), Vector2(x, y - tall * 0.6)]), GOLD)


## Streaks of foam on the water, anchored to the sea so they slide past as
## she moves and swing across as she turns.
func _draw_waves(heading: float, focal: float, depth: float) -> void:
	var forward := SailingModel.bearing_to_vector(heading)
	var right := SailingModel.bearing_to_vector(heading + PI / 2.0)
	var strength := clampf(game.wind_kn / 14.0, 0.4, 1.6)
	var cells := int(WAVE_RANGE_M / WAVE_SPACING_M) + 1
	var home_x := int(floor(water_m.x / WAVE_SPACING_M))
	var home_y := int(floor(water_m.y / WAVE_SPACING_M))
	for ix in range(home_x - cells, home_x + cells + 1):
		for iy in range(home_y - cells, home_y + cells + 1):
			var seed_value := posmod(hash(Vector2i(ix, iy)), 10000)
			var point := Vector2(ix + (seed_value % 100) / 100.0, iy + (seed_value / 100) / 100.0) * WAVE_SPACING_M
			var offset := point - water_m
			var ahead := offset.dot(forward)
			if ahead < 4.0 or ahead > WAVE_RANGE_M:
				continue
			var x := offset.dot(right) / ahead * focal
			if absf(x) > size.x:
				continue
			var y := EYE_HEIGHT_M * focal / ahead
			if y > depth + 40.0:
				continue
			var half := (2.0 + (seed_value % 5)) / ahead * focal * 0.5
			var alpha := clampf(1.0 - ahead / WAVE_RANGE_M, 0.0, 1.0) * 0.45 * strength
			draw_line(Vector2(x - half, y), Vector2(x + half, y), Color(1, 1, 1, alpha), clampf(40.0 / ahead, 1.0, 5.0))


func _draw_rain(w: float, h: float, gloom: float, side: float) -> void:
	var slant := -side * 26.0
	for i in 70:
		var seed_value := posmod(hash(i * 104729 + int(game.anim_time * 14.0) * 31), 100000)
		var x := (seed_value % 2000) / 2000.0 * w * 2.0 - w
		var y := (seed_value / 2000) / 50.0 * h * 1.4 - h * 0.6
		draw_line(Vector2(x, y), Vector2(x + slant, y + 60.0), Color(0.85, 0.9, 1.0, 0.35 * gloom), 2.0)


## The foredeck, mast and sails as seen from the helm.
func _draw_own_ship(w: float, h: float, twa: float, side: float) -> void:
	var centre := w / 2.0
	var deck := Color("b08a55")
	var no_go := SailingModel.in_no_go(twa)
	var flutter: float = sin(game.anim_time * 18.0) * 0.06 if no_go else 0.0
	var sheet_deg: float = game.ship.sheet_deg if game.ship.manual_trim else SailingModel.ideal_sheet_deg(twa)
	var eased := clampf(sheet_deg / 90.0, 0.05, 1.0) + flutter
	var leeward := -side

	var bow := Vector2(centre, h * 0.66)
	draw_colored_polygon(PackedVector2Array([Vector2(centre - w * 0.26, h), Vector2(centre + w * 0.26, h),
		Vector2(centre + w * 0.07, h * 0.76), bow, Vector2(centre - w * 0.07, h * 0.76)]), deck)
	draw_polyline(PackedVector2Array([Vector2(centre - w * 0.26, h), Vector2(centre - w * 0.07, h * 0.76), bow,
		Vector2(centre + w * 0.07, h * 0.76), Vector2(centre + w * 0.26, h)]), Color("4a2d16"), 6.0)
	# Bowsprit, mast and forestay.
	draw_line(bow, bow + Vector2(0, -h * 0.07), Color("4a2d16"), 5.0)
	var mast_foot := Vector2(centre, h * 0.84)
	var mast_head := Vector2(centre, -20.0)
	var sail := Color(0.96, 0.94, 0.86, 0.9)
	# Headsail: set forward, drawing out to leeward.
	var jib_clew := Vector2(centre + leeward * w * (0.05 + 0.2 * eased), h * 0.72)
	draw_colored_polygon(PackedVector2Array([bow + Vector2(0, -h * 0.07), Vector2(centre, h * 0.05), jib_clew]), sail)
	# Mainsail: from the mast back towards you, the boom swinging out to leeward.
	var boom_end := Vector2(centre + leeward * w * (0.06 + 0.4 * eased), h * 0.9)
	draw_colored_polygon(PackedVector2Array([mast_head, mast_foot + Vector2(0, -h * 0.06), boom_end]), sail)
	draw_line(mast_foot + Vector2(0, -h * 0.06), boom_end, Color("4a2d16"), 7.0)
	draw_line(mast_foot, mast_head, Color("5a3a1e"), 8.0)
	if game.ship.reefed:
		# A reefed sail shows its lashed-down foot.
		draw_line(mast_foot + Vector2(0, -h * 0.12), boom_end + Vector2(0, -h * 0.05), Color("8a7a5a"), 4.0)


## A strip of compass across the top: steer by it when nothing is in sight.
func _draw_compass(w: float, heading: float) -> void:
	var font := ThemeDB.fallback_font
	var centre := w / 2.0
	var top := 150.0
	var half_width := 300.0
	var px_per_degree := 5.0
	draw_rect(Rect2(centre - half_width, top, half_width * 2.0, 48.0), Color(0, 0, 0, 0.55))
	var heading_deg := rad_to_deg(heading)
	var names := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	for degrees in range(0, 360, 5):
		var offset := wrapf(degrees - heading_deg, -180.0, 180.0)
		if absf(offset) > half_width / px_per_degree - 2.0:
			continue
		var x := centre + offset * px_per_degree
		var major := degrees % 15 == 0
		draw_line(Vector2(x, top + 48.0), Vector2(x, top + (30.0 if major else 40.0)), Color.WHITE, 2.0)
		if names.has(degrees):
			draw_string(font, Vector2(x - 30.0, top + 24.0), names[degrees], HORIZONTAL_ALIGNMENT_CENTER, 60, 22, Color.WHITE)
		elif degrees % 30 == 0:
			draw_string(font, Vector2(x - 30.0, top + 24.0), str(degrees), HORIZONTAL_ALIGNMENT_CENTER, 60, 18, Color(1, 1, 1, 0.8))
	# Where the wind is coming from (blue) and where the next mark lies (gold).
	_compass_marker(centre, top, half_width, px_per_degree, rad_to_deg(game.wind_from) - heading_deg, Color("7fd0ff"), "WIND")
	var to_target: Vector2 = game.target_point() - game.ship.position
	_compass_marker(centre, top, half_width, px_per_degree, rad_to_deg(SailingModel.vector_to_bearing(to_target)) - heading_deg, GOLD, "MARK")
	draw_colored_polygon(PackedVector2Array([Vector2(centre - 9.0, top - 2.0), Vector2(centre + 9.0, top - 2.0), Vector2(centre, top + 12.0)]), Color.WHITE)
	draw_string(font, Vector2(centre - 100.0, top + 106.0), "Heading %03d°" % posmod(roundi(heading_deg), 360), HORIZONTAL_ALIGNMENT_CENTER, 200, 22, Color.WHITE)


## A marker under the strip. Off the end of the strip it sits at the edge,
## showing which way to turn to bring it round.
func _compass_marker(centre: float, top: float, half_width: float, px_per_degree: float, offset_deg: float, colour: Color, label: String) -> void:
	var offset := wrapf(offset_deg, -180.0, 180.0)
	var x := centre + clampf(offset * px_per_degree, -half_width + 10.0, half_width - 10.0)
	draw_colored_polygon(PackedVector2Array([Vector2(x - 9.0, top + 62.0), Vector2(x + 9.0, top + 62.0), Vector2(x, top + 48.0)]), colour)
	draw_string(ThemeDB.fallback_font, Vector2(x - 40.0, top + 80.0), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, colour)
