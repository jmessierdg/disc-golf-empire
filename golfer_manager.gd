# Disc Golf Empire - Update 34: flight shapes and multi-hole progression safeguards.
# Based on the working Update 30 arrival/check-in/navigation system.
extends Node2D

signal visitor_arrived(person_id: int)
signal visitor_departed(person_id: int)

const MAX_VISITORS := 4
const GROUP_SIZE := 2
const PARTNER_WAIT_SECONDS := 1.5
const TEE_PREPARE_SECONDS := 2.2
const BETWEEN_SHOTS_SECONDS := 1.0
const CHECKIN_SECONDS := 2.0
const FEEDBACK_SECONDS := 3.0
const WALK_SPEED := 19.0
const CAR_SPEED := 95.0
const PARK_SECONDS := 2.0
const SPAWN_INTERVAL := 14.0
const THROW_INTERVAL := 1.6
const MAX_STROKES := 12
const FEET_PER_PIXEL := 15.0 / 32.0
const PUTT_RANGE_PIXELS := 42.0
const FLIGHT_MIN_SECONDS := 0.65
const FLIGHT_MAX_SECONDS := 2.3
const FLIGHT_ARC_PIXELS := 82.0
const FLIGHT_SHADOW_ALPHA := 0.26
const FLIGHT_DISC_RADIUS := 4.0
const SAVE_PATH := "user://dge_people_v1.json"
const FIRST_NAMES := ["Ethan", "Morgan", "Avery", "Taylor", "Riley", "Jordan", "Casey", "Alex", "Jamie", "Quinn", "Parker", "Rowan", "Sam", "Cameron"]
const LAST_NAMES := ["Brooks", "Reed", "Morgan", "Walker", "Parker", "Bennett", "Hayes", "Rivera", "Turner", "Ellis", "Stone", "Miller"]
const SKILLS := ["power", "accuracy", "putting", "control", "course_iq", "composure"]
const PALETTE := [Color("5e9ec7"), Color("d59c64"), Color("b46d9b"), Color("81b36c"), Color("cf8d72"), Color("847dc2")]

var property_manager
var course_manager
var path_manager
var navigation_manager
var people: Dictionary = {}
var visitors: Array = []
var next_person_id: int = 1
var next_membership_number: int = 10001
var spawn_timer: float = 2.0
var next_group_id: int = 1
var last_feedback: String = ""
# One active throw per twosome; tracks whose turn it is on the current hole.
var group_turns: Dictionary = {}
# One active group per hole; queued groups may wait at the tee.
var hole_owners: Dictionary = {}
# All gameplay destinations use PROPERTY-LOCAL coordinates.
var course_locations: Dictionary = {}
const DEBUG_DESTINATIONS := false
var render_timer: float = 0.0
var visual_time: float = 0.0
var visual_positions: Dictionary = {}
const VISUAL_FOLLOW_RATE := 11.0
var rng := RandomNumberGenerator.new()
var profile_layer: CanvasLayer
var profile_panel: PanelContainer
var profile_label: Label
var selected_id: int = -1

func setup(property_ref, course_ref, path_ref) -> void:
	property_manager = property_ref
	course_manager = course_ref
	path_manager = path_ref
	# Reuse the grounds crew's obstacle-aware, path-preferring navigation.
	navigation_manager = get_parent().get_node_or_null("JobManager")
	z_index = 4
	rng.randomize()
	load_people()
	build_profile()
	set_process(true)

func get_entrance_local() -> Vector2:
	# Roadside entrance is the outermost point of the property's connected driveway.
	if property_manager.property_driveway_points.size() > 0:
		var points: Array = property_manager.property_driveway_points
		return property_manager.world_to_property_local(points[0])
	return property_manager.get_property_local_center()

func get_parking_local() -> Vector2:
	var facility: Dictionary = property_manager.get_starter_facility("starter_parking")
	if not facility.is_empty():
		return property_manager.world_to_property_local(facility["position"])
	if property_manager.property_driveway_points.size() > 0:
		var points: Array = property_manager.property_driveway_points
		return property_manager.world_to_property_local(points[points.size() - 1])
	return property_manager.get_property_local_center()

func get_checkin_local() -> Vector2:
	# Starter office position is world-space; golfer destinations are property-local.
	var office: Dictionary = property_manager.get_starter_facility("starter_office")
	if not office.is_empty():
		var office_local: Vector2 = property_manager.world_to_property_local(office["position"])
		# Stand just outside the office entrance rather than inside its footprint.
		var office_size: Vector2 = office.get("size", Vector2(52.0, 64.0))
		return clamp_to_property(office_local + Vector2(office_size.x * 0.5 + 10.0, 0.0))
	return get_parking_local()


func get_parking_slot(slot_index: int) -> Vector2:
	# Four distinct marked positions inside the existing starter parking footprint.
	var center: Vector2 = get_parking_local()
	var facility: Dictionary = property_manager.get_starter_facility("starter_parking")
	var size: Vector2 = facility.get("size", Vector2(140.0, 120.0))
	var column: int = slot_index % 2
	var row: int = int(slot_index / 2)
	return center + Vector2(
		(-0.24 if column == 0 else 0.24) * size.x,
		(-0.23 if row == 0 else 0.23) * size.y
	)


func occupied_parking_slots() -> Dictionary:
	var used: Dictionary = {}
	for visitor_value in visitors:
		var visitor: Dictionary = visitor_value
		used[int(visitor.get("slot_index", -1))] = true
	return used


func get_partner(visitor: Dictionary) -> Dictionary:
	var partner_id: int = int(visitor.get("partner_id", -1))
	for value in visitors:
		var other: Dictionary = value
		if int(other["id"]) == partner_id:
			return other
	return {}


func group_ready_for_tee(visitor: Dictionary) -> bool:
	var partner: Dictionary = get_partner(visitor)
	if partner.is_empty():
		return false
	if int(partner["hole_cursor"]) != int(visitor["hole_cursor"]):
		return false
	# Both must actually reach the tee before either is allowed to throw.
	return str(partner["stage"]) == "waiting_at_tee" or int(partner.get("strokes", 0)) > 0


func get_group_turn(visitor: Dictionary) -> int:
	var group_id: int = int(visitor["group_id"])
	if not group_turns.has(group_id):
		var partner: Dictionary = get_partner(visitor)
		if partner.is_empty():
			return int(visitor["id"])
		group_turns[group_id] = mini(int(visitor["id"]), int(partner["id"]))
	return int(group_turns[group_id])


func may_throw(visitor: Dictionary) -> bool:
	var partner: Dictionary = get_partner(visitor)
	if partner.is_empty() or int(partner["hole_cursor"]) != int(visitor["hole_cursor"]):
		return false
	var hole_index: int = int(visitor["holes"][int(visitor["hole_cursor"])])
	if int(hole_owners.get(hole_index, -1)) != int(visitor["group_id"]):
		return false
	var partner_stage: String = str(partner["stage"])
	if partner_stage == "disc_flying":
		return false
	if int(visitor["strokes"]) == 0:
		if not bool(visitor.get("tee_ready", false)) or not bool(partner.get("tee_ready", false)):
			return false
		# Complete both tee shots before fairway throws.
		if int(partner["strokes"]) > 0:
			return true
		return get_group_turn(visitor) == int(visitor["id"])
	if int(partner["strokes"]) == 0:
		return false
	if partner_stage in ["waiting_at_basket", "walking_to_basket"]:
		return true
	# A golfer at the lie may throw while the partner walks, but only
	# if they are farther out or their partner is not ready to throw.
	if partner_stage == "walking_to_lie":
		return true
	if partner_stage == "throwing":
		var basket: Vector2 = hole_local(hole_index, "basket")
		var own_distance: float = (visitor["disc_position"] as Vector2).distance_to(basket)
		var other_distance: float = (partner["disc_position"] as Vector2).distance_to(basket)
		if absf(own_distance - other_distance) > 1.0:
			return own_distance > other_distance
	return get_group_turn(visitor) == int(visitor["id"])


func finish_throw_turn(visitor: Dictionary) -> void:
	var partner: Dictionary = get_partner(visitor)
	if not partner.is_empty():
		group_turns[int(visitor["group_id"])] = int(partner["id"])


func group_ready_for_next_hole(visitor: Dictionary) -> bool:
	var partner: Dictionary = get_partner(visitor)
	if partner.is_empty():
		return false
	return str(partner["stage"]) == "waiting_at_basket" and int(partner["hole_cursor"]) == int(visitor["hole_cursor"])


func move_group_to_next_hole(visitor: Dictionary) -> void:
	var partner: Dictionary = get_partner(visitor)
	if partner.is_empty():
		return
	var cursor: int = int(visitor["hole_cursor"])
	# Pick up newly completed holes at the transition, not just at arrival.
	var latest_holes: Array = completed_holes()
	for member in [visitor, partner]:
		var itinerary: Array = member["holes"]
		for candidate in latest_holes:
			if not itinerary.has(candidate):
				itinerary.append(candidate)
		itinerary.sort()
		member["holes"] = itinerary
	refresh_course_locations()
	group_turns.erase(int(visitor["group_id"]))
	var completed_hole: int = int(visitor["holes"][cursor])
	if int(hole_owners.get(completed_hole, -1)) == int(visitor["group_id"]):
		hole_owners.erase(completed_hole)
	for member in [visitor, partner]:
		member["tee_ready"] = false
		member["strokes"] = 0
		member["hole_cursor"] = cursor + 1
		if cursor + 1 < member["holes"].size():
			member["stage"] = "walking_to_tee"
			set_destination(member, hole_local(int(member["holes"][cursor + 1]), "tee"))
		else:
			member["stage"] = "feedback"
			member["wait"] = FEEDBACK_SECONDS
			record_round(member)


func record_round(visitor: Dictionary) -> void:
	if bool(visitor.get("round_recorded", false)):
		return
	visitor["round_recorded"] = true
	var person: Dictionary = people[int(visitor["id"])]
	person["visits"] = int(person["visits"]) + 1
	var scores: Dictionary = visitor["round_scores"]
	var total_strokes: int = 0
	var total_par: int = 0
	for result_value in scores.values():
		var result: Dictionary = result_value
		total_strokes += int(result["strokes"])
		total_par += int(result["par"])
	var feedback: String = "Enjoyed playing %d available holes with a partner." % scores.size()
	if float(visitor["off_path"]) > float(visitor["walked"]) * 0.55:
		feedback = "Fun round with a partner, but the walking routes need improvement."
	person["feedback"].append(feedback)
	person["history"].append({"holes": scores.size(), "scores": scores.duplicate(true), "strokes": total_strokes, "par": total_par, "feedback": feedback})
	last_feedback = "%s: %s" % [str(person["name"]), feedback]
	save_people()


func get_driveway_route(to_parking: bool, parking_slot: Vector2) -> Array:
	var route: Array = []
	for world_point in property_manager.property_driveway_points:
		route.append(property_manager.world_to_property_local(world_point))
	if not to_parking:
		route.reverse()
		route.push_front(parking_slot)
	else:
		route.append(parking_slot)
	return route

func refresh_course_locations() -> void:
	# CourseManager stores tee and basket coordinates in property-local space.
	# Never convert these a second time.
	course_locations.clear()
	course_locations["entrance"] = get_entrance_local()
	course_locations["parking"] = get_parking_local()
	course_locations["checkin"] = get_checkin_local()
	for i in range(course_manager.holes.size()):
		if not course_manager.is_hole_complete(i):
			continue
		var hole: Dictionary = course_manager.get_hole(i)
		course_locations[i] = {
			"tee": hole["tee"],
			"basket": hole["basket"]
		}


func completed_holes() -> Array:
	var result: Array = []
	for i in range(course_manager.holes.size()):
		if course_manager.is_hole_complete(i):
			result.append(i)
	return result

func make_person() -> Dictionary:
	var person_id: int = next_person_id
	next_person_id += 1
	var registered: bool = rng.randf() < 0.28
	var professional: bool = registered and rng.randf() < 0.09
	var skills: Dictionary = {}
	for skill in SKILLS:
		var baseline: int = 57 if registered else 43
		skills[skill] = clampi(baseline + rng.randi_range(-22, 22) + (19 if professional else 0), 10, 99)
	var number: int = -1
	if registered:
		number = next_membership_number
		next_membership_number += 1
	var person: Dictionary = {
		"id": person_id,
		"name": "%s %s" % [FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)], LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]],
		"age": rng.randi_range(16, 69),
		"handedness": "Left" if rng.randf() < 0.12 else "Right",
		"personality": ["Patient", "Competitive", "Curious", "Social", "Methodical"][rng.randi_range(0, 4)],
		"appearance": rng.randi_range(0, PALETTE.size() - 1),
		"skills": skills,
		"membership_number": number,
		"classification": "Professional" if professional else ("Amateur" if registered else "Recreational"),
		"visits": 0,
		"holes_visited": 0,
		"feedback": [],
		"history": []
	}
	people[person_id] = person
	save_people()
	return person

func spawn_visitor() -> void:
	# Only admit a complete pair when two actual parking spaces are free.
	refresh_course_locations()
	var holes: Array = completed_holes()
	if holes.is_empty() or visitors.size() + GROUP_SIZE > MAX_VISITORS:
		return
	var used: Dictionary = occupied_parking_slots()
	var available: Array = []
	for slot_index in range(MAX_VISITORS):
		if not used.has(slot_index):
			available.append(slot_index)
	if available.size() < GROUP_SIZE:
		return
	var group_id: int = next_group_id
	next_group_id += 1
	var pair: Array = []
	for index in range(GROUP_SIZE):
		var person: Dictionary = make_person()
		var start: Vector2 = get_entrance_local()
		var slot_index: int = int(available[index])
		var slot: Vector2 = get_parking_slot(slot_index)
		var visitor: Dictionary = {
			"id": int(person["id"]), "position": start,
			"state": "arriving", "holes": holes.duplicate(),
			"hole_cursor": 0, "stage": "driving_in",
			"group_id": group_id, "partner_id": -1, "slot_index": slot_index,
			"parking_slot": slot, "car_position": start,
			"route": get_driveway_route(true, slot), "route_index": 0,
			"wait": float(index) * 2.5, "walked": 0.0, "off_path": 0.0,
			"route_distance": 0.0, "strokes": 0, "round_scores": {},
			"disc_position": start, "last_throw": "", "throw_wait": 0.0,
			"round_recorded": false, "destination": slot, "destination_kind": "parking",
			"tee_ready": false, "shot_pause": 0.0, "checked_in": false,
			"flight_start": start, "flight_end": start, "flight_elapsed": 0.0,
			"flight_duration": 0.0, "flight_sunk": false,
			"flight_curve": 0.0, "flight_turn": 0.0, "flight_fade": 0.0
		}
		pair.append(visitor)
	pair[0]["partner_id"] = int(pair[1]["id"])
	pair[1]["partner_id"] = int(pair[0]["id"])
	for visitor in pair:
		visitors.append(visitor)
		visitor_arrived.emit(int(visitor["id"]))


func hole_local(index: int, which: String) -> Vector2:
	# Single source of truth: all cached hole locations are property-local.
	if not course_locations.has(index):
		refresh_course_locations()
	if course_locations.has(index):
		return course_locations[index].get(which, Vector2.ZERO)
	return Vector2.ZERO

func _process(delta: float) -> void:
	if property_manager == null:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = SPAWN_INTERVAL
		spawn_visitor()
	# Process a snapshot because visitors can depart during this frame.
	for value in visitors.duplicate():
		var visitor: Dictionary = value
		if not visitors.has(visitor):
			continue
		if float(visitor["wait"]) > 0.0:
			visitor["wait"] = maxf(0.0, float(visitor["wait"]) - delta)
			continue
		var stage: String = str(visitor["stage"])
		match stage:
			"driving_in", "driving_out":
				if advance_vehicle(visitor, delta):
					advance_stage(visitor)
			"waiting_partner":
				var partner: Dictionary = get_partner(visitor)
				# Synchronize at parking, then send BOTH to the check-in desk.
				if not partner.is_empty() and str(partner["stage"]) == "waiting_partner":
					for member in [visitor, partner]:
						member["stage"] = "walking_to_checkin"
						set_destination(member, get_checkin_local())
			"waiting_at_checkin":
				var partner: Dictionary = get_partner(visitor)
				if not partner.is_empty() and str(partner["stage"]) == "waiting_at_checkin":
					for member in [visitor, partner]:
						member["checked_in"] = true
						member["stage"] = "walking_to_tee"
						set_destination(member, hole_local(int(member["holes"][0]), "tee"))
			"waiting_at_tee":
				var partner: Dictionary = get_partner(visitor)
				if bool(visitor.get("checked_in", false)) and not partner.is_empty() and bool(partner.get("checked_in", false)) and str(partner["stage"]) == "waiting_at_tee":
					var hole_index: int = int(visitor["holes"][int(visitor["hole_cursor"])])
					var owner: int = int(hole_owners.get(hole_index, -1))
					if owner == -1 or owner == int(visitor["group_id"]):
						hole_owners[hole_index] = int(visitor["group_id"])
						for member in [visitor, partner]:
							member["tee_ready"] = true
							member["disc_position"] = hole_local(hole_index, "tee")
							member["stage"] = "throwing"
							member["wait"] = TEE_PREPARE_SECONDS
			"waiting_at_basket":
				if group_ready_for_next_hole(visitor):
					move_group_to_next_hole(visitor)
			"feedback":
				visitor["stage"] = "walking_to_car"
				set_destination(visitor, visitor["parking_slot"])
			"navigation_blocked":
				# Don't wander: retry the actual current objective.
				visitor["wait"] = 4.0
				if int(visitor["hole_cursor"]) >= visitor["holes"].size():
					visitor["stage"] = "walking_to_car"
					set_destination(visitor, visitor["parking_slot"])
				elif str(visitor.get("blocked_goal", "")) == "basket":
					visitor["stage"] = "walking_to_basket"
					set_destination(visitor, hole_local(int(visitor["holes"][int(visitor["hole_cursor"])]), "basket"))
				elif str(visitor.get("blocked_goal", "")) == "lie":
					visitor["stage"] = "walking_to_lie"
					set_destination(visitor, visitor["disc_position"])
				else:
					visitor["stage"] = "walking_to_tee"
					set_destination(visitor, hole_local(int(visitor["holes"][int(visitor["hole_cursor"])]), "tee"))
			"throwing":
				if may_throw(visitor):
					perform_throw(visitor)
					finish_throw_turn(visitor)
			"disc_flying":
				visitor["flight_elapsed"] = minf(float(visitor["flight_duration"]), float(visitor["flight_elapsed"]) + delta)
				if float(visitor["flight_elapsed"]) >= float(visitor["flight_duration"]):
					complete_flight(visitor)
			"parking":
				advance_stage(visitor)
			"walking_to_checkin", "walking_to_tee", "walking_to_lie", "walking_to_basket", "walking_to_car":
				# Never freeze navigation because partners are too far apart.
				# Synchronization happens at check-in, tees, and baskets.
				if advance_visitor(visitor, delta):
					advance_stage(visitor)
	visual_time += delta
	update_visual_positions(delta)
	render_timer += delta
	if render_timer >= 1.0 / 30.0:
		render_timer = 0.0
		queue_redraw()


func clamp_to_property(point: Vector2) -> Vector2:
	var size: Vector2 = property_manager.get_property_size_pixels()
	var inset: float = property_manager.CELL_SIZE * 0.6
	return Vector2(clampf(point.x, inset, size.x - inset), clampf(point.y, inset, size.y - inset))

func route_on_property(start: Vector2, finish: Vector2) -> Array:
	# Temporary forced-play routing: walk straight to the real objective.
	# Do not use worker A*: it was sending golfers on long detours.
	# Both points are PROPERTY-LOCAL, never world coordinates.
	var safe_finish: Vector2 = clamp_to_property(finish)
	if start.distance_to(safe_finish) <= 1.0:
		return [safe_finish]
	return [safe_finish]


func set_destination(visitor: Dictionary, destination: Vector2) -> void:
	var safe_destination: Vector2 = clamp_to_property(destination)
	visitor["destination"] = safe_destination
	visitor["destination_kind"] = str(visitor.get("stage", ""))
	var route: Array = route_on_property(visitor["position"], safe_destination)
	if route.is_empty():
		# No traversable route: remain in place instead of walking into nowhere.
		visitor["blocked_goal"] = ("basket" if str(visitor["stage"]) == "walking_to_basket" else ("lie" if str(visitor["stage"]) == "walking_to_lie" else "tee"))
		visitor["stage"] = "navigation_blocked"
		visitor["route"] = []
		visitor["route_index"] = 0
		visitor["wait"] = 3.0
		return
	visitor["route"] = route
	visitor["route_index"] = 0
	visitor["route_distance"] = 0.0

func route_via_walkways(start: Vector2, finish: Vector2) -> Array:
	# Build a small connected graph from completed trail segments. Junctions
	# inserted by PathManager become shared graph vertices.
	var nodes: Array = []
	var edges: Dictionary = {}
	var index_by_key: Dictionary = {}
	for trail_value in path_manager.get_completed_trails():
		var trail: Dictionary = trail_value
		var previous: int = -1
		for point_value in trail["points"]:
			var point: Vector2 = point_value
			var key: Vector2i = Vector2i(roundi(point.x * 2.0), roundi(point.y * 2.0))
			if not index_by_key.has(key):
				index_by_key[key] = nodes.size()
				nodes.append(point)
				edges[nodes.size() - 1] = []
			var current: int = int(index_by_key[key])
			if previous >= 0 and previous != current:
				var cost: float = (nodes[previous] as Vector2).distance_to(point)
				edges[previous].append({"to": current, "cost": cost})
				edges[current].append({"to": previous, "cost": cost})
			previous = current
	if nodes.is_empty():
		return [finish]
	# Use the closest walkable trail entry/exit; avoid absurd detours.
	var entry: int = 0
	var exit_node: int = 0
	for n in range(nodes.size()):
		if (nodes[n] as Vector2).distance_to(start) < (nodes[entry] as Vector2).distance_to(start):
			entry = n
		if (nodes[n] as Vector2).distance_to(finish) < (nodes[exit_node] as Vector2).distance_to(finish):
			exit_node = n
	var dist: Dictionary = {entry: 0.0}
	var prev: Dictionary = {}
	var open_nodes: Array = [entry]
	while not open_nodes.is_empty():
		var best: int = 0
		for j in range(1, open_nodes.size()):
			if float(dist[open_nodes[j]]) < float(dist[open_nodes[best]]):
				best = j
		var current: int = int(open_nodes[best])
		open_nodes.remove_at(best)
		if current == exit_node:
			break
		for edge_value in edges[current]:
			var edge: Dictionary = edge_value
			var other: int = int(edge["to"])
			var candidate: float = float(dist[current]) + float(edge["cost"])
			if not dist.has(other) or candidate < float(dist[other]):
				dist[other] = candidate
				prev[other] = current
				if not open_nodes.has(other):
					open_nodes.append(other)
	if not dist.has(exit_node):
		return [finish]
	var total: float = start.distance_to(nodes[entry]) + float(dist[exit_node]) + (nodes[exit_node] as Vector2).distance_to(finish)
	if total > start.distance_to(finish) * 2.5 + 90.0:
		return [finish]
	var indexes: Array = [exit_node]
	var cursor: int = exit_node
	while cursor != entry and prev.has(cursor):
		cursor = int(prev[cursor])
		indexes.push_front(cursor)
	var route: Array = []
	for index_value in indexes:
		route.append(nodes[int(index_value)])
	route.append(finish)
	return route

func advance_vehicle(visitor: Dictionary, delta: float) -> bool:
	var route: Array = visitor["route"]
	var index: int = int(visitor["route_index"])
	if index >= route.size():
		return true
	var target: Vector2 = route[index]
	var current: Vector2 = visitor["position"]
	visitor["position"] = current.move_toward(target, CAR_SPEED * delta)
	visitor["car_position"] = visitor["position"]
	if visitor["position"].distance_to(target) <= 0.1:
		visitor["route_index"] = index + 1
	return int(visitor["route_index"]) >= route.size()

func advance_visitor(visitor: Dictionary, delta: float) -> bool:
	var route: Array = visitor["route"]
	var index: int = int(visitor["route_index"])
	if index >= route.size():
		return false
	var target: Vector2 = route[index]
	var current: Vector2 = visitor["position"]
	var distance: float = current.distance_to(target)
	var travel: float = minf(distance, WALK_SPEED * delta)
	if distance > 0.01:
		visitor["position"] = current.move_toward(target, travel)
	visitor["walked"] = float(visitor["walked"]) + travel
	if route.size() == 1 or index == 0 or index == route.size() - 1:
		visitor["off_path"] = float(visitor["off_path"]) + travel
	if distance <= WALK_SPEED * delta + 0.01:
		visitor["route_index"] = index + 1
	return int(visitor["route_index"]) >= route.size()

# Distances are property-local pixels; 32 px represents 15 real feet.
# A recreational player's drive typically travels farther than the old 24-264 px range.
# This is a gameplay approximation, not a full aerodynamic physics simulation.
func perform_throw(visitor: Dictionary) -> void:
	var holes: Array = visitor["holes"]
	var hole_number: int = int(holes[int(visitor["hole_cursor"])])
	if not course_manager.is_hole_complete(hole_number):
		finish_hole(visitor)
		return
	var person: Dictionary = people[int(visitor["id"])]
	var skills: Dictionary = person["skills"]
	var basket: Vector2 = hole_local(hole_number, "basket")
	var lie: Vector2 = visitor["disc_position"]
	var remaining: float = lie.distance_to(basket)
	var putting: bool = remaining <= PUTT_RANGE_PIXELS
	var accuracy: float = float(skills["putting"] if putting else skills["accuracy"])
	var control: float = float(skills["control"])
	var power: float = float(skills["power"])
	var skill_factor: float = clampf((accuracy + control) / 200.0, 0.1, 1.0)
	# A typical 40-60 power golfer reaches roughly 190-255 feet on a full drive.
	# Higher-power players can reach 300+ feet; approaches scale down near the pin.
	var drive_feet: float = 120.0 + power * 2.15
	var max_reach: float = drive_feet / FEET_PER_PIXEL
	var reach: float = max_reach if not putting else (18.0 + accuracy * 0.36)
	var power_variation: float = lerpf(0.66, 0.92, control / 100.0)
	var forward: float = minf(remaining, reach * rng.randf_range(power_variation, 1.05))
	# Aim down the flight line (current lie -> basket), with a skill-based
	# angular release error. Accuracy reduces the angle; control reduces
	# power variation. Flight shape will be a separate later update.
	var direction: Vector2 = (basket - lie).normalized()
	if direction.length_squared() < 0.001:
		direction = Vector2.RIGHT
	var max_error_degrees: float = (2.0 if putting else 17.0) * (1.0 - skill_factor) + 0.5
	var release_error: float = deg_to_rad(rng.randf_range(-max_error_degrees, max_error_degrees))
	var aimed_direction: Vector2 = direction.rotated(release_error)
	var landing: Vector2 = clamp_to_property(lie + aimed_direction * forward)
	if navigation_manager != null:
		var landing_cell: Vector2i = property_manager.world_to_cell(landing)
		var blocked: Dictionary = navigation_manager.build_navigation_blocked_cells(landing_cell, landing_cell)
		if blocked.has(landing_cell):
			var nearby: Vector2i = navigation_manager.find_nearest_walkable_cell(landing_cell, blocked)
			if nearby.x >= 0:
				landing = property_manager.cell_to_world_center(nearby)
	var sunk: bool = false
	if putting:
		var putt_chance: float = clampf(0.12 + accuracy / 120.0 - remaining / 140.0, 0.08, 0.94)
		sunk = rng.randf() < putt_chance
	elif remaining <= reach and skill_factor > 0.85:
		sunk = rng.randf() < 0.015
	if sunk:
		landing = basket
	visitor["strokes"] = int(visitor["strokes"]) + 1
	visitor["last_throw"] = "Putt" if putting else ("Drive" if int(visitor["strokes"]) == 1 else "Approach")
	# Shape varies by handedness, skill, and throw type. This is a
	# deterministic visual flight curve, not full disc aerodynamics.
	var hand_sign: float = -1.0 if str(person["handedness"]) == "Left" else 1.0
	var shape_choice: int = rng.randi_range(0, 2)
	var release_shape: float = [-1.0, 0.0, 1.0][shape_choice]
	var execution: float = (1.0 - skill_factor) * rng.randf_range(-0.65, 0.65)
	var scale: float = minf(1.0, lie.distance_to(landing) / 350.0)
	visitor["flight_curve"] = (release_shape + execution) * 32.0 * scale * hand_sign
	visitor["flight_turn"] = -20.0 * scale * hand_sign
	visitor["flight_fade"] = 27.0 * scale * hand_sign
	visitor["flight_start"] = lie
	visitor["flight_end"] = landing
	visitor["flight_elapsed"] = 0.0
	var travel: float = lie.distance_to(landing)
	visitor["flight_duration"] = clampf(0.5 + travel / 360.0, FLIGHT_MIN_SECONDS, FLIGHT_MAX_SECONDS)
	visitor["flight_sunk"] = sunk or int(visitor["strokes"]) >= MAX_STROKES
	visitor["stage"] = "disc_flying"
	if selected_id == int(visitor["id"]) and profile_panel.visible:
		show_profile(selected_id)


func complete_flight(visitor: Dictionary) -> void:
	var landing: Vector2 = visitor["flight_end"]
	var basket: Vector2 = hole_local(int(visitor["holes"][int(visitor["hole_cursor"])]), "basket")
	if bool(visitor["flight_sunk"]):
		visitor["disc_position"] = basket
		visitor["wait"] = 1.2
		visitor["stage"] = "walking_to_basket"
		set_destination(visitor, basket)
	else:
		visitor["disc_position"] = landing
		visitor["stage"] = "walking_to_lie"
		visitor["wait"] = THROW_INTERVAL
		set_destination(visitor, landing)


func get_flight_visual(visitor: Dictionary) -> Vector2:
	var duration: float = maxf(0.01, float(visitor.get("flight_duration", 1.0)))
	var t: float = clampf(float(visitor.get("flight_elapsed", 0.0)) / duration, 0.0, 1.0)
	var start: Vector2 = visitor["flight_start"]
	var finish: Vector2 = visitor["flight_end"]
	var flat: Vector2 = start.lerp(finish, t)
	var heading: Vector2 = (finish - start).normalized()
	var sideways: Vector2 = Vector2(-heading.y, heading.x)
	# Turn peaks early, fade peaks late, and release shape affects the
	# entire trajectory. Each contribution is zero at takeoff and landing.
	var envelope: float = sin(PI * t)
	var early: float = envelope * (1.0 - t)
	var late: float = envelope * t
	var offset: float = float(visitor.get("flight_curve", 0.0)) * envelope
	offset += float(visitor.get("flight_turn", 0.0)) * early
	offset += float(visitor.get("flight_fade", 0.0)) * late
	var arc: float = envelope * minf(FLIGHT_ARC_PIXELS, 14.0 + start.distance_to(finish) * 0.19)
	return flat + sideways * offset + Vector2(0.0, -arc)


func finish_hole(visitor: Dictionary) -> void:
	var holes: Array = visitor["holes"]
	var cursor: int = int(visitor["hole_cursor"])
	if cursor >= holes.size():
		return
	var hole_index: int = int(holes[cursor])
	var person: Dictionary = people[int(visitor["id"])]
	var strokes: int = int(visitor["strokes"])
	var par: int = course_manager.calculate_par(course_manager.calculate_hole_distance(hole_index, property_manager.CELL_SIZE))
	visitor["round_scores"][str(hole_index + 1)] = {"strokes": strokes, "par": par}
	person["holes_visited"] = int(person["holes_visited"]) + 1
	visitor["stage"] = "waiting_at_basket"


func advance_stage(visitor: Dictionary) -> void:
	var holes: Array = visitor["holes"]
	var cursor: int = int(visitor["hole_cursor"])
	var stage: String = str(visitor["stage"])
	match stage:
		"driving_in":
			visitor["stage"] = "parking"
			visitor["wait"] = PARK_SECONDS
			visitor["position"] = visitor["parking_slot"]
			visitor["car_position"] = visitor["parking_slot"]
		"parking":
			visitor["stage"] = "waiting_partner"
		"walking_to_checkin":
			visitor["stage"] = "waiting_at_checkin"
			visitor["wait"] = CHECKIN_SECONDS
		"walking_to_tee":
			visitor["stage"] = "waiting_at_tee"
		"walking_to_lie":
			visitor["stage"] = "throwing"
			visitor["wait"] = BETWEEN_SHOTS_SECONDS
		"walking_to_basket":
			finish_hole(visitor)
		"walking_to_car":
			visitor["stage"] = "driving_out"
			visitor["position"] = visitor["parking_slot"]
			visitor["car_position"] = visitor["parking_slot"]
			visitor["route"] = get_driveway_route(false, visitor["parking_slot"])
			visitor["route_index"] = 0
		"driving_out":
			if not bool(visitor.get("round_recorded", false)):
				record_round(visitor)
			visitors.erase(visitor)
			if get_partner(visitor).is_empty():
				group_turns.erase(int(visitor["group_id"]))
			visitor_departed.emit(int(visitor["id"]))
			save_people()


func update_visual_positions(delta: float) -> void:
	# Display-only smoothing: never alter gameplay positions or objectives.
	var active: Dictionary = {}
	for value in visitors:
		var visitor: Dictionary = value
		var id: int = int(visitor["id"])
		active[id] = true
		var target: Vector2 = visitor["position"]
		if not visual_positions.has(id):
			visual_positions[id] = target
		else:
			var previous: Vector2 = visual_positions[id]
			visual_positions[id] = previous.lerp(target, 1.0 - exp(-VISUAL_FOLLOW_RATE * delta))
	for id in visual_positions.keys():
		if not active.has(id):
			visual_positions.erase(id)


func get_activity_label(stage: String) -> String:
	match stage:
		"parking": return "Parking"
		"waiting_partner": return "Waiting"
		"walking_to_checkin": return "Check-in"
		"waiting_at_checkin": return "Checking in"
		"walking_to_tee": return "To tee"
		"waiting_at_tee": return "Tee queue"
		"throwing": return "Throwing"
		"disc_flying": return "Disc flying"
		"walking_to_lie": return "Retrieving"
		"walking_to_basket": return "Finishing"
		"waiting_at_basket": return "Hole complete"
		"feedback": return "Reviewing"
		"walking_to_car": return "Leaving"
	return ""


func _draw() -> void:
	if property_manager == null:
		return
	for visitor_value in visitors:
		var visitor: Dictionary = visitor_value
		var id: int = int(visitor["id"])
		var person: Dictionary = people[id]
		var stage: String = str(visitor["stage"])
		var local_position: Vector2 = visual_positions.get(id, visitor["position"])
		var world: Vector2 = property_manager.property_local_to_world(local_position)
		var color: Color = PALETTE[int(person["appearance"]) % PALETTE.size()]
		var car_local: Vector2 = visitor.get("car_position", visitor["position"])
		var car_world: Vector2 = property_manager.property_local_to_world(car_local)
		var car_color: Color = color.darkened(0.25)
		# Cars remain parked while their owners play.
		draw_rect(Rect2(car_world - Vector2(10.0, 5.0), Vector2(20.0, 10.0)), Color(0, 0, 0, 0.25), true)
		draw_rect(Rect2(car_world - Vector2(9.0, 7.0), Vector2(18.0, 11.0)), car_color, true)
		draw_rect(Rect2(car_world - Vector2(2.0, 6.0), Vector2(7.0, 9.0)), Color(0.55, 0.75, 0.84, 0.95), true)
		if stage in ["driving_in", "driving_out"]:
			continue
		if DEBUG_DESTINATIONS and visitor.has("destination"):
			var goal_world: Vector2 = property_manager.property_local_to_world(visitor["destination"])
			draw_line(world, goal_world, Color(1.0, 0.8, 0.15, 0.8), 2.0)
			draw_circle(goal_world, 7.0, Color(1.0, 0.8, 0.15, 0.8))
		var moving: bool = stage.begins_with("walking_")
		var bob: float = sin(visual_time * 11.0 + float(id)) * 1.1 if moving else 0.0
		var body: Vector2 = world + Vector2(0.0, bob)
		draw_ellipse_shadow(body)
		# Small readable torso/head silhouette rather than a single dot.
		draw_line(body + Vector2(0, -1), body + Vector2(0, 5), color.darkened(0.28), 5.0)
		draw_circle(body + Vector2(0, -2), 5.5, color)
		draw_circle(body + Vector2(0, -9), 4.0, Color("efc49d"))
		if stage in ["throwing", "disc_flying", "walking_to_lie", "walking_to_basket"]:
			var disc_local: Vector2 = get_flight_visual(visitor) if stage == "disc_flying" else visitor["disc_position"]
			var disc_world: Vector2 = property_manager.property_local_to_world(disc_local)
			if stage == "disc_flying":
				var duration: float = maxf(0.01, float(visitor["flight_duration"]))
				var progress: float = clampf(float(visitor["flight_elapsed"]) / duration, 0.0, 1.0)
				var ground_local: Vector2 = (visitor["flight_start"] as Vector2).lerp(visitor["flight_end"], progress)
				var ground_world: Vector2 = property_manager.property_local_to_world(ground_local)
				# Ground shadow anchors the disc to its real horizontal position.
				draw_circle(ground_world + Vector2(2, 2), 4.0, Color(0, 0, 0, FLIGHT_SHADOW_ALPHA))
				draw_circle(disc_world, 7.0, Color(1.0, 0.87, 0.32, 0.18))
			else:
				draw_circle(disc_world + Vector2(1, 2), 4.5, Color(0, 0, 0, 0.24))
			draw_circle(disc_world, FLIGHT_DISC_RADIUS, Color(0.98, 0.83, 0.23, 1.0))
			draw_arc(disc_world, 5.5, 0.0, TAU, 12, Color(0.13, 0.16, 0.12, 0.8), 1.0)
		# Restrict status labels to stationary interactions to reduce clutter.
		if stage in ["waiting_partner", "waiting_at_checkin", "waiting_at_tee", "throwing", "disc_flying", "waiting_at_basket"]:
			var label_text: String = get_activity_label(stage)
			var font: Font = ThemeDB.fallback_font
			var font_size: int = 11
			var width: float = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var label_position: Vector2 = body + Vector2(-width * 0.5, -20)
			draw_string_outline(font, label_position, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.07, 0.11, 0.09, 0.9))
			draw_string(font, label_position, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
		if selected_id == id:
			draw_arc(body, 10.0, 0.0, TAU, 16, Color.WHITE, 1.8)


func draw_ellipse_shadow(at: Vector2) -> void:
	# Lightweight elliptical ground shadow (no extra sprites or assets).
	draw_set_transform(at + Vector2(2, 6), 0.0, Vector2(1.25, 0.55))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.23))
	draw_set_transform(Vector2.ZERO)


func select_at(world_point: Vector2) -> bool:
	if property_manager == null:
		return false
	for visitor_value in visitors:
		var visitor: Dictionary = visitor_value
		if str(visitor["stage"]) in ["driving_in", "driving_out"]:
			continue
		var world: Vector2 = property_manager.property_local_to_world(visitor["position"])
		if world.distance_to(world_point) < 22.0:
			selected_id = int(visitor["id"])
			show_profile(selected_id)
			queue_redraw()
			return true
	return false

func build_profile() -> void:
	profile_layer = CanvasLayer.new()
	profile_layer.layer = 20
	add_child(profile_layer)
	profile_panel = PanelContainer.new()
	profile_panel.visible = false
	profile_panel.position = Vector2(220, 105)
	profile_panel.custom_minimum_size = Vector2(295, 0)
	profile_layer.add_child(profile_panel)
	var layout := VBoxContainer.new()
	profile_panel.add_child(layout)
	var close_button := Button.new()
	close_button.text = "Close golfer profile"
	close_button.pressed.connect(func(): profile_panel.hide())
	layout.add_child(close_button)
	profile_label = Label.new()
	profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(profile_label)

func show_profile(person_id: int) -> void:
	if not people.has(person_id):
		return
	var person: Dictionary = people[person_id]
	var membership: String = "Unregistered" if int(person["membership_number"]) < 0 else "WDGA #%d" % int(person["membership_number"])
	var skills: Dictionary = person["skills"]
	profile_label.text = "%s  •  Age %d\n%s  •  %s\n%s-handed  •  %s\n\nPower %d   Accuracy %d\nPutting %d   Control %d\nCourse IQ %d   Composure %d\n\nVisits: %d   Holes visited: %d" % [str(person["name"]), int(person["age"]), membership, str(person["classification"]), str(person["handedness"]), str(person["personality"]), int(skills["power"]), int(skills["accuracy"]), int(skills["putting"]), int(skills["control"]), int(skills["course_iq"]), int(skills["composure"]), int(person["visits"]), int(person["holes_visited"])]
	for visitor_value in visitors:
		var active: Dictionary = visitor_value
		if int(active["id"]) == person_id and str(active["stage"]) in ["throwing", "disc_flying", "walking_to_lie", "walking_to_basket"]:
			profile_label.text += "\n\nHole %d | Strokes: %d\n%s" % [int(active["holes"][int(active["hole_cursor"])]) + 1, int(active["strokes"]), str(active["last_throw"])]
			break
	if not person["history"].is_empty():
		var last_round: Dictionary = person["history"][-1]
		if last_round.has("strokes"):
			profile_label.text += "\nLast round: %d strokes / Par %d" % [int(last_round["strokes"]), int(last_round["par"])]
	if not person["feedback"].is_empty():
		profile_label.text += "\n\nLast feedback: " + str(person["feedback"][-1])
	profile_panel.show()

func save_people() -> void:
	var records: Array = []
	for person in people.values():
		records.append(person)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"next_id": next_person_id, "next_membership": next_membership_number, "people": records}))

func load_people() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	next_person_id = int(parsed.get("next_id", 1))
	next_membership_number = int(parsed.get("next_membership", 10001))
	for value in parsed.get("people", []):
		if value is Dictionary:
			people[int(value.get("id", -1))] = value
