# course_renderer.gd
class_name CourseRenderer
extends Node2D


# ==================================================
# REFERENCES
# ==================================================

var property_manager
var course_manager
var job_manager

# Separate CanvasItems retain their drawing commands until invalidated.
# 0 = terrain, 1 = course, 2 = moving characters/jobs, 3 = selection UI.
var render_layer: int = 0
var course_layer
var actors_layer
var overlay_layer
var world_dirty: bool = false
var world_refresh_count: int = 0
var dynamic_refresh_count: int = 0


# ==================================================
# PERFORMANCE
# ==================================================

# The old renderer could redraw the entire property every game frame.
# This renderer batches redraw requests and limits the giant world
# renderer to 30 visual updates per second.
#
# Simulation can continue at full speed. Only this expensive visual
# renderer is throttled.

const MAX_RENDER_FPS := 30.0
const RENDER_INTERVAL := 1.0 / MAX_RENDER_FPS

var redraw_requested := true
var redraw_accumulator := 0.0


# ==================================================
# SETTINGS
# ==================================================

const PATH_WIDTH_SELECTED := 5.0
const PATH_WIDTH_NORMAL := 3.0

const PATH_POINT_RADIUS := 13.0
const PATH_POINT_HIT_RADIUS := 32.0

const TEE_HIT_RADIUS := 42.0
const BASKET_HIT_RADIUS := 42.0


# ==================================================
# COLORS
# ==================================================

const COLOR_WORLD_GRASS := Color(0.40, 0.54, 0.31, 1.0)
const COLOR_PROPERTY_GRASS := Color(0.49, 0.63, 0.38, 1.0)

const COLOR_ROUGH := Color(0.43, 0.56, 0.30, 1.0)
const COLOR_TALL_GRASS := Color(0.48, 0.52, 0.25, 1.0)
const COLOR_WILD_GRASS := Color(0.38, 0.43, 0.20, 1.0)
const COLOR_DIRT := Color(0.47, 0.38, 0.25, 1.0)

const COLOR_NEIGHBOR_FIELD := Color(0.54, 0.59, 0.34, 1.0)

const COLOR_PROPERTY_LINE := Color(0.93, 0.83, 0.48, 0.90)

const COLOR_WATER := Color(0.31, 0.50, 0.72, 1.0)
const COLOR_WATER_EDGE := Color(0.24, 0.41, 0.61, 1.0)

const COLOR_ROAD_SHOULDER := Color(0.40, 0.37, 0.32, 1.0)
const COLOR_ROAD := Color(0.23, 0.24, 0.23, 1.0)
const COLOR_ROAD_CENTER := Color(0.88, 0.76, 0.34, 0.82)

const COLOR_TRAIL_EDGE := Color(0.35, 0.29, 0.20, 1.0)
const COLOR_TRAIL := Color(0.63, 0.53, 0.35, 1.0)

const COLOR_BUSH_OUTER := Color(0.15, 0.31, 0.13, 1.0)
const COLOR_BUSH_INNER := Color(0.27, 0.45, 0.20, 1.0)

const COLOR_BRUSH_OUTER := Color(0.20, 0.29, 0.12, 1.0)
const COLOR_BRUSH_INNER := Color(0.36, 0.46, 0.20, 1.0)

const COLOR_VIEW_HIGHLIGHT := Color(0.36, 0.92, 0.48, 1.0)

const COLOR_WORK_AREA_FILL := Color(
	0.28,
	0.95,
	0.42,
	0.32
)

const COLOR_WORK_AREA_EDGE := Color(
	0.55,
	1.0,
	0.62,
	0.95
)

const COLOR_QUEUED_WORK_FILL := Color(
	1.0,
	0.48,
	0.12,
	0.20
)

const COLOR_QUEUED_WORK_EDGE := Color(
	1.0,
	0.58,
	0.16,
	0.92
)

const COLOR_ACTIVE_WORK_FILL := Color(
	0.95,
	0.82,
	0.24,
	0.18
)

const COLOR_ACTIVE_WORK_EDGE := Color(
	1.0,
	0.88,
	0.30,
	0.82
)


# ==================================================
# STATE
# ==================================================

var path_edit_mode := false
var viewed_object: Dictionary = {}

var landscape_preview_visible := false
var landscape_preview_position := Vector2.ZERO
var landscape_preview_radius := 0.0

var landscape_selected_cells: Array[Vector2i] = []
var landscape_selected_lookup: Dictionary = {}


# ==================================================
# SETUP
# ==================================================

func setup(
	property_ref,
	course_ref
) -> void:

	property_manager = property_ref
	course_manager = course_ref

	position = Vector2.ZERO

	set_process(true)
	if render_layer == 0:
		_create_render_layers()
	refresh_immediately()


func set_job_manager(
	job_ref
) -> void:

	job_manager = job_ref
	if render_layer == 0:
		course_layer.job_manager = job_ref
		actors_layer.job_manager = job_ref
		overlay_layer.job_manager = job_ref
	refresh_immediately()


# ==================================================
# PERFORMANCE UPDATE
# ==================================================

func _process(
	delta: float
) -> void:

	if not redraw_requested:
		return

	redraw_accumulator += delta

	if redraw_accumulator < RENDER_INTERVAL:
		return

	redraw_accumulator = 0.0
	redraw_requested = false

	queue_redraw()


# Keep the expensive static canvas untouched for ordinary tool interactions.
func _create_render_layers() -> void:
	course_layer = get_script().new()
	course_layer.name = "CourseCanvas"
	course_layer.render_layer = 1
	course_layer.property_manager = property_manager
	course_layer.course_manager = course_manager
	add_child(course_layer)

	actors_layer = get_script().new()
	actors_layer.name = "ActorsCanvas"
	actors_layer.render_layer = 2
	actors_layer.property_manager = property_manager
	actors_layer.course_manager = course_manager
	add_child(actors_layer)

	overlay_layer = get_script().new()
	overlay_layer.name = "ToolOverlayCanvas"
	overlay_layer.render_layer = 3
	overlay_layer.property_manager = property_manager
	overlay_layer.course_manager = course_manager
	add_child(overlay_layer)


func refresh() -> void:
	# Existing builder calls update course graphics and overlays, not terrain.
	if render_layer == 0:
		if course_layer != null:
			course_layer.redraw_requested = true
		if overlay_layer != null:
			_sync_overlay()
			overlay_layer.redraw_requested = true
	else:
		redraw_requested = true


func refresh_immediately() -> void:
	if render_layer == 0:
		if course_layer != null:
			course_layer.queue_redraw()
		if actors_layer != null:
			actors_layer.queue_redraw()
		if overlay_layer != null:
			_sync_overlay()
			overlay_layer.queue_redraw()
	queue_redraw()


func refresh_dynamic() -> void:
	# Moving workers do not invalidate terrain or course drawing.
	if render_layer == 0 and actors_layer != null:
		actors_layer.redraw_requested = true
		dynamic_refresh_count += 1
	elif render_layer == 2:
		redraw_requested = true


func refresh_world() -> void:
	# Terrain changes (mowing, brush, tree removal) explicitly invalidate
	# the static canvas. Godot retains draw commands between redraws.
	if render_layer == 0:
		world_refresh_count += 1
		redraw_requested = true
		refresh()
	else:
		redraw_requested = true


func _sync_overlay() -> void:
	if overlay_layer == null:
		return
	overlay_layer.path_edit_mode = path_edit_mode
	overlay_layer.viewed_object = viewed_object
	overlay_layer.landscape_preview_visible = landscape_preview_visible
	overlay_layer.landscape_preview_position = landscape_preview_position
	overlay_layer.landscape_preview_radius = landscape_preview_radius
	overlay_layer.landscape_selected_cells = landscape_selected_cells
	overlay_layer.landscape_selected_lookup = landscape_selected_lookup


func refresh_overlay() -> void:
	if render_layer == 0 and overlay_layer != null:
		_sync_overlay()
		overlay_layer.redraw_requested = true


func get_render_diagnostics() -> Dictionary:
	return {
		"world_invalidations": world_refresh_count,
		"actor_refresh_requests": dynamic_refresh_count,
		"fps": Engine.get_frames_per_second()
	}


func set_path_edit_mode(
	edit_active: bool
) -> void:

	path_edit_mode = edit_active

	refresh_overlay()


func set_viewed_object(
	object_data: Dictionary
) -> void:

	viewed_object = object_data.duplicate(
		true
	)

	refresh_overlay()


func clear_viewed_object() -> void:

	viewed_object.clear()

	refresh_overlay()


# ==================================================
# LANDSCAPE SELECTION
# ==================================================

func set_landscape_cursor(
	world_position: Vector2,
	radius: float
) -> void:

	landscape_preview_visible = true
	landscape_preview_position = world_position
	landscape_preview_radius = radius

	refresh_overlay()


func add_landscape_selection_cell(
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

	refresh_overlay()


func clear_landscape_selection() -> void:

	landscape_preview_visible = false
	landscape_preview_radius = 0.0

	landscape_selected_cells.clear()
	landscape_selected_lookup.clear()

	refresh_overlay()


# ==================================================
# DRAW
# ==================================================

func _draw() -> void:
	if property_manager == null or course_manager == null:
		return

	match render_layer:
		0:
			# Static draw commands are cached by CanvasItem.
			draw_world_background()
			draw_neighbor_fields()
			draw_public_road()
			draw_walking_trail()
			draw_world_trees()
			draw_owned_property()
			draw_property_ground_cover()
			draw_water()
			draw_property_bushes()
			draw_property_brush()
			draw_property_trees()
			draw_starter_facilities()
			draw_property_boundary()
		1:
			draw_all_holes()
		2:
			draw_all_queued_work_orders()
			draw_all_active_work_orders()
			draw_all_active_workers()
			draw_selected_worker_highlight()
		3:
			draw_landscape_preview()
			draw_view_highlight()


# ==================================================
# WORLD BACKGROUND
# ==================================================

# ==================================================
# STARTER FACILITIES
# ==================================================

func draw_starter_facilities() -> void:
	var entry: Array = property_manager.property_driveway_points
	var parking: Dictionary = property_manager.get_starter_facility("starter_parking")
	var shed: Dictionary = property_manager.get_starter_facility("starter_shed")
	var yard: Dictionary = property_manager.get_starter_facility("starter_yard")
	if entry.size() >= 4 and not parking.is_empty():
		# Public-road branch along the east property edge, connected to the
		# existing northern public road before entering the owned property.
		var road_x: float = entry[0].x
		var northern_road_y: float = property_manager.get_road_reference_y()
		draw_line(Vector2(road_x, northern_road_y), entry[0], Color(0.37, 0.35, 0.31), 54.0, true)
		draw_line(Vector2(road_x, northern_road_y), entry[0], Color(0.54, 0.52, 0.46), 43.0, true)
		var lot_center: Vector2 = parking["position"]
		# Entrance driveway terminates at visitor parking.
		for i in range(1, entry.size()):
			draw_line(entry[i - 1], entry[i], Color(0.40, 0.36, 0.30), 30.0, true)
			draw_line(entry[i - 1], entry[i], Color(0.68, 0.62, 0.50), 25.0, true)
		draw_line(entry[3], lot_center, Color(0.68, 0.62, 0.50), 25.0, true)
	if not parking.is_empty() and not shed.is_empty() and not yard.is_empty():
		# Narrow dirt maintenance track, visually separate from the parking.
		var lot: Vector2 = parking["position"]
		var shop: Vector2 = shed["position"]
		var storage: Vector2 = yard["position"]
		var track_start: Vector2 = lot + Vector2(-30.0, 20.0)
		var track_turn: Vector2 = Vector2(shop.x + 20.0, track_start.y + 35.0)
		draw_line(track_start, track_turn, Color(0.43, 0.34, 0.23), 16.0, true)
		draw_line(track_turn, storage, Color(0.43, 0.34, 0.23), 16.0, true)
		draw_line(track_start, track_turn, Color(0.58, 0.46, 0.32), 11.0, true)
		draw_line(track_turn, storage, Color(0.58, 0.46, 0.32), 11.0, true)
	for value in property_manager.buildings:
		var item: Dictionary = value
		var kind: String = str(item.get("type", ""))
		if not kind.begins_with("starter_"):
			continue
		var center: Vector2 = item["position"]
		var size: Vector2 = item["size"]
		var area: Rect2 = Rect2(center - size * 0.5, size)
		if kind == "starter_parking":
			draw_rect(area, Color(0.48, 0.44, 0.38), true)
			draw_rect(area, Color(0.72, 0.65, 0.53), false, 2.0)
			for i in range(5):
				var x: float = area.position.x + 12.0 + float(i) * (size.x - 24.0) / 5.0
				draw_line(Vector2(x, area.position.y + 6.0), Vector2(x, area.position.y + size.y * 0.38), Color(0.87, 0.82, 0.71), 1.8)
			continue
		if kind == "starter_yard":
			draw_rect(area, Color(0.52, 0.43, 0.30), true)
			draw_rect(area, Color(0.74, 0.65, 0.43), false, 2.5)
			for i in range(3):
				var x: float = area.position.x + 8.0 + float(i) * 23.0
				draw_rect(Rect2(Vector2(x, center.y - 7.0), Vector2(16.0, 12.0)), Color(0.23, 0.43, 0.26), true)
			continue
		var roof: Color = Color(0.22, 0.37, 0.43) if kind == "starter_office" else Color(0.36, 0.40, 0.33)
		draw_rect(Rect2(area.position + Vector2(4.0, 5.0), size), Color(0.0, 0.0, 0.0, 0.22), true)
		draw_rect(area, Color(0.77, 0.72, 0.61), true)
		draw_rect(area.grow(-4.0), roof, true)
		draw_line(Vector2(center.x, area.position.y + 4.0), Vector2(center.x, area.end.y - 4.0), Color(0.70, 0.72, 0.67), 2.0)
		draw_rect(area, Color(0.19, 0.23, 0.20), false, 2.0)
		var caption: String = "OFFICE" if kind == "starter_office" else "SHED"
		draw_string(ThemeDB.fallback_font, Vector2(area.position.x, area.position.y - 7.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


func draw_world_background() -> void:

	draw_rect(
		property_manager.get_world_rect(),
		COLOR_WORLD_GRASS,
		true
	)


# ==================================================
# NEIGHBOR FIELDS
# ==================================================

func draw_neighbor_fields() -> void:

	var world_size: Vector2 = (
		property_manager.get_world_size_pixels()
	)

	var property_rect: Rect2 = (
		property_manager.get_property_world_rect()
	)

	var cell_size: float = (
		property_manager.CELL_SIZE
	)

	var left_field := Rect2(
		Vector2(
			cell_size * 3.0,
			property_rect.position.y
			+ property_rect.size.y * 0.08
		),
		Vector2(
			property_rect.position.x
			- cell_size * 8.0,
			property_rect.size.y * 0.58
		)
	)

	draw_rect(
		left_field,
		COLOR_NEIGHBOR_FIELD,
		true
	)

	var right_start_x: float = (
		property_rect.end.x
		+ cell_size * 6.0
	)

	var right_field := Rect2(
		Vector2(
			right_start_x,
			property_rect.position.y
			+ property_rect.size.y * 0.30
		),
		Vector2(
			max(
				0.0,
				world_size.x
				- right_start_x
				- cell_size * 3.0
			),
			property_rect.size.y * 0.48
		)
	)

	draw_rect(
		right_field,
		COLOR_NEIGHBOR_FIELD,
		true
	)


# ==================================================
# OWNED PROPERTY
# ==================================================

func draw_owned_property() -> void:

	draw_rect(
		property_manager.get_property_world_rect(),
		COLOR_PROPERTY_GRASS,
		true
	)


# ==================================================
# PROPERTY GROUND COVER
# ==================================================

func draw_property_ground_cover() -> void:

	var origin: Vector2 = (
		property_manager.property_world_origin
	)

	var cell_size: float = (
		property_manager.CELL_SIZE
	)

	for y in range(
		property_manager.GRID_HEIGHT
	):

		for x in range(
			property_manager.GRID_WIDTH
		):

			var terrain_type: int = (
				property_manager.terrain[y][x]
			)

			if (
				terrain_type == property_manager.GRASS
				or terrain_type == property_manager.WATER
			):
				continue

			var terrain_color: Color = (
				COLOR_PROPERTY_GRASS
			)

			match terrain_type:

				property_manager.ROUGH:
					terrain_color = COLOR_ROUGH

				property_manager.TALL_GRASS:
					terrain_color = COLOR_TALL_GRASS

				property_manager.WILD_GRASS:
					terrain_color = COLOR_WILD_GRASS

				property_manager.FIELD:
					terrain_color = COLOR_NEIGHBOR_FIELD

				property_manager.DIRT:
					terrain_color = COLOR_DIRT

				_:
					continue

			var world_position: Vector2 = (
				origin
				+
				Vector2(
					x * cell_size,
					y * cell_size
				)
			)

			draw_rect(
				Rect2(
					world_position,
					Vector2(
						cell_size,
						cell_size
					)
				),
				terrain_color,
				true
			)

			if terrain_type == property_manager.TALL_GRASS:

				draw_grass_stalks(
					world_position,
					false
				)

			elif terrain_type == property_manager.WILD_GRASS:

				draw_grass_stalks(
					world_position,
					true
				)


# ==================================================
# GRASS DETAIL
# ==================================================

func draw_grass_stalks(
	world_position: Vector2,
	wild: bool
) -> void:

	var stalk_color := Color(
		0.62,
		0.66,
		0.32,
		0.50
	)

	var stalk_height := 15.0

	if wild:

		stalk_color = Color(
			0.65,
			0.59,
			0.25,
			0.60
		)

		stalk_height = 23.0

	draw_line(
		world_position + Vector2(8.0, 28.0),
		world_position + Vector2(
			11.0,
			28.0 - stalk_height
		),
		stalk_color,
		2.0,
		true
	)

	draw_line(
		world_position + Vector2(18.0, 29.0),
		world_position + Vector2(
			16.0,
			29.0 - stalk_height
		),
		stalk_color,
		2.0,
		true
	)

	draw_line(
		world_position + Vector2(27.0, 27.0),
		world_position + Vector2(
			23.0,
			27.0 - stalk_height * 0.85
		),
		stalk_color,
		2.0,
		true
	)


# ==================================================
# WATER
# ==================================================

func draw_water() -> void:

	var origin: Vector2 = (
		property_manager.property_world_origin
	)

	var cell_size: float = (
		property_manager.CELL_SIZE
	)

	for y in range(
		property_manager.GRID_HEIGHT
	):

		for x in range(
			property_manager.GRID_WIDTH
		):

			if not property_manager.is_water_cell(
				x,
				y
			):
				continue

			var world_position: Vector2 = (
				origin
				+
				Vector2(
					x * cell_size,
					y * cell_size
				)
			)

			draw_rect(
				Rect2(
					world_position
					- Vector2(1.5, 1.5),
					Vector2(
						cell_size + 3.0,
						cell_size + 3.0
					)
				),
				COLOR_WATER_EDGE,
				true
			)

	for y in range(
		property_manager.GRID_HEIGHT
	):

		for x in range(
			property_manager.GRID_WIDTH
		):

			if not property_manager.is_water_cell(
				x,
				y
			):
				continue

			var world_position: Vector2 = (
				origin
				+
				Vector2(
					x * cell_size,
					y * cell_size
				)
			)

			draw_rect(
				Rect2(
					world_position,
					Vector2(
						cell_size,
						cell_size
					)
				),
				COLOR_WATER,
				true
			)


# ==================================================
# PROPERTY BUSHES
# ==================================================

func draw_property_bushes() -> void:

	if not "bushes" in property_manager:
		return

	for i in range(
		property_manager.bushes.size()
	):

		var local_position: Vector2 = (
			property_manager.bushes[i]
		)

		var bush_scale := 1.0

		if (
			"bush_sizes" in property_manager
			and i < property_manager.bush_sizes.size()
		):

			bush_scale = (
				property_manager.bush_sizes[i]
			)

		var world_position: Vector2 = (
			property_manager.property_local_to_world(
				local_position
			)
		)

		draw_bush(
			world_position,
			bush_scale
		)


func draw_bush(
	world_position: Vector2,
	bush_scale: float
) -> void:

	var radius: float = (
		11.0 * bush_scale
	)

	draw_circle(
		world_position + Vector2(3.0, 4.0),
		radius + 2.0,
		Color(0.0, 0.0, 0.0, 0.20)
	)

	draw_circle(
		world_position + Vector2(-5.0, 1.0),
		radius,
		COLOR_BUSH_OUTER
	)

	draw_circle(
		world_position + Vector2(5.0, 2.0),
		radius * 0.90,
		COLOR_BUSH_OUTER
	)

	draw_circle(
		world_position + Vector2(0.0, -5.0),
		radius * 0.92,
		COLOR_BUSH_INNER
	)


# ==================================================
# PROPERTY BRUSH
# ==================================================

func draw_property_brush() -> void:

	if not "brush_clusters" in property_manager:
		return

	for i in range(
		property_manager.brush_clusters.size()
	):

		var local_position: Vector2 = (
			property_manager.brush_clusters[i]
		)

		var brush_scale := 1.0

		if (
			"brush_sizes" in property_manager
			and i < property_manager.brush_sizes.size()
		):

			brush_scale = (
				property_manager.brush_sizes[i]
			)

		var world_position: Vector2 = (
			property_manager.property_local_to_world(
				local_position
			)
		)

		draw_brush_cluster(
			world_position,
			brush_scale
		)


func draw_brush_cluster(
	world_position: Vector2,
	brush_scale: float
) -> void:

	var radius: float = (
		16.0 * brush_scale
	)

	draw_circle(
		world_position + Vector2(4.0, 5.0),
		radius,
		Color(0.0, 0.0, 0.0, 0.18)
	)

	draw_circle(
		world_position + Vector2(-7.0, 2.0),
		radius * 0.78,
		COLOR_BRUSH_OUTER
	)

	draw_circle(
		world_position + Vector2(7.0, 3.0),
		radius * 0.75,
		COLOR_BRUSH_OUTER
	)

	draw_circle(
		world_position + Vector2(0.0, -6.0),
		radius * 0.78,
		COLOR_BRUSH_INNER
	)

	draw_circle(
		world_position,
		radius * 0.45,
		COLOR_BRUSH_INNER
	)


# ==================================================
# TREES
# ==================================================

func draw_world_trees() -> void:

	var tree_count: int = (
		property_manager.world_trees.size()
	)

	for i in range(tree_count):

		if i >= property_manager.world_tree_sizes.size():
			continue

		draw_tree(
			property_manager.world_trees[i],
			property_manager.world_tree_sizes[i],
			false
		)


func draw_property_trees() -> void:

	var origin: Vector2 = (
		property_manager.property_world_origin
	)

	for i in range(
		property_manager.trees.size()
	):

		if i >= property_manager.tree_sizes.size():
			continue

		draw_tree(
			origin + property_manager.trees[i],
			property_manager.tree_sizes[i],
			true
		)


func draw_tree(
	world_position: Vector2,
	tree_scale: float,
	owned_tree: bool
) -> void:

	var trunk_radius: float = 4.0 * tree_scale
	var crown_radius: float = 18.0 * tree_scale

	draw_circle(
		world_position + Vector2(6.0, 8.0),
		crown_radius,
		Color(0.08, 0.12, 0.07, 0.30)
	)

	var outer_color := Color(0.13, 0.28, 0.15, 1.0)
	var inner_color := Color(0.22, 0.42, 0.23, 1.0)
	var highlight_color := Color(0.36, 0.56, 0.32, 1.0)

	if not owned_tree:

		outer_color = Color(0.12, 0.25, 0.14, 1.0)
		inner_color = Color(0.19, 0.36, 0.20, 1.0)
		highlight_color = Color(0.30, 0.47, 0.27, 1.0)

	draw_circle(
		world_position,
		crown_radius,
		outer_color
	)

	draw_circle(
		world_position - Vector2(2.0, 3.0),
		crown_radius * 0.72,
		inner_color
	)

	draw_circle(
		world_position
		-
		Vector2(
			crown_radius * 0.25,
			crown_radius * 0.30
		),
		crown_radius * 0.27,
		highlight_color
	)

	draw_circle(
		world_position,
		trunk_radius,
		Color(0.25, 0.19, 0.11, 0.72)
	)


# ==================================================
# PUBLIC ROAD
# ==================================================

func draw_public_road() -> void:

	var road_points: Array = (
		property_manager.road_points
	)

	if road_points.size() < 2:
		return

	var curve: Curve2D = (
		create_smooth_curve(
			road_points,
			0.28
		)
	)

	var baked_points: PackedVector2Array = (
		curve.get_baked_points()
	)

	if baked_points.size() < 2:
		return

	for i in range(
		baked_points.size() - 1
	):

		draw_line(
			baked_points[i],
			baked_points[i + 1],
			COLOR_ROAD_SHOULDER,
			58.0,
			true
		)

	for i in range(
		baked_points.size() - 1
	):

		draw_line(
			baked_points[i],
			baked_points[i + 1],
			COLOR_ROAD,
			46.0,
			true
		)

	draw_dashed_polyline(
		baked_points,
		COLOR_ROAD_CENTER,
		3.0,
		26.0,
		20.0
	)


# ==================================================
# WALKING TRAIL
# ==================================================

func draw_walking_trail() -> void:

	var trail_points: Array = (
		property_manager.walking_trail_points
	)

	if trail_points.size() < 2:
		return

	var curve: Curve2D = (
		create_smooth_curve(
			trail_points,
			0.30
		)
	)

	var baked_points: PackedVector2Array = (
		curve.get_baked_points()
	)

	if baked_points.size() < 2:
		return

	for i in range(
		baked_points.size() - 1
	):

		draw_line(
			baked_points[i],
			baked_points[i + 1],
			COLOR_TRAIL_EDGE,
			22.0,
			true
		)

	for i in range(
		baked_points.size() - 1
	):

		draw_line(
			baked_points[i],
			baked_points[i + 1],
			COLOR_TRAIL,
			15.0,
			true
		)


# ==================================================
# PROPERTY BOUNDARY
# ==================================================

func draw_property_boundary() -> void:

	var property_rect: Rect2 = (
		property_manager.get_property_world_rect()
	)

	draw_rect(
		property_rect,
		COLOR_PROPERTY_LINE,
		false,
		4.0
	)

	var marker_length: float = (
		property_manager.CELL_SIZE * 0.65
	)

	var top_left: Vector2 = property_rect.position

	var top_right := Vector2(
		property_rect.end.x,
		property_rect.position.y
	)

	var bottom_left := Vector2(
		property_rect.position.x,
		property_rect.end.y
	)

	var bottom_right: Vector2 = property_rect.end

	draw_boundary_corner(
		top_left,
		Vector2(1.0, 1.0),
		marker_length
	)

	draw_boundary_corner(
		top_right,
		Vector2(-1.0, 1.0),
		marker_length
	)

	draw_boundary_corner(
		bottom_left,
		Vector2(1.0, -1.0),
		marker_length
	)

	draw_boundary_corner(
		bottom_right,
		Vector2(-1.0, -1.0),
		marker_length
	)


func draw_boundary_corner(
	corner_position: Vector2,
	direction: Vector2,
	marker_length: float
) -> void:

	draw_line(
		corner_position,
		corner_position
		+
		Vector2(
			direction.x * marker_length,
			0.0
		),
		Color.WHITE,
		5.0,
		true
	)

	draw_line(
		corner_position,
		corner_position
		+
		Vector2(
			0.0,
			direction.y * marker_length
		),
		Color.WHITE,
		5.0,
		true
	)


# ==================================================
# CURVES
# ==================================================

func create_smooth_curve(
	points: Array,
	handle_strength: float
) -> Curve2D:

	var curve := Curve2D.new()

	curve.bake_interval = 8.0

	for i in range(
		points.size()
	):

		var current_point: Vector2 = points[i]
		var previous_point: Vector2 = current_point
		var next_point: Vector2 = current_point

		if i > 0:
			previous_point = points[i - 1]

		if i < points.size() - 1:
			next_point = points[i + 1]

		var tangent: Vector2 = (
			next_point - previous_point
		)

		var handle: Vector2 = (
			tangent * handle_strength
		)

		if i == 0:

			handle = (
				(next_point - current_point)
				* handle_strength
			)

		elif i == points.size() - 1:

			handle = (
				(current_point - previous_point)
				* handle_strength
			)

		curve.add_point(
			current_point,
			-handle,
			handle
		)

	return curve


func draw_dashed_polyline(
	points: PackedVector2Array,
	line_color: Color,
	line_width: float,
	dash_length: float,
	gap_length: float
) -> void:

	if points.size() < 2:
		return

	var draw_dash := true
	var remaining: float = dash_length

	for i in range(
		points.size() - 1
	):

		var segment_start: Vector2 = points[i]
		var segment_end: Vector2 = points[i + 1]

		var segment_vector: Vector2 = (
			segment_end - segment_start
		)

		var segment_length: float = (
			segment_vector.length()
		)

		if segment_length <= 0.0:
			continue

		var direction: Vector2 = (
			segment_vector / segment_length
		)

		var travelled := 0.0

		while travelled < segment_length:

			var step: float = min(
				remaining,
				segment_length - travelled
			)

			var part_start: Vector2 = (
				segment_start
				+
				direction * travelled
			)

			var part_end: Vector2 = (
				segment_start
				+
				direction
				*
				(travelled + step)
			)

			if draw_dash:

				draw_line(
					part_start,
					part_end,
					line_color,
					line_width,
					true
				)

			travelled += step
			remaining -= step

			if remaining <= 0.001:

				draw_dash = not draw_dash

				if draw_dash:
					remaining = dash_length
				else:
					remaining = gap_length


# ==================================================
# COURSE HOLES
# ==================================================

func draw_all_holes() -> void:

	var selected_hole: int = (
		course_manager.selected_hole
	)

	for hole_index in range(
		course_manager.holes.size()
	):

		if hole_index == selected_hole:
			continue

		draw_hole(
			hole_index,
			false
		)

	if (
		selected_hole >= 0
		and
		selected_hole < course_manager.holes.size()
	):

		draw_hole(
			selected_hole,
			true
		)


func draw_hole(
	hole_index: int,
	is_selected: bool
) -> void:

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return

	var tee: Vector2 = hole["tee"]
	var basket: Vector2 = hole["basket"]

	if (
		tee.x >= 0
		and basket.x >= 0
	):

		draw_flight_path(
			hole_index,
			is_selected
		)

	if tee.x >= 0:

		draw_tee(
			property_to_world(
				tee
			),
			hole_index,
			is_selected
		)

	if basket.x >= 0:

		draw_basket(
			property_to_world(
				basket
			),
			hole_index,
			is_selected
		)

	if (
		is_selected
		and path_edit_mode
	):

		draw_path_control_points(
			hole_index
		)


# ==================================================
# PROPERTY / WORLD CONVERSION
# ==================================================

func property_to_world(
	local_position: Vector2
) -> Vector2:

	return (
		property_manager.property_local_to_world(
			local_position
		)
	)


func world_to_property(
	world_position: Vector2
) -> Vector2:

	return (
		property_manager.world_to_property_local(
			world_position
		)
	)


# ==================================================
# TEE
# ==================================================

func draw_tee(
	world_position: Vector2,
	hole_index: int,
	is_selected: bool
) -> void:

	var radius := 18.0

	if is_selected:
		radius = 21.0

	draw_circle(
		world_position + Vector2(4.0, 5.0),
		radius,
		Color(0.0, 0.0, 0.0, 0.28)
	)

	draw_circle(
		world_position,
		radius,
		Color(0.18, 0.38, 0.95, 1.0)
	)

	draw_arc(
		world_position,
		radius,
		0.0,
		TAU,
		32,
		Color.WHITE,
		4.0,
		true
	)

	draw_string(
		ThemeDB.fallback_font,
		world_position
		+
		Vector2(
			radius + 8.0,
			8.0
		),
		"T" + str(hole_index + 1),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		24,
		Color.WHITE
	)


# ==================================================
# BASKET
# ==================================================

func draw_basket(
	world_position: Vector2,
	hole_index: int,
	is_selected: bool
) -> void:

	var radius := 18.0

	if is_selected:
		radius = 21.0

	draw_circle(
		world_position + Vector2(4.0, 5.0),
		radius,
		Color(0.0, 0.0, 0.0, 0.28)
	)

	draw_circle(
		world_position,
		radius,
		Color(1.0, 0.78, 0.26, 1.0)
	)

	draw_arc(
		world_position,
		radius,
		0.0,
		TAU,
		32,
		Color.WHITE,
		4.0,
		true
	)

	draw_string(
		ThemeDB.fallback_font,
		world_position
		+
		Vector2(
			radius + 8.0,
			8.0
		),
		"B" + str(hole_index + 1),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		24,
		Color.WHITE
	)


# ==================================================
# HOLE CURVE
# ==================================================

func build_hole_curve(
	hole_index: int
) -> Curve2D:

	var curve := Curve2D.new()

	curve.bake_interval = 6.0

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return curve

	var tee: Vector2 = hole["tee"]
	var basket: Vector2 = hole["basket"]
	var path_points: Array = hole["path_points"]

	if (
		tee.x < 0
		or basket.x < 0
	):
		return curve

	var route_points: Array = []

	route_points.append(
		property_to_world(
			tee
		)
	)

	for point_value in path_points:

		var local_point: Vector2 = (
			point_value
		)

		route_points.append(
			property_to_world(
				local_point
			)
		)

	route_points.append(
		property_to_world(
			basket
		)
	)

	for i in range(
		route_points.size()
	):

		var current_point: Vector2 = route_points[i]
		var previous_point: Vector2 = current_point
		var next_point: Vector2 = current_point

		if i > 0:
			previous_point = route_points[i - 1]

		if i < route_points.size() - 1:
			next_point = route_points[i + 1]

		var tangent: Vector2 = (
			next_point - previous_point
		)

		var handle: Vector2 = (
			tangent * 0.25
		)

		curve.add_point(
			current_point,
			-handle,
			handle
		)

	return curve


# ==================================================
# FLIGHT PATH
# ==================================================

func draw_flight_path(
	hole_index: int,
	is_selected: bool
) -> void:

	var curve: Curve2D = (
		build_hole_curve(
			hole_index
		)
	)

	var baked_points: PackedVector2Array = (
		curve.get_baked_points()
	)

	if baked_points.size() < 2:
		return

	var width := PATH_WIDTH_NORMAL

	var line_color := Color(
		1.0,
		1.0,
		1.0,
		0.72
	)

	if is_selected:

		width = PATH_WIDTH_SELECTED

		line_color = Color(
			1.0,
			1.0,
			1.0,
			0.96
		)

	for i in range(
		baked_points.size() - 1
	):

		draw_line(
			baked_points[i],
			baked_points[i + 1],
			line_color,
			width,
			true
		)


# ==================================================
# PATH CONTROL POINTS
# ==================================================

func draw_path_control_points(
	hole_index: int
) -> void:

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return

	var path_points: Array = (
		hole["path_points"]
	)

	for i in range(
		path_points.size()
	):

		var local_point: Vector2 = (
			path_points[i]
		)

		var world_point: Vector2 = (
			property_to_world(
				local_point
			)
		)

		draw_circle(
			world_point,
			PATH_POINT_RADIUS + 4.0,
			Color.WHITE
		)

		draw_circle(
			world_point,
			PATH_POINT_RADIUS,
			Color(0.78, 0.30, 0.92, 1.0)
		)

		draw_string(
			ThemeDB.fallback_font,
			world_point
			+
			Vector2(
				PATH_POINT_RADIUS + 8.0,
				7.0
			),
			str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			20,
			Color.WHITE
		)


# ==================================================
# HIT TESTS
# ==================================================

func find_path_point_at_position(
	hole_index: int,
	world_position: Vector2
) -> int:

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return -1

	var path_points: Array = (
		hole["path_points"]
	)

	for i in range(
		path_points.size()
	):

		var point_world: Vector2 = (
			property_to_world(
				path_points[i]
			)
		)

		if (
			world_position.distance_to(
				point_world
			)
			<= PATH_POINT_HIT_RADIUS
		):

			return i

	return -1


func is_position_near_tee(
	hole_index: int,
	world_position: Vector2
) -> bool:

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return false

	var tee: Vector2 = hole["tee"]

	if tee.x < 0:
		return false

	return (
		world_position.distance_to(
			property_to_world(
				tee
			)
		)
		<= TEE_HIT_RADIUS
	)


func is_position_near_basket(
	hole_index: int,
	world_position: Vector2
) -> bool:

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return false

	var basket: Vector2 = hole["basket"]

	if basket.x < 0:
		return false

	return (
		world_position.distance_to(
			property_to_world(
				basket
			)
		)
		<= BASKET_HIT_RADIUS
	)


func find_property_tree_at_position(
	world_position: Vector2
) -> int:

	var best_index: int = -1
	var best_distance: float = INF

	for i in range(
		property_manager.trees.size()
	):

		if i >= property_manager.tree_sizes.size():
			continue

		var local_position: Vector2 = (
			property_manager.trees[i]
		)

		var tree_world: Vector2 = (
			property_to_world(
				local_position
			)
		)

		var tree_scale: float = (
			property_manager.tree_sizes[i]
		)

		var hit_radius: float = max(
			30.0,
			24.0 * tree_scale
		)

		var distance: float = (
			world_position.distance_to(
				tree_world
			)
		)

		if (
			distance <= hit_radius
			and distance < best_distance
		):

			best_distance = distance
			best_index = i

	return best_index


func get_nearest_path_position(
	hole_index: int,
	world_position: Vector2
) -> Vector2:

	var curve: Curve2D = (
		build_hole_curve(
			hole_index
		)
	)

	if curve.point_count < 2:
		return world_position

	return curve.get_closest_point(
		world_position
	)


func is_position_near_path(
	hole_index: int,
	world_position: Vector2,
	maximum_distance: float = 45.0
) -> bool:

	var nearest_position: Vector2 = (
		get_nearest_path_position(
			hole_index,
			world_position
		)
	)

	return (
		world_position.distance_to(
			nearest_position
		)
		<= maximum_distance
	)


# ==================================================
# QUEUED WORK ORDERS
# ==================================================

func draw_all_queued_work_orders() -> void:

	if job_manager == null:
		return

	var queued_jobs: Array = (
		job_manager.get_queued_jobs()
	)

	for job_value in queued_jobs:

		var job: Dictionary = job_value

		var job_id: int = int(
			job.get(
				"id",
				-1
			)
		)

		var remaining_cells: Array = (
			job_manager.get_remaining_cells_for_job(
				job_id
			)
		)

		draw_work_order_cells(
			remaining_cells,
			COLOR_QUEUED_WORK_FILL,
			COLOR_QUEUED_WORK_EDGE,
			3.0
		)


# ==================================================
# ACTIVE WORK ORDERS
# ==================================================

func draw_all_active_work_orders() -> void:

	if job_manager == null:
		return

	var active_jobs: Array = (
		job_manager.get_active_jobs()
	)

	for job_value in active_jobs:

		var job: Dictionary = job_value

		var job_id: int = int(
			job.get(
				"id",
				-1
			)
		)

		var remaining_cells: Array = (
			job_manager.get_remaining_cells_for_job(
				job_id
			)
		)

		draw_work_order_cells(
			remaining_cells,
			COLOR_ACTIVE_WORK_FILL,
			COLOR_ACTIVE_WORK_EDGE,
			2.0
		)


# ==================================================
# GENERIC WORK ORDER DRAWING
# ==================================================

func draw_work_order_cells(
	remaining_cells: Array,
	fill_color: Color,
	edge_color: Color,
	edge_width: float
) -> void:

	if remaining_cells.is_empty():
		return

	var cell_size: float = (
		property_manager.CELL_SIZE
	)

	var origin: Vector2 = (
		property_manager.property_world_origin
	)

	var remaining_lookup: Dictionary = {}

	for cell_value in remaining_cells:

		var cell: Vector2i = cell_value

		remaining_lookup[cell] = true

	for cell_value in remaining_cells:

		var cell: Vector2i = cell_value

		var world_position: Vector2 = (
			origin
			+
			Vector2(
				float(cell.x) * cell_size,
				float(cell.y) * cell_size
			)
		)

		draw_rect(
			Rect2(
				world_position,
				Vector2(
					cell_size,
					cell_size
				)
			),
			fill_color,
			true
		)

		draw_work_cell_edges(
			cell,
			world_position,
			cell_size,
			remaining_lookup,
			edge_color,
			edge_width
		)


func draw_work_cell_edges(
	cell: Vector2i,
	world_position: Vector2,
	cell_size: float,
	remaining_lookup: Dictionary,
	edge_color: Color,
	edge_width: float
) -> void:

	var top_left: Vector2 = world_position

	var top_right := Vector2(
		world_position.x + cell_size,
		world_position.y
	)

	var bottom_left := Vector2(
		world_position.x,
		world_position.y + cell_size
	)

	var bottom_right := Vector2(
		world_position.x + cell_size,
		world_position.y + cell_size
	)

	if not remaining_lookup.has(
		Vector2i(
			cell.x,
			cell.y - 1
		)
	):

		draw_line(
			top_left,
			top_right,
			edge_color,
			edge_width,
			true
		)

	if not remaining_lookup.has(
		Vector2i(
			cell.x,
			cell.y + 1
		)
	):

		draw_line(
			bottom_left,
			bottom_right,
			edge_color,
			edge_width,
			true
		)

	if not remaining_lookup.has(
		Vector2i(
			cell.x - 1,
			cell.y
		)
	):

		draw_line(
			top_left,
			bottom_left,
			edge_color,
			edge_width,
			true
		)

	if not remaining_lookup.has(
		Vector2i(
			cell.x + 1,
			cell.y
		)
	):

		draw_line(
			top_right,
			bottom_right,
			edge_color,
			edge_width,
			true
		)


# ==================================================
# ACTIVE WORKERS
# ==================================================

func draw_all_active_workers() -> void:

	if job_manager == null:
		return

	var active_workers: Array = (
		job_manager.get_all_workers()
	)

	for worker_value in active_workers:

		var worker: Dictionary = worker_value

		draw_worker(
			worker
		)


func draw_worker(
	worker: Dictionary
) -> void:

	var local_position: Vector2 = (
		worker.get(
			"position",
			Vector2(-1.0, -1.0)
		)
	)

	if local_position.x < 0.0:
		return

	var world_position: Vector2 = (
		property_manager.property_local_to_world(
			local_position
		)
	)

	var direction: Vector2 = (
		worker.get(
			"direction",
			Vector2.RIGHT
		)
	)

	if direction.length_squared() <= 0.001:
		direction = Vector2.RIGHT

	direction = direction.normalized()

	var side := Vector2(
		-direction.y,
		direction.x
	)

	var phase: String = str(worker.get("state", "idle"))
	if phase != "working":
		draw_circle(world_position + Vector2(2.0, 3.0), 9.0, Color(0.0, 0.0, 0.0, 0.20))
		draw_circle(world_position, 7.0, Color(0.24, 0.44, 0.83))
		draw_circle(world_position - direction * 5.0, 4.0, Color(0.88, 0.71, 0.53))
		return

	var job_id: int = int(
		worker.get(
			"job_id",
			-1
		)
	)

	var job: Dictionary = (
		job_manager.get_job_by_id(
			job_id
		)
	)

	var job_type: String = (
		job.get(
			"type",
			""
		)
	)

	if job_type == job_manager.JOB_BRUSH:

		draw_brush_worker(
			world_position,
			direction,
			side
		)

	else:

		draw_mower_worker(
			world_position,
			direction,
			side
		)


func draw_mower_worker(
	world_position: Vector2,
	direction: Vector2,
	side: Vector2
) -> void:

	draw_circle(
		world_position + Vector2(3.0, 5.0),
		13.0,
		Color(0.0, 0.0, 0.0, 0.24)
	)

	draw_circle(
		world_position,
		11.0,
		Color(0.22, 0.68, 0.30, 1.0)
	)

	draw_arc(
		world_position,
		11.0,
		0.0,
		TAU,
		24,
		Color.WHITE,
		2.0,
		true
	)

	var handle_start: Vector2 = (
		world_position
		- direction * 7.0
	)

	var handle_end: Vector2 = (
		world_position
		- direction * 20.0
	)

	draw_line(
		handle_start,
		handle_end,
		Color(0.18, 0.18, 0.18, 1.0),
		3.0,
		true
	)

	var worker_position: Vector2 = (
		world_position
		- direction * 27.0
	)

	draw_worker_body(
		worker_position,
		direction,
		side,
		handle_end
	)


func draw_brush_worker(
	world_position: Vector2,
	direction: Vector2,
	side: Vector2
) -> void:

	var worker_position: Vector2 = (
		world_position
		- direction * 15.0
	)

	var cutter_head: Vector2 = (
		world_position
		+ direction * 10.0
	)

	draw_circle(
		cutter_head + Vector2(2.0, 3.0),
		8.0,
		Color(0.0, 0.0, 0.0, 0.22)
	)

	draw_circle(
		cutter_head,
		6.5,
		Color(0.92, 0.46, 0.16, 1.0)
	)

	draw_line(
		worker_position,
		cutter_head,
		Color(0.22, 0.22, 0.22, 1.0),
		3.0,
		true
	)

	var handle_position: Vector2 = (
		worker_position
		+ direction * 5.0
	)

	draw_line(
		handle_position - side * 6.0,
		handle_position + side * 6.0,
		Color(0.18, 0.18, 0.18, 1.0),
		2.5,
		true
	)

	draw_worker_body(
		worker_position,
		direction,
		side,
		handle_position
	)


func draw_worker_body(
	worker_position: Vector2,
	direction: Vector2,
	side: Vector2,
	hand_target: Vector2
) -> void:

	draw_circle(
		worker_position,
		7.0,
		Color(0.22, 0.34, 0.82, 1.0)
	)

	draw_line(
		worker_position + side * 4.0,
		hand_target + side * 3.0,
		Color(0.84, 0.68, 0.52, 1.0),
		2.5,
		true
	)

	draw_line(
		worker_position - side * 4.0,
		hand_target - side * 3.0,
		Color(0.84, 0.68, 0.52, 1.0),
		2.5,
		true
	)

	draw_circle(
		worker_position - direction * 7.0,
		4.5,
		Color(0.84, 0.68, 0.52, 1.0)
	)


# ==================================================
# LANDSCAPE PREVIEW
# ==================================================

func draw_landscape_preview() -> void:

	draw_landscape_selected_area()
	draw_landscape_cursor()


func draw_landscape_selected_area() -> void:

	if landscape_selected_cells.is_empty():
		return

	var cell_size: float = (
		property_manager.CELL_SIZE
	)

	var origin: Vector2 = (
		property_manager.property_world_origin
	)

	for cell in landscape_selected_cells:

		var world_position: Vector2 = (
			origin
			+
			Vector2(
				float(cell.x) * cell_size,
				float(cell.y) * cell_size
			)
		)

		draw_rect(
			Rect2(
				world_position,
				Vector2(
					cell_size,
					cell_size
				)
			),
			COLOR_WORK_AREA_FILL,
			true
		)

		draw_landscape_cell_edges(
			cell,
			world_position,
			cell_size
		)


func draw_landscape_cell_edges(
	cell: Vector2i,
	world_position: Vector2,
	cell_size: float
) -> void:

	var left_cell := Vector2i(
		cell.x - 1,
		cell.y
	)

	var right_cell := Vector2i(
		cell.x + 1,
		cell.y
	)

	var top_cell := Vector2i(
		cell.x,
		cell.y - 1
	)

	var bottom_cell := Vector2i(
		cell.x,
		cell.y + 1
	)

	var top_left: Vector2 = world_position

	var top_right := Vector2(
		world_position.x + cell_size,
		world_position.y
	)

	var bottom_left := Vector2(
		world_position.x,
		world_position.y + cell_size
	)

	var bottom_right := Vector2(
		world_position.x + cell_size,
		world_position.y + cell_size
	)

	if not landscape_selected_lookup.has(
		top_cell
	):

		draw_line(
			top_left,
			top_right,
			COLOR_WORK_AREA_EDGE,
			3.0,
			true
		)

	if not landscape_selected_lookup.has(
		bottom_cell
	):

		draw_line(
			bottom_left,
			bottom_right,
			COLOR_WORK_AREA_EDGE,
			3.0,
			true
		)

	if not landscape_selected_lookup.has(
		left_cell
	):

		draw_line(
			top_left,
			bottom_left,
			COLOR_WORK_AREA_EDGE,
			3.0,
			true
		)

	if not landscape_selected_lookup.has(
		right_cell
	):

		draw_line(
			top_right,
			bottom_right,
			COLOR_WORK_AREA_EDGE,
			3.0,
			true
		)


func draw_landscape_cursor() -> void:

	if not landscape_preview_visible:
		return

	if landscape_preview_radius <= 0.0:
		return

	draw_circle(
		landscape_preview_position,
		landscape_preview_radius,
		Color(0.40, 0.95, 0.48, 0.10)
	)

	draw_arc(
		landscape_preview_position,
		landscape_preview_radius,
		0.0,
		TAU,
		40,
		COLOR_WORK_AREA_EDGE,
		3.0,
		true
	)


# ==================================================
# VIEW HIGHLIGHT
# ==================================================

func draw_view_highlight() -> void:

	if viewed_object.is_empty():
		return

	var object_type: String = (
		viewed_object.get(
			"type",
			""
		)
	)

	match object_type:

		"tree":
			draw_tree_view_highlight()

		"tee":
			draw_tee_view_highlight()

		"basket":
			draw_basket_view_highlight()

		"path_point":
			draw_path_point_view_highlight()

		"building":
			var index: int = int(viewed_object.get("index", -1))
			if index >= 0 and index < property_manager.buildings.size():
				var item: Dictionary = property_manager.buildings[index]
				var center: Vector2 = item["position"]
				var size: Vector2 = item["size"]
				draw_rect(Rect2(center - size * 0.5, size).grow(5.0), Color(1.0, 0.85, 0.25), false, 3.0)


func draw_tree_view_highlight() -> void:

	var tree_index: int = (
		viewed_object.get(
			"index",
			-1
		)
	)

	if (
		tree_index < 0
		or tree_index >= property_manager.trees.size()
		or tree_index >= property_manager.tree_sizes.size()
	):
		return

	var local_position: Vector2 = (
		property_manager.trees[
			tree_index
		]
	)

	var tree_scale: float = (
		property_manager.tree_sizes[
			tree_index
		]
	)

	draw_selection_ring(
		property_to_world(
			local_position
		),
		28.0 * tree_scale
	)


func draw_tee_view_highlight() -> void:

	var hole_index: int = (
		viewed_object.get(
			"hole_index",
			-1
		)
	)

	if hole_index < 0:
		return

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return

	var tee: Vector2 = hole["tee"]

	if tee.x < 0:
		return

	draw_selection_ring(
		property_to_world(
			tee
		),
		31.0
	)


func draw_basket_view_highlight() -> void:

	var hole_index: int = (
		viewed_object.get(
			"hole_index",
			-1
		)
	)

	if hole_index < 0:
		return

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return

	var basket: Vector2 = hole["basket"]

	if basket.x < 0:
		return

	draw_selection_ring(
		property_to_world(
			basket
		),
		31.0
	)


func draw_path_point_view_highlight() -> void:

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
		return

	var hole: Dictionary = (
		course_manager.get_hole(
			hole_index
		)
	)

	if hole.is_empty():
		return

	var path_points: Array = (
		hole["path_points"]
	)

	if point_index >= path_points.size():
		return

	var local_point: Vector2 = (
		path_points[
			point_index
		]
	)

	draw_selection_ring(
		property_to_world(
			local_point
		),
		PATH_POINT_RADIUS + 12.0
	)


func draw_selection_ring(
	world_position: Vector2,
	radius: float
) -> void:

	draw_circle(
		world_position,
		radius + 8.0,
		Color(
			COLOR_VIEW_HIGHLIGHT.r,
			COLOR_VIEW_HIGHLIGHT.g,
			COLOR_VIEW_HIGHLIGHT.b,
			0.13
		)
	)

	draw_arc(
		world_position,
		radius,
		0.0,
		TAU,
		48,
		COLOR_VIEW_HIGHLIGHT,
		5.0,
		true
	)

# Worker selection highlight (independent of active work orders).
func draw_selected_worker_highlight() -> void:
	if job_manager == null or property_manager == null:
		return
	if str(viewed_object.get("type", "")) != "worker":
		return
	var selected_id: int = int(viewed_object.get("worker_id", -1))
	for worker_value in job_manager.get_all_workers():
		var worker: Dictionary = worker_value
		if int(worker.get("id", -1)) != selected_id:
			continue
		var local_pos: Vector2 = worker.get("position", Vector2(-1, -1))
		if local_pos.x >= 0.0:
			draw_arc(property_manager.property_local_to_world(local_pos), 20.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.28, 0.95), 3.0, true)
		return
