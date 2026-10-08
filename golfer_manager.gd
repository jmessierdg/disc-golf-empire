# Disc Golf Empire - Update 18: persistent visitor foundation.
# No licensed brands, no simulated disc flight yet.
extends Node2D

signal visitor_arrived(person_id: int)
signal visitor_departed(person_id: int)

const MAX_VISITORS := 3
const WALK_SPEED := 54.0
const SPAWN_INTERVAL := 14.0
const SAVE_PATH := "user://dge_people_v1.json"
const FIRST_NAMES := ["Ethan", "Morgan", "Avery", "Taylor", "Riley", "Jordan", "Casey", "Alex", "Jamie", "Quinn", "Parker", "Rowan", "Sam", "Cameron"]
const LAST_NAMES := ["Brooks", "Reed", "Morgan", "Walker", "Parker", "Bennett", "Hayes", "Rivera", "Turner", "Ellis", "Stone", "Miller"]
const SKILLS := ["power", "accuracy", "putting", "control", "course_iq", "composure"]
const PALETTE := [Color("5e9ec7"), Color("d59c64"), Color("b46d9b"), Color("81b36c"), Color("cf8d72"), Color("847dc2")]

var property_manager
var course_manager
var path_manager
var people: Dictionary = {}
var visitors: Array = []
var next_person_id: int = 1
var next_membership_number: int = 10001
var spawn_timer: float = 2.0
var render_timer: float = 0.0
var rng := RandomNumberGenerator.new()
var profile_layer: CanvasLayer
var profile_panel: PanelContainer
var profile_label: Label
var selected_id: int = -1

func setup(property_ref, course_ref, path_ref) -> void:
	property_manager = property_ref
	course_manager = course_ref
	path_manager = path_ref
	z_index = 4
	rng.randomize()
	load_people()
	build_profile()
	set_process(true)

func get_entrance_local() -> Vector2:
	if property_manager.property_driveway_points.size() > 0:
		var points: Array = property_manager.property_driveway_points
		return property_manager.world_to_property_local(points[points.size() - 1])
	return property_manager.get_property_local_center()

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
	var holes: Array = completed_holes()
	if holes.is_empty() or visitors.size() >= MAX_VISITORS:
		return
	var person: Dictionary = make_person()
	var start: Vector2 = get_entrance_local()
	var visitor: Dictionary = {"id": int(person["id"]), "position": start, "state": "arriving", "holes": holes, "hole_cursor": 0, "stage": "tee", "route": [], "route_index": 0, "wait": 0.0, "walked": 0.0, "off_path": 0.0, "route_distance": 0.0}
	visitors.append(visitor)
	set_destination(visitor, hole_local(holes[0], "tee"))
	visitor_arrived.emit(int(person["id"]))

func hole_local(index: int, which: String) -> Vector2:
	return property_manager.world_to_property_local(course_manager.get_hole(index)[which])

func _process(delta: float) -> void:
	if property_manager == null:
		return
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = SPAWN_INTERVAL
		spawn_visitor()
	for i in range(visitors.size() - 1, -1, -1):
		var visitor: Dictionary = visitors[i]
		if float(visitor["wait"]) > 0.0:
			visitor["wait"] = maxf(0.0, float(visitor["wait"]) - delta)
			continue
		if advance_visitor(visitor, delta):
			advance_stage(visitor)
	render_timer += delta
	if render_timer >= 1.0 / 30.0:
		render_timer = 0.0
		queue_redraw()

func set_destination(visitor: Dictionary, destination: Vector2) -> void:
	var start: Vector2 = visitor["position"]
	var route: Array = route_via_walkways(start, destination)
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

func advance_visitor(visitor: Dictionary, delta: float) -> bool:
	var route: Array = visitor["route"]
	var index: int = int(visitor["route_index"])
	if index >= route.size():
		return true
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

func advance_stage(visitor: Dictionary) -> void:
	var holes: Array = visitor["holes"]
	var cursor: int = int(visitor["hole_cursor"])
	if str(visitor["stage"]) == "tee":
		visitor["stage"] = "basket"
		visitor["wait"] = 2.0
		set_destination(visitor, hole_local(int(holes[cursor]), "basket"))
	elif str(visitor["stage"]) == "basket":
		var person: Dictionary = people[int(visitor["id"])]
		person["holes_visited"] = int(person["holes_visited"]) + 1
		visitor["hole_cursor"] = cursor + 1
		if cursor + 1 < holes.size():
			visitor["stage"] = "tee"
			set_destination(visitor, hole_local(int(holes[cursor + 1]), "tee"))
		else:
			visitor["stage"] = "exiting"
			set_destination(visitor, get_entrance_local())
	else:
		var person: Dictionary = people[int(visitor["id"])]
		person["visits"] = int(person["visits"]) + 1
		var feedback: String = "Walking routes were easy to follow."
		if float(visitor["off_path"]) > float(visitor["walked"]) * 0.55:
			feedback = "The course needs better walking paths between holes."
		person["feedback"].append(feedback)
		person["history"].append({"holes": holes.size(), "feedback": feedback})
		visitors.erase(visitor)
		visitor_departed.emit(int(person["id"]))
		save_people()

func _draw() -> void:
	if property_manager == null:
		return
	for visitor_value in visitors:
		var visitor: Dictionary = visitor_value
		var person: Dictionary = people[int(visitor["id"])]
		var world: Vector2 = property_manager.property_local_to_world(visitor["position"])
		var color: Color = PALETTE[int(person["appearance"]) % PALETTE.size()]
		draw_circle(world + Vector2(2, 5), 7.0, Color(0, 0, 0, 0.22))
		draw_circle(world, 6.5, color)
		draw_circle(world + Vector2(0, -7), 4.5, Color("efc49d"))
		draw_arc(world, 10.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.8) if selected_id == int(person["id"]) else Color.TRANSPARENT, 1.8)

func select_at(world_point: Vector2) -> bool:
	if property_manager == null:
		return false
	for visitor_value in visitors:
		var visitor: Dictionary = visitor_value
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
