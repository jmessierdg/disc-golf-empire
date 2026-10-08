# Disc Golf Empire - Update 15: independently rendered walking-trail construction.
# Flight paths remain in CourseManager; these are physical visitor walkways.
# Draw order is controlled by main.gd: paths z=1, below foliage and actors.
extends Node2D

signal paths_changed
signal status_changed(message: String)

const COST_PER_FOOT := 2.0
const FEET_PER_PIXEL := 15.0 / 32.0
const BUILD_FEET_PER_SECOND := 9.0
const WORKER_WALK_SPEED := 66.0
const MIN_POINT_SPACING := 18.0
const SNAP_RADIUS := 24.0
const SNAP_ENDPOINT_RADIUS := 28.0
const CORNER_RADIUS := 15.0
const CURVE_STEPS := 7

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
var walkway_cell_cache: Dictionary = {}
var walkway_cache_dirty: bool = true
var snapping_enabled: bool = true
var last_snap: Dictionary = {}

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
		last_snap.clear()
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
	last_snap = find_snap(local_point)
	if snapping_enabled and not last_snap.is_empty():
		local_point = last_snap["point"]
	if not draft.is_empty() and draft[-1].distance_to(local_point) < MIN_POINT_SPACING:
		return true
	if not draft.is_empty() and not segment_is_clear(draft[-1], local_point):
		status = "That segment crosses water or leaves the property. Add a different waypoint."
		status_changed.emit(status)
		return true
	draft.append(local_point)
	status = "%d waypoints  •  Estimated cost $%d" % [draft.size(), estimate_cost(draft)]
	if snapping_enabled and not last_snap.is_empty():
		status += "  •  SNAPPED"
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
	# Split intersections into explicit graph vertices. Existing trail lengths
	# remain unchanged, so construction progress and costs are preserved.
	connect_trail_intersections(record)
	next_trail_id += 1
	draft.clear()
	editing = false
	status = "Walkway #%d queued for construction ($%d)." % [int(record["id"]), price]
	status_changed.emit(status)
	walkway_cache_dirty = true
	paths_changed.emit()
	queue_redraw()
	return true

func cancel_draft() -> void:
	draft.clear()
	last_snap.clear()
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
				walkway_cache_dirty = true
				paths_changed.emit()
		dirty = true
	if dirty:
		draw_clock += delta
		if draw_clock >= 0.1:
			draw_clock = 0.0
			walkway_cache_dirty = true
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

# Magnetic snapping to endpoints, intersections, and the middle of built segments.
# Only completed trails are snap targets; unfinished construction is not navigable.
func find_snap(local_point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = SNAP_RADIUS
	for trail_value in trails:
		var trail: Dictionary = trail_value
		if str(trail.get("status", "")) != "complete":
			continue
		var points: Array = trail["points"]
		for i in range(points.size()):
			var vertex: Vector2 = points[i]
			var d: float = local_point.distance_to(vertex)
			if d < minf(best_distance, SNAP_ENDPOINT_RADIUS):
				best_distance = d
				best = {"point": vertex, "trail_id": int(trail["id"]), "kind": "endpoint"}
		for i in range(1, points.size()):
			var a: Vector2 = points[i - 1]
			var b: Vector2 = points[i]
			var delta: Vector2 = b - a
			if delta.length_squared() < 0.01:
				continue
			var t: float = clampf((local_point - a).dot(delta) / delta.length_squared(), 0.0, 1.0)
			var projected: Vector2 = a + delta * t
			var d: float = local_point.distance_to(projected)
			if d < best_distance:
				best_distance = d
				best = {"point": projected, "trail_id": int(trail["id"]), "kind": "segment"}
	return best

func set_snapping_enabled(value: bool) -> void:
	snapping_enabled = value
	last_snap.clear()
	status = "Walkway snapping ON" if value else "Walkway snapping OFF"
	status_changed.emit(status)
	queue_redraw()

# Segment intersection using the parametric cross-product method.
func segment_intersection(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Dictionary:
	var r: Vector2 = b - a
	var q: Vector2 = d - c
	var denom: float = r.cross(q)
	if absf(denom) < 0.00001:
		return {}
	var t: float = (c - a).cross(q) / denom
	var u: float = (c - a).cross(r) / denom
	if t < -0.0001 or t > 1.0001 or u < -0.0001 or u > 1.0001:
		return {}
	return {"point": a + r * clampf(t, 0.0, 1.0), "t": t, "u": u}

func insert_vertices(points: Array, insertions: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if points.is_empty():
		return result
	result.append(points[0])
	for i in range(1, points.size()):
		var additions: Array = insertions.get(i, [])
		additions.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
		for item in additions:
			var vertex: Vector2 = item["point"]
			if result[-1].distance_to(vertex) > 0.1 and vertex.distance_to(points[i]) > 0.1:
				result.append(vertex)
		if result[-1].distance_to(points[i]) > 0.1:
			result.append(points[i])
	return result

func connect_trail_intersections(new_trail: Dictionary) -> void:
	var new_points: Array = new_trail["points"]
	var new_additions: Dictionary = {}
	for trail_value in trails:
		var existing: Dictionary = trail_value
		if existing == new_trail or str(existing.get("status", "")) != "complete":
			continue
		var old_points: Array = existing["points"]
		var old_additions: Dictionary = {}
		for i in range(1, new_points.size()):
			for j in range(1, old_points.size()):
				var hit: Dictionary = segment_intersection(new_points[i - 1], new_points[i], old_points[j - 1], old_points[j])
				if hit.is_empty():
					continue
				if not new_additions.has(i):
					new_additions[i] = []
				new_additions[i].append({"t": hit["t"], "point": hit["point"]})
				if not old_additions.has(j):
					old_additions[j] = []
				old_additions[j].append({"t": hit["u"], "point": hit["point"]})
		if not old_additions.is_empty():
			existing["points"] = insert_vertices(old_points, old_additions)
	if not new_additions.is_empty():
		new_trail["points"] = insert_vertices(new_points, new_additions)
	walkway_cache_dirty = true

func draw_round_stroke(from_point: Vector2, to_point: Vector2, tint: Color, width: float) -> void:
	draw_line(from_point, to_point, tint, width, true)
	draw_circle(from_point, width * 0.5, tint)
	draw_circle(to_point, width * 0.5, tint)

# Smooth a polyline using quadratic Bezier arcs at sharp bends.
# A corner is rounded only when both adjacent segments are already built.
func rounded_points(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.is_empty():
		return result
	result.append(points[0])
	for i in range(1, points.size() - 1):
		var previous: Vector2 = points[i - 1]
		var corner: Vector2 = points[i]
		var following: Vector2 = points[i + 1]
		var incoming: Vector2 = corner - previous
		var outgoing: Vector2 = following - corner
		if incoming.length() < 0.1 or outgoing.length() < 0.1:
			result.append(corner)
			continue
		var turn: float = incoming.normalized().dot(outgoing.normalized())
		if turn > 0.985 or turn < -0.985:
			result.append(corner)
			continue
		var radius: float = minf(CORNER_RADIUS, minf(incoming.length(), outgoing.length()) * 0.35)
		var before: Vector2 = corner - incoming.normalized() * radius
		var after: Vector2 = corner + outgoing.normalized() * radius
		result.append(before)
		for step in range(1, CURVE_STEPS):
			var t: float = float(step) / float(CURVE_STEPS)
			result.append(before * (1.0 - t) * (1.0 - t) + corner * 2.0 * t * (1.0 - t) + after * t * t)
		result.append(after)
	result.append(points[-1])
	return result

func draw_smooth_trail(points: Array, tint: Color, width: float) -> void:
	var curve: PackedVector2Array = rounded_points(points)
	for i in range(1, curve.size()):
		draw_round_stroke(curve[i - 1], curve[i], tint, width)

func _draw() -> void:
	if property_manager == null:
		return
	for trail_value in trails:
		var trail: Dictionary = trail_value
		var points: Array = trail["points"]
		var built_distance: float = float(trail["built"])
		var covered: float = 0.0
		var corridor: Array = []
		var completed: Array = []
		if not points.is_empty():
			corridor.append(property_manager.property_local_to_world(points[0]))
			completed.append(corridor[0])
		for i in range(1, points.size()):
			var start: Vector2 = points[i - 1]
			var finish: Vector2 = points[i]
			var length: float = start.distance_to(finish)
			var world_finish: Vector2 = property_manager.property_local_to_world(finish)
			corridor.append(world_finish)
			if built_distance > covered:
				var fraction: float = clampf((built_distance - covered) / maxf(length, 0.001), 0.0, 1.0)
				completed.append(property_manager.property_local_to_world(start.lerp(finish, fraction)))
			covered += length
		# Draw border first, then the entire built surface, merging all joints.
		draw_smooth_trail(corridor, Color(0.26, 0.23, 0.16, 0.65), 13.0)
		if completed.size() > 1:
			draw_smooth_trail(completed, Color(0.76, 0.64, 0.39, 1.0), 10.0)
	if draft.size() > 0:
		var draft_world: Array = []
		for point in draft:
			draft_world.append(property_manager.property_local_to_world(point))
		draw_smooth_trail(draft_world, Color(0.35, 0.92, 0.48, 0.85), 7.0)
		for point in draft_world:
			draw_circle(point, 5.0, Color(0.35, 0.92, 0.48, 0.85))
# Sample built trail corridors once into a shared lookup for worker and future
# golfer navigation. Do not sample these paths inside each A* node expansion.
func get_walkway_cells() -> Dictionary:
	if not walkway_cache_dirty:
		return walkway_cell_cache
	walkway_cell_cache.clear()
	if property_manager == null:
		return walkway_cell_cache
	for trail_value in trails:
		var trail: Dictionary = trail_value
		var points: Array = trail["points"]
		var built_length: float = float(trail["built"])
		var covered: float = 0.0
		for index in range(1, points.size()):
			if covered >= built_length:
				break
			var first: Vector2 = points[index - 1]
			var last: Vector2 = points[index]
			var length: float = first.distance_to(last)
			var usable: float = minf(length, built_length - covered)
			var steps: int = maxi(1, ceili(usable / 8.0))
			for step in range(steps + 1):
				var location: Vector2 = first.lerp(last, (usable * float(step) / float(steps)) / maxf(length, 0.001))
				var cell: Vector2i = property_manager.world_to_cell(location)
				if property_manager.is_valid_cell(cell.x, cell.y):
					walkway_cell_cache[cell] = true
			covered += length
	walkway_cache_dirty = false
	return walkway_cell_cache

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
