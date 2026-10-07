class_name CourseBuilder
extends Node


# ==================================================
# SIGNALS
# ==================================================

signal viewed_object_changed(object_data: Dictionary)
signal pending_edit_changed(pending: bool)


# ==================================================
# TOOL TYPES
# ==================================================

enum Tool {
	NONE,
	TEE,
	BASKET,
	PATH,
	MOWER,
	BRUSH,
	CHAINSAW,
	VIEW
}


# ==================================================
# VIEW TYPES
# ==================================================

const VIEW_NONE := ""
const VIEW_TREE := "tree"
const VIEW_TEE := "tee"
const VIEW_BASKET := "basket"
const VIEW_PATH_POINT := "path_point"


# ==================================================
# LANDSCAPING
# ==================================================

const MOWER_RADIUS := 16.0
const BRUSH_RADIUS := 22.0

# Smaller values make fast finger movement fill in more
# intermediate positions.
const LANDSCAPE_SAMPLE_DISTANCE := 6.0


# ==================================================
# REFERENCES
# ==================================================

var course_manager
var property_manager
var course_renderer
var camera_controller
var economy_manager
var job_manager


# ==================================================
# TOOL STATE
# ==================================================

var current_tool: int = Tool.NONE

var active_touch_index: int = -1

var dragging_path_point := false
var dragged_path_point_index := -1

var dragging_tee := false
var dragging_basket := false

var landscaping_active := false

# Selected cells for the current landscaping work order.
var landscape_selected_cells: Array[Vector2i] = []

# Dictionary gives us very fast duplicate checking.
var landscape_selected_lookup: Dictionary = {}

var last_landscape_local_position := Vector2.ZERO
var has_last_landscape_position := false

var viewed_object: Dictionary = {}

# Pending transaction state.
# Edits stay live so the player can keep painting/moving things, but they
# are not committed until the checkmark is pressed.
var pending_edit_active := false
var pending_course_snapshot: Array = []
var pending_economy_snapshot: Dictionary = {}

var pending_mow_cells: Array[Vector2i] = []
var pending_mow_lookup: Dictionary = {}

var pending_brush_cells: Array[Vector2i] = []
var pending_brush_lookup: Dictionary = {}


# ==================================================
# SETUP
# ==================================================

func setup(
	course_ref,
	property_ref,
	renderer_ref,
	camera_ref,
	economy_ref,
	job_ref
) -> void:
	course_manager = course_ref
	property_manager = property_ref
	course_renderer = renderer_ref
	camera_controller = camera_ref
	economy_manager = economy_ref
	job_manager = job_ref

	current_tool = Tool.NONE

	clear_drag_state()
	clear_viewed_object()


# ==================================================
# SET TOOL
# ==================================================

func set_tool(
	new_tool: int
) -> void:
	if current_tool == new_tool:
		current_tool = Tool.NONE
	else:
		current_tool = new_tool

	clear_active_gesture()
	clear_viewed_object()

	if course_renderer != null:
		var show_handles: bool = (
			current_tool == Tool.PATH
			or current_tool == Tool.VIEW
		)

		course_renderer.set_path_edit_mode(
			show_handles
		)

		course_renderer.refresh()


# ==================================================
# TOOL HELPERS
# ==================================================

func select_none_tool() -> void:
	set_tool(Tool.NONE)


func select_tee_tool() -> void:
	set_tool(Tool.TEE)


func select_basket_tool() -> void:
	set_tool(Tool.BASKET)


func select_path_tool() -> void:
	set_tool(Tool.PATH)


func select_mower_tool() -> void:
	set_tool(Tool.MOWER)


func select_brush_tool() -> void:
	set_tool(Tool.BRUSH)


func select_chainsaw_tool() -> void:
	set_tool(Tool.CHAINSAW)


func select_view_tool() -> void:
	set_tool(Tool.VIEW)


func select_delete_tool() -> void:
	select_view_tool()


# ==================================================
# CURRENT TOOL
# ==================================================

func get_current_tool() -> int:
	return current_tool


func get_current_tool_name() -> String:
	match current_tool:
		Tool.TEE:
			return "TEE"

		Tool.BASKET:
			return "BASKET"

		Tool.PATH:
			return "PATH"

		Tool.MOWER:
			return "MOWER"

		Tool.BRUSH:
			return "BRUSH"

		Tool.CHAINSAW:
			return "CHAINSAW"

		Tool.VIEW:
			return "VIEW"

		_:
			return "NONE"


# ==================================================
# TOUCH PRESSED
# ==================================================

func touch_pressed(
	touch_index: int,
	screen_position: Vector2
) -> bool:
	if not references_ready():
		return false

	var world_position: Vector2 = (
		camera_controller.screen_to_world(
			screen_position
		)
	)

	if not property_manager.is_world_position_inside_property(
		world_position
	):
		return false

	active_touch_index = touch_index

	match current_tool:
		Tool.MOWER:
			return handle_landscape_press(
				world_position
			)

		Tool.BRUSH:
			return handle_landscape_press(
				world_position
			)

		Tool.CHAINSAW:
			return handle_chainsaw_press(
				world_position
			)

		Tool.VIEW:
			return handle_view_press(
				world_position
			)

		Tool.PATH:
			return handle_path_press(
				world_position
			)

		Tool.TEE:
			return handle_tee_press(
				world_position
			)

		Tool.BASKET:
			return handle_basket_press(
				world_position
			)

	return false


# ==================================================
# TOUCH DRAGGED
# ==================================================

func touch_dragged(
	touch_index: int,
	screen_position: Vector2
) -> bool:
	if not references_ready():
		return false

	if touch_index != active_touch_index:
		return false

	var world_position: Vector2 = (
		camera_controller.screen_to_world(
			screen_position
		)
	)

	if not property_manager.is_world_position_inside_property(
		world_position
	):
		return true

	var local_position: Vector2 = (
		property_manager.world_to_property_local(
			world_position
		)
	)

	if landscaping_active:
		paint_landscape_segment(
			last_landscape_local_position,
			local_position
		)

		last_landscape_local_position = local_position
		has_last_landscape_position = true

		course_renderer.set_landscape_cursor(
			world_position,
			get_landscape_radius()
		)

		return true

	if dragging_path_point:
		course_manager.move_path_point(
			course_manager.selected_hole,
			dragged_path_point_index,
			local_position
		)

		course_renderer.refresh()
		return true

	if dragging_tee:
		course_manager.set_tee(
			course_manager.selected_hole,
			local_position
		)

		course_renderer.refresh()
		return true

	if dragging_basket:
		course_manager.set_basket(
			course_manager.selected_hole,
			local_position
		)

		course_renderer.refresh()
		return true

	return false


# ==================================================
# TOUCH RELEASED
# ==================================================

func touch_released(
	touch_index: int
) -> bool:
	if touch_index != active_touch_index:
		return false

	var consumed: bool = (
		dragging_path_point
		or dragging_tee
		or dragging_basket
		or landscaping_active
	)

	clear_active_gesture()

	return consumed


# ==================================================
# LANDSCAPING
# ==================================================

func handle_landscape_press(
	world_position: Vector2
) -> bool:
	var local_position: Vector2 = (
		property_manager.world_to_property_local(
			world_position
		)
	)

	begin_pending_edit()

	landscaping_active = true

	last_landscape_local_position = local_position
	has_last_landscape_position = true

	camera_controller.set_camera_input_enabled(
		false
	)

	paint_landscape_at_position(
		local_position
	)

	course_renderer.set_landscape_cursor(
		world_position,
		get_landscape_radius()
	)

	return true


# ==================================================
# PAINT LANDSCAPE SEGMENT
# ==================================================

func paint_landscape_segment(
	start_position: Vector2,
	end_position: Vector2
) -> void:
	if not has_last_landscape_position:
		paint_landscape_at_position(
			end_position
		)
		return

	var distance: float = (
		start_position.distance_to(
			end_position
		)
	)

	if distance <= 0.001:
		paint_landscape_at_position(
			end_position
		)
		return

	var steps: int = max(
		1,
		int(
			ceil(
				distance
				/ LANDSCAPE_SAMPLE_DISTANCE
			)
		)
	)

	for i in range(
		steps + 1
	):
		var amount: float = (
			float(i)
			/ float(steps)
		)

		var sample_position: Vector2 = (
			start_position.lerp(
				end_position,
				amount
			)
		)

		paint_landscape_at_position(
			sample_position
		)


# ==================================================
# PAINT AT POSITION
# ==================================================

func paint_landscape_at_position(
	local_position: Vector2
) -> void:
	var radius: float = (
		get_landscape_radius()
	)

	if radius <= 0.0:
		return

	var cell_size: float = (
		property_manager.CELL_SIZE
	)

	var center_cell := Vector2i(
		int(
			floor(
				local_position.x
				/ cell_size
			)
		),
		int(
			floor(
				local_position.y
				/ cell_size
			)
		)
	)

	var cell_radius: int = max(
		0,
		int(
			ceil(
				radius
				/ cell_size
			)
		)
	)

	for y_offset in range(
		-cell_radius,
		cell_radius + 1
	):
		for x_offset in range(
			-cell_radius,
			cell_radius + 1
		):
			var cell := Vector2i(
				center_cell.x + x_offset,
				center_cell.y + y_offset
			)

			if not is_valid_landscape_cell(
				cell
			):
				continue

			var cell_center := Vector2(
				(
					float(cell.x)
					+ 0.5
				)
				* cell_size,
				(
					float(cell.y)
					+ 0.5
				)
				* cell_size
			)

			var expanded_radius: float = (
				radius
				+ cell_size * 0.50
			)

			if (
				cell_center.distance_to(
					local_position
				)
				> expanded_radius
			):
				continue

			add_landscape_cell(
				cell
			)


# ==================================================
# VALID LANDSCAPE CELL
# ==================================================

func is_valid_landscape_cell(
	cell: Vector2i
) -> bool:
	if cell.x < 0:
		return false

	if cell.y < 0:
		return false

	if cell.x >= property_manager.GRID_WIDTH:
		return false

	if cell.y >= property_manager.GRID_HEIGHT:
		return false

	var terrain_type: int = (
		property_manager.terrain[
			cell.y
		][
			cell.x
		]
	)

	if current_tool == Tool.MOWER:
		return (
			terrain_type == property_manager.ROUGH
			or terrain_type == property_manager.TALL_GRASS
		)

	if current_tool == Tool.BRUSH:
		return (
			terrain_type == property_manager.WILD_GRASS
		)

	return false


# ==================================================
# ADD LANDSCAPE CELL
# ==================================================

func add_landscape_cell(
	cell: Vector2i
) -> void:
	if landscape_selected_lookup.has(
		cell
	):
		return

	landscape_selected_lookup[
		cell
	] = true

	landscape_selected_cells.append(
		cell
	)

	if current_tool == Tool.MOWER:
		if not pending_mow_lookup.has(cell):
			pending_mow_lookup[cell] = true
			pending_mow_cells.append(cell)

	elif current_tool == Tool.BRUSH:
		if not pending_brush_lookup.has(cell):
			pending_brush_lookup[cell] = true
			pending_brush_cells.append(cell)

	course_renderer.add_landscape_selection_cell(
		cell
	)


# ==================================================
# CREATE LANDSCAPE JOB
# ==================================================

func create_landscape_job() -> void:
	if job_manager == null:
		return

	if not pending_mow_cells.is_empty():
		job_manager.create_mowing_area_job(
			pending_mow_cells
		)

	if not pending_brush_cells.is_empty():
		job_manager.create_brush_area_job(
			pending_brush_cells
		)


func get_landscape_radius() -> float:
	if current_tool == Tool.MOWER:
		return MOWER_RADIUS

	if current_tool == Tool.BRUSH:
		return BRUSH_RADIUS

	return 0.0


# ==================================================
# CHAINSAW
# ==================================================

func handle_chainsaw_press(
	world_position: Vector2
) -> bool:
	var tree_index: int = (
		course_renderer.find_property_tree_at_position(
			world_position
		)
	)

	if tree_index < 0:
		return true

	# Tree jobs come after the area-work system
	# is established.
	return true


# ==================================================
# TEE
# ==================================================

func handle_tee_press(
	world_position: Vector2
) -> bool:
	var hole_index: int = (
		course_manager.selected_hole
	)

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return false

	var tee: Vector2 = hole["tee"]

	begin_pending_edit()

	if tee.x < 0:
		if not economy_manager.acquire_tee_for_placement():
			return true

	var local_position: Vector2 = (
		property_manager.world_to_property_local(
			world_position
		)
	)

	course_manager.set_tee(
		hole_index,
		local_position
	)

	dragging_tee = true

	camera_controller.set_camera_input_enabled(
		false
	)

	course_renderer.refresh()

	return true


# ==================================================
# BASKET
# ==================================================

func handle_basket_press(
	world_position: Vector2
) -> bool:
	var hole_index: int = (
		course_manager.selected_hole
	)

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return false

	var basket: Vector2 = hole["basket"]

	begin_pending_edit()

	if basket.x < 0:
		if not economy_manager.acquire_basket_for_placement():
			return true

	var local_position: Vector2 = (
		property_manager.world_to_property_local(
			world_position
		)
	)

	course_manager.set_basket(
		hole_index,
		local_position
	)

	dragging_basket = true

	camera_controller.set_camera_input_enabled(
		false
	)

	course_renderer.refresh()

	return true


# ==================================================
# PATH
# ==================================================

func handle_path_press(
	world_position: Vector2
) -> bool:
	var hole_index: int = (
		course_manager.selected_hole
	)

	if not course_manager.is_hole_complete(
		hole_index
	):
		return true

	var existing_point: int = (
		course_renderer.find_path_point_at_position(
			hole_index,
			world_position
		)
	)

	if existing_point >= 0:
		start_path_drag(
			existing_point
		)

		return true

	if not course_renderer.is_position_near_path(
		hole_index,
		world_position,
		60.0
	):
		return true

	var nearest_world_position: Vector2 = (
		course_renderer.get_nearest_path_position(
			hole_index,
			world_position
		)
	)

	var nearest_local_position: Vector2 = (
		property_manager.world_to_property_local(
			nearest_world_position
		)
	)

	var insert_index: int = (
		find_path_insert_index(
			hole_index,
			nearest_local_position
		)
	)

	begin_pending_edit()

	var new_point_index: int = (
		course_manager.insert_path_point(
			hole_index,
			insert_index,
			nearest_local_position
		)
	)

	if new_point_index < 0:
		return true

	course_renderer.refresh()

	start_path_drag(
		new_point_index
	)

	return true


func start_path_drag(
	point_index: int
) -> void:
	begin_pending_edit()

	dragging_path_point = true
	dragged_path_point_index = point_index

	camera_controller.set_camera_input_enabled(
		false
	)


func find_path_insert_index(
	hole_index: int,
	new_point: Vector2
) -> int:
	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return 0

	var tee: Vector2 = hole["tee"]
	var basket: Vector2 = hole["basket"]
	var path_points: Array = hole["path_points"]

	var route: Array[Vector2] = []

	route.append(tee)

	for point_value in path_points:
		var route_point: Vector2 = point_value
		route.append(route_point)

	route.append(basket)

	var best_segment := 0
	var best_distance: float = INF

	for i in range(route.size() - 1):
		var nearest_on_segment: Vector2 = (
			Geometry2D.get_closest_point_to_segment(
				new_point,
				route[i],
				route[i + 1]
			)
		)

		var distance_to_segment: float = (
			new_point.distance_to(
				nearest_on_segment
			)
		)

		if distance_to_segment < best_distance:
			best_distance = distance_to_segment
			best_segment = i

	return best_segment


# ==================================================
# VIEW
# ==================================================

func handle_view_press(
	world_position: Vector2
) -> bool:
	var hole_index: int = (
		course_manager.selected_hole
	)

	var path_point_index: int = (
		course_renderer.find_path_point_at_position(
			hole_index,
			world_position
		)
	)

	if path_point_index >= 0:
		set_viewed_object({
			"type": VIEW_PATH_POINT,
			"hole_index": hole_index,
			"index": path_point_index
		})

		return true

	if course_renderer.is_position_near_tee(
		hole_index,
		world_position
	):
		set_viewed_object({
			"type": VIEW_TEE,
			"hole_index": hole_index
		})

		return true

	if course_renderer.is_position_near_basket(
		hole_index,
		world_position
	):
		set_viewed_object({
			"type": VIEW_BASKET,
			"hole_index": hole_index
		})

		return true

	var tree_index: int = (
		course_renderer.find_property_tree_at_position(
			world_position
		)
	)

	if tree_index >= 0:
		var tree_scale: float = (
			property_manager.tree_sizes[
				tree_index
			]
		)

		var removal_cost: int = (
			economy_manager.get_tree_removal_cost(
				tree_scale
			)
		)

		set_viewed_object({
			"type": VIEW_TREE,
			"index": tree_index,
			"scale": tree_scale,
			"removal_cost": removal_cost
		})

		return true

	clear_viewed_object()

	return true


func set_viewed_object(
	object_data: Dictionary
) -> void:
	viewed_object = object_data.duplicate(
		true
	)

	if course_renderer != null:
		course_renderer.set_viewed_object(
			viewed_object
		)

	viewed_object_changed.emit(
		get_viewed_object_info()
	)


func clear_viewed_object() -> void:
	viewed_object.clear()

	if course_renderer != null:
		course_renderer.clear_viewed_object()

	viewed_object_changed.emit({})


# ==================================================
# VIEW INFORMATION
# ==================================================

func get_viewed_object_info() -> Dictionary:
	if viewed_object.is_empty():
		return {}

	var object_type: String = (
		viewed_object.get(
			"type",
			VIEW_NONE
		)
	)

	match object_type:
		VIEW_TREE:
			return get_tree_view_info()

		VIEW_TEE:
			return get_tee_view_info()

		VIEW_BASKET:
			return get_basket_view_info()

		VIEW_PATH_POINT:
			return get_path_point_view_info()

	return {}


func get_tree_view_info() -> Dictionary:
	var tree_index: int = (
		viewed_object.get(
			"index",
			-1
		)
	)

	if (
		tree_index < 0
		or tree_index >= property_manager.trees.size()
	):
		return {}

	var tree_scale: float = (
		property_manager.tree_sizes[
			tree_index
		]
	)

	var size_name := "MEDIUM TREE"

	if tree_scale < 0.85:
		size_name = "SMALL TREE"

	elif tree_scale >= 1.2:
		size_name = "LARGE TREE"

	var removal_cost: int = (
		economy_manager.get_tree_removal_cost(
			tree_scale
		)
	)

	return {
		"type": VIEW_TREE,
		"title": size_name,
		"subtitle": "Healthy property tree",
		"detail": "Existing vegetation on your property.",
		"action_text":
			"REMOVE  •  "
			+ economy_manager.format_money(
				removal_cost
			),
		"action_enabled":
			economy_manager.can_afford(
				removal_cost
			),
		"cost": removal_cost,
		"destructive": true
	}


func get_tee_view_info() -> Dictionary:
	var hole_index: int = (
		viewed_object.get(
			"hole_index",
			course_manager.selected_hole
		)
	)

	return {
		"type": VIEW_TEE,
		"title":
			"HOLE "
			+ str(hole_index + 1)
			+ " TEE",
		"subtitle": "Installed tee area",
		"detail":
			"Return this tee to equipment storage for reuse.",
		"action_text": "RETURN TO STORAGE",
		"action_enabled": true,
		"cost": 0,
		"destructive": false
	}


func get_basket_view_info() -> Dictionary:
	var hole_index: int = (
		viewed_object.get(
			"hole_index",
			course_manager.selected_hole
		)
	)

	return {
		"type": VIEW_BASKET,
		"title":
			"HOLE "
			+ str(hole_index + 1)
			+ " BASKET",
		"subtitle": "Installed target",
		"detail":
			"Return this basket to equipment storage for reuse.",
		"action_text": "RETURN TO STORAGE",
		"action_enabled": true,
		"cost": 0,
		"destructive": false
	}


func get_path_point_view_info() -> Dictionary:
	var point_index: int = (
		viewed_object.get(
			"index",
			-1
		)
	)

	return {
		"type": VIEW_PATH_POINT,
		"title":
			"FLIGHT PATH POINT "
			+ str(point_index + 1),
		"subtitle": "Hole shaping control point",
		"detail":
			"Remove this point to simplify the intended flight path.",
		"action_text": "REMOVE POINT",
		"action_enabled": true,
		"cost": 0,
		"destructive": true
	}


# ==================================================
# VIEW ACTION
# ==================================================

func perform_view_action() -> bool:
	if viewed_object.is_empty():
		return false

	var object_type: String = (
		viewed_object.get(
			"type",
			VIEW_NONE
		)
	)

	match object_type:
		VIEW_TREE:
			return remove_viewed_tree()

		VIEW_TEE:
			return remove_viewed_tee()

		VIEW_BASKET:
			return remove_viewed_basket()

		VIEW_PATH_POINT:
			return remove_viewed_path_point()

	return false


func remove_viewed_tree() -> bool:
	var tree_index: int = (
		viewed_object.get(
			"index",
			-1
		)
	)

	if (
		tree_index < 0
		or tree_index >= property_manager.trees.size()
	):
		clear_viewed_object()
		return false

	var tree_scale: float = (
		property_manager.tree_sizes[
			tree_index
		]
	)

	var removal_cost: int = (
		economy_manager.get_tree_removal_cost(
			tree_scale
		)
	)

	if not economy_manager.spend(
		removal_cost
	):
		return false

	property_manager.remove_property_tree(
		tree_index
	)

	clear_viewed_object()
	course_renderer.refresh()

	return true


func remove_viewed_tee() -> bool:
	var hole_index: int = (
		viewed_object.get(
			"hole_index",
			-1
		)
	)

	if hole_index < 0:
		return false

	economy_manager.return_tee_to_inventory()

	course_manager.remove_tee(
		hole_index
	)

	clear_viewed_object()
	course_renderer.refresh()

	return true


func remove_viewed_basket() -> bool:
	var hole_index: int = (
		viewed_object.get(
			"hole_index",
			-1
		)
	)

	if hole_index < 0:
		return false

	economy_manager.return_basket_to_inventory()

	course_manager.remove_basket(
		hole_index
	)

	clear_viewed_object()
	course_renderer.refresh()

	return true


func remove_viewed_path_point() -> bool:
	var hole_index: int = (
		viewed_object.get(
			"hole_index",
			-1
		)
	)

	var point_index: int = (
		viewed_object.get(
			"index",
			-1
		)
	)

	if (
		hole_index < 0
		or point_index < 0
	):
		return false

	course_manager.remove_path_point(
		hole_index,
		point_index
	)

	clear_viewed_object()
	course_renderer.refresh()

	return true


# ==================================================
# CLEAR DRAG
# ==================================================

func clear_active_gesture() -> void:
	active_touch_index = -1

	dragging_path_point = false
	dragged_path_point_index = -1

	dragging_tee = false
	dragging_basket = false

	landscaping_active = false

	has_last_landscape_position = false
	last_landscape_local_position = Vector2.ZERO

	if course_renderer != null:
		course_renderer.clear_landscape_cursor()

	if camera_controller != null:
		camera_controller.set_camera_input_enabled(
			true
		)


func clear_drag_state() -> void:
	clear_active_gesture()
	clear_pending_landscape()


func clear_pending_landscape() -> void:
	landscape_selected_cells.clear()
	landscape_selected_lookup.clear()

	pending_mow_cells.clear()
	pending_mow_lookup.clear()

	pending_brush_cells.clear()
	pending_brush_lookup.clear()

	if course_renderer != null:
		course_renderer.clear_landscape_selection()


# ==================================================
# PENDING EDIT TRANSACTION
# ==================================================

func begin_pending_edit() -> void:
	if pending_edit_active:
		return

	pending_edit_active = true

	pending_course_snapshot = (
		course_manager.holes.duplicate(true)
	)

	pending_economy_snapshot = {
		"cash": economy_manager.cash,
		"total_spent": economy_manager.total_spent,
		"total_earned": economy_manager.total_earned,
		"tee_inventory": economy_manager.tee_inventory,
		"basket_inventory": economy_manager.basket_inventory
	}

	pending_edit_changed.emit(true)


func has_pending_edit() -> bool:
	return pending_edit_active


func get_pending_landscape_cell_count() -> int:
	return (
		pending_mow_cells.size()
		+ pending_brush_cells.size()
	)


func confirm_pending_edit() -> void:
	if not pending_edit_active:
		return

	create_landscape_job()

	pending_edit_active = false
	pending_course_snapshot.clear()
	pending_economy_snapshot.clear()

	clear_pending_landscape()
	clear_active_gesture()

	current_tool = Tool.NONE

	if course_renderer != null:
		course_renderer.set_path_edit_mode(false)
		course_renderer.refresh()

	pending_edit_changed.emit(false)


func cancel_pending_edit() -> void:
	if not pending_edit_active:
		return

	if not pending_course_snapshot.is_empty():
		course_manager.holes = (
			pending_course_snapshot.duplicate(true)
		)

	if not pending_economy_snapshot.is_empty():
		economy_manager.cash = int(
			pending_economy_snapshot.get(
				"cash",
				economy_manager.cash
			)
		)

		economy_manager.total_spent = int(
			pending_economy_snapshot.get(
				"total_spent",
				economy_manager.total_spent
			)
		)

		economy_manager.total_earned = int(
			pending_economy_snapshot.get(
				"total_earned",
				economy_manager.total_earned
			)
		)

		economy_manager.tee_inventory = int(
			pending_economy_snapshot.get(
				"tee_inventory",
				economy_manager.tee_inventory
			)
		)

		economy_manager.basket_inventory = int(
			pending_economy_snapshot.get(
				"basket_inventory",
				economy_manager.basket_inventory
			)
		)

	pending_edit_active = false
	pending_course_snapshot.clear()
	pending_economy_snapshot.clear()

	clear_pending_landscape()
	clear_active_gesture()

	current_tool = Tool.NONE

	if course_renderer != null:
		course_renderer.set_path_edit_mode(false)
		course_renderer.refresh()

	pending_edit_changed.emit(false)


func suspend_active_gesture_for_camera() -> void:
	clear_active_gesture()


# ==================================================
# READY?
# ==================================================

func references_ready() -> bool:
	return (
		course_manager != null
		and property_manager != null
		and course_renderer != null
		and camera_controller != null
		and economy_manager != null
		and job_manager != null
	)