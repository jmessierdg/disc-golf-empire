# Disc Golf Empire - Update 15: independently rendered walking-trail construction.
# Flight paths remain in CourseManager; these are physical visitor walkways.
extends Node2D

signal paths_changed
signal status_changed(message: String)

const COST_PER_FOOT := 2.0
const FEET_PER_PIXEL := 15.0 / 32.0
const BUILD_FEET_PER_SECOND := 9.0
const WORKER_WALK_SPEED := 66.0
const MIN_POINT_SPACING := 18.0

var property_manager
var economy_manager
var job_manager
var course_manager
var editing: bool = false
var draft: Array[Vector2] = []
var trails: Array = []
var next_trail_id: int = 1
var status: String = "Select WALKWAY to plan a walking trail."
var draw_clock: float = 0.0

func setup(property_ref, economy_ref, job_ref, course_ref) -> void:
	property_manager = property_ref
	economy_manager = economy_ref
	job_manager = job_ref
	course_manager = course_ref
	set_process(true)

func toggle_editing() -> void:
	editing = not editing
	if not editing:
		draft.clear()
	status = "Tap the property to add trail waypoints, then BUILD." if editing else "Walking-trail tool closed."
	status_changed.emit(status)
	queue_redraw()

func add_point(world_point: Vector2) -> bool:
	if not editing or property_manager == null:
		return false
	if not property_manager.is_world_position_inside_property(world_point):
		status = "Trail must stay inside your property."
		status_changed.emit(status)
		return true
	var local_point: Vector2 = property_manager.world_to_property_local(world_point)
	var cell: Vector2i = property_manager.world_to_cell(local_point)
	if property_manager.is_water_cell(cell.x, cell.y):
		status = "A bridge is required to cross water (future upgrade)."
		status_changed.emit(status)
		return true
	if not draft.is_empty() and draft[-1].distance_to(local_point) < MIN_POINT_SPACING:
		return true
	if not draft.is_empty() and not segment_is_clear(draft[-1], local_point):
		status = "That segment crosses water or leaves the property. Add a different waypoint."
		status_changed.emit(status)
		return true
	draft.append(local_point)
	status = "%d waypoints  •  Estimated cost $%d" % [draft.size(), estimate_cost(draft)]
	status_changed.emit(status)
	queue_redraw()
	return true

func segment_is_clear(start: Vector2, finish: Vector2) -> bool:
	var distance: float = start.distance_to(finish)
	var steps: int = maxi(1, ceili(distance / 12.0))
	for index in range(steps + 1):
		var local_point: Vector2 = start.lerp(finish, float(index) / float(steps))
		if not property_manager.is_local_position_inside_property(local_point):
			return false
		var cell: Vector2i = property_manager.world_to_cell(local_point)
		if property_manager.is_water_cell(cell.x, cell.y):
			return false
	return true

func trail_length(points: Array) -> float:
	var result: float = 0.0
	for index in range(1, points.size()):
		result += (points[index] as Vector2).distance_to(points[index - 1] as Vector2)
	return result

func estimate_cost(points: Array) -> int:
	return ceili(trail_length(points) * FEET_PER_PIXEL * COST_PER_FOOT)

func confirm_draft() -> bool:
	if draft.size() < 2:
		status = "Place at least two waypoints to construct a walkway."
		status_changed.emit(status)
		return false
	var price: int = estimate_cost(draft)
	if not economy_manager.spend(price):
		status = "Not enough cash. Trail costs $%d." % price
		status_changed.emit(status)
		return false
	var path_points: Array[Vector2] = draft.duplicate()
	var record: Dictionary = {
		"id": next_trail_id,
		"points": path_points,
		"length": trail_length(path_points),
		"built": 0.0,
		"status": "queued",
		"worker_id": -1,
		"cost": price
	}
	trails.append(record)
	next_trail_id += 1
	draft.clear()
	editing = false
	status = "Walkway #%d queued for construction ($%d)." % [int(record["id"]), price]
	status_changed.emit(status)
	paths_changed.emit()
	queue_redraw()
	return true

func cancel_draft() -> void:
	draft.clear()
	editing = false
	status = "Walkway plan canceled; no money spent."
	status_changed.emit(status)
	queue_redraw()

func _process(delta: float) -> void:
	if job_manager == null:
		return
	var dirty: bool = false
	for trail_value in trails:
		var trail: Dictionary = trail_value
		if str(trail["status"]) == "complete":
			continue
		var worker: Dictionary = get_assigned_worker(trail)
		if worker.is_empty():
			worker = claim_idle_worker(trail)
		if worker.is_empty():
			continue
		var work_point: Vector2 = point_along(trail["points"], float(trail["built"]))
		var current: Vector2 = worker.get("position", work_point)
		var remaining: float = current.distance_to(work_point)
		if remaining > 8.0:
			var heading: Vector2 = (work_point - current).normalized()
			worker["direction"] = heading
			worker["position"] = current + heading * minf(remaining, WORKER_WALK_SPEED * delta)
		else:
			trail["built"] = minf(float(trail["length"]), float(trail["built"]) + BUILD_FEET_PER_SECOND / FEET_PER_PIXEL * delta)
			if float(trail["built"]) >= float(trail["length"]):
				trail["status"] = "complete"
				worker["state"] = job_manager.WORKER_IDLE
				worker["job_id"] = -1
				worker["wander_wait"] = 3.0
				trail["worker_id"] = -1
				status = "Walkway #%d complete and ready for golfers." % int(trail["id"])
				status_changed.emit(status)
				paths_changed.emit()
		dirty = true
	if dirty:
		draw_clock += delta
		if draw_clock >= 0.1:
			draw_clock = 0.0
			queue_redraw()
			# Worker graphics are already on the independent dynamic renderer.
			if job_manager.course_renderer != null:
				job_manager.course_renderer.refresh_dynamic()

func claim_idle_worker(trail: Dictionary) -> Dictionary:
	for worker_value in job_manager.workers:
		var worker: Dictionary = worker_value
		if str(worker.get("state", "")) != job_manager.WORKER_IDLE:
			continue
		worker["state"] = "path_building"
		worker["job_id"] = -1
		worker["equipment_type"] = ""
		worker["movement_path"] = []
		worker["movement_index"] = 0
		trail["worker_id"] = int(worker["id"])
		trail["status"] = "building"
		job_manager.workers_changed.emit()
		return worker
	return {}

func get_assigned_worker(trail: Dictionary) -> Dictionary:
	var wanted: int = int(trail.get("worker_id", -1))
	if wanted < 0:
		return {}
	for worker_value in job_manager.workers:
		var worker: Dictionary = worker_value
		if int(worker.get("id", -1)) == wanted and str(worker.get("state", "")) == "path_building":
			return worker
	return {}

func point_along(points: Array, distance: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var remaining: float = distance
	for index in range(1, points.size()):
		var start: Vector2 = points[index - 1]
		var finish: Vector2 = points[index]
		var length: float = start.distance_to(finish)
		if remaining <= length:
			return start.lerp(finish, clampf(remaining / maxf(length, 0.001), 0.0, 1.0))
		remaining -= length
	return points[-1]

func _draw() -> void:
	if property_manager == null:
		return
	for trail_value in trails:
		var trail: Dictionary = trail_value
		var points: Array = trail["points"]
		var built_distance: float = float(trail["built"])
		var covered: float = 0.0
		for index in range(1, points.size()):
			var start: Vector2 = points[index - 1]
			var finish: Vector2 = points[index]
			var length: float = start.distance_to(finish)
			var first: Vector2 = property_manager.property_local_to_world(start)
			var last: Vector2 = property_manager.property_local_to_world(finish)
			draw_line(first, last, Color(0.26, 0.23, 0.16, 0.65), 13.0, true)
			if built_distance > covered:
				var fraction: float = clampf((built_distance - covered) / maxf(length, 0.001), 0.0, 1.0)
				var partial: Vector2 = first.lerp(last, fraction)
				draw_line(first, partial, Color(0.76, 0.64, 0.39, 1.0), 10.0, true)
			covered += length
	if draft.size() > 0:
		for index in range(draft.size()):
			var world_point: Vector2 = property_manager.property_local_to_world(draft[index])
			draw_circle(world_point, 8.0, Color(0.35, 0.92, 0.48, 0.85))
			if index > 0:
				var previous: Vector2 = property_manager.property_local_to_world(draft[index - 1])
				draw_line(previous, world_point, Color(0.35, 0.92, 0.48, 0.85), 7.0, true)

func get_completed_trails() -> Array:
	var result: Array = []
	for trail_value in trails:
		var trail: Dictionary = trail_value
		if str(trail["status"]) == "complete":
			result.append(trail)
	return result

func get_navigation_quality(from_local: Vector2, to_local: Vector2) -> Dictionary:
	# Designed for Update 17 golfers: path coverage and route continuity.
	var completed: Array = get_completed_trails()
	var direct: float = from_local.distance_to(to_local)
	var near_start: bool = false
	var near_end: bool = false
	for trail_value in completed:
		var trail: Dictionary = trail_value
		for waypoint in trail["points"]:
			if (waypoint as Vector2).distance_to(from_local) < 80.0:
				near_start = true
			if (waypoint as Vector2).distance_to(to_local) < 80.0:
				near_end = true
	return {"start_connected": near_start, "end_connected": near_end, "direct_distance": direct, "quality": "good" if near_start and near_end else "poor"}
