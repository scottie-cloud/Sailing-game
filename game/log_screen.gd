extends Control
## The ship's log: every completed passage, newest first, with the course
## that was sailed. A logged course for the current route can be followed again.

const Weather = preload("res://sim/weather.gd")
const World = preload("res://game/world.gd")

var game
var rows: VBoxContainer


func setup(game_ref) -> void:
	game = game_ref
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Ship's log"
	title.add_theme_font_size_override("font_size", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(150, 60)
	close.pressed.connect(_close)
	header.add_child(close)
	box.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)


func _close() -> void:
	game.close_log()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d2b3e"))


func entry_text(entry: Dictionary) -> String:
	var wind_deg: float = entry["wind_deg"]
	var wind_kn: float = entry["wind_kn"]
	var hours: float = entry["hours"]
	var takings: float = entry["takings"]
	var text := "%s to %s   %s   wind %s %d kn   $%d" % [World.port_name(entry["from"]), World.port_name(entry["to"]),
		game.format_hours(hours), Weather.compass_name(wind_deg), roundi(wind_kn), roundi(takings)]
	if entry["record"]:
		text += "   RECORD"
	return text


func refresh() -> void:
	for child in rows.get_children():
		child.queue_free()
	if game.ship_log.is_empty():
		var note := Label.new()
		note.text = "No passages yet. Each passage you complete is written here with the course you sailed."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(note)
		return
	for i in game.ship_log.size():
		var entry: Dictionary = game.ship_log[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = entry_text(entry)
		label.add_theme_font_size_override("font_size", 20)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if entry["from"] == game.current_port and entry["to"] == game.destination:
			var follow := Button.new()
			follow.text = "Follow this course"
			follow.custom_minimum_size = Vector2(230, 52)
			follow.pressed.connect(game.follow_log_entry.bind(i))
			row.add_child(follow)
		rows.add_child(row)
