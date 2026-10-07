class_name PropertyManager
extends Node


# ==================================================
# WORLD SCALE
# ==================================================

const CELL_SIZE := 32.0

const PROPERTY_GRID_WIDTH := 70
const PROPERTY_GRID_HEIGHT := 90

const WORLD_MARGIN_CELLS := 40

const WORLD_GRID_WIDTH := PROPERTY_GRID_WIDTH + WORLD_MARGIN_CELLS * 2
const WORLD_GRID_HEIGHT := PROPERTY_GRID_HEIGHT + WORLD_MARGIN_CELLS * 2

# Compatibility with existing systems.
const GRID_WIDTH := PROPERTY_GRID_WIDTH
const GRID_HEIGHT := PROPERTY_GRID_HEIGHT


# ==================================================
# TERRAIN TYPES
# ==================================================

const GRASS := 0
const WATER := 1
const ROUGH := 2
const FIELD := 3
const TALL_GRASS := 4
const WILD_GRASS := 5
const DIRT := 6


# ==================================================
# SEED
# ==================================================

var property_seed := 847291
var rng := RandomNumberGenerator.new()


# ==================================================
# PROPERTY DATA
# ==================================================

var terrain: Array = []

var trees: Array[Vector2] = []
var tree_sizes: Array[float] = []

var bushes: Array[Vector2] = []
var bush_sizes: Array[float] = []

var brush_clusters: Array[Vector2] = []
var brush_sizes: Array[float] = []


# ==================================================
# SURROUNDING WORLD DATA
# ==================================================

var world_trees: Array[Vector2] = []
var world_tree_sizes: Array[float] = []

var road_points: Array[Vector2] = []
var walking_trail_points: Array[Vector2] = []

var neighbor_parcels: Array = []
var buildings: Array = []
var driveways: Array = []

var property_driveway_points: Array[Vector2] = []


# ==================================================
# PROPERTY POSITION
# ==================================================

var property_world_origin := Vector2.ZERO


# ==================================================
# STARTUP
# ==================================================

func _ready() -> void:
	generate_property(property_seed)


# ==================================================
# GENERATE COMPLETE WORLD
# ==================================================

func generate_property(seed_value: int) -> void:
	property_seed = seed_value
	rng.seed = property_seed

	terrain.clear()

	trees.clear()
	tree_sizes.clear()

	bushes.clear()
	bush_sizes.clear()

	brush_clusters.clear()
	brush_sizes.clear()

	world_trees.clear()
	world_tree_sizes.clear()

	road_points.clear()
	walking_trail_points.clear()

	neighbor_parcels.clear()
	buildings.clear()
	driveways.clear()

	property_driveway_points.clear()

	property_world_origin = Vector2(
		WORLD_MARGIN_CELLS * CELL_SIZE,
		WORLD_MARGIN_CELLS * CELL_SIZE
	)

	# Owned land.
	generate_base_terrain()
	generate_vegetation_regions()
	generate_pond()

	generate_tree_clusters()
	generate_scattered_trees()

	generate_bushes()
	generate_brush_clusters()

	# Surrounding world.
	generate_public_road()
	generate_neighbor_parcels()
	generate_neighbor_buildings()
	generate_driveways()
	generate_property_entrance()
	generate_walking_trail()
	generate_surrounding_world()


# ==================================================
# BASE TERRAIN
# ==================================================

func generate_base_terrain() -> void:
	terrain.clear()

	for y in range(PROPERTY_GRID_HEIGHT):
		var row: Array = []

		for x in range(PROPERTY_GRID_WIDTH):
			row.append(ROUGH)

		terrain.append(row)


# ==================================================
# VEGETATION REGIONS
# ==================================================

func generate_vegetation_regions() -> void:
	# Existing maintained/open area near the property entrance.
	paint_terrain_blob(
		Vector2(18, 10),
		14.0,
		10.0,
		GRASS
	)

	# Existing somewhat-maintained open land.
	paint_terrain_blob(
		Vector2(35, 23),
		18.0,
		14.0,
		ROUGH
	)

	# Tall meadow regions.
	paint_terrain_blob(
		Vector2(15, 45),
		18.0,
		21.0,
		TALL_GRASS
	)

	paint_terrain_blob(
		Vector2(51, 40),
		17.0,
		18.0,
		TALL_GRASS
	)

	paint_terrain_blob(
		Vector2(37, 70),
		23.0,
		18.0,
		TALL_GRASS
	)

	# Heavy neglected vegetation.
	paint_terrain_blob(
		Vector2(8, 77),
		12.0,
		16.0,
		WILD_GRASS
	)

	paint_terrain_blob(
		Vector2(61, 67),
		11.0,
		18.0,
		WILD_GRASS
	)

	paint_terrain_blob(
		Vector2(60, 17),
		10.0,
		13.0,
		WILD_GRASS
	)


# ==================================================
# PAINT TERRAIN BLOB
# ==================================================

func paint_terrain_blob(
	center_cell: Vector2,
	radius_x: float,
	radius_y: float,
	terrain_type: int
) -> void:
	var min_x: int = max(
		0,
		int(center_cell.x - radius_x - 2.0)
	)

	var max_x: int = min(
		PROPERTY_GRID_WIDTH - 1,
		int(center_cell.x + radius_x + 2.0)
	)

	var min_y: int = max(
		0,
		int(center_cell.y - radius_y - 2.0)
	)

	var max_y: int = min(
		PROPERTY_GRID_HEIGHT - 1,
		int(center_cell.y + radius_y + 2.0)
	)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx: float = (
				(float(x) - center_cell.x)
				/ radius_x
			)

			var dy: float = (
				(float(y) - center_cell.y)
				/ radius_y
			)

			var normalized_distance: float = (
				dx * dx
				+ dy * dy
			)

			var edge_noise: float = rng.randf_range(
				-0.18,
				0.18
			)

			if normalized_distance <= 1.0 + edge_noise:
				terrain[y][x] = terrain_type


# ==================================================
# POND
# ==================================================

func generate_pond() -> void:
	var pond_center := Vector2(48, 29)

	for y in range(PROPERTY_GRID_HEIGHT):
		for x in range(PROPERTY_GRID_WIDTH):
			var edge_variation: float = rng.randf_range(
				-2.0,
				2.0
			)

			var stretched_distance: float = sqrt(
				pow(
					(x - pond_center.x) / 1.4,
					2
				)
				+
				pow(
					y - pond_center.y,
					2
				)
			)

			if stretched_distance < 8.0 + edge_variation:
				terrain[y][x] = WATER


# ==================================================
# PROPERTY TREE CLUSTERS
# ==================================================

func generate_tree_clusters() -> void:
	create_tree_cluster(Vector2(12, 16), 10, 90)
	create_tree_cluster(Vector2(24, 39), 9, 75)
	create_tree_cluster(Vector2(55, 52), 11, 110)
	create_tree_cluster(Vector2(16, 69), 12, 120)
	create_tree_cluster(Vector2(48, 78), 10, 85)
	create_tree_cluster(Vector2(63, 14), 7, 55)


func create_tree_cluster(
	center_cell: Vector2,
	radius_cells: float,
	tree_count: int
) -> void:
	for i in range(tree_count):
		var angle: float = rng.randf_range(
			0.0,
			TAU
		)

		var distance: float = (
			sqrt(rng.randf())
			* radius_cells
		)

		var cell_position: Vector2 = (
			center_cell
			+
			Vector2(
				cos(angle),
				sin(angle)
			)
			* distance
		)

		var local_position := Vector2(
			cell_position.x * CELL_SIZE,
			cell_position.y * CELL_SIZE
		)

		add_tree(local_position)


# ==================================================
# SCATTERED PROPERTY TREES
# ==================================================

func generate_scattered_trees() -> void:
	for i in range(115):
		var local_position := Vector2(
			rng.randf_range(
				2.0,
				PROPERTY_GRID_WIDTH - 2.0
			) * CELL_SIZE,
			rng.randf_range(
				2.0,
				PROPERTY_GRID_HEIGHT - 2.0
			) * CELL_SIZE
		)

		add_tree(local_position)


func add_tree(local_position: Vector2) -> void:
	var cell: Vector2i = world_to_cell(
		local_position
	)

	if not is_valid_cell(
		cell.x,
		cell.y
	):
		return

	if terrain[cell.y][cell.x] == WATER:
		return

	trees.append(local_position)

	tree_sizes.append(
		rng.randf_range(
			0.75,
			1.35
		)
	)


# ==================================================
# BUSHES
# ==================================================

func generate_bushes() -> void:
	for i in range(145):
		var local_position := Vector2(
			rng.randf_range(
				CELL_SIZE,
				get_property_size_pixels().x - CELL_SIZE
			),
			rng.randf_range(
				CELL_SIZE,
				get_property_size_pixels().y - CELL_SIZE
			)
		)

		var cell: Vector2i = world_to_cell(
			local_position
		)

		if not is_valid_cell(
			cell.x,
			cell.y
		):
			continue

		var terrain_type: int = terrain[cell.y][cell.x]

		if (
			terrain_type != ROUGH
			and terrain_type != TALL_GRASS
			and terrain_type != WILD_GRASS
		):
			continue

		if is_tree_too_close(
			local_position,
			CELL_SIZE * 0.45
		):
			continue

		bushes.append(local_position)

		bush_sizes.append(
			rng.randf_range(
				0.65,
				1.30
			)
		)


# ==================================================
# HEAVY BRUSH
# ==================================================

func generate_brush_clusters() -> void:
	create_brush_cluster(
		Vector2(8, 77),
		9.0,
		35
	)

	create_brush_cluster(
		Vector2(61, 67),
		9.0,
		32
	)

	create_brush_cluster(
		Vector2(60, 17),
		7.0,
		24
	)


func create_brush_cluster(
	center_cell: Vector2,
	radius_cells: float,
	brush_count: int
) -> void:
	for i in range(brush_count):
		var angle: float = rng.randf_range(
			0.0,
			TAU
		)

		var distance: float = (
			sqrt(rng.randf())
			* radius_cells
			* CELL_SIZE
		)

		var local_position: Vector2 = (
			center_cell * CELL_SIZE
			+
			Vector2(
				cos(angle),
				sin(angle)
			)
			* distance
		)

		var cell: Vector2i = world_to_cell(
			local_position
		)

		if not is_valid_cell(
			cell.x,
			cell.y
		):
			continue

		if terrain[cell.y][cell.x] == WATER:
			continue

		brush_clusters.append(
			local_position
		)

		brush_sizes.append(
			rng.randf_range(
				0.75,
				1.45
			)
		)


# ==================================================
# MOWING
# ==================================================

func mow_at_local_position(
	local_position: Vector2,
	radius_pixels: float
) -> bool:
	var changed := false

	var center_cell: Vector2i = world_to_cell(
		local_position
	)

	var cell_radius: int = int(
		ceil(
			radius_pixels / CELL_SIZE
		)
	)

	for y in range(
		center_cell.y - cell_radius,
		center_cell.y + cell_radius + 1
	):
		for x in range(
			center_cell.x - cell_radius,
			center_cell.x + cell_radius + 1
		):
			if not is_valid_cell(
				x,
				y
			):
				continue

			var cell_center: Vector2 = (
				cell_to_world_center(
					Vector2i(x, y)
				)
			)

			if cell_center.distance_to(
				local_position
			) > radius_pixels:
				continue

			var terrain_type: int = terrain[y][x]

			if (
				terrain_type == ROUGH
				or terrain_type == TALL_GRASS
			):
				terrain[y][x] = GRASS
				changed = true

	return changed


# ==================================================
# BRUSH CUTTING
# ==================================================

func brush_cut_at_local_position(
	local_position: Vector2,
	radius_pixels: float
) -> bool:
	var changed := false

	var center_cell: Vector2i = world_to_cell(
		local_position
	)

	var cell_radius: int = int(
		ceil(
			radius_pixels / CELL_SIZE
		)
	)

	# Heavy wild grass gets knocked down to tall grass.
	for y in range(
		center_cell.y - cell_radius,
		center_cell.y + cell_radius + 1
	):
		for x in range(
			center_cell.x - cell_radius,
			center_cell.x + cell_radius + 1
		):
			if not is_valid_cell(
				x,
				y
			):
				continue

			var cell_center: Vector2 = (
				cell_to_world_center(
					Vector2i(x, y)
				)
			)

			if cell_center.distance_to(
				local_position
			) > radius_pixels:
				continue

			if terrain[y][x] == WILD_GRASS:
				terrain[y][x] = TALL_GRASS
				changed = true

	# Remove bushes.
	for i in range(
		bushes.size() - 1,
		-1,
		-1
	):
		if bushes[i].distance_to(
			local_position
		) <= radius_pixels:
			bushes.remove_at(i)

			if i < bush_sizes.size():
				bush_sizes.remove_at(i)

			changed = true

	# Remove heavy brush objects.
	for i in range(
		brush_clusters.size() - 1,
		-1,
		-1
	):
		if brush_clusters[i].distance_to(
			local_position
		) <= radius_pixels:
			brush_clusters.remove_at(i)

			if i < brush_sizes.size():
				brush_sizes.remove_at(i)

			changed = true

	return changed


# ==================================================
# TERRAIN INFORMATION
# ==================================================

func get_terrain_at_local_position(
	local_position: Vector2
) -> int:
	var cell: Vector2i = world_to_cell(
		local_position
	)

	if not is_valid_cell(
		cell.x,
		cell.y
	):
		return -1

	return terrain[cell.y][cell.x]


func get_disc_search_difficulty(
	local_position: Vector2
) -> float:
	match get_terrain_at_local_position(
		local_position
	):
		GRASS:
			return 1.0

		ROUGH:
			return 1.4

		TALL_GRASS:
			return 3.0

		WILD_GRASS:
			return 5.0

		FIELD:
			return 1.8

		_:
			return 1.0


# ==================================================
# PUBLIC ROAD
# ==================================================

func generate_public_road() -> void:
	road_points.clear()

	var property_rect: Rect2 = (
		get_property_world_rect()
	)

	var road_y: float = (
		property_rect.position.y
		- CELL_SIZE * 11.0
	)

	var world_width: float = (
		get_world_size_pixels().x
	)

	road_points.append(
		Vector2(
			-CELL_SIZE * 4.0,
			road_y - CELL_SIZE * 0.8
		)
	)

	road_points.append(
		Vector2(
			world_width * 0.18,
			road_y
		)
	)

	road_points.append(
		Vector2(
			world_width * 0.38,
			road_y + CELL_SIZE * 1.1
		)
	)

	road_points.append(
		Vector2(
			world_width * 0.58,
			road_y + CELL_SIZE * 0.7
		)
	)

	road_points.append(
		Vector2(
			world_width * 0.78,
			road_y - CELL_SIZE * 0.7
		)
	)

	road_points.append(
		Vector2(
			world_width + CELL_SIZE * 4.0,
			road_y + CELL_SIZE * 0.3
		)
	)


# ==================================================
# NEIGHBOR PARCELS
# ==================================================

func generate_neighbor_parcels() -> void:
	neighbor_parcels.clear()

	var property_rect: Rect2 = (
		get_property_world_rect()
	)

	neighbor_parcels.append({
		"name": "Northwest Home",
		"type": "residential",
		"rect": Rect2(
			Vector2(
				property_rect.position.x - CELL_SIZE * 31.0,
				property_rect.position.y - CELL_SIZE * 8.0
			),
			Vector2(
				CELL_SIZE * 24.0,
				CELL_SIZE * 27.0
			)
		)
	})

	neighbor_parcels.append({
		"name": "Northeast Home",
		"type": "residential",
		"rect": Rect2(
			Vector2(
				property_rect.end.x + CELL_SIZE * 7.0,
				property_rect.position.y - CELL_SIZE * 7.0
			),
			Vector2(
				CELL_SIZE * 25.0,
				CELL_SIZE * 28.0
			)
		)
	})

	neighbor_parcels.append({
		"name": "West Farm",
		"type": "farm",
		"rect": Rect2(
			Vector2(
				property_rect.position.x - CELL_SIZE * 34.0,
				property_rect.position.y + CELL_SIZE * 28.0
			),
			Vector2(
				CELL_SIZE * 27.0,
				CELL_SIZE * 42.0
			)
		)
	})

	neighbor_parcels.append({
		"name": "Southeast Home",
		"type": "residential",
		"rect": Rect2(
			Vector2(
				property_rect.end.x + CELL_SIZE * 7.0,
				property_rect.position.y + CELL_SIZE * 49.0
			),
			Vector2(
				CELL_SIZE * 27.0,
				CELL_SIZE * 30.0
			)
		)
	})


# ==================================================
# BUILDINGS
# ==================================================

func generate_neighbor_buildings() -> void:
	buildings.clear()

	if neighbor_parcels.size() < 4:
		return

	var northwest: Rect2 = neighbor_parcels[0]["rect"]
	var northeast: Rect2 = neighbor_parcels[1]["rect"]
	var west_farm: Rect2 = neighbor_parcels[2]["rect"]
	var southeast: Rect2 = neighbor_parcels[3]["rect"]

	add_building(
		"house",
		northwest.position + Vector2(
			northwest.size.x * 0.45,
			northwest.size.y * 0.47
		),
		Vector2(
			CELL_SIZE * 5.6,
			CELL_SIZE * 3.8
		),
		-0.06
	)

	add_building(
		"garage",
		northwest.position + Vector2(
			northwest.size.x * 0.72,
			northwest.size.y * 0.64
		),
		Vector2(
			CELL_SIZE * 3.4,
			CELL_SIZE * 2.8
		),
		0.03
	)

	add_building(
		"house",
		northeast.position + Vector2(
			northeast.size.x * 0.48,
			northeast.size.y * 0.50
		),
		Vector2(
			CELL_SIZE * 6.0,
			CELL_SIZE * 4.0
		),
		0.05
	)

	add_building(
		"shed",
		northeast.position + Vector2(
			northeast.size.x * 0.73,
			northeast.size.y * 0.72
		),
		Vector2(
			CELL_SIZE * 2.6,
			CELL_SIZE * 2.2
		),
		-0.04
	)

	add_building(
		"farmhouse",
		west_farm.position + Vector2(
			west_farm.size.x * 0.44,
			west_farm.size.y * 0.25
		),
		Vector2(
			CELL_SIZE * 6.2,
			CELL_SIZE * 4.1
		),
		0.03
	)

	add_building(
		"barn",
		west_farm.position + Vector2(
			west_farm.size.x * 0.67,
			west_farm.size.y * 0.43
		),
		Vector2(
			CELL_SIZE * 6.5,
			CELL_SIZE * 4.8
		),
		-0.08
	)

	add_building(
		"house",
		southeast.position + Vector2(
			southeast.size.x * 0.48,
			southeast.size.y * 0.48
		),
		Vector2(
			CELL_SIZE * 5.8,
			CELL_SIZE * 3.8
		),
		-0.04
	)

	add_building(
		"garage",
		southeast.position + Vector2(
			southeast.size.x * 0.72,
			southeast.size.y * 0.65
		),
		Vector2(
			CELL_SIZE * 3.4,
			CELL_SIZE * 2.7
		),
		0.05
	)


func add_building(
	building_type: String,
	center_position: Vector2,
	building_size: Vector2,
	building_rotation: float
) -> void:
	buildings.append({
		"type": building_type,
		"position": center_position,
		"size": building_size,
		"rotation": building_rotation
	})


# ==================================================
# DRIVEWAYS
# ==================================================

func generate_driveways() -> void:
	driveways.clear()

	if buildings.size() < 8:
		return

	var road_y: float = (
		get_road_reference_y()
	)

	var property_rect: Rect2 = (
		get_property_world_rect()
	)

	add_driveway([
		Vector2(
			buildings[0]["position"].x,
			road_y
		),
		Vector2(
			buildings[0]["position"].x,
			road_y + CELL_SIZE * 2.5
		),
		buildings[0]["position"]
	])

	add_driveway([
		Vector2(
			buildings[2]["position"].x,
			road_y
		),
		Vector2(
			buildings[2]["position"].x - CELL_SIZE * 1.5,
			road_y + CELL_SIZE * 3.0
		),
		buildings[2]["position"]
	])

	add_driveway([
		Vector2(
			buildings[4]["position"].x,
			road_y
		),
		Vector2(
			buildings[4]["position"].x + CELL_SIZE * 2.0,
			road_y + CELL_SIZE * 5.0
		),
		buildings[4]["position"]
	])

	add_driveway([
		Vector2(
			property_rect.end.x + CELL_SIZE * 14.0,
			road_y
		),
		Vector2(
			property_rect.end.x + CELL_SIZE * 16.0,
			property_rect.position.y + CELL_SIZE * 22.0
		),
		Vector2(
			property_rect.end.x + CELL_SIZE * 13.0,
			property_rect.position.y + CELL_SIZE * 43.0
		),
		buildings[6]["position"]
	])


func add_driveway(points: Array) -> void:
	driveways.append(points)


# ==================================================
# PROPERTY ENTRANCE
# ==================================================

func generate_property_entrance() -> void:
	property_driveway_points.clear()

	var property_rect: Rect2 = (
		get_property_world_rect()
	)

	var entrance_x: float = (
		property_rect.position.x
		+ property_rect.size.x * 0.22
	)

	var road_y: float = (
		get_road_reference_y()
	)

	property_driveway_points.append(
		Vector2(
			entrance_x,
			road_y
		)
	)

	property_driveway_points.append(
		Vector2(
			entrance_x + CELL_SIZE * 0.5,
			property_rect.position.y - CELL_SIZE * 3.0
		)
	)

	property_driveway_points.append(
		Vector2(
			entrance_x + CELL_SIZE * 1.2,
			property_rect.position.y + CELL_SIZE * 3.0
		)
	)

	property_driveway_points.append(
		Vector2(
			entrance_x + CELL_SIZE * 2.0,
			property_rect.position.y + CELL_SIZE * 7.0
		)
	)


# ==================================================
# WALKING / BIKE TRAIL
# ==================================================

func generate_walking_trail() -> void:
	walking_trail_points.clear()

	var property_rect: Rect2 = (
		get_property_world_rect()
	)

	walking_trail_points.append(
		Vector2(
			-CELL_SIZE * 3.0,
			property_rect.position.y + property_rect.size.y * 0.34
		)
	)

	walking_trail_points.append(
		Vector2(
			property_rect.position.x - CELL_SIZE * 15.0,
			property_rect.position.y + property_rect.size.y * 0.37
		)
	)

	walking_trail_points.append(
		Vector2(
			property_rect.position.x - CELL_SIZE * 3.0,
			property_rect.position.y + property_rect.size.y * 0.42
		)
	)

	walking_trail_points.append(
		Vector2(
			property_rect.position.x + property_rect.size.x * 0.18,
			property_rect.position.y + property_rect.size.y * 0.46
		)
	)

	walking_trail_points.append(
		Vector2(
			property_rect.position.x + property_rect.size.x * 0.42,
			property_rect.position.y + property_rect.size.y * 0.51
		)
	)

	walking_trail_points.append(
		Vector2(
			property_rect.position.x + property_rect.size.x * 0.67,
			property_rect.position.y + property_rect.size.y * 0.48
		)
	)

	walking_trail_points.append(
		Vector2(
			property_rect.position.x + property_rect.size.x * 0.88,
			property_rect.position.y + property_rect.size.y * 0.56
		)
	)

	walking_trail_points.append(
		Vector2(
			property_rect.end.x + CELL_SIZE * 7.0,
			property_rect.position.y + property_rect.size.y * 0.61
		)
	)

	walking_trail_points.append(
		Vector2(
			get_world_size_pixels().x + CELL_SIZE * 3.0,
			property_rect.position.y + property_rect.size.y * 0.68
		)
	)


# ==================================================
# SURROUNDING WORLD TREES
# ==================================================

func generate_surrounding_world() -> void:
	world_trees.clear()
	world_tree_sizes.clear()

	var world_size: Vector2 = (
		get_world_size_pixels()
	)

	for i in range(720):
		var world_position := Vector2(
			rng.randf_range(
				0.0,
				world_size.x
			),
			rng.randf_range(
				0.0,
				world_size.y
			)
		)

		if not can_place_world_tree(
			world_position
		):
			continue

		add_world_tree(
			world_position
		)

	create_world_tree_cluster(
		Vector2(
			CELL_SIZE * 13.0,
			CELL_SIZE * 18.0
		),
		CELL_SIZE * 9.0,
		75
	)

	create_world_tree_cluster(
		Vector2(
			world_size.x - CELL_SIZE * 14.0,
			CELL_SIZE * 27.0
		),
		CELL_SIZE * 10.0,
		90
	)

	create_world_tree_cluster(
		Vector2(
			CELL_SIZE * 16.0,
			world_size.y - CELL_SIZE * 19.0
		),
		CELL_SIZE * 11.0,
		95
	)

	create_world_tree_cluster(
		Vector2(
			world_size.x - CELL_SIZE * 16.0,
			world_size.y - CELL_SIZE * 17.0
		),
		CELL_SIZE * 10.0,
		85
	)


func create_world_tree_cluster(
	center_position: Vector2,
	radius_pixels: float,
	tree_count: int
) -> void:
	for i in range(tree_count):
		var angle: float = rng.randf_range(
			0.0,
			TAU
		)

		var distance: float = (
			sqrt(rng.randf())
			* radius_pixels
		)

		var world_position: Vector2 = (
			center_position
			+
			Vector2(
				cos(angle),
				sin(angle)
			)
			* distance
		)

		if not can_place_world_tree(
			world_position
		):
			continue

		add_world_tree(
			world_position
		)


func add_world_tree(
	world_position: Vector2
) -> void:
	world_trees.append(
		world_position
	)

	world_tree_sizes.append(
		rng.randf_range(
			0.70,
			1.45
		)
	)


# ==================================================
# WORLD TREE PLACEMENT
# ==================================================

func can_place_world_tree(
	world_position: Vector2
) -> bool:
	if is_world_position_inside_property(
		world_position
	):
		return false

	if is_position_near_polyline(
		world_position,
		road_points,
		CELL_SIZE * 2.2
	):
		return false

	if is_position_near_polyline(
		world_position,
		walking_trail_points,
		CELL_SIZE * 0.9
	):
		return false

	if is_position_near_polyline(
		world_position,
		property_driveway_points,
		CELL_SIZE * 1.2
	):
		return false

	for driveway_value in driveways:
		var driveway: Array = driveway_value

		if is_position_near_polyline(
			world_position,
			driveway,
			CELL_SIZE * 1.1
		):
			return false

	for building_value in buildings:
		var building: Dictionary = building_value

		var building_position: Vector2 = (
			building["position"]
		)

		var building_size: Vector2 = (
			building["size"]
		)

		var clearance_radius: float = (
			max(
				building_size.x,
				building_size.y
			)
			* 0.75
		)

		if world_position.distance_to(
			building_position
		) < clearance_radius:
			return false

	return true


# ==================================================
# POLYLINE DISTANCE
# ==================================================

func is_position_near_polyline(
	world_position: Vector2,
	points: Array,
	clearance: float
) -> bool:
	if points.size() < 2:
		return false

	for i in range(points.size() - 1):
		var point_a: Vector2 = points[i]
		var point_b: Vector2 = points[i + 1]

		var closest: Vector2 = (
			Geometry2D.get_closest_point_to_segment(
				world_position,
				point_a,
				point_b
			)
		)

		if world_position.distance_to(
			closest
		) <= clearance:
			return true

	return false


# ==================================================
# ROAD REFERENCE
# ==================================================

func get_road_reference_y() -> float:
	return (
		get_property_world_rect().position.y
		- CELL_SIZE * 11.0
	)


# ==================================================
# PROPERTY CELLS
# ==================================================

func is_valid_cell(
	grid_x: int,
	grid_y: int
) -> bool:
	return (
		grid_x >= 0
		and grid_x < PROPERTY_GRID_WIDTH
		and grid_y >= 0
		and grid_y < PROPERTY_GRID_HEIGHT
	)


func world_to_cell(
	local_position: Vector2
) -> Vector2i:
	return Vector2i(
		int(
			floor(
				local_position.x / CELL_SIZE
			)
		),
		int(
			floor(
				local_position.y / CELL_SIZE
			)
		)
	)


func cell_to_world_center(
	cell: Vector2i
) -> Vector2:
	return Vector2(
		cell.x * CELL_SIZE + CELL_SIZE / 2.0,
		cell.y * CELL_SIZE + CELL_SIZE / 2.0
	)


# ==================================================
# WATER
# ==================================================

func is_water_cell(
	grid_x: int,
	grid_y: int
) -> bool:
	if not is_valid_cell(
		grid_x,
		grid_y
	):
		return false

	return terrain[grid_y][grid_x] == WATER


func is_water_at_world_position(
	local_position: Vector2
) -> bool:
	var cell: Vector2i = world_to_cell(
		local_position
	)

	if not is_valid_cell(
		cell.x,
		cell.y
	):
		return false

	return is_water_cell(
		cell.x,
		cell.y
	)


# ==================================================
# PROPERTY TREES
# ==================================================

func is_tree_too_close(
	local_position: Vector2,
	minimum_distance: float = CELL_SIZE * 0.75
) -> bool:
	for tree_position in trees:
		if local_position.distance_to(
			tree_position
		) < minimum_distance:
			return true

	return false


func find_property_tree_at_world_position(
	world_position: Vector2
) -> int:
	if not is_world_position_inside_property(
		world_position
	):
		return -1

	var local_position: Vector2 = (
		world_to_property_local(
			world_position
		)
	)

	var best_tree_index: int = -1
	var best_distance: float = INF

	for i in range(trees.size()):
		if i >= tree_sizes.size():
			continue

		var tree_scale: float = tree_sizes[i]

		var hit_radius: float = max(
			24.0,
			18.0 * tree_scale + 10.0
		)

		var distance: float = (
			local_position.distance_to(
				trees[i]
			)
		)

		if (
			distance <= hit_radius
			and distance < best_distance
		):
			best_distance = distance
			best_tree_index = i

	return best_tree_index


func get_property_tree_size(
	tree_index: int
) -> float:
	if (
		tree_index < 0
		or tree_index >= tree_sizes.size()
	):
		return -1.0

	return tree_sizes[tree_index]


func remove_property_tree(
	tree_index: int
) -> bool:
	if (
		tree_index < 0
		or tree_index >= trees.size()
		or tree_index >= tree_sizes.size()
	):
		return false

	trees.remove_at(
		tree_index
	)

	tree_sizes.remove_at(
		tree_index
	)

	return true


# ==================================================
# PROPERTY BOUNDS
# ==================================================

func is_world_position_inside_property(
	world_position: Vector2
) -> bool:
	return get_property_world_rect().has_point(
		world_position
	)


func is_local_position_inside_property(
	local_position: Vector2
) -> bool:
	return (
		local_position.x >= 0.0
		and local_position.x < PROPERTY_GRID_WIDTH * CELL_SIZE
		and local_position.y >= 0.0
		and local_position.y < PROPERTY_GRID_HEIGHT * CELL_SIZE
	)


# ==================================================
# PROPERTY DIMENSIONS
# ==================================================

func get_property_size_pixels() -> Vector2:
	return Vector2(
		PROPERTY_GRID_WIDTH * CELL_SIZE,
		PROPERTY_GRID_HEIGHT * CELL_SIZE
	)


func get_property_local_center() -> Vector2:
	return get_property_size_pixels() / 2.0


func get_property_center() -> Vector2:
	return get_property_local_center()


# ==================================================
# WORLD DIMENSIONS
# ==================================================

func get_world_size_pixels() -> Vector2:
	return Vector2(
		WORLD_GRID_WIDTH * CELL_SIZE,
		WORLD_GRID_HEIGHT * CELL_SIZE
	)


func get_world_rect() -> Rect2:
	return Rect2(
		Vector2.ZERO,
		get_world_size_pixels()
	)


# ==================================================
# PROPERTY WORLD RECT
# ==================================================

func get_property_world_rect() -> Rect2:
	return Rect2(
		property_world_origin,
		get_property_size_pixels()
	)


func get_property_world_center() -> Vector2:
	return (
		property_world_origin
		+
		get_property_size_pixels() / 2.0
	)


# ==================================================
# COORDINATE CONVERSION
# ==================================================

func property_local_to_world(
	local_position: Vector2
) -> Vector2:
	return (
		property_world_origin
		+
		local_position
	)


func world_to_property_local(
	world_position: Vector2
) -> Vector2:
	return (
		world_position
		-
		property_world_origin
	)


# ==================================================
# CAMERA VIEW AREA
# ==================================================

func get_camera_world_rect() -> Rect2:
	var margin_pixels: float = (
		CELL_SIZE * 22.0
	)

	var property_rect: Rect2 = (
		get_property_world_rect()
	)

	var camera_rect := Rect2(
		property_rect.position
		-
		Vector2(
			margin_pixels,
			margin_pixels
		),
		property_rect.size
		+
		Vector2(
			margin_pixels * 2.0,
			margin_pixels * 2.0
		)
	)

	return camera_rect.intersection(
		get_world_rect()
	)