class_name CourseUI
extends CanvasLayer


# ==================================================
# COLORS
# ==================================================

const UI_SCALE_FACTOR := 1.61 # Previous 1.15 scale increased by 40%

const COLOR_PANEL := Color(0.045, 0.065, 0.05, 0.97)
const COLOR_CARD := Color(0.085, 0.115, 0.09, 0.98)
const COLOR_CARD_HOVER := Color(0.12, 0.16, 0.125, 1.0)

const COLOR_GREEN := Color(0.36, 0.78, 0.42, 1.0)
const COLOR_GREEN_DARK := Color(0.16, 0.38, 0.20, 1.0)

const COLOR_GOLD := Color(1.0, 0.79, 0.30, 1.0)
const COLOR_ORANGE := Color(1.0, 0.52, 0.18, 1.0)

const COLOR_RED := Color(0.92, 0.31, 0.31, 1.0)
const COLOR_RED_DARK := Color(0.34, 0.09, 0.09, 1.0)

const COLOR_TEXT := Color(0.96, 0.97, 0.95, 1.0)
const COLOR_MUTED := Color(0.65, 0.71, 0.66, 1.0)

const COLOR_SHADOW := Color(0.0, 0.0, 0.0, 0.48)


# ==================================================
# MENU CATEGORIES
# ==================================================

const CATEGORY_BUILD := "BUILD"
const CATEGORY_LANDSCAPE := "LANDSCAPE"

var active_category := CATEGORY_BUILD

# Update 11: RollerCoaster Tycoon-inspired collapsible tool sidebar.
var empire_sidebar: PanelContainer
var empire_sidebar_scroll: ScrollContainer
var empire_sidebar_content: VBoxContainer
var empire_sidebar_toggle: Button
var empire_sidebar_collapsed := false
var empire_sidebar_buttons: Dictionary = {}
var empire_sidebar_hints: Dictionary = {}
var empire_sidebar_last_tool := ""
var empire_sidebar_radio_title: Button
var empire_sidebar_radio_play: Button
var empire_sidebar_drag_handle: Button
var empire_sidebar_top_offset := 155.0
var empire_drag_active := false
var empire_drag_last_y := 0.0



# ==================================================
# REFERENCES
# ==================================================

var course_manager
var economy_manager
var course_builder
var property_manager
var camera_controller
var course_renderer
var job_manager


# ==================================================
# TOP HUD
# ==================================================

var top_panel: PanelContainer

var money_label: Label
var hole_label: Label
var hole_detail_label: Label
var course_label: Label

var workers_button: Button


# ==================================================
# GROUNDS CREW
# ==================================================

var crew_panel: PanelContainer
var crew_list: VBoxContainer
var crew_summary_label: Label
var crew_close_button: Button

var crew_panel_open := false


# ==================================================
# BOTTOM TOOL DOCK
# ==================================================

var tool_dock: PanelContainer

var previous_button: Button
var next_button: Button

var build_button: Button
var landscape_button: Button
var view_button: Button

var reset_camera_button: Button

var submenu_container: HBoxContainer

var tee_button: Button
var basket_button: Button
var path_button: Button

var mower_button: Button
var brush_button: Button
var chainsaw_button: Button


# ==================================================
# TOOLTIP
# ==================================================

var tooltip_panel: PanelContainer
var tooltip_label: Label


# ==================================================
# PENDING EDIT CONFIRMATION
# ==================================================

var pending_panel: PanelContainer
var pending_label: Label
var pending_confirm_button: Button
var pending_cancel_button: Button


# ==================================================
# OBJECT INSPECTOR
# ==================================================

var inspector_panel: PanelContainer

var inspector_title: Label
var inspector_subtitle: Label
var inspector_detail: Label

var inspector_action_button: Button
var inspector_close_button: Button


# ==================================================
# SETUP
# ==================================================

func setup(
	course_ref,
	economy_ref,
	builder_ref,
	property_ref,
	camera_ref,
	renderer_ref
) -> void:

	course_manager = course_ref
	economy_manager = economy_ref
	course_builder = builder_ref
	property_manager = property_ref
	camera_controller = camera_ref
	course_renderer = renderer_ref

	if course_builder != null:
		job_manager = course_builder.job_manager

	create_interface()

	if course_builder != null:

		if not course_builder.viewed_object_changed.is_connected(
			_on_viewed_object_changed
		):

			course_builder.viewed_object_changed.connect(
				_on_viewed_object_changed
			)

		if not course_builder.pending_edit_changed.is_connected(
			_on_pending_edit_changed
		):

			course_builder.pending_edit_changed.connect(
				_on_pending_edit_changed
			)

	if job_manager != null:

		if not job_manager.jobs_changed.is_connected(
			_on_workforce_changed
		):

			job_manager.jobs_changed.connect(
				_on_workforce_changed
			)

		if not job_manager.workers_changed.is_connected(
			_on_workforce_changed
		):

			job_manager.workers_changed.connect(
				_on_workforce_changed
			)

	update_interface()


# ==================================================
# CREATE INTERFACE
# ==================================================

func create_interface() -> void:

	create_top_hud()
	create_tool_dock()
	create_tooltip()
	create_pending_panel()
	create_inspector()
	create_crew_panel()
	apply_ui_scale()
	create_empire_sidebar()
	apply_empire_sidebar_layout()
	if tooltip_panel != null:
		tooltip_panel.hide() # Hints now live beside the selected tool.


# ==================================================
# TOP HUD
# ==================================================

# ==================================================
# ACCESSIBILITY / TOUCH TARGET SCALE
# ==================================================

func apply_ui_scale() -> void:
	# Scale interface widgets, not the game world or camera.
	# Each widget is visited once after the interface is constructed.
	for child in get_children():
		if child is Control:
			scale_interface_branch(child)

	# Increase the main panel footprints to accommodate larger text and touch targets.
	if top_panel != null:
		top_panel.offset_bottom = 110.0
	if tool_dock != null:
		tool_dock.offset_left = -747.5
		tool_dock.offset_right = 747.5
		tool_dock.offset_top = -218.0
	if tooltip_panel != null:
		tooltip_panel.offset_left = -471.5
		tooltip_panel.offset_right = 471.5
	if pending_panel != null:
		pending_panel.offset_left = -333.5
		pending_panel.offset_right = 333.5
	if inspector_panel != null:
		inspector_panel.offset_right = 510.0
		inspector_panel.offset_top = -510.0
		inspector_panel.offset_bottom = -210.0
	if crew_panel != null:
		crew_panel.offset_left = -580.0
		crew_panel.offset_top = 150.0
		crew_panel.offset_bottom = 610.0

func scale_interface_branch(widget: Control) -> void:
	if widget.has_theme_font_size_override("font_size"):
		var old_font_size: int = widget.get_theme_font_size("font_size")
		widget.add_theme_font_size_override("font_size", int(ceil(float(old_font_size) * UI_SCALE_FACTOR)))
	if widget.custom_minimum_size != Vector2.ZERO:
		widget.custom_minimum_size *= UI_SCALE_FACTOR
	for child in widget.get_children():
		if child is Control:
			scale_interface_branch(child)



func create_top_hud() -> void:

	top_panel = PanelContainer.new()
	top_panel.name = "TopHUD"

	top_panel.set_anchors_preset(
		Control.PRESET_TOP_WIDE
	)

	top_panel.offset_left = 18.0
	top_panel.offset_top = 14.0
	top_panel.offset_right = -18.0
	top_panel.offset_bottom = 92.0

	top_panel.add_theme_stylebox_override(
		"panel",
		create_panel_style()
	)

	add_child(top_panel)


	var margin := MarginContainer.new()

	margin.add_theme_constant_override(
		"margin_left",
		22
	)

	margin.add_theme_constant_override(
		"margin_right",
		22
	)

	margin.add_theme_constant_override(
		"margin_top",
		10
	)

	margin.add_theme_constant_override(
		"margin_bottom",
		10
	)

	top_panel.add_child(margin)


	var row := HBoxContainer.new()

	row.add_theme_constant_override(
		"separation",
		18
	)

	margin.add_child(row)


	# --------------------------------------------------
	# BRAND
	# --------------------------------------------------

	var brand_box := VBoxContainer.new()

	brand_box.custom_minimum_size = Vector2(
		230,
		0
	)

	brand_box.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER
	)

	row.add_child(brand_box)


	var title := Label.new()

	title.text = "COURSE BUILDER"

	title.add_theme_font_size_override(
		"font_size",
		24
	)

	title.add_theme_color_override(
		"font_color",
		COLOR_TEXT
	)

	brand_box.add_child(title)


	var property_title := Label.new()

	property_title.text = "STARTER PROPERTY"

	property_title.add_theme_font_size_override(
		"font_size",
		14
	)

	property_title.add_theme_color_override(
		"font_color",
		COLOR_GREEN
	)

	brand_box.add_child(property_title)


	row.add_child(
		create_vertical_divider()
	)


	# --------------------------------------------------
	# MONEY
	# --------------------------------------------------

	var money_box := VBoxContainer.new()

	money_box.custom_minimum_size = Vector2(
		180,
		0
	)

	money_box.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER
	)

	row.add_child(money_box)


	var money_title := Label.new()

	money_title.text = "CASH"

	money_title.add_theme_font_size_override(
		"font_size",
		13
	)

	money_title.add_theme_color_override(
		"font_color",
		COLOR_MUTED
	)

	money_box.add_child(money_title)


	money_label = Label.new()

	money_label.add_theme_font_size_override(
		"font_size",
		25
	)

	money_label.add_theme_color_override(
		"font_color",
		COLOR_GOLD
	)

	money_box.add_child(money_label)


	row.add_child(
		create_vertical_divider()
	)


	# --------------------------------------------------
	# CURRENT HOLE
	# --------------------------------------------------

	var hole_box := VBoxContainer.new()

	hole_box.custom_minimum_size = Vector2(
		250,
		0
	)

	hole_box.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	hole_box.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER
	)

	row.add_child(hole_box)


	hole_label = Label.new()

	hole_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	hole_label.add_theme_font_size_override(
		"font_size",
		24
	)

	hole_label.add_theme_color_override(
		"font_color",
		COLOR_TEXT
	)

	hole_box.add_child(hole_label)


	hole_detail_label = Label.new()

	hole_detail_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	hole_detail_label.add_theme_font_size_override(
		"font_size",
		14
	)

	hole_detail_label.add_theme_color_override(
		"font_color",
		COLOR_MUTED
	)

	hole_box.add_child(hole_detail_label)


	row.add_child(
		create_vertical_divider()
	)


	# --------------------------------------------------
	# COURSE SUMMARY
	# --------------------------------------------------

	var course_box := VBoxContainer.new()

	course_box.custom_minimum_size = Vector2(
		260,
		0
	)

	course_box.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	course_box.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER
	)

	row.add_child(course_box)


	var course_title := Label.new()

	course_title.text = "COURSE"

	course_title.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	course_title.add_theme_font_size_override(
		"font_size",
		13
	)

	course_title.add_theme_color_override(
		"font_color",
		COLOR_MUTED
	)

	course_box.add_child(course_title)


	course_label = Label.new()

	course_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	course_label.add_theme_font_size_override(
		"font_size",
		18
	)

	course_label.add_theme_color_override(
		"font_color",
		COLOR_TEXT
	)

	course_box.add_child(course_label)


	row.add_child(
		create_vertical_divider()
	)


	# --------------------------------------------------
	# WORKFORCE
	# --------------------------------------------------

	workers_button = create_ui_button(
		"WORKERS\n0 / 0",
		Vector2(180, 58)
	)

	workers_button.size_flags_vertical = (
		Control.SIZE_SHRINK_CENTER
	)

	workers_button.pressed.connect(
		_on_workers_pressed
	)

	row.add_child(
		workers_button
	)


# ==================================================
# TOOL DOCK
# ==================================================

func create_tool_dock() -> void:

	tool_dock = PanelContainer.new()
	tool_dock.name = "ToolDock"

	tool_dock.set_anchors_preset(
		Control.PRESET_CENTER_BOTTOM
	)

	tool_dock.offset_left = -650.0
	tool_dock.offset_top = -192.0
	tool_dock.offset_right = 650.0
	tool_dock.offset_bottom = -18.0

	tool_dock.add_theme_stylebox_override(
		"panel",
		create_floating_panel_style()
	)

	add_child(tool_dock)


	var margin := MarginContainer.new()

	margin.add_theme_constant_override(
		"margin_left",
		14
	)

	margin.add_theme_constant_override(
		"margin_right",
		14
	)

	margin.add_theme_constant_override(
		"margin_top",
		10
	)

	margin.add_theme_constant_override(
		"margin_bottom",
		10
	)

	tool_dock.add_child(margin)


	var main_box := VBoxContainer.new()

	main_box.add_theme_constant_override(
		"separation",
		8
	)

	margin.add_child(main_box)


	var category_row := HBoxContainer.new()

	category_row.add_theme_constant_override(
		"separation",
		10
	)

	main_box.add_child(category_row)


	previous_button = create_ui_button(
		"‹",
		Vector2(72, 64)
	)

	previous_button.pressed.connect(
		_on_previous_hole_pressed
	)

	category_row.add_child(
		previous_button
	)


	next_button = create_ui_button(
		"›",
		Vector2(72, 64)
	)

	next_button.pressed.connect(
		_on_next_hole_pressed
	)

	category_row.add_child(
		next_button
	)


	category_row.add_child(
		create_vertical_divider()
	)


	build_button = create_ui_button(
		"BUILD",
		Vector2(245, 64)
	)

	build_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	build_button.pressed.connect(
		_on_build_category_pressed
	)

	category_row.add_child(
		build_button
	)


	landscape_button = create_ui_button(
		"LANDSCAPE",
		Vector2(245, 64)
	)

	landscape_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	landscape_button.pressed.connect(
		_on_landscape_category_pressed
	)

	category_row.add_child(
		landscape_button
	)


	view_button = create_ui_button(
		"VIEW",
		Vector2(200, 64)
	)

	view_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	view_button.pressed.connect(
		_on_view_pressed
	)

	category_row.add_child(
		view_button
	)


	category_row.add_child(
		create_vertical_divider()
	)


	reset_camera_button = create_ui_button(
		"⌖",
		Vector2(72, 64)
	)

	reset_camera_button.pressed.connect(
		_on_reset_camera_pressed
	)

	category_row.add_child(
		reset_camera_button
	)


	submenu_container = HBoxContainer.new()

	submenu_container.custom_minimum_size = Vector2(
		0,
		66
	)

	submenu_container.add_theme_constant_override(
		"separation",
		10
	)

	main_box.add_child(
		submenu_container
	)


	create_build_submenu()


# ==================================================
# CLEAR SUBMENU
# ==================================================

func clear_submenu() -> void:

	if submenu_container == null:
		return

	for child in submenu_container.get_children():
		child.queue_free()

	tee_button = null
	basket_button = null
	path_button = null

	mower_button = null
	brush_button = null
	chainsaw_button = null


# ==================================================
# BUILD SUBMENU
# ==================================================

func create_build_submenu() -> void:

	clear_submenu()

	active_category = CATEGORY_BUILD


	tee_button = create_ui_button(
		"TEE",
		Vector2(0, 62)
	)

	tee_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	tee_button.pressed.connect(
		_on_tee_pressed
	)

	submenu_container.add_child(
		tee_button
	)


	basket_button = create_ui_button(
		"BASKET",
		Vector2(0, 62)
	)

	basket_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	basket_button.pressed.connect(
		_on_basket_pressed
	)

	submenu_container.add_child(
		basket_button
	)


	path_button = create_ui_button(
		"PATH",
		Vector2(0, 62)
	)

	path_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	path_button.pressed.connect(
		_on_path_pressed
	)

	submenu_container.add_child(
		path_button
	)


# ==================================================
# LANDSCAPE SUBMENU
# ==================================================

func create_landscape_submenu() -> void:

	clear_submenu()

	active_category = CATEGORY_LANDSCAPE


	mower_button = create_ui_button(
		"MOWER",
		Vector2(0, 62)
	)

	mower_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	mower_button.pressed.connect(
		_on_mower_pressed
	)

	submenu_container.add_child(
		mower_button
	)


	brush_button = create_ui_button(
		"BRUSH CUTTER",
		Vector2(0, 62)
	)

	brush_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	brush_button.pressed.connect(
		_on_brush_pressed
	)

	submenu_container.add_child(
		brush_button
	)


	chainsaw_button = create_ui_button(
		"CHAINSAW",
		Vector2(0, 62)
	)

	chainsaw_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	chainsaw_button.pressed.connect(
		_on_chainsaw_pressed
	)

	submenu_container.add_child(
		chainsaw_button
	)


# ==================================================
# TOOLTIP
# ==================================================

func create_tooltip() -> void:

	tooltip_panel = PanelContainer.new()
	tooltip_panel.name = "ToolTip"

	tooltip_panel.set_anchors_preset(
		Control.PRESET_CENTER_BOTTOM
	)

	tooltip_panel.offset_left = -410.0
	tooltip_panel.offset_top = -248.0
	tooltip_panel.offset_right = 410.0
	tooltip_panel.offset_bottom = -202.0

	tooltip_panel.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)

	tooltip_panel.add_theme_stylebox_override(
		"panel",
		create_tooltip_style()
	)

	add_child(tooltip_panel)


	var margin := MarginContainer.new()

	margin.add_theme_constant_override(
		"margin_left",
		18
	)

	margin.add_theme_constant_override(
		"margin_right",
		18
	)

	margin.add_theme_constant_override(
		"margin_top",
		7
	)

	margin.add_theme_constant_override(
		"margin_bottom",
		7
	)

	tooltip_panel.add_child(margin)


	tooltip_label = Label.new()

	tooltip_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	tooltip_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	tooltip_label.add_theme_font_size_override(
		"font_size",
		16
	)

	tooltip_label.add_theme_color_override(
		"font_color",
		COLOR_TEXT
	)

	margin.add_child(
		tooltip_label
	)


# ==================================================
# PENDING EDIT CONFIRMATION
# ==================================================

func create_pending_panel() -> void:

	pending_panel = PanelContainer.new()
	pending_panel.name = "PendingEdit"

	pending_panel.set_anchors_preset(
		Control.PRESET_CENTER_BOTTOM
	)

	pending_panel.offset_left = -290.0
	pending_panel.offset_top = -322.0
	pending_panel.offset_right = 290.0
	pending_panel.offset_bottom = -258.0

	pending_panel.add_theme_stylebox_override(
		"panel",
		create_floating_panel_style()
	)

	add_child(
		pending_panel
	)


	var margin := MarginContainer.new()

	margin.add_theme_constant_override(
		"margin_left",
		12
	)

	margin.add_theme_constant_override(
		"margin_right",
		12
	)

	margin.add_theme_constant_override(
		"margin_top",
		8
	)

	margin.add_theme_constant_override(
		"margin_bottom",
		8
	)

	pending_panel.add_child(
		margin
	)


	var row := HBoxContainer.new()

	row.add_theme_constant_override(
		"separation",
		10
	)

	margin.add_child(
		row
	)


	pending_label = Label.new()

	pending_label.text = "PENDING CHANGES"
	pending_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	pending_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	pending_label.add_theme_font_size_override(
		"font_size",
		17
	)

	pending_label.add_theme_color_override(
		"font_color",
		COLOR_GOLD
	)

	row.add_child(
		pending_label
	)


	pending_cancel_button = create_ui_button(
		"✕",
		Vector2(64, 46)
	)

	pending_cancel_button.add_theme_stylebox_override(
		"normal",
		create_button_style(
			COLOR_RED_DARK,
			COLOR_RED
		)
	)

	pending_cancel_button.pressed.connect(
		_on_pending_cancel_pressed
	)

	row.add_child(
		pending_cancel_button
	)


	pending_confirm_button = create_ui_button(
		"✓",
		Vector2(76, 46)
	)

	pending_confirm_button.add_theme_stylebox_override(
		"normal",
		create_button_style(
			COLOR_GREEN_DARK,
			COLOR_GREEN
		)
	)

	pending_confirm_button.pressed.connect(
		_on_pending_confirm_pressed
	)

	row.add_child(
		pending_confirm_button
	)


	pending_panel.visible = false


# ==================================================
# INSPECTOR
# ==================================================

func create_inspector() -> void:

	inspector_panel = PanelContainer.new()
	inspector_panel.name = "ObjectInspector"

	inspector_panel.set_anchors_preset(
		Control.PRESET_BOTTOM_LEFT
	)

	inspector_panel.offset_left = 28.0
	inspector_panel.offset_top = -620.0
	inspector_panel.offset_right = 650.0
	inspector_panel.offset_bottom = -176.0

	inspector_panel.add_theme_stylebox_override(
		"panel",
		create_floating_panel_style()
	)

	add_child(inspector_panel)


	var outer_margin := MarginContainer.new()

	outer_margin.add_theme_constant_override(
		"margin_left",
		20
	)

	outer_margin.add_theme_constant_override(
		"margin_right",
		20
	)

	outer_margin.add_theme_constant_override(
		"margin_top",
		16
	)

	outer_margin.add_theme_constant_override(
		"margin_bottom",
		16
	)

	inspector_panel.add_child(
		outer_margin
	)


	var main_vbox := VBoxContainer.new()

	main_vbox.add_theme_constant_override(
		"separation",
		7
	)

	outer_margin.add_child(
		main_vbox
	)


	var header := HBoxContainer.new()

	header.add_theme_constant_override(
		"separation",
		10
	)

	main_vbox.add_child(
		header
	)


	inspector_title = Label.new()

	inspector_title.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	inspector_title.add_theme_font_size_override(
		"font_size",
		27
	)

	inspector_title.add_theme_color_override(
		"font_color",
		COLOR_TEXT
	)

	header.add_child(
		inspector_title
	)


	inspector_close_button = create_ui_button(
		"×",
		Vector2(48, 42)
	)

	inspector_close_button.add_theme_font_size_override(
		"font_size",
		24
	)

	inspector_close_button.pressed.connect(
		_on_inspector_close_pressed
	)

	header.add_child(
		inspector_close_button
	)


	inspector_subtitle = Label.new()

	inspector_subtitle.add_theme_font_size_override(
		"font_size",
		19
	)

	inspector_subtitle.add_theme_color_override(
		"font_color",
		COLOR_GREEN
	)

	main_vbox.add_child(
		inspector_subtitle
	)


	inspector_detail = Label.new()

	inspector_detail.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)

	inspector_detail.add_theme_font_size_override(
		"font_size",
		18
	)

	inspector_detail.add_theme_color_override(
		"font_color",
		COLOR_MUTED
	)

	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(inspector_scroll)
	inspector_scroll.add_child(inspector_detail)
	inspector_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL


	var spacer := Control.new()

	spacer.custom_minimum_size = Vector2(
		0,
		5
	)

	main_vbox.add_child(
		spacer
	)


	inspector_action_button = create_ui_button(
		"ACTION",
		Vector2(0, 54)
	)

	inspector_action_button.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	inspector_action_button.pressed.connect(
		_on_inspector_action_pressed
	)

	main_vbox.add_child(
		inspector_action_button
	)


	inspector_panel.visible = false


# ==================================================
# GROUNDS CREW PANEL
# ==================================================

func create_crew_panel() -> void:

	crew_panel = PanelContainer.new()
	crew_panel.name = "GroundsCrewPanel"

	crew_panel.set_anchors_preset(
		Control.PRESET_TOP_RIGHT
	)

	crew_panel.offset_left = -510.0
	crew_panel.offset_top = 108.0
	crew_panel.offset_right = -28.0
	crew_panel.offset_bottom = 520.0

	crew_panel.add_theme_stylebox_override(
		"panel",
		create_floating_panel_style()
	)

	add_child(
		crew_panel
	)


	var outer_margin := MarginContainer.new()

	outer_margin.add_theme_constant_override(
		"margin_left",
		20
	)

	outer_margin.add_theme_constant_override(
		"margin_right",
		20
	)

	outer_margin.add_theme_constant_override(
		"margin_top",
		16
	)

	outer_margin.add_theme_constant_override(
		"margin_bottom",
		16
	)

	crew_panel.add_child(
		outer_margin
	)


	var main_box := VBoxContainer.new()

	main_box.add_theme_constant_override(
		"separation",
		12
	)

	outer_margin.add_child(
		main_box
	)


	var header := HBoxContainer.new()

	header.add_theme_constant_override(
		"separation",
		10
	)

	main_box.add_child(
		header
	)


	var title := Label.new()

	title.text = "GROUNDS CREW"

	title.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	title.add_theme_font_size_override(
		"font_size",
		24
	)

	title.add_theme_color_override(
		"font_color",
		COLOR_TEXT
	)

	header.add_child(
		title
	)


	crew_close_button = create_ui_button(
		"×",
		Vector2(48, 42)
	)

	crew_close_button.add_theme_font_size_override(
		"font_size",
		24
	)

	crew_close_button.pressed.connect(
		_on_crew_close_pressed
	)

	header.add_child(
		crew_close_button
	)


	crew_summary_label = Label.new()

	crew_summary_label.add_theme_font_size_override(
		"font_size",
		15
	)

	crew_summary_label.add_theme_color_override(
		"font_color",
		COLOR_MUTED
	)

	main_box.add_child(
		crew_summary_label
	)


	var scroll := ScrollContainer.new()

	scroll.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	scroll.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL
	)

	scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)

	main_box.add_child(
		scroll
	)


	crew_list = VBoxContainer.new()

	crew_list.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)

	crew_list.add_theme_constant_override(
		"separation",
		10
	)

	scroll.add_child(
		crew_list
	)


	crew_panel.visible = false


# ==================================================
# STYLE HELPERS
# ==================================================

func create_panel_style() -> StyleBoxFlat:

	var style := StyleBoxFlat.new()

	style.bg_color = COLOR_PANEL

	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 2

	style.border_color = Color(
		COLOR_GREEN.r,
		COLOR_GREEN.g,
		COLOR_GREEN.b,
		0.34
	)

	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12

	style.shadow_color = COLOR_SHADOW
	style.shadow_size = 8

	return style


func create_floating_panel_style() -> StyleBoxFlat:

	var style := StyleBoxFlat.new()

	style.bg_color = COLOR_PANEL

	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2

	style.border_color = Color(
		COLOR_GREEN.r,
		COLOR_GREEN.g,
		COLOR_GREEN.b,
		0.42
	)

	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14

	style.shadow_color = COLOR_SHADOW
	style.shadow_size = 12

	return style


func create_tooltip_style() -> StyleBoxFlat:

	var style := StyleBoxFlat.new()

	style.bg_color = Color(
		0.055,
		0.075,
		0.06,
		0.94
	)

	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1

	style.border_color = Color(
		1.0,
		1.0,
		1.0,
		0.10
	)

	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10

	return style


func create_button_style(
	background_color: Color,
	border_color: Color
) -> StyleBoxFlat:

	var style := StyleBoxFlat.new()

	style.bg_color = background_color

	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2

	style.border_color = border_color

	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10

	return style


func create_vertical_divider() -> VSeparator:

	var divider := VSeparator.new()

	divider.add_theme_constant_override(
		"separation",
		8
	)

	return divider


func create_ui_button(
	button_text: String,
	minimum_size: Vector2
) -> Button:

	var button := Button.new()

	button.text = button_text
	button.custom_minimum_size = minimum_size

	button.add_theme_font_size_override(
		"font_size",
		19
	)

	button.add_theme_color_override(
		"font_color",
		COLOR_TEXT
	)

	button.add_theme_color_override(
		"font_hover_color",
		COLOR_TEXT
	)

	button.add_theme_color_override(
		"font_pressed_color",
		COLOR_TEXT
	)

	button.add_theme_color_override(
		"font_disabled_color",
		COLOR_MUTED
	)

	button.add_theme_stylebox_override(
		"normal",
		create_button_style(
			COLOR_CARD,
			Color(
				1.0,
				1.0,
				1.0,
				0.12
			)
		)
	)

	button.add_theme_stylebox_override(
		"hover",
		create_button_style(
			COLOR_CARD_HOVER,
			Color(
				1.0,
				1.0,
				1.0,
				0.20
			)
		)
	)

	button.add_theme_stylebox_override(
		"pressed",
		create_button_style(
			COLOR_GREEN_DARK,
			COLOR_GREEN
		)
	)

	return button


# ==================================================
# BUTTON STYLES
# ==================================================

func apply_tool_button_style(
	button: Button,
	is_selected: bool
) -> void:

	if button == null:
		return

	var background_color: Color = (
		COLOR_CARD
	)

	var border_color := Color(
		1.0,
		1.0,
		1.0,
		0.12
	)

	if is_selected:

		background_color = (
			COLOR_GREEN_DARK
		)

		border_color = COLOR_GREEN

	button.add_theme_stylebox_override(
		"normal",
		create_button_style(
			background_color,
			border_color
		)
	)


func update_category_styles() -> void:

	apply_tool_button_style(
		build_button,
		active_category == CATEGORY_BUILD
	)

	apply_tool_button_style(
		landscape_button,
		active_category == CATEGORY_LANDSCAPE
	)

	apply_tool_button_style(
		view_button,
		course_builder.get_current_tool_name() == "VIEW"
	)


# ==================================================
# CATEGORY CALLBACKS
# ==================================================

func _on_build_category_pressed() -> void:

	if active_category != CATEGORY_BUILD:
		create_build_submenu()

	course_builder.select_none_tool()

	update_interface()


func _on_landscape_category_pressed() -> void:

	if active_category != CATEGORY_LANDSCAPE:
		create_landscape_submenu()

	course_builder.select_none_tool()

	update_interface()


# ==================================================
# TOOL CALLBACKS
# ==================================================

func _on_previous_hole_pressed() -> void:

	course_manager.select_previous_hole()

	course_builder.select_none_tool()

	course_renderer.refresh()

	update_interface()


func _on_next_hole_pressed() -> void:

	course_manager.select_next_hole()

	course_builder.select_none_tool()

	course_renderer.refresh()

	update_interface()


func _on_tee_pressed() -> void:

	course_builder.select_tee_tool()

	update_interface()


func _on_basket_pressed() -> void:

	course_builder.select_basket_tool()

	update_interface()


func _on_path_pressed() -> void:

	course_builder.select_path_tool()

	update_interface()


func _on_mower_pressed() -> void:

	course_builder.select_mower_tool()

	update_interface()


func _on_brush_pressed() -> void:

	course_builder.select_brush_tool()

	update_interface()


func _on_chainsaw_pressed() -> void:

	course_builder.select_chainsaw_tool()

	update_interface()


func _on_view_pressed() -> void:

	course_builder.select_view_tool()

	update_interface()


func _on_reset_camera_pressed() -> void:

	camera_controller.reset_camera(
		property_manager.get_property_world_center()
	)


# ==================================================
# PENDING EDIT CALLBACKS
# ==================================================

func _on_pending_edit_changed(
	_pending: bool
) -> void:

	update_pending_panel()
	update_interface()


func _on_pending_confirm_pressed() -> void:

	course_builder.confirm_pending_edit()

	update_interface()


func _on_pending_cancel_pressed() -> void:

	course_builder.cancel_pending_edit()

	update_interface()


# ==================================================
# CREW CALLBACKS
# ==================================================

func _on_workers_pressed() -> void:

	crew_panel_open = (
		not crew_panel_open
	)

	crew_panel.visible = (
		crew_panel_open
	)

	if crew_panel_open:
		update_crew_panel()

	refresh_empire_sidebar()


func _on_crew_close_pressed() -> void:

	crew_panel_open = false
	crew_panel.visible = false


func _on_workforce_changed() -> void:

	update_workforce_information()
	update_pending_panel()

	if crew_panel_open:
		update_crew_panel()


# ==================================================
# INSPECTOR CALLBACKS
# ==================================================

func _on_viewed_object_changed(
	object_data: Dictionary
) -> void:

	update_inspector(
		object_data
	)

	update_interface()


func _on_inspector_close_pressed() -> void:

	course_builder.clear_viewed_object()

	update_interface()


func _on_inspector_action_pressed() -> void:

	if course_builder.perform_view_action():
		update_inspector(course_builder.get_viewed_object_info())
		update_interface()


# ==================================================
# UPDATE INTERFACE
# ==================================================

func update_interface() -> void:

	if course_manager == null:
		return

	if course_builder == null:
		return

	var hole_index: int = (
		course_manager.selected_hole
	)

	hole_label.text = (
		"HOLE "
		+ str(hole_index + 1)
		+ " / "
		+ str(course_manager.TOTAL_HOLES)
	)

	previous_button.disabled = (
		hole_index <= 0
	)

	next_button.disabled = (
		hole_index
		>= course_manager.TOTAL_HOLES - 1
	)

	update_hole_information()
	update_tool_buttons()
	update_category_styles()
	refresh_empire_sidebar()
	update_course_information()
	update_economy_information()
	update_workforce_information()
	update_pending_panel()

	if crew_panel_open:
		update_crew_panel()


# ==================================================
# PENDING EDIT PANEL
# ==================================================

func update_pending_panel() -> void:

	if pending_panel == null:
		return

	var pending: bool = (
		course_builder.has_pending_edit()
	)

	pending_panel.visible = pending

	if not pending:
		return

	var selected_cells: int = (
		course_builder.get_pending_landscape_cell_count()
	)

	if selected_cells > 0:

		pending_label.text = (
			"PENDING  •  "
			+ str(selected_cells)
			+ " CELLS"
		)

	else:

		pending_label.text = (
			"PENDING CHANGES"
		)


# ==================================================
# HOLE INFORMATION
# ==================================================

func update_hole_information() -> void:

	var hole_index: int = (
		course_manager.selected_hole
	)

	if not course_manager.is_hole_complete(
		hole_index
	):

		hole_detail_label.text = (
			"INCOMPLETE HOLE"
		)

		return

	var distance_feet: int = (
		course_manager.calculate_hole_distance(
			hole_index,
			property_manager.CELL_SIZE
		)
	)

	var par: int = (
		course_manager.calculate_par(
			distance_feet
		)
	)

	hole_detail_label.text = (
		str(distance_feet)
		+ " FT  •  PAR "
		+ str(par)
	)


# ==================================================
# TOOL BUTTONS
# ==================================================

func update_tool_buttons() -> void:

	var tool_name: String = (
		course_builder.get_current_tool_name()
	)

	var hole: Dictionary = (
		course_manager.get_hole(
			course_manager.selected_hole
		)
	)

	if hole.is_empty():
		return

	if active_category == CATEGORY_BUILD:

		update_build_buttons(
			tool_name,
			hole
		)

	elif active_category == CATEGORY_LANDSCAPE:

		update_landscape_buttons(
			tool_name
		)


# ==================================================
# BUILD BUTTONS
# ==================================================

func update_build_buttons(
	tool_name: String,
	hole: Dictionary
) -> void:

	if (
		tee_button == null
		or basket_button == null
		or path_button == null
	):
		return

	var tee: Vector2 = hole["tee"]
	var basket: Vector2 = hole["basket"]

	var tee_state := ""

	if tee.x >= 0:

		tee_state = "MOVE"

	elif economy_manager.get_tee_inventory() > 0:

		tee_state = "PLACE"

	else:

		tee_state = (
			"$"
			+ str(
				economy_manager.get_tee_install_cost()
			)
		)

	tee_button.text = (
		"TEE\n"
		+ tee_state
	)

	var basket_state := ""

	if basket.x >= 0:

		basket_state = "MOVE"

	elif economy_manager.get_basket_inventory() > 0:

		basket_state = "PLACE"

	else:

		basket_state = (
			"$"
			+ str(
				economy_manager.get_basket_install_cost()
			)
		)

	basket_button.text = (
		"BASKET\n"
		+ basket_state
	)

	if course_manager.is_hole_complete(
		course_manager.selected_hole
	):

		if tool_name == "PATH":

			path_button.text = (
				"PATH\nACTIVE"
			)

		else:

			path_button.text = (
				"PATH\nEDIT"
			)

	else:

		path_button.text = (
			"PATH\nLOCKED"
		)

	apply_tool_button_style(
		tee_button,
		tool_name == "TEE"
	)

	apply_tool_button_style(
		basket_button,
		tool_name == "BASKET"
	)

	apply_tool_button_style(
		path_button,
		tool_name == "PATH"
	)


# ==================================================
# LANDSCAPE BUTTONS
# ==================================================

func update_landscape_buttons(
	tool_name: String
) -> void:

	if (
		mower_button == null
		or brush_button == null
		or chainsaw_button == null
	):
		return

	if tool_name == "MOWER":

		mower_button.text = (
			"MOWER\nACTIVE"
		)

	else:

		mower_button.text = (
			"MOWER\nCUT GRASS"
		)

	if tool_name == "BRUSH":

		brush_button.text = (
			"BRUSH CUTTER\nACTIVE"
		)

	else:

		brush_button.text = (
			"BRUSH CUTTER\nCLEAR"
		)

	if tool_name == "CHAINSAW":

		chainsaw_button.text = (
			"CHAINSAW\nACTIVE"
		)

	else:

		chainsaw_button.text = (
			"CHAINSAW\nTREES"
		)

	apply_tool_button_style(
		mower_button,
		tool_name == "MOWER"
	)

	apply_tool_button_style(
		brush_button,
		tool_name == "BRUSH"
	)

	apply_tool_button_style(
		chainsaw_button,
		tool_name == "CHAINSAW"
	)


# ==================================================
# TOOLTIP
# ==================================================

func update_tooltip() -> void:

	var tool_name: String = (
		course_builder.get_current_tool_name()
	)

	match tool_name:

		"TEE":

			tooltip_panel.visible = true

			tooltip_label.text = (
				"TEE TOOL  •  Touch and drag anywhere on your property."
			)

		"BASKET":

			tooltip_panel.visible = true

			tooltip_label.text = (
				"BASKET TOOL  •  Touch and drag to position the target."
			)

		"PATH":

			tooltip_panel.visible = true

			if course_manager.is_hole_complete(
				course_manager.selected_hole
			):

				tooltip_label.text = (
					"PATH TOOL  •  Touch the flight line and drag to shape the hole."
				)

			else:

				tooltip_label.text = (
					"PATH LOCKED  •  Place a tee and basket first."
				)

		"MOWER":

			tooltip_panel.visible = true

			tooltip_label.text = (
				"MOWER  •  Drag through rough and tall grass to create maintained turf."
			)

		"BRUSH":

			tooltip_panel.visible = true

			tooltip_label.text = (
				"BRUSH CUTTER  •  Drag through heavy growth to clear brush and knock down wild grass."
			)

		"CHAINSAW":

			tooltip_panel.visible = true

			tooltip_label.text = (
				"CHAINSAW  •  Tap a tree to remove it. Removal costs apply."
			)

		"VIEW":

			tooltip_panel.visible = true

			tooltip_label.text = (
				"VIEW TOOL  •  Tap an object to inspect it."
			)

		_:

			tooltip_panel.visible = false


# ==================================================
# INSPECTOR
# ==================================================

func update_inspector(
	object_data: Dictionary
) -> void:

	if object_data.is_empty():

		inspector_panel.visible = false

		return

	inspector_panel.visible = true

	inspector_title.text = (
		object_data.get(
			"title",
			"OBJECT"
		)
	)

	inspector_subtitle.text = (
		object_data.get(
			"subtitle",
			""
		)
	)

	inspector_detail.text = (
		object_data.get(
			"detail",
			""
		)
	)

	inspector_action_button.text = (
		object_data.get(
			"action_text",
			"ACTION"
		)
	)

	inspector_action_button.disabled = (
		not object_data.get(
			"action_enabled",
			true
		)
	)

	var object_type: String = (
		object_data.get(
			"type",
			""
		)
	)

	if object_type == "tree":

		inspector_action_button.add_theme_stylebox_override(
			"normal",
			create_button_style(
				COLOR_RED_DARK,
				COLOR_RED
			)
		)

	else:

		inspector_action_button.add_theme_stylebox_override(
			"normal",
			create_button_style(
				COLOR_GREEN_DARK,
				COLOR_GREEN
			)
		)


# ==================================================
# COURSE INFORMATION
# ==================================================

func update_course_information() -> void:

	var completed: int = (
		course_manager.get_completed_hole_count()
	)

	var total_distance: int = (
		course_manager.get_total_course_distance(
			property_manager.CELL_SIZE
		)
	)

	var total_par: int = (
		course_manager.get_total_course_par(
			property_manager.CELL_SIZE
		)
	)

	course_label.text = (
		str(completed)
		+ " / "
		+ str(course_manager.TOTAL_HOLES)
		+ " HOLES"
		+ "  •  "
		+ str(total_distance)
		+ " FT"
		+ "  •  PAR "
		+ str(total_par)
	)


# ==================================================
# ECONOMY
# ==================================================

func update_economy_information() -> void:

	money_label.text = (
		economy_manager.format_money(
			economy_manager.get_cash()
		)
	)


# ==================================================
# WORKFORCE INFORMATION
# ==================================================

func update_workforce_information() -> void:

	if job_manager == null:
		return

	if workers_button == null:
		return

	var total_workers: int = (
		job_manager.get_worker_count()
	)

	var working_workers: int = (
		job_manager.get_working_worker_count()
	)

	workers_button.text = (
		"WORKERS\n"
		+ str(working_workers)
		+ " / "
		+ str(total_workers)
	)

	if job_manager.get_queued_job_count() > 0:

		workers_button.add_theme_color_override(
			"font_color",
			COLOR_ORANGE
		)

	else:

		workers_button.add_theme_color_override(
			"font_color",
			COLOR_TEXT
		)


# ==================================================
# UPDATE CREW PANEL
# ==================================================

func update_crew_panel() -> void:

	if job_manager == null:
		return

	if crew_list == null:
		return

	for child in crew_list.get_children():
		child.queue_free()

	var all_workers: Array = (
		job_manager.get_all_workers()
	)

	var working_count: int = (
		job_manager.get_working_worker_count()
	)

	var idle_count: int = (
		job_manager.get_idle_worker_count()
	)

	var queued_count: int = (
		job_manager.get_queued_job_count()
	)

	crew_summary_label.text = (
		str(working_count)
		+ " WORKING  •  "
		+ str(idle_count)
		+ " IDLE  •  "
		+ str(queued_count)
		+ " QUEUED"
	)

	var report_count: int = job_manager.get_worker_observations().size()
	if report_count > 0:
		crew_summary_label.text += "  •  " + str(report_count) + " REPORTS"

	for worker_value in all_workers:

		var worker: Dictionary = (
			worker_value
		)

		create_worker_card(
			worker
		)


# ==================================================
# WORKER CARD
# ==================================================

func create_worker_card(
	worker: Dictionary
) -> void:

	var worker_id: int = int(
		worker.get(
			"id",
			-1
		)
	)

	var card := PanelContainer.new()

	card.custom_minimum_size = Vector2(
		0,
		112
	)

	card.add_theme_stylebox_override(
		"panel",
		create_button_style(
			COLOR_CARD,
			Color(
				1.0,
				1.0,
				1.0,
				0.10
			)
		)
	)

	crew_list.add_child(
		card
	)


	var margin := MarginContainer.new()

	margin.add_theme_constant_override(
		"margin_left",
		16
	)

	margin.add_theme_constant_override(
		"margin_right",
		16
	)

	margin.add_theme_constant_override(
		"margin_top",
		10
	)

	margin.add_theme_constant_override(
		"margin_bottom",
		10
	)

	card.add_child(
		margin
	)


	var box := VBoxContainer.new()

	box.add_theme_constant_override(
		"separation",
		4
	)

	margin.add_child(
		box
	)


	var name_label := Label.new()

	name_label.text = (
		"EMPLOYEE #"
		+ str(worker_id)
	)

	name_label.add_theme_font_size_override(
		"font_size",
		19
	)

	name_label.add_theme_color_override(
		"font_color",
		COLOR_TEXT
	)

	box.add_child(
		name_label
	)


	var status: String = (
		job_manager.get_worker_status_text(
			worker_id
		)
	)

	var status_label := Label.new()

	status_label.text = status

	status_label.add_theme_font_size_override(
		"font_size",
		15
	)

	if status == "Idle":

		status_label.add_theme_color_override(
			"font_color",
			COLOR_MUTED
		)

	elif status == "Traveling":

		status_label.add_theme_color_override(
			"font_color",
			COLOR_ORANGE
		)

	else:

		status_label.add_theme_color_override(
			"font_color",
			COLOR_GREEN
		)

	box.add_child(
		status_label
	)

	var report_text: String = str(worker.get("observation", ""))
	if not report_text.is_empty():
		var report_label := Label.new()
		report_label.text = "REPORT: " + report_text
		report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		report_label.add_theme_font_size_override("font_size", 14)
		report_label.add_theme_color_override("font_color", COLOR_GOLD)
		box.add_child(report_label)


	var job_id: int = int(
		worker.get(
			"job_id",
			-1
		)
	)

	if job_id < 0:

		var available_label := Label.new()

		available_label.text = (
			"Available for work"
		)

		available_label.add_theme_font_size_override(
			"font_size",
			13
		)

		available_label.add_theme_color_override(
			"font_color",
			COLOR_MUTED
		)

		box.add_child(
			available_label
		)

		return


	var job: Dictionary = (
		job_manager.get_job_by_id(
			job_id
		)
	)

	if job.is_empty():
		return


	var progress: float = (
		job_manager.get_job_progress(
			job_id
		)
	)


	var job_label := Label.new()

	job_label.text = (
		"Work Order #"
		+ str(job_id)
		+ "  •  "
		+ str(
			int(
				round(
					progress
					* 100.0
				)
			)
		)
		+ "%"
	)

	job_label.add_theme_font_size_override(
		"font_size",
		13
	)

	job_label.add_theme_color_override(
		"font_color",
		COLOR_MUTED
	)

	box.add_child(
		job_label
	)

# ==================================================
# UPDATE 11: STYLE 2 — LEFT COMMAND SIDEBAR
# ==================================================
# Existing tool actions and state machines remain authoritative.
# The original bottom dock stays instantiated (for compatibility),
# but is hidden in favor of this compact, touch-friendly command rail.

func create_empire_sidebar() -> void:
	if tool_dock != null:
		tool_dock.hide()

	empire_sidebar = PanelContainer.new()
	empire_sidebar.name = "EmpireCommandSidebar"
	empire_sidebar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	empire_sidebar.add_theme_stylebox_override("panel", create_floating_panel_style())
	add_child(empire_sidebar)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	empire_sidebar.add_child(outer)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	outer.add_child(heading)

	# Long-press and drag this grip to reposition the whole toolbar vertically.
	empire_sidebar_drag_handle = create_ui_button("↕", Vector2(72, 76))
	empire_sidebar_drag_handle.tooltip_text = "Hold and drag up or down to move toolbar"
	empire_sidebar_drag_handle.gui_input.connect(_on_empire_drag_input)
	heading.add_child(empire_sidebar_drag_handle)

	empire_sidebar_toggle = create_ui_button("≡  TOOLS", Vector2(0, 76))
	empire_sidebar_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empire_sidebar_toggle.pressed.connect(toggle_empire_sidebar)
	heading.add_child(empire_sidebar_toggle)

	empire_sidebar_scroll = ScrollContainer.new()
	empire_sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empire_sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(empire_sidebar_scroll)

	empire_sidebar_content = VBoxContainer.new()
	empire_sidebar_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empire_sidebar_content.add_theme_constant_override("separation", 7)
	empire_sidebar_scroll.add_child(empire_sidebar_content)

	add_empire_sidebar_caption("COURSE DESIGN")
	add_empire_sidebar_button("tee", "   Tee Pad", _on_tee_pressed)
	add_empire_sidebar_button("basket", "   Basket", _on_basket_pressed)
	add_empire_sidebar_button("path", "   Path", _on_path_pressed)
	add_empire_sidebar_caption("GROUNDSKEEPING")
	add_empire_sidebar_button("mower", "   Mower", _on_mower_pressed)
	add_empire_sidebar_button("brush", "   Brush Cutter", _on_brush_pressed)
	add_empire_sidebar_button("chainsaw", "   Chainsaw", _on_chainsaw_pressed)
	add_empire_sidebar_caption("MANAGEMENT")
	add_empire_sidebar_button("view", "◉  Inspect", _on_view_pressed)
	add_empire_sidebar_button("crew", "♟  Grounds Crew", _on_workers_pressed)
	add_empire_sidebar_button("camera", "⌖  Reset Camera", _on_reset_camera_pressed)

	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 5)
	empire_sidebar_content.add_child(navigation)
	var back := create_ui_button("‹ HOLE", Vector2(0, 76))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_on_previous_hole_pressed)
	navigation.add_child(back)
	empire_sidebar_buttons["previous"] = back
	var forward := create_ui_button("HOLE ›", Vector2(0, 76))
	forward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forward.pressed.connect(_on_next_hole_pressed)
	navigation.add_child(forward)
	empire_sidebar_buttons["next"] = forward

	# Radio stays at the bottom of the command bar, outside its scroll region.
	var radio_strip := VBoxContainer.new()
	radio_strip.add_theme_constant_override("separation", 3)
	outer.add_child(radio_strip)
	empire_sidebar_radio_title = create_ui_button("♫  RADIO  ▴", Vector2(0, 62))
	empire_sidebar_radio_title.pressed.connect(_on_empire_radio_open)
	radio_strip.add_child(empire_sidebar_radio_title)
	var radio_buttons := HBoxContainer.new()
	radio_buttons.add_theme_constant_override("separation", 4)
	radio_strip.add_child(radio_buttons)
	var prev_radio := create_ui_button("◀", Vector2(0, 62))
	prev_radio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_radio.pressed.connect(_on_empire_radio_previous)
	radio_buttons.add_child(prev_radio)
	empire_sidebar_radio_play = create_ui_button("Ⅱ", Vector2(0, 62))
	empire_sidebar_radio_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empire_sidebar_radio_play.pressed.connect(_on_empire_radio_play)
	radio_buttons.add_child(empire_sidebar_radio_play)
	var next_radio := create_ui_button("▶", Vector2(0, 62))
	next_radio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_radio.pressed.connect(_on_empire_radio_next)
	radio_buttons.add_child(next_radio)
	refresh_empire_sidebar()

func add_empire_sidebar_caption(caption_text: String) -> void:
	var caption := Label.new()
	caption.text = caption_text
	caption.add_theme_font_size_override("font_size", 21)
	caption.add_theme_color_override("font_color", COLOR_GOLD)
	empire_sidebar_content.add_child(caption)

func add_empire_sidebar_button(key: String, title: String, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	empire_sidebar_content.add_child(row)
	var button := create_ui_button(title, Vector2(0, 77))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 27)
	button.pressed.connect(callback)
	row.add_child(button)
	empire_sidebar_buttons[key] = button
	var hint := Label.new()
	hint.visible = false
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 19)
	hint.add_theme_color_override("font_color", COLOR_GOLD)
	hint.custom_minimum_size = Vector2(135, 0)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	empire_sidebar_hints[key] = hint

func get_empire_tool_hint(tool_key: String) -> String:
	match tool_key:
		"tee": return "Drag to place tee"
		"basket": return "Drag to place basket"
		"path": return "Shape flight path"
		"mower": return "Drag to mow grass"
		"brush": return "Drag to clear brush"
		"chainsaw": return "Tap tree to remove"
		"view": return "Tap item to inspect"
	return ""

func toggle_empire_sidebar() -> void:
	empire_sidebar_collapsed = not empire_sidebar_collapsed
	apply_empire_sidebar_layout()

func apply_empire_sidebar_layout() -> void:
	if empire_sidebar == null:
		return
	var screen_width: float = get_viewport().get_visible_rect().size.x
	var compact_width: float = 87.0
	var expanded_width: float = minf(535.0, maxf(330.0, screen_width * 0.44))
	var width: float = compact_width if empire_sidebar_collapsed else expanded_width
	empire_sidebar.anchor_left = 0.0
	empire_sidebar.anchor_right = 0.0
	empire_sidebar.anchor_top = 0.0
	empire_sidebar.anchor_bottom = 1.0
	empire_sidebar.offset_left = 12.0
	empire_sidebar.offset_right = 12.0 + width
	var screen_height: float = get_viewport().get_visible_rect().size.y
	var bar_height: float = maxf(320.0, screen_height - 171.0)
	empire_sidebar_top_offset = clampf(empire_sidebar_top_offset, 115.0, maxf(115.0, screen_height - 250.0))
	empire_sidebar.offset_top = empire_sidebar_top_offset
	empire_sidebar.offset_bottom = minf(screen_height - 12.0, empire_sidebar_top_offset + bar_height) - screen_height
	empire_sidebar.custom_minimum_size = Vector2.ZERO
	empire_sidebar_scroll.visible = not empire_sidebar_collapsed
	empire_sidebar_toggle.text = "☰" if empire_sidebar_collapsed else "≡  TOOLS  ‹"
	if empire_sidebar_drag_handle != null:
		empire_sidebar_drag_handle.text = "↕"
	if inspector_panel != null:
		inspector_panel.offset_left = 110.0 if empire_sidebar_collapsed else width + 28.0
		# About 65% of the crew panel footprint, as requested.
		var crew_width: float = 580.0
		if crew_panel != null:
			crew_width = crew_panel.offset_right - crew_panel.offset_left
		inspector_panel.offset_right = inspector_panel.offset_left + crew_width * 0.68

func refresh_empire_sidebar() -> void:
	if empire_sidebar == null or course_builder == null:
		return
	var tool_name: String = course_builder.get_current_tool_name()
	var tool_keys := {"tee": "TEE", "basket": "BASKET", "path": "PATH", "mower": "MOWER", "brush": "BRUSH", "chainsaw": "CHAINSAW", "view": "VIEW"}
	for key in tool_keys:
		var button: Button = empire_sidebar_buttons.get(key)
		var is_active: bool = tool_name == tool_keys[key]
		if button != null:
			apply_tool_button_style(button, is_active)
			button.add_theme_color_override("font_color", COLOR_GOLD if is_active else COLOR_TEXT)
		var hint: Label = empire_sidebar_hints.get(key)
		if hint != null:
			hint.visible = is_active
			if is_active:
				hint.text = get_empire_tool_hint(key)
	if tooltip_panel != null:
		tooltip_panel.hide()
	var radio_node = get_parent().get_node_or_null("RadioManager")
	if radio_node != null and empire_sidebar_radio_play != null:
		empire_sidebar_radio_play.text = "▶" if radio_node.player != null and radio_node.player.stream_paused else "Ⅱ"
	var previous: Button = empire_sidebar_buttons.get("previous")
	var following: Button = empire_sidebar_buttons.get("next")
	if previous != null and course_manager != null:
		previous.disabled = course_manager.selected_hole <= 0
	if following != null and course_manager != null:
		following.disabled = course_manager.selected_hole >= course_manager.TOTAL_HOLES - 1


# ==================================================
# UPDATE 13: DRAGGABLE SIDEBAR AND DOCKED RADIO
# ==================================================

func _on_empire_drag_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			empire_drag_active = true
			empire_drag_last_y = event.position.y
		else:
			empire_drag_active = false
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and empire_drag_active:
		empire_sidebar_top_offset += event.relative.y
		empire_drag_last_y = event.position.y
		apply_empire_sidebar_layout()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		empire_drag_active = event.pressed
		empire_drag_last_y = event.position.y
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and empire_drag_active:
		empire_sidebar_top_offset += event.relative.y
		empire_drag_last_y = event.position.y
		apply_empire_sidebar_layout()
		get_viewport().set_input_as_handled()

func _get_empire_radio():
	return get_parent().get_node_or_null("RadioManager")

func _on_empire_radio_open() -> void:
	var radio = _get_empire_radio()
	if radio != null:
		radio.toggle_expanded()

func _on_empire_radio_previous() -> void:
	var radio = _get_empire_radio()
	if radio != null:
		radio.previous_track()

func _on_empire_radio_play() -> void:
	var radio = _get_empire_radio()
	if radio != null:
		radio.toggle_pause()
		refresh_empire_sidebar()

func _on_empire_radio_next() -> void:
	var radio = _get_empire_radio()
	if radio != null:
		radio.next_track()
