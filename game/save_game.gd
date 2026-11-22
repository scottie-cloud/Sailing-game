extends RefCounted
## Writes the game to the save file and reads it back. Anything in a save
## that no longer makes sense (an unknown port, a mark on land) is dropped.

const Shipyard = preload("res://sim/shipyard.gd")
const Contracts = preload("res://sim/contracts.gd")
const World = preload("res://game/world.gd")

const SAVE_PATH := "user://save.json"


static func save(game) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	var saved_plans := {}
	for key: String in game.plans:
		saved_plans[key] = _pack(game.plans[key])
	var saved_records := {}
	for key: String in game.record_tracks:
		saved_records[key] = _pack(game.record_tracks[key])
	var saved_log: Array = []
	for entry: Dictionary in game.ship_log:
		var saved_entry := entry.duplicate()
		saved_entry["track"] = _pack(entry["track"])
		saved_log.append(saved_entry)
	file.store_string(JSON.stringify({
		"money": game.money,
		"port": game.current_port,
		"ship": game.ship_id,
		"upgrades": game.upgrade_levels,
		"glut": game.glut,
		"active_contract": game.active_contract,
		"completed_contracts": game.completed_contracts,
		"best_times": game.best_times,
		"plans": saved_plans,
		"manual_trim": game.ship.manual_trim,
		"deck_mode": game.deck_mode,
		"clock_hours": game.clock_hours,
		"damaged": game.ship.damaged,
		"record_tracks": saved_records,
		"ship_log": saved_log,
	}))


## Points as [[x, y], ...] whole numbers for the save file.
static func _pack(points: Array) -> Array:
	var packed: Array = []
	for point: Vector2 in points:
		packed.append([roundi(point.x), roundi(point.y)])
	return packed


## The reverse of _pack, dropping anything malformed or off the water.
static func _unpack(entries: Variant, limit: int) -> Array:
	var points: Array = []
	if typeof(entries) != TYPE_ARRAY:
		return points
	for entry: Variant in entries:
		if typeof(entry) == TYPE_ARRAY and entry.size() == 2 and points.size() < limit:
			var point := Vector2(float(entry[0]), float(entry[1]))
			if not World.is_blocked(point):
				points.append(point)
	return points


static func load_into(game) -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	game.money = int(data.get("money", game.STARTING_MONEY))
	var saved_ship: String = str(data.get("ship", "cutter"))
	game.ship_id = saved_ship if Shipyard.SHIPS.has(saved_ship) else "cutter"
	var saved_upgrades: Variant = data.get("upgrades", {})
	if typeof(saved_upgrades) != TYPE_DICTIONARY:
		saved_upgrades = {}
	# Saves from before the shipyard kept the two upgrades under their own names.
	var legacy := {"hold": data.get("hold_level", 0), "sails": data.get("sail_level", 0)}
	for kind in Shipyard.UPGRADE_ORDER:
		var level := int(saved_upgrades.get(kind, legacy.get(kind, 0)))
		game.upgrade_levels[kind] = clampi(level, 0, Shipyard.max_level(kind))
	var saved_glut: Variant = data.get("glut", {})
	if typeof(saved_glut) == TYPE_DICTIONARY:
		for key: String in saved_glut:
			game.glut[key] = float(saved_glut[key])
	var saved_contract: String = str(data.get("active_contract", ""))
	game.active_contract = saved_contract if not Contracts.by_id(saved_contract).is_empty() else ""
	var saved_completed: Variant = data.get("completed_contracts", {})
	if typeof(saved_completed) == TYPE_DICTIONARY:
		for key: String in saved_completed:
			game.completed_contracts[key] = int(saved_completed[key])
	var port: String = str(data.get("port", "melbourne"))
	game.current_port = port if World.PORTS.has(port) else "melbourne"
	game.ship.manual_trim = bool(data.get("manual_trim", false))
	game.deck_mode = bool(data.get("deck_mode", false))
	game.clock_hours = float(data.get("clock_hours", 0.0))
	game.ship.damaged = bool(data.get("damaged", false))
	var times: Variant = data.get("best_times", {})
	if typeof(times) == TYPE_DICTIONARY:
		game.best_times = times
	var saved_plans: Variant = data.get("plans", {})
	if typeof(saved_plans) == TYPE_DICTIONARY:
		for key: String in saved_plans:
			game.plans[key] = _unpack(saved_plans[key], game.MAX_MARKS)
	var saved_records: Variant = data.get("record_tracks", {})
	if typeof(saved_records) == TYPE_DICTIONARY:
		for key: String in saved_records:
			game.record_tracks[key] = _unpack(saved_records[key], 500)
	var saved_log: Variant = data.get("ship_log", [])
	if typeof(saved_log) == TYPE_ARRAY:
		for saved_entry: Variant in saved_log:
			if typeof(saved_entry) != TYPE_DICTIONARY or game.ship_log.size() >= game.MAX_LOG_ENTRIES:
				continue
			var from_port: String = str(saved_entry.get("from", ""))
			var to_port: String = str(saved_entry.get("to", ""))
			if not World.PORTS.has(from_port) or not World.PORTS.has(to_port):
				continue
			game.ship_log.append({
				"from": from_port,
				"to": to_port,
				"hours": float(saved_entry.get("hours", 0.0)),
				"wind_deg": float(saved_entry.get("wind_deg", 0.0)),
				"wind_kn": float(saved_entry.get("wind_kn", 0.0)),
				"takings": int(saved_entry.get("takings", 0)),
				"record": bool(saved_entry.get("record", false)),
				"track": _unpack(saved_entry.get("track", []), 500),
			})
