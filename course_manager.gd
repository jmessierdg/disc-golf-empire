class_name CourseManager
extends Node


# ==================================================
# COURSE SETTINGS
# ==================================================

const TOTAL_HOLES := 9

# One property grid cell represents 15 real-world feet.
# Previous prototype used 10 feet.
const FEET_PER_CELL := 15.0


# ==================================================
# COURSE DATA
# ==================================================

var holes: Array = []

var selected_hole := 0


# ==================================================
# STARTUP
# ==================================================

func _ready() -> void:
	create_course()


# ==================================================
# CREATE COURSE
# ==================================================

func create_course() -> void:

	holes.clear()

	for i in range(TOTAL_HOLES):

		holes.append({
			"tee": Vector2(-1, -1),
			"basket": Vector2(-1, -1),
			"path_points": []
		})


# ==================================================
# GET HOLE
# ==================================================

func get_hole(hole_index: int) -> Dictionary:

	if not is_valid_hole_index(hole_index):
		return {}

	return holes[hole_index]


# ==================================================
# SET TEE
# ==================================================

func set_tee(
	hole_index: int,
	world_position: Vector2
) -> void:

	if not is_valid_hole_index(hole_index):
		return

	var hole: Dictionary = holes[hole_index]

	hole["tee"] = world_position

	holes[hole_index] = hole


# ==================================================
# SET BASKET
# ==================================================

func set_basket(
	hole_index: int,
	world_position: Vector2
) -> void:

	if not is_valid_hole_index(hole_index):
		return

	var hole: Dictionary = holes[hole_index]

	hole["basket"] = world_position

	holes[hole_index] = hole


# ==================================================
# REMOVE TEE
# ==================================================

func remove_tee(hole_index: int) -> void:

	if not is_valid_hole_index(hole_index):
		return

	var hole: Dictionary = holes[hole_index]

	hole["tee"] = Vector2(-1, -1)

	# A path cannot exist without both endpoints.
	hole["path_points"] = []

	holes[hole_index] = hole


# ==================================================
# REMOVE BASKET
# ==================================================

func remove_basket(hole_index: int) -> void:

	if not is_valid_hole_index(hole_index):
		return

	var hole: Dictionary = holes[hole_index]

	hole["basket"] = Vector2(-1, -1)

	# A path cannot exist without both endpoints.
	hole["path_points"] = []

	holes[hole_index] = hole


# ==================================================
# ADD PATH POINT
# ==================================================

func add_path_point(
	hole_index: int,
	world_position: Vector2
) -> int:

	if not is_valid_hole_index(hole_index):
		return -1

	var hole: Dictionary = holes[hole_index]

	var points: Array = hole["path_points"]

	points.append(world_position)

	hole["path_points"] = points

	holes[hole_index] = hole

	return points.size() - 1


# ==================================================
# INSERT PATH POINT
# ==================================================

func insert_path_point(
	hole_index: int,
	point_index: int,
	world_position: Vector2
) -> int:

	if not is_valid_hole_index(hole_index):
		return -1

	var hole: Dictionary = holes[hole_index]

	var points: Array = hole["path_points"]

	point_index = clamp(
		point_index,
		0,
		points.size()
	)

	points.insert(
		point_index,
		world_position
	)

	hole["path_points"] = points

	holes[hole_index] = hole

	return point_index


# ==================================================
# MOVE PATH POINT
# ==================================================

func move_path_point(
	hole_index: int,
	point_index: int,
	world_position: Vector2
) -> void:

	if not is_valid_hole_index(hole_index):
		return

	var hole: Dictionary = holes[hole_index]

	var points: Array = hole["path_points"]

	if point_index < 0:
		return

	if point_index >= points.size():
		return

	points[point_index] = world_position

	hole["path_points"] = points

	holes[hole_index] = hole


# ==================================================
# REMOVE PATH POINT
# ==================================================

func remove_path_point(
	hole_index: int,
	point_index: int
) -> void:

	if not is_valid_hole_index(hole_index):
		return

	var hole: Dictionary = holes[hole_index]

	var points: Array = hole["path_points"]

	if point_index < 0:
		return

	if point_index >= points.size():
		return

	points.remove_at(point_index)

	hole["path_points"] = points

	holes[hole_index] = hole


# ==================================================
# CLEAR PATH POINTS
# ==================================================

func clear_path_points(hole_index: int) -> void:

	if not is_valid_hole_index(hole_index):
		return

	var hole: Dictionary = holes[hole_index]

	hole["path_points"] = []

	holes[hole_index] = hole


# ==================================================
# HOLE COMPLETE?
# ==================================================

func is_hole_complete(hole_index: int) -> bool:

	if not is_valid_hole_index(hole_index):
		return false

	var hole: Dictionary = holes[hole_index]

	var tee: Vector2 = hole["tee"]
	var basket: Vector2 = hole["basket"]

	return (
		tee.x >= 0
		and basket.x >= 0
	)


# ==================================================
# HOLE DISTANCE
# ==================================================

func calculate_hole_distance(
	hole_index: int,
	cell_size: float
) -> int:

	if not is_hole_complete(hole_index):
		return 0

	var hole: Dictionary = holes[hole_index]

	var tee: Vector2 = hole["tee"]
	var basket: Vector2 = hole["basket"]

	var pixel_distance := tee.distance_to(
		basket
	)

	var cell_distance := (
		pixel_distance
		/ cell_size
	)

	return int(
		round(
			cell_distance
			* FEET_PER_CELL
		)
	)


# ==================================================
# PAR
# ==================================================

func calculate_par(distance_feet: int) -> int:

	if distance_feet < 400:
		return 3

	if distance_feet < 700:
		return 4

	return 5


# ==================================================
# COMPLETED HOLE COUNT
# ==================================================

func get_completed_hole_count() -> int:

	var completed := 0

	for i in range(holes.size()):

		if is_hole_complete(i):
			completed += 1

	return completed


# ==================================================
# TOTAL COURSE DISTANCE
# ==================================================

func get_total_course_distance(
	cell_size: float
) -> int:

	var total := 0

	for i in range(holes.size()):

		total += calculate_hole_distance(
			i,
			cell_size
		)

	return total


# ==================================================
# TOTAL COURSE PAR
# ==================================================

func get_total_course_par(
	cell_size: float
) -> int:

	var total := 0

	for i in range(holes.size()):

		if not is_hole_complete(i):
			continue

		var distance := calculate_hole_distance(
			i,
			cell_size
		)

		total += calculate_par(
			distance
		)

	return total


# ==================================================
# PREVIOUS HOLE
# ==================================================

func select_previous_hole() -> void:

	if selected_hole > 0:
		selected_hole -= 1


# ==================================================
# NEXT HOLE
# ==================================================

func select_next_hole() -> void:

	if selected_hole < TOTAL_HOLES - 1:
		selected_hole += 1


# ==================================================
# SET SELECTED HOLE
# ==================================================

func set_selected_hole(
	hole_index: int
) -> void:

	selected_hole = clamp(
		hole_index,
		0,
		TOTAL_HOLES - 1
	)


# ==================================================
# VALIDATE HOLE INDEX
# ==================================================

func is_valid_hole_index(
	hole_index: int
) -> bool:

	return (
		hole_index >= 0
		and hole_index < holes.size()
	)