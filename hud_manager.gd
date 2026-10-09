# Disc Golf Empire — Update 22: Readable Tycoon Command Dock
# Mobile-first left dock; reuses the established CourseUI callbacks.
extends CanvasLayer

const INK := Color(0.055, 0.095, 0.075, 0.97)
const EDGE := Color(0.26, 0.40, 0.29, 1.0)
const GOLD := Color(0.96, 0.76, 0.36, 1.0)
const WHITE := Color(0.94, 0.97, 0.93, 1.0)
const MUTED := Color(0.67, 0.76, 0.68, 1.0)
const ACTIVE := Color(0.17, 0.33, 0.23, 1.0)

var ui
var course_manager
var economy_manager
var job_manager
var golfer_manager
var radio_manager
var camera_controller
var top_bar: PanelContainer
var dock: PanelContainer
var dock_scroll: ScrollContainer
var drawer: PanelContainer
var drawer_title: Label
var drawer_body: VBoxContainer
var status_label: Label
var speed_button: Button
var dock_buttons: Dictionary = {}
var selected_tab := ""
var sim_speeds := [0.0, 1.0, 2.0, 4.0]
var speed_index := 1
var refresh_clock := 0.0

func setup(ui_ref, course_ref, economy_ref, job_ref, golfer_ref, radio_ref, camera_ref) -> void:
	ui = ui_ref
	course_manager = course_ref
	economy_manager = economy_ref
	job_manager = job_ref
	golfer_manager = golfer_ref
	radio_manager = radio_ref
	camera_controller = camera_ref
	if ui.top_panel != null:
		ui.top_panel.hide()
	if ui.empire_sidebar != null:
		ui.empire_sidebar.hide()
	build_hud()
	get_viewport().size_changed.connect(_layout_hud)
	set_process(true)

func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(7)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.36)
	style.shadow_size = 6
	return style

func button_style(active: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ACTIVE if active else Color(0.085, 0.145, 0.11, 0.97)
	style.border_color = GOLD if active else Color(0.22, 0.35, 0.26, 0.8)
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(9)
	style.set_content_margin_all(5)
	return style

func make_button(label_text: String, callback: Callable, width: float = 94.0) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(width, 66)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_stylebox_override("normal", button_style())
	button.add_theme_stylebox_override("hover", button_style(true))
	button.add_theme_stylebox_override("pressed", button_style(true))
	button.pressed.connect(callback)
	return button

func build_hud() -> void:
	top_bar = PanelContainer.new()
	top_bar.name = "ParkStatusBar"
	top_bar.add_theme_stylebox_override("panel", panel_style())
	add_child(top_bar)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top_bar.add_child(top_row)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	status_label.add_theme_font_size_override("font_size", 21)
	status_label.add_theme_color_override("font_color", GOLD)
	top_row.add_child(status_label)
	speed_button = make_button("1×", _cycle_speed, 72)
	speed_button.custom_minimum_size.y = 48
	top_row.add_child(speed_button)

	dock = PanelContainer.new()
	dock.name = "FloatingCommandDock"
	dock.add_theme_stylebox_override("panel", panel_style())
	add_child(dock)
	dock_scroll = ScrollContainer.new()
	dock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dock_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	dock.add_child(dock_scroll)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	dock_scroll.add_child(buttons)
	# Icons only; full names are displayed in the expanded drawer.
	var tabs := [
		["Build", "⚒"], ["Land", "♣"], ["Staff", "♟"],
		["Golfers", "●"], ["Course", "⚑"], ["Radio", "♫"]
	]
	for entry in tabs:
		var tab_name: String = entry[0]
		var button := make_button(entry[1], _toggle_tab.bind(tab_name), 76)
		button.tooltip_text = tab_name
		button.add_theme_font_size_override("font_size", 29)
		buttons.add_child(button)
		dock_buttons[tab_name] = button
	var inspect_button := make_button("◎", _inspect, 76)
	inspect_button.add_theme_font_size_override("font_size", 29)
	buttons.add_child(inspect_button)
	var camera_button := make_button("⌖", _reset_camera, 76)
	camera_button.add_theme_font_size_override("font_size", 29)
	buttons.add_child(camera_button)

	drawer = PanelContainer.new()
	drawer.name = "FloatingActionDrawer"
	drawer.add_theme_stylebox_override("panel", panel_style())
	add_child(drawer)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	drawer.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	drawer_title = Label.new()
	drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_title.add_theme_color_override("font_color", GOLD)
	drawer_title.add_theme_font_size_override("font_size", 29)
	heading.add_child(drawer_title)
	var close_button := make_button("×", close_drawer, 42)
	close_button.custom_minimum_size.y = 54
	heading.add_child(close_button)
	var rule := HSeparator.new()
	column.add_child(rule)
	var scroller := ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroller)
	drawer_body = VBoxContainer.new()
	drawer_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_body.add_theme_constant_override("separation", 6)
	scroller.add_child(drawer_body)
	drawer.hide()
	_layout_hud()
	refresh_status()

func _layout_hud() -> void:
	if dock == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var compact := screen.x < 760.0
	var margin := 10.0
	var top_height := 70.0
	top_bar.position = Vector2(margin, 8.0)
	top_bar.size = Vector2(maxf(180.0, screen.x - margin * 2.0), top_height)
	var dock_width := clampf(screen.x * 0.18, 90.0, 164.0)
	var dock_height := maxf(190.0, screen.y - 112.0)
	dock.position = Vector2(12.0, 92.0)
	dock.size = Vector2(dock_width, dock_height)
	fit_drawer()

func _toggle_tab(tab: String) -> void:
	if selected_tab == tab and drawer.visible:
		close_drawer()
		return
	selected_tab = tab
	drawer_title.text = tab.to_upper()
	for child in drawer_body.get_children():
		child.queue_free()
	match tab:
		"Build":
			add_action("Place Tee", "_on_tee_pressed")
			add_action("Place Basket", "_on_basket_pressed")
			add_action("Flight Path", "_on_path_pressed")
			add_action("Walking Trail", "_on_walkway_pressed")
			add_action("✓ Construct Trail", "_on_build_walkway_pressed")
			add_action("× Cancel Trail", "_on_cancel_walkway_pressed")
		"Land":
			add_action("Mow Grass", "_on_mower_pressed")
			add_action("Clear Brush", "_on_brush_pressed")
			add_action("Remove Tree", "_on_chainsaw_pressed")
		"Staff":
			add_action("Grounds Crew", "_on_workers_pressed")
		"Golfers":
			var message := Label.new()
			message.text = "Tap a golfer in the world to open their profile."
			message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			message.add_theme_font_size_override("font_size", 23)
			drawer_body.add_child(message)
		"Course":
			add_action("Previous Hole", "_on_previous_hole_pressed")
			add_action("Next Hole", "_on_next_hole_pressed")
			add_action("Inspect", "_on_view_pressed")
		"Radio":
			add_radio_action("◀ Previous", "previous_track")
			add_radio_action("Play / Pause", "toggle_pause")
			add_radio_action("Next ▶", "next_track")
			add_radio_action("Full Player", "toggle_expanded")
	drawer.show()
	fit_drawer()
	_update_active_buttons()

func fit_drawer() -> void:
	if drawer == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var compact := screen.x < 760.0
	var dock_width := clampf(screen.x * 0.18, 90.0, 164.0)
	var gap := 12.0
	var drawer_left := 12.0 + dock_width + gap
	var available_width := maxf(150.0, screen.x - drawer_left - 14.0)
	var drawer_width := minf(560.0 if compact else 680.0, available_width)
	var usable_height := maxf(160.0, screen.y - 118.0)
	var drawer_height := usable_height
	var top := 92.0
	drawer.position = Vector2(drawer_left, top)
	drawer.size = Vector2(drawer_width, drawer_height)

func _update_active_buttons() -> void:
	for tab_name in dock_buttons:
		var button: Button = dock_buttons[tab_name]
		var active: bool = tab_name == selected_tab and drawer.visible
		button.add_theme_stylebox_override("normal", button_style(active))
		button.add_theme_color_override("font_color", GOLD if active else WHITE)

func add_action(title: String, method_name: String) -> void:
	var action := make_button(title, _invoke_ui.bind(method_name), 120)
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_body.add_child(action)

func add_radio_action(title: String, method_name: String) -> void:
	var action := make_button(title, _invoke_radio.bind(method_name), 120)
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_body.add_child(action)

func _invoke_ui(method_name: String) -> void:
	if ui != null and ui.has_method(method_name):
		ui.call(method_name)
		if method_name != "_on_workers_pressed":
			close_drawer()

func _invoke_radio(method_name: String) -> void:
	if radio_manager != null and radio_manager.has_method(method_name):
		radio_manager.call(method_name)

func _inspect() -> void:
	_invoke_ui("_on_view_pressed")

func _reset_camera() -> void:
	_invoke_ui("_on_reset_camera_pressed")

func close_drawer() -> void:
	selected_tab = ""
	drawer.hide()
	_update_active_buttons()

func _cycle_speed() -> void:
	speed_index = (speed_index + 1) % sim_speeds.size()
	Engine.time_scale = sim_speeds[speed_index]
	speed_button.text = "Ⅱ" if speed_index == 0 else "%d×" % int(sim_speeds[speed_index])

func _process(delta: float) -> void:
	refresh_clock += delta
	if refresh_clock >= 0.4:
		refresh_clock = 0.0
		refresh_status()

func refresh_status() -> void:
	if status_label == null:
		return
	var money_text := ""
	if ui != null and ui.money_label != null:
		money_text = ui.money_label.text
	var golfer_count := 0
	if golfer_manager != null:
		golfer_count = golfer_manager.visitors.size()
	var crew_count := 0
	if job_manager != null:
		crew_count = job_manager.get_worker_count()
	var hole_num := 1
	if course_manager != null:
		hole_num = course_manager.selected_hole + 1
	status_label.text = "%s   |   Hole %d   |   Golfers %d   |   Crew %d" % [money_text, hole_num, golfer_count, crew_count]
