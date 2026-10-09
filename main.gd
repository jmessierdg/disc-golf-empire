# main.gd
extends Node2D


# ==================================================
# COMPONENT SCRIPTS
# ==================================================

const PROPERTY_MANAGER_SCRIPT = preload(
	"res://property_manager.gd"
)

const COURSE_MANAGER_SCRIPT = preload(
	"res://course_manager.gd"
)

const ECONOMY_MANAGER_SCRIPT = preload(
	"res://economy_manager.gd"
)

const JOB_MANAGER_SCRIPT = preload(
	"res://job_manager.gd"
)

const COURSE_RENDERER_SCRIPT = preload(
	"res://course_renderer.gd"
)

const CAMERA_CONTROLLER_SCRIPT = preload(
	"res://camera_controller.gd"
)

const COURSE_BUILDER_SCRIPT = preload(
	"res://course_builder.gd"
)

const COURSE_UI_SCRIPT = preload(
	"res://course_ui.gd"
)

const PATH_MANAGER_SCRIPT = preload("res://path_manager.gd")
const GOLFER_MANAGER_PATH := "res://golfer_manager.gd"
const HUD_MANAGER_PATH := "res://hud_manager.gd"

const RADIO_MANAGER_SCRIPT = preload(
	"res://radio_manager.gd"
)


# ==================================================
# COMPONENTS
# ==================================================

var property_manager
var course_manager
var economy_manager
var job_manager
var course_renderer
var camera_controller
var course_builder
var course_ui
var radio_manager
var path_manager
var golfer_manager
var hud_manager


# ==================================================
# INPUT STATE
# ==================================================

var active_screen_touches: Dictionary = {}
var builder_consumed_touch: Dictionary = {}


# ==================================================
# STARTUP
# ==================================================

func _ready() -> void:

	create_components()


# ==================================================
# CREATE COMPONENTS
# ==================================================

func create_components() -> void:

	# --------------------------------------------------
	# PROPERTY
	# --------------------------------------------------

	property_manager = (
		PROPERTY_MANAGER_SCRIPT.new()
	)

	property_manager.name = (
		"PropertyManager"
	)

	add_child(
		property_manager
	)


	# --------------------------------------------------
	# COURSE
	# --------------------------------------------------

	course_manager = (
		COURSE_MANAGER_SCRIPT.new()
	)

	course_manager.name = (
		"CourseManager"
	)

	add_child(
		course_manager
	)


	# --------------------------------------------------
	# ECONOMY
	# --------------------------------------------------

	economy_manager = (
		ECONOMY_MANAGER_SCRIPT.new()
	)

	economy_manager.name = (
		"EconomyManager"
	)

	add_child(
		economy_manager
	)

	economy_manager.setup()


	# --------------------------------------------------
	# RENDERER
	# --------------------------------------------------

	course_renderer = (
		COURSE_RENDERER_SCRIPT.new()
	)

	course_renderer.name = (
		"CourseRenderer"
	)

	add_child(
		course_renderer
	)


	# --------------------------------------------------
	# JOB MANAGER
	# --------------------------------------------------

	job_manager = (
		JOB_MANAGER_SCRIPT.new()
	)

	job_manager.name = (
		"JobManager"
	)

	add_child(
		job_manager
	)


	# --------------------------------------------------
	# CAMERA
	# --------------------------------------------------

	camera_controller = (
		CAMERA_CONTROLLER_SCRIPT.new()
	)

	camera_controller.name = (
		"CameraController"
	)

	add_child(
		camera_controller
	)


	# --------------------------------------------------
	# BUILDER
	# --------------------------------------------------

	course_builder = (
		COURSE_BUILDER_SCRIPT.new()
	)

	course_builder.name = (
		"CourseBuilder"
	)

	add_child(
		course_builder
	)


	# --------------------------------------------------
	# CONNECT GAME SYSTEMS
	# --------------------------------------------------

	course_renderer.setup(
		property_manager,
		course_manager
	)


	job_manager.setup(
		property_manager,
		course_renderer,
		economy_manager
	)


	course_renderer.set_job_manager(
		job_manager
	)


	camera_controller.setup(
		property_manager.get_property_world_center(),
		property_manager
	)


	course_builder.setup(
		course_manager,
		property_manager,
		course_renderer,
		camera_controller,
		economy_manager,
		job_manager
	)


	# --------------------------------------------------
	# USER INTERFACE
	# --------------------------------------------------

	course_ui = (
		COURSE_UI_SCRIPT.new()
	)

	course_ui.name = (
		"CourseUI"
	)

	add_child(
		course_ui
	)


	course_ui.setup(
		course_manager,
		economy_manager,
		course_builder,
		property_manager,
		camera_controller,
		course_renderer
	)


	# Walkway construction is independent from flight-path editing.
	path_manager = PATH_MANAGER_SCRIPT.new()
	path_manager.name = "PathManager"
	# Ground is z=0; paths z=1; vegetation z=2; holes z=3; actors z=4.
	path_manager.z_index = 1
	add_child(path_manager)
	path_manager.setup(property_manager, economy_manager, job_manager, course_manager)
	job_manager.set_walkway_manager(path_manager)
	course_ui.set_walkway_manager(path_manager)

	# Persistent visitors draw independently of retained terrain layers.
	# Golfer simulation is optional at boot; it must not prevent the park from loading.
	if ResourceLoader.exists(GOLFER_MANAGER_PATH):
		var golfer_script = load(GOLFER_MANAGER_PATH)
		if golfer_script != null and golfer_script.can_instantiate():
			golfer_manager = golfer_script.new()
			golfer_manager.name = "GolferManager"
			add_child(golfer_manager)
			golfer_manager.setup(property_manager, course_manager, path_manager)
		else:
			push_warning("Golfer script failed to load; park remains playable.")
	else:
		push_warning("Golfer script missing; park remains playable.")

	# Disc Golf Empire Radio runs independently of gameplay UI.
	radio_manager = RADIO_MANAGER_SCRIPT.new()
	radio_manager.name = "RadioManager"
	add_child(radio_manager)

	# Mobile-first management HUD; existing gameplay UI remains functional.
	# Load HUD after the working CourseUI is initialized.
	# If the optional HUD cannot load, the original controls remain available.
	if ResourceLoader.exists(HUD_MANAGER_PATH):
		var hud_script = load(HUD_MANAGER_PATH)
		if hud_script != null and hud_script.can_instantiate():
			hud_manager = hud_script.new()
			hud_manager.name = "HUDManager"
			add_child(hud_manager)
			hud_manager.setup(course_ui, course_manager, economy_manager, job_manager, golfer_manager, radio_manager, camera_controller)
		else:
			push_warning("HUD failed to load; original CourseUI remains available.")
	else:
		push_warning("HUD script missing; original CourseUI remains available.")


# ==================================================
# INPUT
# ==================================================

func _unhandled_input(
	event: InputEvent
) -> void:

	if event is InputEventScreenTouch:

		var touch_event: InputEventScreenTouch = (
			event
		)

		if touch_event.pressed:

			handle_touch_pressed(
				touch_event
			)

		else:

			handle_touch_released(
				touch_event
			)

		return


	if event is InputEventScreenDrag:

		var drag_event: InputEventScreenDrag = (
			event
		)

		handle_touch_dragged(
			drag_event
		)


# ==================================================
# TOUCH PRESSED
# ==================================================

func handle_touch_pressed(
	touch_event: InputEventScreenTouch
) -> void:

	active_screen_touches[
		touch_event.index
	] = touch_event.position


	if active_screen_touches.size() >= 2:

		# A second finger always means camera navigation.
		# End the current edit gesture without discarding the pending edit.
		course_builder.suspend_active_gesture_for_camera()

		for touch_key in active_screen_touches.keys():

			builder_consumed_touch[
				touch_key
			] = false

			camera_controller.register_touch(
				touch_key,
				active_screen_touches[touch_key]
			)

		return


	if path_manager != null and path_manager.editing:
		var waypoint_world: Vector2 = camera_controller.screen_to_world(touch_event.position)
		if path_manager.add_point(waypoint_world):
			builder_consumed_touch[touch_event.index] = true
			course_ui.update_interface()
			return

	# Tapping a visible golfer opens that persistent person profile.
	if golfer_manager != null:
		var tapped_world: Vector2 = camera_controller.screen_to_world(touch_event.position)
		if golfer_manager.select_at(tapped_world):
			builder_consumed_touch[touch_event.index] = true
			return

	var builder_used_touch: bool = (
		course_builder.touch_pressed(
			touch_event.index,
			touch_event.position
		)
	)


	builder_consumed_touch[
		touch_event.index
	] = builder_used_touch


	if not builder_used_touch:

		camera_controller.register_touch(
			touch_event.index,
			touch_event.position
		)


	course_ui.update_interface()


# ==================================================
# TOUCH DRAGGED
# ==================================================

func handle_touch_dragged(
	drag_event: InputEventScreenDrag
) -> void:

	active_screen_touches[
		drag_event.index
	] = drag_event.position


	var builder_used_touch: bool = false


	if builder_consumed_touch.has(
		drag_event.index
	):

		builder_used_touch = (
			builder_consumed_touch[
				drag_event.index
			]
		)


	if builder_used_touch and path_manager != null and path_manager.editing:
		return
	if builder_used_touch:

		course_builder.touch_dragged(
			drag_event.index,
			drag_event.position
		)

		# IMPORTANT:
		# Do not rebuild the entire UI every time the finger moves.
		# The builder/renderer already handles the live visual preview.

		return


	camera_controller.handle_drag(
		drag_event.index,
		drag_event.position,
		drag_event.relative
	)


# ==================================================
# TOUCH RELEASED
# ==================================================

func handle_touch_released(
	touch_event: InputEventScreenTouch
) -> void:

	var builder_used_touch: bool = false


	if builder_consumed_touch.has(
		touch_event.index
	):

		builder_used_touch = (
			builder_consumed_touch[
				touch_event.index
			]
		)


	if builder_used_touch and path_manager != null and path_manager.editing:
		pass
	elif builder_used_touch:

		course_builder.touch_released(
			touch_event.index
		)

	else:

		camera_controller.release_touch(
			touch_event.index
		)


	active_screen_touches.erase(
		touch_event.index
	)

	builder_consumed_touch.erase(
		touch_event.index
	)


	course_ui.update_interface()