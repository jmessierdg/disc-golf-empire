class_name CameraController
extends Camera2D


# ==================================================
# CAMERA SETTINGS
# ==================================================

const MIN_ZOOM := 0.25
const MAX_ZOOM := 2.5
const ZOOM_SPEED := 0.004
const DEFAULT_ZOOM := 0.45

# Extra breathing room inside the camera boundary.
# This prevents the very edge of the generated world
# from becoming visible.

const WORLD_EDGE_PADDING := 80.0


# ==================================================
# REFERENCES
# ==================================================

var property_manager = null


# ==================================================
# TOUCH DATA
# ==================================================

var touches: Dictionary = {}

var last_pinch_distance: float = 0.0

var camera_input_enabled: bool = true


# ==================================================
# SETUP
# ==================================================

func setup(
	starting_position: Vector2,
	property_ref = null
) -> void:

	property_manager = property_ref

	position = starting_position

	zoom = Vector2(
		DEFAULT_ZOOM,
		DEFAULT_ZOOM
	)

	clamp_camera()


# ==================================================
# SET PROPERTY MANAGER
# ==================================================

func set_property_manager(
	property_ref
) -> void:

	property_manager = property_ref

	clamp_camera()


# ==================================================
# ENABLE / DISABLE CAMERA INPUT
# ==================================================

func set_camera_input_enabled(
	input_active: bool
) -> void:

	camera_input_enabled = input_active

	if not input_active:

		touches.clear()

		last_pinch_distance = 0.0


# ==================================================
# REGISTER TOUCH
# ==================================================

func register_touch(
	touch_index: int,
	screen_position: Vector2
) -> void:

	if not camera_input_enabled:
		return

	touches[touch_index] = (
		screen_position
	)


# ==================================================
# RELEASE TOUCH
# ==================================================

func release_touch(
	touch_index: int
) -> void:

	touches.erase(
		touch_index
	)

	if touches.size() < 2:

		last_pinch_distance = 0.0


# ==================================================
# HANDLE DRAG
# ==================================================

func handle_drag(
	touch_index: int,
	screen_position: Vector2,
	relative_motion: Vector2
) -> void:

	if not camera_input_enabled:
		return


	touches[touch_index] = (
		screen_position
	)


	# --------------------------------------------------
	# ONE FINGER = PAN
	# --------------------------------------------------

	if touches.size() == 1:

		position -= (
			relative_motion
			/ zoom.x
		)

		clamp_camera()

		return


	# --------------------------------------------------
	# TWO FINGERS = PINCH ZOOM
	# --------------------------------------------------

	if touches.size() == 2:

		handle_pinch_zoom()


# ==================================================
# PINCH ZOOM
# ==================================================

func handle_pinch_zoom() -> void:

	var touch_positions: Array = (
		touches.values()
	)

	if touch_positions.size() != 2:
		return


	var first_touch: Vector2 = (
		touch_positions[0]
	)

	var second_touch: Vector2 = (
		touch_positions[1]
	)


	var current_distance: float = (
		first_touch.distance_to(
			second_touch
		)
	)


	if last_pinch_distance > 0.0:

		var difference: float = (
			current_distance
			- last_pinch_distance
		)


		var new_zoom: float = (
			zoom.x
			+
			difference
			* ZOOM_SPEED
		)


		new_zoom = get_safe_zoom(
			new_zoom
		)


		zoom = Vector2(
			new_zoom,
			new_zoom
		)


		clamp_camera()


	last_pinch_distance = (
		current_distance
	)


# ==================================================
# SAFE ZOOM
# ==================================================

func get_safe_zoom(
	requested_zoom: float
) -> float:

	var safe_zoom: float = clamp(
		requested_zoom,
		MIN_ZOOM,
		MAX_ZOOM
	)


	if property_manager == null:
		return safe_zoom


	var camera_rect: Rect2 = (
		get_camera_bounds()
	)


	if (
		camera_rect.size.x <= 0.0
		or
		camera_rect.size.y <= 0.0
	):
		return safe_zoom


	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)


	if (
		viewport_size.x <= 0.0
		or
		viewport_size.y <= 0.0
	):
		return safe_zoom


	# --------------------------------------------------
	# MINIMUM ZOOM REQUIRED TO KEEP THE VIEWPORT
	# INSIDE THE GENERATED WORLD
	# --------------------------------------------------

	var minimum_zoom_x: float = (
		viewport_size.x
		/ camera_rect.size.x
	)

	var minimum_zoom_y: float = (
		viewport_size.y
		/ camera_rect.size.y
	)


	var boundary_minimum_zoom: float = max(
		minimum_zoom_x,
		minimum_zoom_y
	)


	safe_zoom = max(
		safe_zoom,
		boundary_minimum_zoom
	)


	safe_zoom = min(
		safe_zoom,
		MAX_ZOOM
	)


	return safe_zoom


# ==================================================
# CAMERA BOUNDS
# ==================================================

func get_camera_bounds() -> Rect2:

	if property_manager == null:

		return Rect2()


	var bounds: Rect2


	# --------------------------------------------------
	# PREFERRED CAMERA WORLD RECT
	# --------------------------------------------------

	if property_manager.has_method(
		"get_camera_world_rect"
	):

		bounds = (
			property_manager.get_camera_world_rect()
		)


	# --------------------------------------------------
	# FALLBACK TO FULL WORLD
	# --------------------------------------------------

	elif property_manager.has_method(
		"get_world_rect"
	):

		bounds = (
			property_manager.get_world_rect()
		)


	else:

		return Rect2()


	# --------------------------------------------------
	# KEEP THE CAMERA SLIGHTLY AWAY FROM THE RAW
	# GENERATED WORLD EDGE
	# --------------------------------------------------

	var padding: float = min(
		WORLD_EDGE_PADDING,
		min(
			bounds.size.x * 0.08,
			bounds.size.y * 0.08
		)
	)


	if (
		bounds.size.x > padding * 2.0
		and
		bounds.size.y > padding * 2.0
	):

		bounds = Rect2(
			bounds.position
			+
			Vector2(
				padding,
				padding
			),
			bounds.size
			-
			Vector2(
				padding * 2.0,
				padding * 2.0
			)
		)


	return bounds


# ==================================================
# CLAMP CAMERA
# ==================================================

func clamp_camera() -> void:

	if property_manager == null:
		return


	var bounds: Rect2 = (
		get_camera_bounds()
	)


	if (
		bounds.size.x <= 0.0
		or
		bounds.size.y <= 0.0
	):
		return


	var viewport_size: Vector2 = (
		get_viewport_rect().size
	)


	if (
		viewport_size.x <= 0.0
		or
		viewport_size.y <= 0.0
	):
		return


	var safe_zoom: float = (
		get_safe_zoom(
			zoom.x
		)
	)


	if not is_equal_approx(
		safe_zoom,
		zoom.x
	):

		zoom = Vector2(
			safe_zoom,
			safe_zoom
		)


	# --------------------------------------------------
	# HOW MUCH WORLD IS CURRENTLY VISIBLE?
	# --------------------------------------------------

	var visible_world_size: Vector2 = (
		viewport_size
		/ zoom.x
	)


	var half_visible: Vector2 = (
		visible_world_size
		/ 2.0
	)


	# --------------------------------------------------
	# X LIMITS
	# --------------------------------------------------

	var minimum_x: float = (
		bounds.position.x
		+
		half_visible.x
	)

	var maximum_x: float = (
		bounds.end.x
		-
		half_visible.x
	)


	# --------------------------------------------------
	# Y LIMITS
	# --------------------------------------------------

	var minimum_y: float = (
		bounds.position.y
		+
		half_visible.y
	)

	var maximum_y: float = (
		bounds.end.y
		-
		half_visible.y
	)


	# --------------------------------------------------
	# IF THE VIEWPORT IS LARGER THAN A DIMENSION,
	# LOCK THAT AXIS TO THE CENTER.
	# --------------------------------------------------

	var new_x: float = position.x

	var new_y: float = position.y


	if minimum_x > maximum_x:

		new_x = (
			bounds.position.x
			+
			bounds.size.x * 0.5
		)

	else:

		new_x = clamp(
			position.x,
			minimum_x,
			maximum_x
		)


	if minimum_y > maximum_y:

		new_y = (
			bounds.position.y
			+
			bounds.size.y * 0.5
		)

	else:

		new_y = clamp(
			position.y,
			minimum_y,
			maximum_y
		)


	position = Vector2(
		new_x,
		new_y
	)


# ==================================================
# SCREEN TO WORLD
# ==================================================

func screen_to_world(
	screen_position: Vector2
) -> Vector2:

	var viewport_center: Vector2 = (
		get_viewport_rect().size
		/ 2.0
	)


	var world_position: Vector2 = (
		get_screen_center_position()
		+
		(
			screen_position
			- viewport_center
		)
		/ zoom.x
	)


	return world_position


# ==================================================
# RESET CAMERA
# ==================================================

func reset_camera(
	target_position: Vector2
) -> void:

	position = target_position


	var safe_default_zoom: float = (
		get_safe_zoom(
			DEFAULT_ZOOM
		)
	)


	zoom = Vector2(
		safe_default_zoom,
		safe_default_zoom
	)


	touches.clear()

	last_pinch_distance = 0.0


	clamp_camera()