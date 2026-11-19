extends Control
## A full-screen list with a title, a line of notes and a Close button. Each
## row is text with an optional button. Used for the shipyard and charters.

var game
var title_label: Label
var note_label: Label
var rows: VBoxContainer


func setup(game_ref, title: String) -> void:
	game = game_ref
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var header := HBoxContainer.new()
	title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(150, 60)
	close.pressed.connect(_close)
	header.add_child(close)
	box.add_child(header)

	note_label = Label.new()
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.add_theme_font_size_override("font_size", 20)
	box.add_child(note_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)


func _close() -> void:
	game.close_screens()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d2b3e"))


## Each entry: {"text": String, "button": String, "action": Callable, "disabled": bool}.
## "button" and what follows it are optional.
func show_rows(note: String, entries: Array[Dictionary]) -> void:
	note_label.text = note
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for entry in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = entry["text"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 20)
		label.custom_minimum_size = Vector2(600, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if entry.has("button"):
			var button := Button.new()
			button.text = entry["button"]
			button.custom_minimum_size = Vector2(200, 56)
			button.disabled = entry.get("disabled", false)
			var action: Callable = entry["action"]
			button.pressed.connect(action)
			row.add_child(button)
		rows.add_child(row)
