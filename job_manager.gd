class_name JobManager
extends Node


# ==================================================
# SIGNALS
# ==================================================

signal jobs_changed
signal workers_changed


# ==================================================
# JOB TYPES
# ==================================================

const JOB_MOW := "mow"
const JOB_BRUSH := "brush"
const JOB_TREE := "tree"


# ==================================================
# JOB STATES
# ==================================================

const STATE_QUEUED := "queued"
const STATE_WORKING := "working"
const STATE_COMPLETE := "complete"


# ==================================================
# WORKER STATES
# ==================================================

const WORKER_IDLE := "idle"
const WORKER_WORKING := "working"


# ==================================================
# WORKFORCE
# ==================================================

const STARTING_WORKER_COUNT := 2


# ==================================================
# WORK SPEEDS
# ==================================================

const MOW_CELLS_PER_SECOND := 5.0
const BRUSH_CELLS_PER_SECOND := 2.5

const MIN_WORK_TIME := 0.35
const WORKER_TRAVEL_SPEED := 220.0
const ADJACENT_CELL_DISTANCE := 1.1


# ==================================================
# NAVIGATION
# ==================================================

const NAV_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1)
]


# ==================================================
# REFERENCES
# ==================================================

var property_manager
var course_renderer


# ==================================================
# JOB DATA
# ==================================================

var jobs: Array = []
var next_job_id := 1


# ==================================================
# WORKER DATA
# ==================================================

var workers: Array = []
var next_worker_id := 1


# ==================================================
# NAVIGATION CACHE
# ==================================================

# Water and trees are expensive to rescan every time a worker needs A*.
# Mowing/brush work does not change either obstacle type, so keep a shared
# blocked-cell map and rebuild it only when the tree count changes.
var navigation_blocked_cache: Dictionary = {}
var navigation_cache_tree_count := -1
var navigation_cache_ready := false


# ==================================================
# SETUP
# ==================================================

func setup(
	property_ref,
	renderer_ref
) -> void:

	property_manager = property_ref
	course_renderer = renderer_ref

	workers.clear()
	next_worker_id = 1

	invalidate_navigation_cache()

	for i in range(
		STARTING_WORKER_COUNT
	):
		create_worker()

	set_process(true)


# ==================================================
# CREATE WORKER
# ==================================================

func create_worker() -> int:

	var worker: Dictionary = {
		"id": next_worker_id,
		"state": WORKER_IDLE,
		"job_id": -1,

		"position": Vector2.ZERO,
		"direction": Vector2.RIGHT,

		"travelling": false,
		"travel_path": [],
		"travel_path_index": 0,
		"travel_target_cell": Vector2i(-1, -1)
	}

	next_worker_id += 1

	workers.append(
		worker
	)

	workers_changed.emit()

	return int(
		worker["id"]
	)


# ==================================================
# PROCESS
# ==================================================

func _process(
	delta: float
) -> void:

	assign_queued_jobs()

	var active_workers: Array = (
		workers.duplicate()
	)

	for worker_value in active_workers:

		var worker: Dictionary = (
			worker_value
		)

		if worker.get(
			"state",
			WORKER_IDLE
		) != WORKER_WORKING:
			continue

		var job_id: int = int(
			worker.get(
				"job_id",
				-1
			)
		)

		var job: Dictionary = (
			get_job_by_id(
				job_id
			)
		)

		if job.is_empty():

			release_worker(
				worker
			)

			continue

		process_job(
			job,
			worker,
			delta
		)

	if (
		course_renderer != null
		and get_working_worker_count() > 0
	):
		course_renderer.refresh()


# ==================================================
# ASSIGN QUEUED JOBS
# ==================================================

func assign_queued_jobs() -> void:

	for worker_value in workers:

		var worker: Dictionary = (
			worker_value
		)

		if worker.get(
			"state",
			WORKER_IDLE
		) != WORKER_IDLE:
			continue

		var job: Dictionary = (
			find_next_queued_job()
		)

		if job.is_empty():
			return

		assign_job_to_worker(
			job,
			worker
		)


# ==================================================
# FIND NEXT QUEUED JOB
# ==================================================

func find_next_queued_job() -> Dictionary:

	for job_value in jobs:

		var job: Dictionary = (
			job_value
		)

		if job.get(
			"state",
			STATE_QUEUED
		) == STATE_QUEUED:

			return job

	return {}


# ==================================================
# ASSIGN JOB TO WORKER
# ==================================================

func assign_job_to_worker(
	job: Dictionary,
	worker: Dictionary
) -> void:

	var cells: Array = (
		job.get(
			"cells",
			[]
		)
	)

	if cells.is_empty():
		return

	var first_cell: Vector2i = (
		cells[0]
	)

	var first_position: Vector2 = (
		get_cell_center_local(
			first_cell
		)
	)

	job["state"] = STATE_WORKING

	job["worker_id"] = int(
		worker["id"]
	)

	worker["state"] = WORKER_WORKING

	worker["job_id"] = int(
		job["id"]
	)

	worker["position"] = first_position
	worker["direction"] = Vector2.RIGHT

	worker["travelling"] = false
	worker["travel_path"] = []
	worker["travel_path_index"] = 0

	worker["travel_target_cell"] = Vector2i(
		-1,
		-1
	)

	jobs_changed.emit()
	workers_changed.emit()


# ==================================================
# RELEASE WORKER
# ==================================================

func release_worker(
	worker: Dictionary
) -> void:

	worker["state"] = WORKER_IDLE
	worker["job_id"] = -1

	worker["travelling"] = false
	worker["travel_path"] = []
	worker["travel_path_index"] = 0

	worker["travel_target_cell"] = Vector2i(
		-1,
		-1
	)

	workers_changed.emit()


# ==================================================
# GET JOB BY ID
# ==================================================

func get_job_by_id(
	job_id: int
) -> Dictionary:

	for job_value in jobs:

		var job: Dictionary = (
			job_value
		)

		if int(
			job.get(
				"id",
				-1
			)
		) == job_id:

			return job

	return {}


# ==================================================
# CREATE MOWING AREA JOB
# ==================================================

func create_mowing_area_job(
	selected_cells: Array
) -> int:

	return create_area_job(
		JOB_MOW,
		selected_cells
	)


# ==================================================
# CREATE BRUSH AREA JOB
# ==================================================

func create_brush_area_job(
	selected_cells: Array
) -> int:

	return create_area_job(
		JOB_BRUSH,
		selected_cells
	)


# ==================================================
# CREATE AREA JOB
# ==================================================

func create_area_job(
	job_type: String,
	selected_cells: Array
) -> int:

	if selected_cells.is_empty():
		return -1

	var unique_cells: Array[Vector2i] = []
	var seen_cells: Dictionary = {}

	for cell_value in selected_cells:

		var cell: Vector2i = (
			cell_value
		)

		if seen_cells.has(
			cell
		):
			continue

		seen_cells[
			cell
		] = true

		if not is_cell_valid_for_job(
			cell,
			job_type
		):
			continue

		unique_cells.append(
			cell
		)

	if unique_cells.is_empty():
		return -1

	var ordered_cells: Array[Vector2i] = (
		build_intelligent_work_order(
			unique_cells
		)
	)

	if ordered_cells.is_empty():
		return -1

	var work_speed: float = (
		get_job_work_speed(
			job_type
		)
	)

	var duration: float = max(
		MIN_WORK_TIME,
		float(
			ordered_cells.size()
		)
		/
		work_speed
	)

	var job: Dictionary = {
		"id": next_job_id,
		"type": job_type,
		"state": STATE_QUEUED,
		"worker_id": -1,

		"cells": ordered_cells,

		"total_cells": ordered_cells.size(),
		"completed_cells": 0,

		"duration": duration,
		"elapsed": 0.0,

		"cell_work_progress": 0.0
	}

	next_job_id += 1

	jobs.append(
		job
	)

	jobs_changed.emit()

	if course_renderer != null:
		course_renderer.refresh()

	return int(
		job["id"]
	)


# ==================================================
# CELL VALID FOR JOB?
# ==================================================

func is_cell_valid_for_job(
	cell: Vector2i,
	job_type: String
) -> bool:

	if property_manager == null:
		return false

	if not property_manager.is_valid_cell(
		cell.x,
		cell.y
	):
		return false

	var terrain_type: int = (
		property_manager.terrain[
			cell.y
		][
			cell.x
		]
	)

	match job_type:

		JOB_MOW:

			return (
				terrain_type == property_manager.ROUGH
				or
				terrain_type == property_manager.TALL_GRASS
			)

		JOB_BRUSH:

			if terrain_type == property_manager.WILD_GRASS:
				return true

			if cell_contains_bush(
				cell
			):
				return true

			if cell_contains_brush_cluster(
				cell
			):
				return true

	return false


# ==================================================
# CELL MOWABLE?
# ==================================================

func is_cell_mowable(
	cell: Vector2i
) -> bool:

	return is_cell_valid_for_job(
		cell,
		JOB_MOW
	)


# ==================================================
# CELL CONTAINS BUSH?
# ==================================================

func cell_contains_bush(
	cell: Vector2i
) -> bool:

	for bush_position_value in property_manager.bushes:

		var bush_position: Vector2 = (
			bush_position_value
		)

		var bush_cell: Vector2i = (
			property_manager.world_to_cell(
				bush_position
			)
		)

		if bush_cell == cell:
			return true

	return false


# ==================================================
# CELL CONTAINS BRUSH CLUSTER?
# ==================================================

func cell_contains_brush_cluster(
	cell: Vector2i
) -> bool:

	for brush_position_value in property_manager.brush_clusters:

		var brush_position: Vector2 = (
			brush_position_value
		)

		var brush_cell: Vector2i = (
			property_manager.world_to_cell(
				brush_position
			)
		)

		if brush_cell == cell:
			return true

	return false


# ==================================================
# JOB WORK SPEED
# ==================================================

func get_job_work_speed(
	job_type: String
) -> float:

	match job_type:

		JOB_BRUSH:
			return BRUSH_CELLS_PER_SECOND

		_:
			return MOW_CELLS_PER_SECOND


# ==================================================
# INTELLIGENT WORK ORDER
# ==================================================

func build_intelligent_work_order(
	cells: Array[Vector2i]
) -> Array[Vector2i]:

	if cells.is_empty():
		return []

	var bounds: Rect2i = (
		get_cell_bounds(
			cells
		)
	)

	var use_horizontal_passes: bool = (
		bounds.size.x
		>=
		bounds.size.y
	)

	var strips: Array = []

	if use_horizontal_passes:

		strips = (
			build_horizontal_strips(
				cells
			)
		)

	else:

		strips = (
			build_vertical_strips(
				cells
			)
		)

	return (
		connect_work_strips(
			strips
		)
	)


# ==================================================
# CELL BOUNDS
# ==================================================

func get_cell_bounds(
	cells: Array[Vector2i]
) -> Rect2i:

	if cells.is_empty():
		return Rect2i()

	var minimum_x: int = cells[0].x
	var maximum_x: int = cells[0].x

	var minimum_y: int = cells[0].y
	var maximum_y: int = cells[0].y

	for cell in cells:

		minimum_x = min(
			minimum_x,
			cell.x
		)

		maximum_x = max(
			maximum_x,
			cell.x
		)

		minimum_y = min(
			minimum_y,
			cell.y
		)

		maximum_y = max(
			maximum_y,
			cell.y
		)

	return Rect2i(
		Vector2i(
			minimum_x,
			minimum_y
		),
		Vector2i(
			maximum_x - minimum_x + 1,
			maximum_y - minimum_y + 1
		)
	)


# ==================================================
# HORIZONTAL STRIPS
# ==================================================

func build_horizontal_strips(
	cells: Array[Vector2i]
) -> Array:

	var rows: Dictionary = {}

	for cell in cells:

		if not rows.has(
			cell.y
		):

			rows[
				cell.y
			] = []

		rows[
			cell.y
		].append(
			cell.x
		)

	var row_numbers: Array = (
		rows.keys()
	)

	row_numbers.sort()

	var strips: Array = []

	for row_value in row_numbers:

		var row: int = int(
			row_value
		)

		var columns: Array = (
			rows[
				row
			]
		)

		columns.sort()

		var current_strip: Array[Vector2i] = []
		var previous_column: int = -999999

		for column_value in columns:

			var column: int = int(
				column_value
			)

			if (
				not current_strip.is_empty()
				and
				column != previous_column + 1
			):

				strips.append(
					current_strip
				)

				current_strip = []

			current_strip.append(
				Vector2i(
					column,
					row
				)
			)

			previous_column = column

		if not current_strip.is_empty():

			strips.append(
				current_strip
			)

	return strips


# ==================================================
# VERTICAL STRIPS
# ==================================================

func build_vertical_strips(
	cells: Array[Vector2i]
) -> Array:

	var columns: Dictionary = {}

	for cell in cells:

		if not columns.has(
			cell.x
		):

			columns[
				cell.x
			] = []

		columns[
			cell.x
		].append(
			cell.y
		)

	var column_numbers: Array = (
		columns.keys()
	)

	column_numbers.sort()

	var strips: Array = []

	for column_value in column_numbers:

		var column: int = int(
			column_value
		)

		var rows: Array = (
			columns[
				column
			]
		)

		rows.sort()

		var current_strip: Array[Vector2i] = []
		var previous_row: int = -999999

		for row_value in rows:

			var row: int = int(
				row_value
			)

			if (
				not current_strip.is_empty()
				and
				row != previous_row + 1
			):

				strips.append(
					current_strip
				)

				current_strip = []

			current_strip.append(
				Vector2i(
					column,
					row
				)
			)

			previous_row = row

		if not current_strip.is_empty():

			strips.append(
				current_strip
			)

	return strips


# ==================================================
# CONNECT WORK STRIPS
# ==================================================

func connect_work_strips(
	input_strips: Array
) -> Array[Vector2i]:

	var remaining_strips: Array = (
		input_strips.duplicate(
			true
		)
	)

	var ordered: Array[Vector2i] = []

	if remaining_strips.is_empty():
		return ordered

	var first_strip: Array = (
		remaining_strips.pop_front()
	)

	for cell_value in first_strip:

		var cell: Vector2i = (
			cell_value
		)

		ordered.append(
			cell
		)

	while not remaining_strips.is_empty():

		var current_cell: Vector2i = (
			ordered[
				ordered.size() - 1
			]
		)

		var best_strip_index := -1
		var best_reverse := false
		var best_distance := INF

		for i in range(
			remaining_strips.size()
		):

			var strip: Array = (
				remaining_strips[i]
			)

			if strip.is_empty():
				continue

			var strip_start: Vector2i = (
				strip[0]
			)

			var strip_end: Vector2i = (
				strip[
					strip.size() - 1
				]
			)

			var distance_to_start: float = (
				cell_distance(
					current_cell,
					strip_start
				)
			)

			var distance_to_end: float = (
				cell_distance(
					current_cell,
					strip_end
				)
			)

			if distance_to_start < best_distance:

				best_distance = distance_to_start
				best_strip_index = i
				best_reverse = false

			if distance_to_end < best_distance:

				best_distance = distance_to_end
				best_strip_index = i
				best_reverse = true

		if best_strip_index < 0:
			break

		var next_strip: Array = (
			remaining_strips[
				best_strip_index
			]
		)

		remaining_strips.remove_at(
			best_strip_index
		)

		if best_reverse:
			next_strip.reverse()

		for cell_value in next_strip:

			var cell: Vector2i = (
				cell_value
			)

			ordered.append(
				cell
			)

	return ordered


# ==================================================
# CELL DISTANCE
# ==================================================

func cell_distance(
	a: Vector2i,
	b: Vector2i
) -> float:

	return Vector2(
		float(
			b.x - a.x
		),
		float(
			b.y - a.y
		)
	).length()


# ==================================================
# CELL CENTER
# ==================================================

func get_cell_center_local(
	cell: Vector2i
) -> Vector2:

	return property_manager.cell_to_world_center(
		cell
	)


# ==================================================
# PROCESS JOB
# ==================================================

func process_job(
	job: Dictionary,
	worker: Dictionary,
	delta: float
) -> void:

	var job_type: String = (
		job.get(
			"type",
			""
		)
	)

	match job_type:

		JOB_MOW, JOB_BRUSH:

			process_area_job(
				job,
				worker,
				delta
			)


# ==================================================
# PROCESS AREA JOB
# ==================================================

func process_area_job(
	job: Dictionary,
	worker: Dictionary,
	delta: float
) -> void:

	var cells: Array = (
		job.get(
			"cells",
			[]
		)
	)

	if cells.is_empty():

		complete_job(
			job,
			worker
		)

		return

	var completed_cells: int = int(
		job.get(
			"completed_cells",
			0
		)
	)

	if completed_cells >= cells.size():

		complete_job(
			job,
			worker
		)

		return

	var target_cell: Vector2i = (
		cells[
			completed_cells
		]
	)

	var target_position: Vector2 = (
		get_cell_center_local(
			target_cell
		)
	)

	if completed_cells == 0:

		worker["position"] = (
			target_position
		)

		process_cell_work(
			job,
			worker,
			target_cell,
			delta
		)

		return

	var previous_cell: Vector2i = (
		cells[
			completed_cells - 1
		]
	)

	var grid_distance: float = (
		cell_distance(
			previous_cell,
			target_cell
		)
	)

	if grid_distance <= ADJACENT_CELL_DISTANCE:

		clear_worker_travel_path(
			worker
		)

		move_worker_during_work(
			job,
			worker,
			previous_cell,
			target_cell
		)

		process_cell_work(
			job,
			worker,
			target_cell,
			delta
		)

		return

	process_navigation_travel(
		job,
		worker,
		previous_cell,
		target_cell,
		delta
	)


# ==================================================
# MOVE DURING NORMAL WORK
# ==================================================

func move_worker_during_work(
	job: Dictionary,
	worker: Dictionary,
	previous_cell: Vector2i,
	target_cell: Vector2i
) -> void:

	var start_position: Vector2 = (
		get_cell_center_local(
			previous_cell
		)
	)

	var target_position: Vector2 = (
		get_cell_center_local(
			target_cell
		)
	)

	var progress: float = clamp(
		float(
			job.get(
				"cell_work_progress",
				0.0
			)
		),
		0.0,
		1.0
	)

	var direction: Vector2 = (
		target_position
		- start_position
	)

	if direction.length_squared() > 0.001:

		worker["direction"] = (
			direction.normalized()
		)

	worker["position"] = (
		start_position.lerp(
			target_position,
			progress
		)
	)

	worker["travelling"] = false


# ==================================================
# NAVIGATION TRAVEL
# ==================================================

func process_navigation_travel(
	job: Dictionary,
	worker: Dictionary,
	previous_cell: Vector2i,
	target_cell: Vector2i,
	delta: float
) -> void:

	var stored_target: Vector2i = (
		worker.get(
			"travel_target_cell",
			Vector2i(-1, -1)
		)
	)

	var travel_path: Array = (
		worker.get(
			"travel_path",
			[]
		)
	)

	if (
		stored_target != target_cell
		or travel_path.is_empty()
	):

		travel_path = (
			find_navigation_path(
				previous_cell,
				target_cell
			)
		)

		worker["travel_path"] = (
			travel_path
		)

		worker["travel_path_index"] = 0

		worker["travel_target_cell"] = (
			target_cell
		)

		worker["travelling"] = true

	if travel_path.is_empty():

		var target_position: Vector2 = (
			get_cell_center_local(
				target_cell
			)
		)

		move_worker_to_position(
			worker,
			target_position,
			delta
		)

		var fallback_worker_position: Vector2 = (
			worker.get(
				"position",
				target_position
			)
		)

		if fallback_worker_position.distance_to(
			target_position
		) <= 1.0:

			worker["position"] = (
				target_position
			)

			clear_worker_travel_path(
				worker
			)

			process_cell_work(
				job,
				worker,
				target_cell,
				delta
			)

		return

	var path_index: int = int(
		worker.get(
			"travel_path_index",
			0
		)
	)

	if path_index >= travel_path.size():

		clear_worker_travel_path(
			worker
		)

		process_cell_work(
			job,
			worker,
			target_cell,
			delta
		)

		return

	var path_cell: Vector2i = (
		travel_path[
			path_index
		]
	)

	var path_position: Vector2 = (
		get_cell_center_local(
			path_cell
		)
	)

	move_worker_to_position(
		worker,
		path_position,
		delta
	)

	var worker_position: Vector2 = (
		worker.get(
			"position",
			path_position
		)
	)

	if worker_position.distance_to(
		path_position
	) <= 1.0:

		worker["position"] = (
			path_position
		)

		path_index += 1

		worker["travel_path_index"] = (
			path_index
		)

		if path_index >= travel_path.size():

			clear_worker_travel_path(
				worker
			)

			process_cell_work(
				job,
				worker,
				target_cell,
				delta
			)


# ==================================================
# MOVE WORKER TO POSITION
# ==================================================

func move_worker_to_position(
	worker: Dictionary,
	target_position: Vector2,
	delta: float
) -> void:

	var worker_position: Vector2 = (
		worker.get(
			"position",
			target_position
		)
	)

	var offset: Vector2 = (
		target_position
		- worker_position
	)

	var distance: float = (
		offset.length()
	)

	if distance <= 0.001:

		worker["position"] = (
			target_position
		)

		return

	var direction: Vector2 = (
		offset
		/ distance
	)

	worker["direction"] = (
		direction
	)

	var movement_distance: float = (
		WORKER_TRAVEL_SPEED
		* delta
	)

	if movement_distance >= distance:

		worker["position"] = (
			target_position
		)

	else:

		worker["position"] = (
			worker_position
			+
			direction
			* movement_distance
		)


# ==================================================
# CLEAR WORKER TRAVEL PATH
# ==================================================

func clear_worker_travel_path(
	worker: Dictionary
) -> void:

	worker["travel_path"] = []
	worker["travel_path_index"] = 0

	worker["travel_target_cell"] = (
		Vector2i(-1, -1)
	)

	worker["travelling"] = false


# ==================================================
# FIND NAVIGATION PATH
# ==================================================

func find_navigation_path(
	start_cell: Vector2i,
	target_cell: Vector2i
) -> Array[Vector2i]:

	var empty_path: Array[Vector2i] = []

	if property_manager == null:
		return empty_path

	if not property_manager.is_valid_cell(
		start_cell.x,
		start_cell.y
	):
		return empty_path

	if not property_manager.is_valid_cell(
		target_cell.x,
		target_cell.y
	):
		return empty_path

	var blocked_cells: Dictionary = (
		build_navigation_blocked_cells(
			start_cell,
			target_cell
		)
	)

	var open_cells: Array[Vector2i] = [
		start_cell
	]

	var open_lookup: Dictionary = {
		start_cell: true
	}

	var came_from: Dictionary = {}

	var g_score: Dictionary = {
		start_cell: 0.0
	}

	var f_score: Dictionary = {
		start_cell: navigation_heuristic(
			start_cell,
			target_cell
		)
	}

	while not open_cells.is_empty():

		var current_index: int = (
			find_lowest_score_index(
				open_cells,
				f_score
			)
		)

		var current: Vector2i = (
			open_cells[
				current_index
			]
		)

		if current == target_cell:

			return reconstruct_navigation_path(
				came_from,
				current,
				start_cell
			)

		open_cells.remove_at(
			current_index
		)

		open_lookup.erase(
			current
		)

		for direction in NAV_DIRECTIONS:

			var neighbor: Vector2i = (
				current
				+
				direction
			)

			if not property_manager.is_valid_cell(
				neighbor.x,
				neighbor.y
			):
				continue

			if (
				neighbor != target_cell
				and blocked_cells.has(
					neighbor
				)
			):
				continue

			var tentative_g: float = (
				float(
					g_score.get(
						current,
						INF
					)
				)
				+ 1.0
			)

			var known_g: float = float(
				g_score.get(
					neighbor,
					INF
				)
			)

			if tentative_g >= known_g:
				continue

			came_from[
				neighbor
			] = current

			g_score[
				neighbor
			] = tentative_g

			f_score[
				neighbor
			] = (
				tentative_g
				+
				navigation_heuristic(
					neighbor,
					target_cell
				)
			)

			if not open_lookup.has(
				neighbor
			):

				open_cells.append(
					neighbor
				)

				open_lookup[
					neighbor
				] = true

	return empty_path


# ==================================================
# NAVIGATION BLOCKED CELLS
# ==================================================

func build_navigation_blocked_cells(
	_start_cell: Vector2i,
	_target_cell: Vector2i
) -> Dictionary:

	var current_tree_count: int = (
		property_manager.trees.size()
	)

	if (
		navigation_cache_ready
		and current_tree_count == navigation_cache_tree_count
	):
		return navigation_blocked_cache

	rebuild_navigation_cache()

	return navigation_blocked_cache


func invalidate_navigation_cache() -> void:

	navigation_blocked_cache.clear()
	navigation_cache_tree_count = -1
	navigation_cache_ready = false


func rebuild_navigation_cache() -> void:

	navigation_blocked_cache.clear()

	if property_manager == null:
		navigation_cache_tree_count = -1
		navigation_cache_ready = true
		return

	for y in range(
		property_manager.PROPERTY_GRID_HEIGHT
	):

		for x in range(
			property_manager.PROPERTY_GRID_WIDTH
		):

			if property_manager.is_water_cell(
				x,
				y
			):

				navigation_blocked_cache[
					Vector2i(
						x,
						y
					)
				] = true

	for tree_position_value in property_manager.trees:

		var tree_position: Vector2 = (
			tree_position_value
		)

		var tree_cell: Vector2i = (
			property_manager.world_to_cell(
				tree_position
			)
		)

		if property_manager.is_valid_cell(
			tree_cell.x,
			tree_cell.y
		):

			navigation_blocked_cache[
				tree_cell
			] = true

	navigation_cache_tree_count = (
		property_manager.trees.size()
	)

	navigation_cache_ready = true


# ==================================================
# NAVIGATION HEURISTIC
# ==================================================

func navigation_heuristic(
	from_cell: Vector2i,
	to_cell: Vector2i
) -> float:

	return float(
		abs(
			to_cell.x
			- from_cell.x
		)
		+
		abs(
			to_cell.y
			- from_cell.y
		)
	)


# ==================================================
# LOWEST A* SCORE
# ==================================================

func find_lowest_score_index(
	open_cells: Array[Vector2i],
	f_score: Dictionary
) -> int:

	var best_index := 0

	var best_score: float = float(
		f_score.get(
			open_cells[0],
			INF
		)
	)

	for i in range(
		1,
		open_cells.size()
	):

		var score: float = float(
			f_score.get(
				open_cells[i],
				INF
			)
		)

		if score < best_score:

			best_score = score
			best_index = i

	return best_index


# ==================================================
# RECONSTRUCT A* PATH
# ==================================================

func reconstruct_navigation_path(
	came_from: Dictionary,
	current: Vector2i,
	start_cell: Vector2i
) -> Array[Vector2i]:

	var reversed_path: Array[Vector2i] = []

	reversed_path.append(
		current
	)

	while came_from.has(
		current
	):

		current = (
			came_from[
				current
			]
		)

		if current == start_cell:
			break

		reversed_path.append(
			current
		)

	reversed_path.reverse()

	return reversed_path


# ==================================================
# PROCESS CELL WORK
# ==================================================

func process_cell_work(
	job: Dictionary,
	worker: Dictionary,
	target_cell: Vector2i,
	delta: float
) -> void:

	var job_type: String = (
		job.get(
			"type",
			""
		)
	)

	var work_speed: float = (
		get_job_work_speed(
			job_type
		)
	)

	var progress: float = float(
		job.get(
			"cell_work_progress",
			0.0
		)
	)

	progress += (
		delta
		* work_speed
	)

	job["elapsed"] = (
		float(
			job.get(
				"elapsed",
				0.0
			)
		)
		+ delta
	)

	if progress < 1.0:

		job["cell_work_progress"] = (
			progress
		)

		return

	perform_cell_work(
		job_type,
		target_cell
	)

	var completed_cells: int = int(
		job.get(
			"completed_cells",
			0
		)
	)

	completed_cells += 1

	job["completed_cells"] = (
		completed_cells
	)

	job["cell_work_progress"] = (
		max(
			0.0,
			progress - 1.0
		)
	)

	if completed_cells >= int(
		job.get(
			"total_cells",
			0
		)
	):

		complete_job(
			job,
			worker
		)


# ==================================================
# PERFORM CELL WORK
# ==================================================

func perform_cell_work(
	job_type: String,
	cell: Vector2i
) -> void:

	match job_type:

		JOB_MOW:

			mow_cell(
				cell
			)

		JOB_BRUSH:

			brush_cut_cell(
				cell
			)


# ==================================================
# MOW CELL
# ==================================================

func mow_cell(
	cell: Vector2i
) -> bool:

	if not is_cell_mowable(
		cell
	):
		return false

	property_manager.terrain[
		cell.y
	][
		cell.x
	] = property_manager.GRASS

	return true


# ==================================================
# BRUSH CUT CELL
# ==================================================

func brush_cut_cell(
	cell: Vector2i
) -> bool:

	if property_manager == null:
		return false

	if not property_manager.is_valid_cell(
		cell.x,
		cell.y
	):
		return false

	var changed := false

	if property_manager.terrain[
		cell.y
	][
		cell.x
	] == property_manager.WILD_GRASS:

		property_manager.terrain[
			cell.y
		][
			cell.x
		] = property_manager.TALL_GRASS

		changed = true

	for i in range(
		property_manager.bushes.size() - 1,
		-1,
		-1
	):

		var bush_position: Vector2 = (
			property_manager.bushes[i]
		)

		var bush_cell: Vector2i = (
			property_manager.world_to_cell(
				bush_position
			)
		)

		if bush_cell != cell:
			continue

		property_manager.bushes.remove_at(
			i
		)

		if i < property_manager.bush_sizes.size():

			property_manager.bush_sizes.remove_at(
				i
			)

		changed = true

	for i in range(
		property_manager.brush_clusters.size() - 1,
		-1,
		-1
	):

		var brush_position: Vector2 = (
			property_manager.brush_clusters[i]
		)

		var brush_cell: Vector2i = (
			property_manager.world_to_cell(
				brush_position
			)
		)

		if brush_cell != cell:
			continue

		property_manager.brush_clusters.remove_at(
			i
		)

		if i < property_manager.brush_sizes.size():

			property_manager.brush_sizes.remove_at(
				i
			)

		changed = true

	return changed


# ==================================================
# COMPLETE JOB
# ==================================================

func complete_job(
	job: Dictionary,
	worker: Dictionary
) -> void:

	var completed_job_id: int = int(
		job.get(
			"id",
			-1
		)
	)

	job["state"] = STATE_COMPLETE
	job["worker_id"] = -1

	release_worker(
		worker
	)

	remove_job_by_id(
		completed_job_id
	)

	jobs_changed.emit()

	if course_renderer != null:
		course_renderer.refresh()


# ==================================================
# REMOVE JOB BY ID
# ==================================================

func remove_job_by_id(
	job_id: int
) -> void:

	for i in range(
		jobs.size()
	):

		var job: Dictionary = (
			jobs[i]
		)

		if int(
			job.get(
				"id",
				-1
			)
		) == job_id:

			jobs.remove_at(
				i
			)

			return


# ==================================================
# ALL ACTIVE JOBS
# ==================================================

func get_active_jobs() -> Array:

	var active_jobs: Array = []

	for job_value in jobs:

		var job: Dictionary = (
			job_value
		)

		if job.get(
			"state",
			STATE_QUEUED
		) != STATE_WORKING:
			continue

		active_jobs.append(
			job.duplicate(
				true
			)
		)

	return active_jobs


# ==================================================
# ALL ACTIVE WORKERS
# ==================================================

func get_active_workers() -> Array:

	var active_workers: Array = []

	for worker_value in workers:

		var worker: Dictionary = (
			worker_value
		)

		if worker.get(
			"state",
			WORKER_IDLE
		) != WORKER_WORKING:
			continue

		active_workers.append(
			worker.duplicate(
				true
			)
		)

	return active_workers


# ==================================================
# REMAINING CELLS FOR JOB
# ==================================================

func get_remaining_cells_for_job(
	job_id: int
) -> Array:

	var job: Dictionary = (
		get_job_by_id(
			job_id
		)
	)

	if job.is_empty():
		return []

	var cells: Array = (
		job.get(
			"cells",
			[]
		)
	)

	var completed_cells: int = int(
		job.get(
			"completed_cells",
			0
		)
	)

	var remaining: Array = []

	for i in range(
		completed_cells,
		cells.size()
	):

		remaining.append(
			cells[i]
		)

	return remaining


# ==================================================
# FIRST WORKING JOB
# ==================================================

func get_first_working_job_reference() -> Dictionary:

	for job_value in jobs:

		var job: Dictionary = (
			job_value
		)

		if job.get(
			"state",
			STATE_QUEUED
		) == STATE_WORKING:

			return job

	return {}


# ==================================================
# WORKER FOR JOB
# ==================================================

func get_worker_for_job(
	job: Dictionary
) -> Dictionary:

	if job.is_empty():
		return {}

	var worker_id: int = int(
		job.get(
			"worker_id",
			-1
		)
	)

	for worker_value in workers:

		var worker: Dictionary = (
			worker_value
		)

		if int(
			worker.get(
				"id",
				-1
			)
		) == worker_id:

			return worker

	return {}


# ==================================================
# COMPATIBILITY API
# ==================================================

func get_active_job() -> Dictionary:

	var job: Dictionary = (
		get_first_working_job_reference()
	)

	if job.is_empty():
		return {}

	return job.duplicate(
		true
	)


func get_active_remaining_cells() -> Array:

	var job: Dictionary = (
		get_first_working_job_reference()
	)

	if job.is_empty():
		return []

	return get_remaining_cells_for_job(
		int(
			job.get(
				"id",
				-1
			)
		)
	)


func get_active_worker_local_position() -> Vector2:

	var job: Dictionary = (
		get_first_working_job_reference()
	)

	if job.is_empty():

		return Vector2(
			-1.0,
			-1.0
		)

	var worker: Dictionary = (
		get_worker_for_job(
			job
		)
	)

	if worker.is_empty():

		return Vector2(
			-1.0,
			-1.0
		)

	return worker.get(
		"position",
		Vector2(
			-1.0,
			-1.0
		)
	)


func get_active_worker_direction() -> Vector2:

	var job: Dictionary = (
		get_first_working_job_reference()
	)

	if job.is_empty():
		return Vector2.RIGHT

	var worker: Dictionary = (
		get_worker_for_job(
			job
		)
	)

	if worker.is_empty():
		return Vector2.RIGHT

	var direction: Vector2 = (
		worker.get(
			"direction",
			Vector2.RIGHT
		)
	)

	if direction.length_squared() <= 0.001:
		return Vector2.RIGHT

	return direction.normalized()


func get_active_job_type() -> String:

	var job: Dictionary = (
		get_first_working_job_reference()
	)

	if job.is_empty():
		return ""

	return String(
		job.get(
			"type",
			""
		)
	)


# ==================================================
# COUNTS
# ==================================================

func get_job_count() -> int:

	return jobs.size()


func get_worker_count() -> int:

	return workers.size()


func get_idle_worker_count() -> int:

	var count := 0

	for worker_value in workers:

		var worker: Dictionary = (
			worker_value
		)

		if worker.get(
			"state",
			WORKER_IDLE
		) == WORKER_IDLE:

			count += 1

	return count


# ==================================================
# ACTIVE JOB PROGRESS
# ==================================================

func get_active_job_progress() -> float:

	var job: Dictionary = (
		get_first_working_job_reference()
	)

	if job.is_empty():
		return 0.0

	var total_cells: int = int(
		job.get(
			"total_cells",
			0
		)
	)

	if total_cells <= 0:
		return 0.0

	var completed_cells: int = int(
		job.get(
			"completed_cells",
			0
		)
	)

	var cell_progress: float = float(
		job.get(
			"cell_work_progress",
			0.0
		)
	)

	return clamp(
		(
			float(
				completed_cells
			)
			+
			cell_progress
		)
		/
		float(
			total_cells
		),
		0.0,
		1.0
	)


# ==================================================
# ESTIMATED TIME REMAINING
# ==================================================

func get_active_job_seconds_remaining() -> float:

	var job: Dictionary = (
		get_first_working_job_reference()
	)

	if job.is_empty():
		return 0.0

	var total_cells: int = int(
		job.get(
			"total_cells",
			0
		)
	)

	var completed_cells: int = int(
		job.get(
			"completed_cells",
			0
		)
	)

	var cell_progress: float = float(
		job.get(
			"cell_work_progress",
			0.0
		)
	)

	var remaining_work: float = max(
		0.0,
		float(
			total_cells
			- completed_cells
		)
		-
		cell_progress
	)

	var job_type: String = (
		job.get(
			"type",
			""
		)
	)

	return (
		remaining_work
		/
		get_job_work_speed(
			job_type
		)
	)
	
# ==================================================
# CREW / QUEUE UI API
# ==================================================

func get_all_workers() -> Array:

	var result: Array = []

	for worker_value in workers:

		var worker: Dictionary = (
			worker_value
		)

		result.append(
			worker.duplicate(
				true
			)
		)

	return result


func get_queued_jobs() -> Array:

	var queued_jobs: Array = []

	for job_value in jobs:

		var job: Dictionary = (
			job_value
		)

		if job.get(
			"state",
			STATE_QUEUED
		) != STATE_QUEUED:
			continue

		queued_jobs.append(
			job.duplicate(
				true
			)
		)

	return queued_jobs


func get_queued_job_count() -> int:

	var count := 0

	for job_value in jobs:

		var job: Dictionary = (
			job_value
		)

		if job.get(
			"state",
			STATE_QUEUED
		) == STATE_QUEUED:

			count += 1

	return count


func get_working_worker_count() -> int:

	var count := 0

	for worker_value in workers:

		var worker: Dictionary = (
			worker_value
		)

		if worker.get(
			"state",
			WORKER_IDLE
		) == WORKER_WORKING:

			count += 1

	return count


func get_job_progress(
	job_id: int
) -> float:

	var job: Dictionary = (
		get_job_by_id(
			job_id
		)
	)

	if job.is_empty():
		return 0.0

	var total_cells: int = int(
		job.get(
			"total_cells",
			0
		)
	)

	if total_cells <= 0:
		return 0.0

	var completed_cells: int = int(
		job.get(
			"completed_cells",
			0
		)
	)

	var cell_progress: float = float(
		job.get(
			"cell_work_progress",
			0.0
		)
	)

	return clamp(
		(
			float(
				completed_cells
			)
			+
			cell_progress
		)
		/
		float(
			total_cells
		),
		0.0,
		1.0
	)


func get_job_display_name(
	job_type: String
) -> String:

	match job_type:

		JOB_MOW:
			return "Mowing"

		JOB_BRUSH:
			return "Clearing Brush"

		JOB_TREE:
			return "Tree Removal"

	return "Working"


func get_worker_status_text(
	worker_id: int
) -> String:

	for worker_value in workers:

		var worker: Dictionary = (
			worker_value
		)

		if int(
			worker.get(
				"id",
				-1
			)
		) != worker_id:
			continue

		if worker.get(
			"state",
			WORKER_IDLE
		) == WORKER_IDLE:

			return "Idle"

		var job_id: int = int(
			worker.get(
				"job_id",
				-1
			)
		)

		var job: Dictionary = (
			get_job_by_id(
				job_id
			)
		)

		if job.is_empty():
			return "Idle"

		if bool(
			worker.get(
				"travelling",
				false
			)
		):

			return "Traveling"

		return get_job_display_name(
			String(
				job.get(
					"type",
					""
				)
			)
		)

	return "Idle"