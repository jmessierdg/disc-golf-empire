# Disc Golf Empire - Update 41: flight shape influences landing and tree contact.
# Based on the working Update 30 arrival/check-in/navigation system.
extends Node2D

signal visitor_arrived(person_id: int)
signal visitor_departed(person_id: int)

const MAX_VISITORS := 8
const MAX_GROUP_SIZE := 4
const GROUP_ASSEMBLY_SECONDS := 8.0
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
# Gameplay-scale putting: 8 px is about 3.75 feet.
# Shot-planning candidate angles are relative to the intended fairway line.
const SHOT_CANDIDATE_ANGLES := [0.0, -12.0, 12.0, -25.0, 25.0, -40.0, 40.0, -60.0, 60.0, -85.0, 85.0]
const SHOT_CANDIDATE_POWERS := [1.0, 0.72, 0.46, 0.28]
const RECOVERY_MIN_ADVANCE := 18.0
const TAP_IN_RANGE_PIXELS := 8.0
const CLOSE_PUTT_RANGE_PIXELS := 22.0
const STANDSTILL_BASE_FEET := 95.0
const STANDSTILL_MIN_FEET := 55.0
const STANDSTILL_MAX_FEET := 140.0
const STANDSTILL_SECONDS := 0.45
const RUNUP_SECONDS := 1.05
const GROUP_WAIT_RADIUS := 25.0
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
var group_sizes: Dictionary = {}
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
	# Eight compact parking positions arranged in two rows.
	var center: Vector2 = get_parking_local()
	var facility: Dictionary = property_manager.get_starter_facility("starter_parking")
	var size: Vector2 = facility.get("size", Vector2(140.0, 120.0))
	var column: int = slot_index % 4
	var row: int = int(slot_index / 4)
	return center + Vector2(
		(float(column) - 1.5) * size.x * 0.22,
		(-0.23 if row == 0 else 0.23) * size.y
	)


func occupied_parking_slots() -> Dictionary:
	var used: Dictionary = {}
	for visitor_value in visitors:
		var visitor: Dictionary = visitor_value
		used[int(visitor.get("slot_index", -1))] = true
	return used


func get_group_members(visitor: Dictionary) -> Array:
	var result: Array = []
	for value in visitors:
		var member: Dictionary = value
		if int(member["group_id"]) == int(visitor["group_id"]):
			result.append(member)
	result.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return result

func group_all_at_stage(visitor: Dictionary, required_stage: String) -> bool:
	var members: Array = get_group_members(visitor)
	if members.size() != int(group_sizes.get(int(visitor["group_id"]), 0)):
		return false
	for member in members:
		if str(member["stage"]) != required_stage:
			return false
	return true

func group_ready_for_tee(visitor: Dictionary) -> bool:
	return group_all_at_stage(visitor, "waiting_at_tee")

func get_group_turn(visitor: Dictionary) -> int:
	var group_id: int = int(visitor["group_id"])
	if not group_turns.has(group_id):
		var members: Array = get_group_members(visitor)
		group_turns[group_id] = int(members[0]["id"]) if not members.is_empty() else int(visitor["id"])
	return int(group_turns[group_id])

func may_throw(visitor: Dictionary) -> bool:
	var hole_index: int = int(visitor["holes"][int(visitor["hole_cursor"])])
	if int(hole_owners.get(hole_index, -1)) != int(visitor["group_id"]):
		return false
	var members: Array = get_group_members(visitor)
	for member in members:
		if str(member["stage"]) == "disc_flying":
			return false
	if int(visitor["strokes"]) == 0:
		for member in members:
			if not bool(member.get("tee_ready", false)):
				return false
		return get_group_turn(visitor) == int(visitor["id"])
	return bool(visitor.get("lie_ready", false)) and bool(visitor.get("active_thrower", false))

func finish_throw_turn(visitor: Dictionary) -> void:
	var members: Array = get_group_members(visitor)
	for index in range(members.size()):
		if int(members[index]["id"]) == int(visitor["id"]):
			group_turns[int(visitor["group_id"])] = int(members[(index + 1) % members.size()]["id"])
			return

func coordinate_group_lies() -> void:
	var visited: Dictionary = {}
	for visitor_value in visitors:
		var visitor: Dictionary = visitor_value
		var gid: int = int(visitor["group_id"])
		if visited.has(gid):
			continue
		visited[gid] = true
		var members: Array = get_group_members(visitor)
		if members.size() != int(group_sizes.get(gid, 0)):
			continue
		var all_ready: bool = true
		var any_remaining: bool = false
		for member in members:
			if int(member["hole_cursor"]) != int(visitor["hole_cursor"]):
				all_ready = false
			if str(member["stage"]) not in ["waiting_group", "waiting_at_basket"]:
				all_ready = false
			if int(member["strokes"]) == 0:
				all_ready = false
			if str(member["stage"]) != "waiting_at_basket":
				any_remaining = true
		if not all_ready or not any_remaining:
			continue
		var hole_index: int = int(visitor["holes"][int(visitor["hole_cursor"])])
		var basket: Vector2 = hole_local(hole_index, "basket")
		var shooter: Dictionary = {}
		var farthest: float = -1.0
		for member in members:
			if str(member["stage"]) == "waiting_at_basket":
				continue
			var distance: float = (member["disc_position"] as Vector2).distance_to(basket)
			if distance > farthest:
				farthest = distance
				shooter = member
		if shooter.is_empty():
			continue
		var lie: Vector2 = shooter["disc_position"]
		var away: Vector2 = (lie - basket).normalized()
		if away.length_squared() < 0.001:
			away = Vector2.DOWN
		var side: Vector2 = Vector2(-away.y, away.x)
		var waiting_index: int = 0
		for member in members:
			if str(member["stage"]) == "waiting_at_basket":
				continue
			var is_shooter: bool = int(member["id"]) == int(shooter["id"])
			member["lie_ready"] = false
			member["active_thrower"] = is_shooter
			member["stage"] = "walking_group_lie"
			var destination: Vector2 = lie
			if not is_shooter:
				var sign: float = -1.0 if waiting_index % 2 == 0 else 1.0
				var rank: int = int(waiting_index / 2)
				var angle: float = deg_to_rad(28.0 + float(rank) * 15.0)
				destination += (away * cos(angle) + side * sin(angle) * sign) * (GROUP_WAIT_RADIUS + float(rank) * 10.0)
				waiting_index += 1
			set_destination(member, destination)

func group_ready_for_next_hole(visitor: Dictionary) -> bool:
	return group_all_at_stage(visitor, "waiting_at_basket")

func move_group_to_next_hole(visitor: Dictionary) -> void:
	if not group_ready_for_next_hole(visitor):
		return
	var members: Array = get_group_members(visitor)
	var cursor: int = int(visitor["hole_cursor"])
	var completed_hole: int = int(visitor["holes"][cursor])
	if int(hole_owners.get(completed_hole, -1)) == int(visitor["group_id"]):
		hole_owners.erase(completed_hole)
	group_turns.erase(int(visitor["group_id"]))
	var latest_holes: Array = completed_holes()
	refresh_course_locations()
	for member in members:
		var itinerary: Array = member["holes"]
		for candidate in latest_holes:
			if not itinerary.has(candidate):
				itinerary.append(candidate)
		itinerary.sort()
		member["holes"] = itinerary
		member["tee_ready"] = false
		member["strokes"] = 0
		member["hole_cursor"] = cursor + 1
		if cursor + 1 < itinerary.size():
			member["stage"] = "walking_to_tee"
			set_destination(member, hole_local(int(itinerary[cursor + 1]), "tee"))
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
	var feedback: String = "Enjoyed playing %d available holes with my group." % scores.size()
	if float(visitor["off_path"]) > float(visitor["walked"]) * 0.55:
		feedback = "Fun round with my group, but the walking routes need improvement."
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
			"basket": hole["basket"],
			"path_points": hole.get("path_points", [])
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
	# Admit a group of 1-4 with capacity for eight visitors total.
	refresh_course_locations()
	var holes: Array = completed_holes()
	if holes.is_empty() or visitors.size() >= MAX_VISITORS:
		return
	var used: Dictionary = occupied_parking_slots()
	var available: Array = []
	for slot_index in range(MAX_VISITORS):
		if not used.has(slot_index):
			available.append(slot_index)
	if available.is_empty():
		return
	var group_size: int = mini(rng.randi_range(1, MAX_GROUP_SIZE), available.size())
	var group_id: int = next_group_id
	next_group_id += 1
	group_sizes[group_id] = group_size
	var group: Array = []
	for index in range(group_size):
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
			"wait": float(index) * 1.7, "walked": 0.0, "off_path": 0.0,
			"route_distance": 0.0, "strokes": 0, "round_scores": {},
			"disc_position": start, "last_throw": "", "throw_wait": 0.0,
			"round_recorded": false, "destination": slot, "destination_kind": "parking",
			"tee_ready": false, "shot_pause": 0.0, "checked_in": false,
			"flight_start": start, "flight_end": start, "flight_elapsed": 0.0,
			"flight_duration": 0.0, "flight_sunk": false,
			"flight_curve": 0.0, "flight_turn": 0.0, "flight_fade": 0.0,
			"shot_style": "Standstill", "shot_animation_total": 0.0,
			"lie_ready": false, "active_thrower": false
		}
		group.append(visitor)
	for visitor in group:
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
				visitor["stage"] = "walking_to_checkin"
				set_destination(visitor, get_checkin_local())
			"waiting_at_checkin":
				if group_all_at_stage(visitor, "waiting_at_checkin"):
					for member in get_group_members(visitor):
						member["checked_in"] = true
						member["stage"] = "walking_to_tee"
						set_destination(member, hole_local(int(member["holes"][0]), "tee"))
			"waiting_at_tee":
				if bool(visitor.get("checked_in", false)) and group_ready_for_tee(visitor):
					var hole_index: int = int(visitor["holes"][int(visitor["hole_cursor"])])
					var owner: int = int(hole_owners.get(hole_index, -1))
					if owner == -1 or owner == int(visitor["group_id"]):
						hole_owners[hole_index] = int(visitor["group_id"])
						for member in get_group_members(visitor):
							member["tee_ready"] = true
							member["disc_position"] = hole_local(hole_index, "tee")
							member["stage"] = "throwing"
							member["wait"] = TEE_PREPARE_SECONDS
			"waiting_group_lie":
				var members: Array = get_group_members(visitor)
				var all_arrived: bool = true
				for member in members:
					if str(member["stage"]) not in ["waiting_group_lie", "waiting_at_basket"]:
						all_arrived = false
				if all_arrived:
					for member in members:
						if str(member["stage"]) == "waiting_at_basket":
							continue
						member["stage"] = "throwing" if bool(member.get("active_thrower", false)) else "waiting_group"
						member["lie_ready"] = bool(member.get("active_thrower", false))
						member["wait"] = BETWEEN_SHOTS_SECONDS
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
					var hole_index: int = int(visitor["holes"][int(visitor["hole_cursor"])])
					var distance_feet: float = (visitor["disc_position"] as Vector2).distance_to(hole_local(hole_index, "basket")) * FEET_PER_PIXEL
					var golfer: Dictionary = people[int(visitor["id"])]
					var skills: Dictionary = golfer["skills"]
					var standstill_range: float = clampf(STANDSTILL_BASE_FEET + (float(skills["control"]) - 50.0) * 0.5, STANDSTILL_MIN_FEET, STANDSTILL_MAX_FEET)
					var standstill: bool = distance_feet <= standstill_range
					visitor["shot_style"] = "Standstill" if standstill else "Run-up"
					visitor["stage"] = "standstill" if standstill else "run_up"
					visitor["shot_animation_total"] = STANDSTILL_SECONDS if standstill else RUNUP_SECONDS
					visitor["wait"] = float(visitor["shot_animation_total"])
			"standstill", "run_up":
				perform_throw(visitor)
				finish_throw_turn(visitor)
			"disc_flying":
				visitor["flight_elapsed"] = minf(float(visitor["flight_duration"]), float(visitor["flight_elapsed"]) + delta)
				if float(visitor["flight_elapsed"]) >= float(visitor["flight_duration"]):
					complete_flight(visitor)
			"parking":
				advance_stage(visitor)
			"walking_to_checkin", "walking_to_tee", "walking_to_lie", "walking_group_lie", "walking_to_basket", "walking_to_car":
				# Never freeze navigation because partners are too far apart.
				# Synchronization happens at check-in, tees, and baskets.
				if advance_visitor(visitor, delta):
					advance_stage(visitor)
	coordinate_group_lies()
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
	var safe_finish: Vector2 = clamp_to_property(finish)
	if start.distance_to(safe_finish) <= 1.0:
		return [safe_finish]
	# Built paths guide walking between facilities and holes. They do not
	# constrain shots or the final approach to a player's lie.
	if path_manager != null:
		return route_via_walkways(start, safe_finish)
	return [safe_finish]


func get_intended_shot_target(hole_index: int, lie: Vector2, basket: Vector2, reach: float, course_iq: float, control: float) -> Vector2:
	# A waypoint is guidance, not a target that must be hit repeatedly.
	# Project the lie onto the authored route, then look FORWARD along it.
	var hole: Dictionary = course_manager.get_hole(hole_index)
	var points: Array = [hole["tee"]]
	for point_value in hole.get("path_points", []):
		if point_value is Vector2 and (points[-1] as Vector2).distance_to(point_value) > 2.0:
			points.append(point_value)
	if (points[-1] as Vector2).distance_to(basket) > 2.0:
		points.append(basket)
	if points.size() < 2:
		return basket
	var cumulative: Array = [0.0]
	for i in range(points.size() - 1):
		cumulative.append(float(cumulative[-1]) + (points[i + 1] as Vector2).distance_to(points[i]))
	var total: float = float(cumulative[-1])
	var nearest_progress: float = 0.0
	var nearest_distance: float = INF
	for i in range(points.size() - 1):
		var start: Vector2 = points[i]
		var finish: Vector2 = points[i + 1]
		var line: Vector2 = finish - start
		var fraction: float = clampf((lie - start).dot(line) / maxf(line.length_squared(), 0.001), 0.0, 1.0)
		var distance: float = lie.distance_squared_to(start.lerp(finish, fraction))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_progress = float(cumulative[i]) + line.length() * fraction
	# Look ahead far enough to prevent tiny repeated throws at a waypoint.
	# More confident players can plan farther along the intended fairway.
	var lookahead: float = maxf(65.0, reach * lerpf(0.48, 0.86, clampf((course_iq + control) / 200.0, 0.0, 1.0)))
	var desired_progress: float = minf(total, nearest_progress + lookahead)
	for i in range(points.size() - 1):
		if desired_progress <= float(cumulative[i + 1]) or i == points.size() - 2:
			var leg: float = float(cumulative[i + 1]) - float(cumulative[i])
			var fraction: float = clampf((desired_progress - float(cumulative[i])) / maxf(leg, 0.001), 0.0, 1.0)
			var target: Vector2 = (points[i] as Vector2).lerp(points[i + 1], fraction)
			# If the player landed off the line, don't repeatedly throw
			# sideways to the same nearby point; advance toward the basket.
			if target.distance_to(lie) < 24.0 and lie.distance_to(basket) > 42.0:
				return basket
			return target
	return basket


func plan_obstacle_aware_shot(visitor: Dictionary, lie: Vector2, basket: Vector2, intended: Vector2, reach: float, course_iq: float, control: float) -> Vector2:
	# Evaluate *possible* throws, not a single waypoint. The designer's
	# route supplies the preferred heading; tree clearance decides safety.
	var preferred: Vector2 = (intended - lie).normalized()
	if preferred.length_squared() < 0.001:
		preferred = (basket - lie).normalized()
	if preferred.length_squared() < 0.001:
		return basket
	var remaining: float = lie.distance_to(basket)
	var previous_hit: bool = str(visitor.get("last_throw", "")) == "Tree hit"
	var old_target: Vector2 = visitor.get("last_shot_target", lie)
	var best_target: Vector2 = intended
	var best_score: float = -INF
	var aggression: float = clampf((course_iq * 0.65 + control * 0.35) / 100.0, 0.0, 1.0)
	for angle_value in SHOT_CANDIDATE_ANGLES:
		var angle: float = float(angle_value)
		var direction: Vector2 = preferred.rotated(deg_to_rad(angle))
		for power_value in SHOT_CANDIDATE_POWERS:
			var fraction: float = float(power_value)
			var length: float = minf(reach * fraction, maxf(remaining * 1.3, 45.0))
			var candidate: Vector2 = clamp_to_property(lie + direction * length)
			var distance: float = lie.distance_to(candidate)
			if distance < RECOVERY_MIN_ADVANCE:
				continue
			var estimated_height: float = minf(FLIGHT_ARC_PIXELS, 14.0 + distance * 0.19)
			var collision: Dictionary = find_tree_contact(lie, candidate, estimated_height)
			var hit_fraction: float = float(collision.get("fraction", 1.0))
			var safe_distance: float = distance * hit_fraction
			# Favor progress along the designer's intended fairway, while
			# rewarding a clear line and penalizing a blocked aggressive shot.
			var progress: float = (candidate - lie).dot(preferred)
			var basket_gain: float = remaining - candidate.distance_to(basket)
			var score: float = progress * 0.48 + basket_gain * 0.28
			score += safe_distance * 0.20
			score -= absf(angle) * lerpf(0.28, 0.12, aggression)
			if not collision.is_empty():
				score -= 125.0 + (distance - safe_distance) * 0.75
			# Avoid selecting the same failed line after a tree hit.
			if previous_hit and candidate.distance_to(old_target) < 32.0:
				score -= 180.0
			# A recovery pitch-out can be sideways but should never be
			# preferred over an equally safe forward fairway shot.
			if basket_gain < -25.0:
				score -= 50.0
			if score > best_score:
				best_score = score
				best_target = candidate
	# If all candidates are poor, still select the least-bad route;
	# the actual throw and collision system remain authoritative.
	return best_target


func set_destination(visitor: Dictionary, destination: Vector2) -> void:
	var safe_destination: Vector2 = clamp_to_property(destination)
	visitor["destination"] = safe_destination
	visitor["destination_kind"] = str(visitor.get("stage", ""))
	var stage: String = str(visitor.get("stage", ""))
	var route: Array = route_on_property(visitor["position"], safe_destination) if stage in ["walking_to_tee", "walking_to_checkin", "walking_to_car"] else [safe_destination]
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
func find_tree_contact(start: Vector2, finish: Vector2, flight_height: float) -> Dictionary:
	# Trees are property-local, like all shot coordinates. Low shots
	# can clip trunks; higher shots still risk the canopy.
	var delta: Vector2 = finish - start
	var distance: float = delta.length()
	if distance < 0.1:
		return {}
	var best_fraction: float = 2.0
	for tree_value in property_manager.trees:
		var tree: Vector2 = tree_value
		var fraction: float = clampf((tree - start).dot(delta) / maxf(delta.length_squared(), 0.001), 0.0, 1.0)
		if fraction <= 0.02 or fraction >= 0.98:
			continue
		var closest: Vector2 = start.lerp(finish, fraction)
		var lateral: float = tree.distance_to(closest)
		var height: float = sin(PI * fraction) * flight_height
		var collision_radius: float = 8.0 if height > 26.0 else 13.0
		if lateral <= collision_radius and fraction < best_fraction:
			best_fraction = fraction
	if best_fraction <= 1.0:
		return {"fraction": best_fraction, "point": start.lerp(finish, maxf(0.04, best_fraction - 0.025))}
	return {}


func find_curved_tree_contact(start: Vector2, finish: Vector2, height: float, curve: float, turn: float, fade: float) -> Dictionary:
	var direction: Vector2 = (finish - start).normalized()
	if direction.length_squared() < 0.001:
		return {}
	var side: Vector2 = Vector2(-direction.y, direction.x)
	var previous: Vector2 = start
	var steps: int = maxi(12, int(ceilf(start.distance_to(finish) / 12.0)))
	for step in range(1, steps + 1):
		var t: float = float(step) / float(steps)
		var envelope: float = sin(PI * t)
		var offset: float = curve * envelope + turn * envelope * (1.0 - t) + fade * envelope * t
		var current: Vector2 = start.lerp(finish, t) + side * offset
		var altitude: float = envelope * height
		var radius: float = 8.0 if altitude > 26.0 else 13.0
		for tree_value in property_manager.trees:
			var tree: Vector2 = tree_value
			if tree.distance_to(current) <= radius:
				return {"fraction": t, "point": previous}
		previous = current
	return {}


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
	var course_iq: float = float(skills.get("course_iq", 50))
	var intended: Vector2 = basket if putting else get_intended_shot_target(hole_number, lie, basket, reach, course_iq, control)
	var shot_target: Vector2 = intended if putting else plan_obstacle_aware_shot(visitor, lie, basket, intended, reach, course_iq, control)
	var target_distance: float = lie.distance_to(shot_target)
	var forward: float = minf(target_distance, reach * rng.randf_range(power_variation, 1.05))
	# Never spend full strokes nudging a few pixels toward a path node.
	if not putting and remaining > 55.0 and forward < 28.0:
		shot_target = plan_obstacle_aware_shot(visitor, lie, basket, basket, reach, course_iq, control)
		target_distance = lie.distance_to(shot_target)
		forward = minf(target_distance, reach * rng.randf_range(power_variation, 1.05))
	# Aim toward the selected fairway waypoint, with a skill-based
	# angular release error. Accuracy reduces the angle; control reduces
	# power variation. Flight shape will be a separate later update.
	var direction: Vector2 = (shot_target - lie).normalized()
	if direction.length_squared() < 0.001:
		direction = Vector2.RIGHT
	var max_error_degrees: float = (2.0 if putting else 17.0) * (1.0 - skill_factor) + 0.5
	var release_error: float = deg_to_rad(rng.randf_range(-max_error_degrees, max_error_degrees))
	var aimed_direction: Vector2 = direction.rotated(release_error)
	var nominal_landing: Vector2 = clamp_to_property(lie + aimed_direction * forward)
	# Shot shape is now part of the resulting landing position, rather
	# than a decorative curve that always ends at the nominal target.
	var hand_sign: float = -1.0 if str(person["handedness"]) == "Left" else 1.0
	var shape_choice: int = rng.randi_range(0, 2)
	var release_shape: float = [-1.0, 0.0, 1.0][shape_choice]
	var execution: float = (1.0 - skill_factor) * rng.randf_range(-0.65, 0.65)
	var scale: float = minf(1.0, lie.distance_to(nominal_landing) / 350.0)
	var curve: float = (release_shape + execution) * 75.0 * scale * hand_sign
	var turn: float = -43.0 * scale * hand_sign
	var fade: float = 52.0 * scale * hand_sign
	var landing: Vector2 = nominal_landing
	if not putting:
		var heading: Vector2 = (nominal_landing - lie).normalized()
		var sideways: Vector2 = Vector2(-heading.y, heading.x)
		# A portion of the release shape and late fade survives to ground.
		# Cap sideways drift so this remains playable at the current scale.
		var drift: float = clampf(curve * 0.22 + turn * 0.12 + fade * 0.48, -55.0, 55.0)
		landing = clamp_to_property(nominal_landing + sideways * drift)
	# Check trees against the curved trajectory, not a straight chord.
	var estimated_height: float = minf(FLIGHT_ARC_PIXELS, 14.0 + lie.distance_to(landing) * 0.19)
	var contact: Dictionary = {} if putting else find_curved_tree_contact(lie, landing, estimated_height, curve, turn, fade)
	if not contact.is_empty():
		landing = clamp_to_property(contact["point"])
	if navigation_manager != null:
		var landing_cell: Vector2i = property_manager.world_to_cell(landing)
		var blocked: Dictionary = navigation_manager.build_navigation_blocked_cells(landing_cell, landing_cell)
		if blocked.has(landing_cell):
			var nearby: Vector2i = navigation_manager.find_nearest_walkable_cell(landing_cell, blocked)
			if nearby.x >= 0:
				landing = property_manager.cell_to_world_center(nearby)
	var sunk: bool = false
	if putting:
		# Do not repeatedly miss from directly beneath the basket.
		# Within tap-in range, resolve the stroke as holed out.
		if remaining <= TAP_IN_RANGE_PIXELS:
			sunk = true
		else:
			var distance_ratio: float = clampf((remaining - TAP_IN_RANGE_PIXELS) / (PUTT_RANGE_PIXELS - TAP_IN_RANGE_PIXELS), 0.0, 1.0)
			var skill_ratio: float = clampf(accuracy / 100.0, 0.0, 1.0)
			var putt_chance: float = lerpf(0.96, 0.28 + 0.45 * skill_ratio, distance_ratio)
			if remaining <= CLOSE_PUTT_RANGE_PIXELS:
				putt_chance = maxf(putt_chance, 0.82)
			sunk = rng.randf() < putt_chance
		if not sunk:
			# Missed putts should finish close to the basket, rather
			# than leave a disc almost stationary on the same lie.
			var miss_direction: Vector2 = (landing - basket).normalized()
			if miss_direction.length_squared() < 0.001:
				miss_direction = Vector2.RIGHT.rotated(rng.randf_range(-PI, PI))
			var miss_distance: float = rng.randf_range(4.0, 12.0 if remaining > CLOSE_PUTT_RANGE_PIXELS else 7.0)
			landing = clamp_to_property(basket + miss_direction * miss_distance)
	elif shot_target.distance_to(basket) < 0.1 and remaining <= reach and skill_factor > 0.85:
		sunk = rng.randf() < 0.015
	if sunk:
		landing = basket
	visitor["strokes"] = int(visitor["strokes"]) + 1
	visitor["last_shot_target"] = shot_target
	visitor["last_throw"] = "Tree hit" if not contact.is_empty() else ("Putt" if putting else ("Drive" if int(visitor["strokes"]) == 1 else "Approach"))
	# On contact the disc stops at the impact point; do not keep a
	# pronounced sideways arc that could visually pass through the tree.
	var contact_scale: float = 0.18 if not contact.is_empty() else 1.0
	visitor["flight_curve"] = 0.0 if putting else curve * contact_scale
	visitor["flight_turn"] = 0.0 if putting else turn * contact_scale
	visitor["flight_fade"] = 0.0 if putting else fade * contact_scale
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
		# A player who holes out stays behind the next outstanding lie.
		# Do not send them walking past the partner's disc to the basket.
		finish_hole(visitor)
	else:
		visitor["disc_position"] = landing
		visitor["stage"] = "waiting_group"
		visitor["wait"] = THROW_INTERVAL
		for member in get_group_members(visitor):
			if int(member["id"]) != int(visitor["id"]) and int(member["strokes"]) > 0 and str(member["stage"]) == "throwing":
				member["stage"] = "waiting_group"


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
		"walking_group_lie":
			visitor["stage"] = "waiting_group_lie"
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
			if get_group_members(visitor).is_empty():
				group_turns.erase(int(visitor["group_id"]))
				group_sizes.erase(int(visitor["group_id"]))
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
		"throwing": return "Preparing"
		"run_up": return "Run-up"
		"standstill": return "Standstill"
		"waiting_group": return "Waiting for lie"
		"waiting_group_lie": return "At lie"
		"walking_group_lie": return "Walking as group"
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
		if stage in ["run_up", "standstill"]:
			var current_hole: int = int(visitor["holes"][int(visitor["hole_cursor"])])
			var basket: Vector2 = hole_local(current_hole, "basket")
			var lie: Vector2 = visitor["disc_position"]
			var heading: Vector2 = (basket - lie).normalized()
			if heading.length_squared() < 0.01:
				heading = Vector2.RIGHT
			var total: float = maxf(0.01, float(visitor.get("shot_animation_total", 1.0)))
			var progress: float = 1.0 - clampf(float(visitor["wait"]) / total, 0.0, 1.0)
			if stage == "run_up":
				body += heading * (-16.0 * (1.0 - progress))
				body += Vector2(0.0, sin(progress * PI * 5.0) * 1.6)
			else:
				body += heading * (-2.5 + progress * 2.5)
		draw_ellipse_shadow(body)
		# Small readable torso/head silhouette rather than a single dot.
		draw_line(body + Vector2(0, -1), body + Vector2(0, 5), color.darkened(0.28), 5.0)
		draw_circle(body + Vector2(0, -2), 5.5, color)
		draw_circle(body + Vector2(0, -9), 4.0, Color("efc49d"))
		if stage in ["throwing", "standstill", "run_up", "disc_flying", "waiting_group", "waiting_group_lie", "walking_group_lie", "walking_to_lie", "walking_to_basket"]:
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
		if int(active["id"]) == person_id and str(active["stage"]) in ["throwing", "standstill", "run_up", "disc_flying", "waiting_group", "waiting_group_lie", "walking_group_lie", "walking_to_lie", "walking_to_basket"]:
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
