extends RefCounted
## Builds every screen control once at start-up and hands each to the game
## by name. Layout lives here; what the controls do lives in main.gd.

const Palette = preload("res://game/palette.gd")
const Hud = preload("res://game/hud.gd")
const DeckView = preload("res://game/deck_view.gd")
const Chart = preload("res://game/chart.gd")
const LogScreen = preload("res://game/log_screen.gd")
const ListScreen = preload("res://game/list_screen.gd")
const BuildInfo = preload("res://game/build_info.gd")

const BUTTON_HEIGHT := 56.0
const SMALL_TEXT := 20


static func make_button(text: String, action: Callable, min_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, BUTTON_HEIGHT)
	if action.is_valid():
		button.pressed.connect(action)
	return button


## A button pinned to a corner of the screen. The offsets are from that
## corner: negative values reach back in from the right or the bottom.
static func _corner_button(parent: Control, text: String, action: Callable, corner: Control.LayoutPreset,
		left: float, top: float, right: float, bottom: float, font_size: int = 0) -> Button:
	var button := make_button(text, action, 0.0)
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_preset(corner)
	button.offset_left = left
	button.offset_top = top
	button.offset_right = right
	button.offset_bottom = bottom
	if font_size > 0:
		button.add_theme_font_size_override("font_size", font_size)
	parent.add_child(button)
	return button


static func build(game) -> void:
	var camera := Camera2D.new()
	camera.zoom = Vector2(0.75, 0.75)
	game.add_child(camera)
	game.camera = camera

	var layer := CanvasLayer.new()
	game.add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 24
	root.theme = ui_theme
	layer.add_child(root)

	var deck_view := DeckView.new()
	deck_view.setup(game)
	deck_view.visible = false
	root.add_child(deck_view)
	game.deck_view = deck_view

	var overlay := Hud.new()
	overlay.game = game
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	game.overlay = overlay

	_build_sailing_labels(game, root)
	_build_helm(game, root)
	_build_port_screen(game, root)
	_build_full_screens(game, root)


## The lines of text along the top of the sailing view, and the hint box.
static func _build_sailing_labels(game, root: Control) -> void:
	var status_label := Label.new()
	status_label.position = Vector2(20, 12)
	root.add_child(status_label)
	game.status_label = status_label

	var passage_label := Label.new()
	passage_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	passage_label.offset_left = -820
	passage_label.offset_right = -20
	passage_label.offset_top = 12
	passage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	passage_label.add_theme_font_size_override("font_size", SMALL_TEXT)
	root.add_child(passage_label)
	game.passage_label = passage_label

	var hint_panel := PanelContainer.new()
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint_panel.offset_left = -330
	hint_panel.offset_right = 330
	hint_panel.offset_top = 64
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_label := Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.custom_minimum_size = Vector2(640, 0)
	hint_panel.add_child(hint_label)
	root.add_child(hint_panel)
	game.hint_panel = hint_panel
	game.hint_label = hint_label


## The buttons used under sail. Left column, top to bottom: Pause and view,
## chart, trim switch, haul in, steer left. Right column: sound, sail (full,
## reefed, lowered), ease out, steer right.
static func _build_helm(game, root: Control) -> void:
	var bottom_left := Control.PRESET_BOTTOM_LEFT
	var bottom_right := Control.PRESET_BOTTOM_RIGHT
	var top_left := Control.PRESET_TOP_LEFT
	game.left_button = _corner_button(root, "<", Callable(), bottom_left, 30, -200, 200, -30, 72)
	game.right_button = _corner_button(root, ">", Callable(), bottom_right, -200, -200, -30, -30, 72)
	game.trim_button = _corner_button(root, "", game._toggle_trim, bottom_left, 30, -366, 200, -306, SMALL_TEXT)
	game.haul_button = _corner_button(root, "Haul in", Callable(), bottom_left, 30, -292, 200, -214)
	game.ease_button = _corner_button(root, "Ease out", Callable(), bottom_right, -200, -292, -30, -214)
	game.reef_button = _corner_button(root, "", game._toggle_reef, bottom_right, -200, -366, -30, -306, SMALL_TEXT)
	game.view_button = _corner_button(root, "Deck", game._toggle_view, top_left, 120, 236, 200, 292, SMALL_TEXT)
	game.chart_button = _corner_button(root, "Chart", game.open_chart, top_left, 30, 300, 200, 356, SMALL_TEXT)
	game.pause_button = _corner_button(root, "Pause", game._toggle_pause, top_left, 30, 236, 112, 292, SMALL_TEXT)
	game.sound_button = _corner_button(root, "", game._toggle_sound, Control.PRESET_TOP_RIGHT, -200, 246, -30, 296, SMALL_TEXT)
	# Shown only when close to the destination, just above the trim bar.
	game.anchor_button = _corner_button(root, "Anchor off", game._anchor_off, Control.PRESET_CENTER_BOTTOM, -120, -302, 120, -250, SMALL_TEXT)


## The port screen fills the height of the screen and scrolls if it has to.
static func _build_port_screen(game, root: Control) -> void:
	var port_panel := PanelContainer.new()
	port_panel.anchor_left = 0.5
	port_panel.anchor_right = 0.5
	port_panel.anchor_top = 0.0
	port_panel.anchor_bottom = 1.0
	port_panel.offset_left = -450
	port_panel.offset_right = 450
	port_panel.offset_top = 8
	port_panel.offset_bottom = -8
	# A solid background: the map behind made the text hard to read.
	var port_style := StyleBoxFlat.new()
	port_style.bg_color = Color("12303f")
	port_style.set_corner_radius_all(8)
	port_panel.add_theme_stylebox_override("panel", port_style)
	root.add_child(port_panel)
	game.port_panel = port_panel

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	port_panel.add_child(margin)
	var port_scroll := ScrollContainer.new()
	port_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(port_scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_scroll.add_child(box)

	var port_title := Label.new()
	port_title.add_theme_font_size_override("font_size", 34)
	box.add_child(port_title)
	game.port_title = port_title
	var port_report := Label.new()
	port_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	port_report.custom_minimum_size = Vector2(810, 0)
	port_report.add_theme_font_size_override("font_size", SMALL_TEXT)
	box.add_child(port_report)
	game.port_report = port_report
	box.add_child(HSeparator.new())
	var port_money := Label.new()
	box.add_child(port_money)
	game.port_money = port_money
	var goods_box := VBoxContainer.new()
	goods_box.add_theme_constant_override("separation", 8)
	box.add_child(goods_box)
	game.goods_box = goods_box
	box.add_child(HSeparator.new())

	var plan_label := Label.new()
	plan_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plan_label.custom_minimum_size = Vector2(810, 0)
	plan_label.add_theme_font_size_override("font_size", SMALL_TEXT)
	box.add_child(plan_label)
	game.plan_label = plan_label
	var menu := HBoxContainer.new()
	menu.add_theme_constant_override("separation", 12)
	for item: Array in [["Plan route", game.open_chart], ["Charters", game.open_contracts],
			["Shipyard", game.open_shipyard], ["Ship's log", game.open_log], ["New game", game._new_game_pressed]]:
		var menu_button := make_button(item[0], item[1], 0)
		menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		menu_button.add_theme_font_size_override("font_size", SMALL_TEXT)
		menu.add_child(menu_button)
		if item[0] == "New game":
			game.new_game_button = menu_button
	box.add_child(menu)

	var departure := HBoxContainer.new()
	departure.add_theme_constant_override("separation", 12)
	var destination_button := make_button("", game._cycle_destination, 400)
	destination_button.custom_minimum_size = Vector2(400, 64)
	destination_button.add_theme_font_size_override("font_size", SMALL_TEXT)
	departure.add_child(destination_button)
	game.destination_button = destination_button
	var sail_button := make_button("", game._set_sail, 0)
	sail_button.custom_minimum_size = Vector2(0, 64)
	sail_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	departure.add_child(sail_button)
	game.sail_button = sail_button
	box.add_child(departure)

	# Which build is running, so it is easy to tell whether the latest has loaded.
	var build_label := Label.new()
	build_label.text = "Build %s" % BuildInfo.BUILD
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build_label.add_theme_font_size_override("font_size", 14)
	build_label.modulate = Color(1, 1, 1, 0.6)
	box.add_child(build_label)
	game.build_label = build_label


## The screens that cover everything: chart, log, shipyard and charters.
static func _build_full_screens(game, root: Control) -> void:
	var chart := Chart.new()
	chart.setup(game)
	chart.visible = false
	root.add_child(chart)
	game.chart = chart

	var log_screen := LogScreen.new()
	log_screen.setup(game)
	log_screen.visible = false
	root.add_child(log_screen)
	game.log_screen = log_screen

	var shipyard_screen := ListScreen.new()
	shipyard_screen.setup(game, "Shipyard")
	shipyard_screen.visible = false
	root.add_child(shipyard_screen)
	game.shipyard_screen = shipyard_screen

	var contracts_screen := ListScreen.new()
	contracts_screen.setup(game, "Charters")
	contracts_screen.visible = false
	root.add_child(contracts_screen)
	game.contracts_screen = contracts_screen
