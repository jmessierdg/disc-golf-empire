# Disc Golf Empire — Update 19: Park Management HUD
# New mobile-first overlay. Reuses CourseUI's existing gameplay callbacks.
extends CanvasLayer

const INK := Color(0.055, 0.09, 0.075, 0.96)
const EDGE := Color(0.27, 0.43, 0.31, 1.0)
const GOLD := Color(0.98, 0.79, 0.38, 1.0)
const WHITE := Color(0.96, 0.97, 0.92, 1.0)

var ui
var course_manager
var economy_manager
var job_manager
var golfer_manager
var radio_manager
var camera_controller
var top_bar: PanelContainer
var bottom_bar: PanelContainer
var drawer: PanelContainer
var drawer_title: Label
var drawer_body: VBoxContainer
var status_label: Label
var speed_button: Button
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
	set_process(true)

func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(13)
	style.set_content_margin_all(8)
	return style

func make_button(label_text: String, callback: Callable, width: float = 94.0) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(width, 56)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", WHITE)
	button.pressed.connect(callback)
	return button

func build_hud() -> void:
	top_bar = PanelContainer.new()
	top_bar.name = "ParkStatusBar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 10
	top_bar.offset_right = -10
	top_bar.offset_top = 8
	top_bar.offset_bottom = 72
	top_bar.add_theme_stylebox_override("panel", panel_style())
	add_child(top_bar)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_bar.add_child(top_row)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_font_size_override("font_size", 19)
	status_label.add_theme_color_override("font_color", GOLD)
	top_row.add_child(status_label)
	speed_button = make_button("1×", _cycle_speed, 65)
	top_row.add_child(speed_button)

	bottom_bar = PanelContainer.new()
	bottom_bar.name = "ParkToolbar"
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_left = 10
	bottom_bar.offset_right = -10
	bottom_bar.offset_top = -82
	bottom_bar.offset_bottom = -7
	bottom_bar.add_theme_stylebox_override("panel", panel_style())
	add_child(bottom_bar)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bottom_bar.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	scroll.add_child(row)
	for tab in ["Build", "Land", "Staff", "Golfers", "Course", "Radio"]:
		row.add_child(make_button(tab, _toggle_tab.bind(tab), 102))
	row.add_child(make_button("Inspect", _inspect, 105))
	row.add_child(make_button("Camera", _reset_camera, 105))

	drawer = PanelContainer.new()
	drawer.name = "ParkActionDrawer"
	drawer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	drawer.offset_left = 10
	drawer.offset_right = 365
	drawer.offset_top = -470
	drawer.offset_bottom = -91
	drawer.add_theme_stylebox_override("panel", panel_style())
	add_child(drawer)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	drawer.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	drawer_title = Label.new()
	drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_title.add_theme_color_override("font_color", GOLD)
	drawer_title.add_theme_font_size_override("font_size", 22)
	heading.add_child(drawer_title)
	heading.add_child(make_button("×", close_drawer, 48))
	var scroller := ScrollContainer.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroller)
	drawer_body = VBoxContainer.new()
	drawer_body.add_theme_constant_override("separation", 5)
	scroller.add_child(drawer_body)
	drawer.hide()
	refresh_status()

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
			message.add_theme_font_size_override("font_size", 17)
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

func fit_drawer() -> void:
	var screen := get_viewport().get_visible_rect().size
	drawer.offset_right = minf(390.0, screen.x - 12.0)
	drawer.offset_top = -minf(470.0, screen.y - 105.0)

func add_action(title: String, method_name: String) -> void:
	var action := make_button(title, _invoke_ui.bind(method_name), 290)
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_body.add_child(action)

func add_radio_action(title: String, method_name: String) -> void:
	var action := make_button(title, _invoke_radio.bind(method_name), 290)
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
