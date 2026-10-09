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
const WORKER_RETURNING := "returning"
const WORKER_FETCHING := "fetching"


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
# Deliberately slower travel than the original 220 px/s.
const WORKER_TRAVEL_SPEED := 88.0
const WORKER_INSPECTION_SPEED := 66.0
const WORKER_EQUIPMENT_SPEED := 77.0
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
var economy_manager
var course_manager = null
var walkway_manager = null

func set_walkway_manager(manager_ref) -> void:
	walkway_manager = manager_ref

var reported_conditions: Dictionary = {}


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
# EQUIPMENT ASSIGNMENTS
# ==================================================

# Equipment ownership lives in EconomyManager. JobManager only tracks
# which owned units are currently reserved by active workers.
var reserved_equipment: Dictionary = {}


# ==================================================
# NAVIGATION CACHE
# ==================================================

var navigation_blocked_cache: Dictionary = {}
var navigation_cache_tree_count := -1
var navigation_cache_ready := false


# ==================================================
# SETUP
# ==================================================

func setup(
	property_ref,
	renderer_ref,
	economy_ref = null
) -> void:

	property_manager = property_ref
	course_renderer = renderer_ref
	economy_manager = economy_ref
	# CourseManager is a sibling created before JobManager setup.
	course_manager = get_parent().get_node_or_null("CourseManager")
	reported_conditions.clear()

	workers.clear()
	next_worker_id = 1

	reserved_equipment.clear()
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
		"equipment_type": "",
		"position": get_maintenance_local_position(),
		"wander_wait": float(next_worker_id) * 1.2,
		"wander_destination": get_maintenance_local_position(),
		"inspection_type": "",
		"inspection_target": Vector2.ZERO,
		"observation": "",
		"observation_cell": Vector2i(-1, -1),
		"inspection_hole": -1,
		"inspection_other_hole": -1,
		"observation_cooldown": 0.0,
		"movement_path": [],
		"movement_index": 0,

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

		var phase: String = str(worker.get("state", WORKER_IDLE))
		if phase == WORKER_IDLE:
			worker["observation_cooldown"] = maxf(0.0, float(worker.get("observation_cooldown", 0.0)) - delta)
			# Workers stay at the maintenance yard until assigned a job.
			continue
		if phase == WORKER_RETURNING:
			if move_worker_to_facility(worker, delta):
				finish_equipment_return(worker)
			continue
		if phase == WORKER_FETCHING:
			if move_worker_to_facility(worker, delta):
				worker["state"] = WORKER_WORKING
				worker["movement_path"] = []
				worker["movement_index"] = 0
			continue
		if phase != WORKER_WORKING:
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
		and workers.size() > 0
	):
		course_renderer.refresh_dynamic()


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
		) != STATE_QUEUED:
			continue

		if not is_required_equipment_available(
			String(
				job.get(
					"type",
					""
				)
			)
		):
			continue

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

	var job_type: String = String(
		job.get(
			"type",
			""
		)
	)

	var equipment_type: String = (
		get_required_equipment_type(
			job_type
		)
	)

	if not reserve_equipment(
		equipment_type
	):
		return

	job["state"] = STATE_WORKING

	job["worker_id"] = int(
		worker["id"]
	)

	worker["state"] = WORKER_FETCHING

	worker["job_id"] = int(
		job["id"]
	)

	worker["equipment_type"] = equipment_type

	worker["movement_path"] = []
	worker["movement_index"] = 0
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

func release_worker(worker: Dictionary) -> void:
	worker["state"] = WORKER_RETURNING
	worker["job_id"] = -1
	worker["movement_path"] = []
	worker["movement_index"] = 0
	clear_worker_travel_path(worker)
	workers_changed.emit()


func finish_equipment_return(worker: Dictionary) -> void:
	release_equipment(str(worker.get("equipment_type", "")))
	worker["equipment_type"] = ""
	worker["state"] = WORKER_IDLE
	worker["wander_wait"] = 0.0
	worker["position"] = get_maintenance_local_position()
	worker["movement_path"] = []
	worker["movement_index"] = 0
	workers_changed.emit()


func get_maintenance_local_position() -> Vector2:
	# Equipment is collected at the exterior yard, NEVER inside the shed.
	if property_manager == null:
		return Vector2(80.0, 80.0)
	var yard: Dictionary = property_manager.get_starter_facility("starter_yard")
	if not yard.is_empty():
		var center: Vector2 = property_manager.world_to_property_local(yard["position"])
		var size: Vector2 = yard["size"]
		return center + Vector2(0.0, size.y * 0.5 + property_manager.CELL_SIZE * 0.7)
	var shed: Dictionary = property_manager.get_starter_facility("starter_shed")
	if not shed.is_empty():
		var center: Vector2 = property_manager.world_to_property_local(shed["position"])
		var size: Vector2 = shed["size"]
		return center + Vector2(0.0, size.y * 0.5 + property_manager.CELL_SIZE * 0.7)
	return property_manager.get_property_world_rect().size * 0.5


func get_worker_cell(local_pos: Vector2) -> Vector2i:
	return Vector2i(clampi(int(local_pos.x / property_manager.CELL_SIZE), 0, property_manager.PROPERTY_GRID_WIDTH - 1), clampi(int(local_pos.y / property_manager.CELL_SIZE), 0, property_manager.PROPERTY_GRID_HEIGHT - 1))


func set_worker_route(worker: Dictionary, target: Vector2) -> bool:
	var current: Vector2 = worker.get("position", target)
	var start_cell: Vector2i = get_worker_cell(current)
	var target_cell: Vector2i = get_worker_cell(target)
	var blocked: Dictionary = build_navigation_blocked_cells(start_cell, target_cell)
	if blocked.has(target_cell):
		target_cell = find_nearest_walkable_cell(target_cell, blocked)
		if target_cell.x < 0:
			return false
		target = get_cell_center_local(target_cell)
	var path: Array[Vector2i] = find_navigation_path(start_cell, target_cell)
	if path.is_empty() and start_cell != target_cell:
		return false
	var route: Array = []
	for cell in path:
		route.append(get_cell_center_local(cell))
	# Only use the exact target when its cell is walkable.
	if route.is_empty() or route[-1].distance_to(target) > 0.5:
		route.append(target)
	worker["movement_path"] = route
	worker["movement_index"] = 0
	return true


func find_nearest_walkable_cell(target: Vector2i, blocked: Dictionary) -> Vector2i:
	for radius in range(1, 9):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var cell: Vector2i = target + Vector2i(dx, dy)
				if property_manager.is_valid_cell(cell.x, cell.y) and not blocked.has(cell):
					return cell
	return Vector2i(-1, -1)


func follow_worker_route(worker: Dictionary, delta: float) -> bool:
	var route: Array = worker.get("movement_path", [])
	var index: int = int(worker.get("movement_index", 0))
	if index >= route.size():
		return true
	var target: Vector2 = route[index]
	var step_cell: Vector2i = get_worker_cell(target)
	if property_manager.is_water_cell(step_cell.x, step_cell.y):
		worker["movement_path"] = []
		worker["movement_index"] = 0
		return false
	move_worker_to_position(worker, target, delta)
	if worker["position"].distance_to(target) < 1.0:
		index += 1
		worker["movement_index"] = index
	return index >= route.size()


func move_worker_to_facility(worker: Dictionary, delta: float) -> bool:
	if worker.get("movement_path", []).is_empty():
		if not set_worker_route(worker, get_maintenance_local_position()):
			# No walkable route: remain stationary and retry later.
			return false
	return follow_worker_route(worker, delta)


func process_idle_wander(worker: Dictionary, delta: float) -> void:
	# Patrols are allowed before construction, but never generate reports.
	var waiting: float = float(worker.get("wander_wait", 0.0))
	if waiting > 0.0:
		worker["wander_wait"] = maxf(0.0, waiting - delta)
		return
	if worker.get("movement_path", []).is_empty():
		if not choose_inspection_destination(worker):
			worker["wander_wait"] = 5.0
		return
	if follow_worker_route(worker, delta):
		worker["movement_path"] = []
		worker["movement_index"] = 0
		complete_worker_inspection(worker)
		# A short pause makes inspections feel intentional.
		worker["wander_wait"] = 8.0 + float(worker["id"]) * 1.7


func get_built_hole_routes() -> Array:
	var result: Array = []
	if course_manager == null:
		return result
	for i in range(course_manager.holes.size()):
		var hole: Dictionary = course_manager.holes[i]
		var tee: Vector2 = hole.get("tee", Vector2(-1.0, -1.0))
		var basket: Vector2 = hole.get("basket", Vector2(-1.0, -1.0))
		if tee.x < 0.0 or basket.x < 0.0:
			continue
		result.append({"number": i + 1, "tee": tee, "basket": basket, "path_points": hole.get("path_points", [])})
	return result


func choose_inspection_destination(worker: Dictionary) -> bool:
	if property_manager == null:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = int(worker["id"]) * 104729 + int(Time.get_ticks_msec() / 11000)
	var holes: Array = get_built_hole_routes()
	var choices: Array = []
	# When there are built holes, inspections stay on playable corridors,
	# their walking paths, and links between successive holes.
	for hole_value in holes:
		var hole: Dictionary = hole_value
		var tee: Vector2 = hole["tee"]
		var basket: Vector2 = hole["basket"]
		var number: int = int(hole["number"])
		for step in range(7):
			var t: float = float(step) / 6.0
			choices.append({"point": tee.lerp(basket, t), "kind": "Hole %d inspection" % number, "hole": number, "other": -1})
		for path_value in hole["path_points"]:
			choices.append({"point": path_value, "kind": "Hole %d path inspection" % number, "hole": number, "other": -1})
	for i in range(holes.size() - 1):
		var current: Dictionary = holes[i]
		var following: Dictionary = holes[i + 1]
		# Inspect the link only when consecutive numbered holes exist.
		if int(following["number"]) != int(current["number"]) + 1:
			continue
		for step in range(1, 5):
			choices.append({"point": current["basket"].lerp(following["tee"], float(step) / 5.0), "kind": "Walking route inspection", "hole": int(current["number"]), "other": int(following["number"])})
	# Facilities are always valid patrol destinations, including before
	# the first hole is completed. No reports originate from these visits.
	if choices.is_empty() or rng.randf() < 0.16:
		var home: Vector2 = get_maintenance_local_position()
		if set_worker_route(worker, home):
			worker["inspection_type"] = "Facility check"
			worker["inspection_target"] = home
			worker["inspection_hole"] = -1
			worker["inspection_other_hole"] = -1
			return true
	if choices.is_empty():
		# Without a playable hole, short local patrols are fine but silent.
		var home_pos: Vector2 = get_maintenance_local_position()
		for attempt in range(10):
			var target: Vector2 = home_pos + Vector2(rng.randf_range(-180.0, 180.0), rng.randf_range(-180.0, 180.0))
			if set_worker_route(worker, target):
				worker["inspection_type"] = "Property patrol"
				worker["inspection_target"] = target
				worker["inspection_hole"] = -1
				worker["inspection_other_hole"] = -1
				return true
		return false
	# Randomize the first candidate, then try alternatives if blocked.
	var first: int = rng.randi_range(0, choices.size() - 1)
	for offset in range(choices.size()):
		var choice: Dictionary = choices[(first + offset) % choices.size()]
		# Hole tees, baskets and path points are already property-local.
		# Converting again sent patrols toward unrelated locations.
		var local_point: Vector2 = choice["point"]
		if set_worker_route(worker, local_point):
			worker["inspection_type"] = str(choice["kind"])
			worker["inspection_target"] = local_point
			worker["inspection_hole"] = int(choice["hole"])
			worker["inspection_other_hole"] = int(choice["other"])
			return true
	return false


func complete_worker_inspection(worker: Dictionary) -> void:
	if property_manager == null or get_built_hole_routes().is_empty():
		return
	if float(worker.get("observation_cooldown", 0.0)) > 0.0:
		return
	var hole_number: int = int(worker.get("inspection_hole", -1))
	if hole_number < 1:
		return
	var other_hole: int = int(worker.get("inspection_other_hole", -1))
	var destination: Vector2 = worker.get("inspection_target", Vector2.ZERO)
	# world_to_cell takes property-local coordinates.
	var cell: Vector2i = property_manager.world_to_cell(destination)
	if not property_manager.is_valid_cell(cell.x, cell.y):
		return
	var terrain_type: int = int(property_manager.terrain[cell.y][cell.x])
	var issue: String = ""
	if terrain_type == property_manager.TALL_GRASS or terrain_type == property_manager.ROUGH:
		issue = "grass"
	elif terrain_type == property_manager.WILD_GRASS:
		issue = "brush"
	if issue.is_empty():
		return
	var location: String = "Hole %d" % hole_number
	if other_hole > 0:
		location = "Holes %d–%d walking route" % [hole_number, other_hole]
	var report_key: String = "%d:%d:%s" % [hole_number, other_hole, issue]
	if reported_conditions.has(report_key):
		return
	var note: String = "%s: Tall grass is affecting the playing area. Consider scheduling mowing." % location
	if issue == "brush":
		note = "%s: Brush is becoming overgrown. Consider scheduling clearing." % location
	worker["observation"] = note
	worker["observation_cell"] = cell
	worker["observation_cooldown"] = 75.0
	reported_conditions[report_key] = true
	workers_changed.emit()


func get_worker_observations() -> Array:
	var reports: Array = []
	if get_built_hole_routes().is_empty():
		return reports
	for worker_value in workers:
		var worker: Dictionary = worker_value
		var note: String = str(worker.get("observation", ""))
		if not note.is_empty():
			reports.append({"worker_id": int(worker["id"]), "text": note, "hole": int(worker.get("inspection_hole", -1))})
	return reports


# ==================================================
# EQUIPMENT SCHEDULING
# ==================================================

func get_required_equipment_type(
	job_type: String
) -> String:

	if economy_manager == null:
		return ""

	match job_type:

		JOB_MOW:
			return economy_manager.EQUIPMENT_MOWER

		JOB_BRUSH:
			return economy_manager.EQUIPMENT_BRUSH_CUTTER

		JOB_TREE:
			return economy_manager.EQUIPMENT_CHAINSAW

	return ""


func get_reserved_equipment_count(
	equipment_type: String
) -> int:

	if equipment_type.is_empty():
		return 0

	return int(
		reserved_equipment.get(
			equipment_type,
			0
		)
	)


func get_available_equipment_count(
	equipment_type: String
) -> int:

	if equipment_type.is_empty():
		return 999999

	if economy_manager == null:
		return 999999

	return max(
		0,
		economy_manager.get_work_equipment_count(
			equipment_type
		)
		- get_reserved_equipment_count(
			equipment_type
		)
	)


func is_required_equipment_available(
	job_type: String
) -> bool:

	var equipment_type: String = (
		get_required_equipment_type(
			job_type
		)
	)

	return (
		get_available_equipment_count(
			equipment_type
		)
		> 0
	)


func reserve_equipment(
	equipment_type: String
) -> bool:

	if equipment_type.is_empty():
		return true

	if get_available_equipment_count(
		equipment_type
	) <= 0:
		return false

	reserved_equipment[
		equipment_type
	] = (
		get_reserved_equipment_count(
			equipment_type
		)
		+ 1
	)

	return true


func release_equipment(
	equipment_type: String
) -> void:

	if equipment_type.is_empty():
		return

	var reserved_count: int = (
		get_reserved_equipment_count(
			equipment_type
		)
	)

	if reserved_count <= 1:
		reserved_equipment.erase(
			equipment_type
		)
		return

	reserved_equipment[
		equipment_type
	] = reserved_count - 1


func get_job_equipment_display_name(
	job_type: String
) -> String:

	var equipment_type: String = (
		get_required_equipment_type(
			job_type
		)
	)

	if equipment_type.is_empty():
		return ""

	if economy_manager == null:
		return "Equipment"

	return economy_manager.get_work_equipment_display_name(
		equipment_type
	)


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
		if worker.get("movement_path", []).is_empty():
			if not set_worker_route(worker, target_position):
				return
		if not follow_worker_route(worker, delta):
			return
		worker["movement_path"] = []
		worker["movement_index"] = 0
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

	if grid_distance <= ADJACENT_CELL_DISTANCE and not property_manager.is_water_cell(target_cell.x, target_cell.y):

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
		# A* could not find a route. Never move straight across water
		# or through a building as a fallback. Retry on a later tick.
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

	if property_manager.is_water_cell(path_cell.x, path_cell.y):
		clear_worker_travel_path(worker)
		return
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

	var travel_speed: float = WORKER_TRAVEL_SPEED
	var phase: String = str(worker.get("state", WORKER_IDLE))
	if phase == WORKER_IDLE:
		travel_speed = WORKER_INSPECTION_SPEED
	elif phase == WORKER_FETCHING or phase == WORKER_RETURNING:
		travel_speed = WORKER_EQUIPMENT_SPEED
	var movement_distance: float = travel_speed * delta

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

	var walkway_cells: Dictionary = {}
	if walkway_manager != null:
		walkway_cells = walkway_manager.get_walkway_cells()
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
		) * 0.35
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

			if blocked_cells.has(neighbor):
				continue

			var tentative_g: float = (
				float(
					g_score.get(
						current,
						INF
					)
				)
				+ (0.35 if walkway_cells.has(neighbor) else 1.0)
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
				) * 0.35
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

	# Building footprints are solid, including the shed, office and
	# equipment yard. Use a small clearance around the exterior walls.
	for building_value in property_manager.buildings:
		var building: Dictionary = building_value
		var kind: String = str(building.get("type", ""))
		if not kind.begins_with("starter_"):
			continue
		if kind == "starter_parking":
			continue
		var center: Vector2 = property_manager.world_to_property_local(building["position"])
		var dimensions: Vector2 = building["size"]
		var footprint: Rect2 = Rect2(center - dimensions * 0.5, dimensions).grow(5.0)
		var min_x: int = maxi(0, int(floor(footprint.position.x / property_manager.CELL_SIZE)))
		var max_x: int = mini(property_manager.PROPERTY_GRID_WIDTH - 1, int(floor(footprint.end.x / property_manager.CELL_SIZE)))
		var min_y: int = maxi(0, int(floor(footprint.position.y / property_manager.CELL_SIZE)))
		var max_y: int = mini(property_manager.PROPERTY_GRID_HEIGHT - 1, int(floor(footprint.end.y / property_manager.CELL_SIZE)))
		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				var center_point: Vector2 = property_manager.cell_to_world_center(Vector2i(x, y))
				if footprint.has_point(center_point):
					navigation_blocked_cache[Vector2i(x, y)] = true

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
	if course_renderer != null:
		course_renderer.refresh_world()

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
			var inspection: String = str(worker.get("inspection_type", ""))
			return inspection if not inspection.is_empty() else "Idle"

		var phase: String = str(worker.get("state", WORKER_IDLE))
		if phase == WORKER_FETCHING:
			return "Collecting equipment"
		if phase == WORKER_RETURNING:
			return "Returning equipment"

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