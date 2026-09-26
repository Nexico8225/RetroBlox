extends Node3D

## Procedural Blockyard arena.  The arena owns one collision body for all static
## geometry so the client has very little physics overhead.

const ARENA_SIZE: float = 80.0
const FLOOR_TOP: float = 0.0

var _world_body: StaticBody3D
var _built: bool = false

var _mint: StandardMaterial3D
var _cream: StandardMaterial3D
var _teal: StandardMaterial3D
var _blue: StandardMaterial3D
var _orange: StandardMaterial3D
var _yellow: StandardMaterial3D
var _leaf: StandardMaterial3D
var _dark: StandardMaterial3D

func _ready() -> void:
	_build_arena()

func spawn_point(index: int) -> Vector3:
	# All points are on the broad central lawn, away from the parkour pieces.
	var points: Array[Vector3] = [
		Vector3(0.0, 0.08, 7.0),
		Vector3(0.0, 0.08, -7.0),
		Vector3(7.0, 0.08, 0.0),
		Vector3(-7.0, 0.08, 0.0),
		Vector3(5.0, 0.08, 5.0),
		Vector3(-5.0, 0.08, -5.0),
		Vector3(5.0, 0.08, -5.0),
		Vector3(-5.0, 0.08, 5.0)
	]
	var safe_index: int = abs(index) % points.size()
	return points[safe_index]

func _build_arena() -> void:
	if _built:
		return
	_built = true
	_make_materials()
	_make_environment()
	_world_body = StaticBody3D.new()
	_world_body.name = "WorldCollision"
	_world_body.collision_layer = 1
	_world_body.collision_mask = 0
	add_child(_world_body)
	_make_baseplate()
	_make_perimeter()
	_make_parkour()
	_make_gardens()

func _make_materials() -> void:
	_mint = _material(Color("#8bd8c1"))
	_cream = _material(Color("#f5e8be"))
	_teal = _material(Color("#168e9b"))
	_blue = _material(Color("#3387c9"))
	_orange = _material(Color("#ed8a3d"))
	_yellow = _material(Color("#f5c95e"))
	_leaf = _material(Color("#4da56b"))
	_dark = _material(Color("#25556b"))

func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material

func _make_environment() -> void:
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "FriendlySky"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dce9f2")
	environment.ambient_light_energy = 0.48
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var sky: Sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#5da5e8")
	sky_material.sky_horizon_color = Color("#d8f3ef")
	sky_material.ground_bottom_color = Color("#72bba9")
	sky_material.ground_horizon_color = Color("#e7edcf")
	sky_material.sun_angle_max = 18.0
	sky.sky_material = sky_material
	environment.sky = sky
	world_environment.environment = environment
	add_child(world_environment)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "WarmSun"
	sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	sun.light_color = Color("#fff0c7")
	sun.light_energy = 0.80
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)

func _make_baseplate() -> void:
	var tile_size: float = 10.0
	for x in range(8):
		for z in range(8):
			var tile_position: Vector3 = Vector3((float(x) - 3.5) * tile_size, -0.20, (float(z) - 3.5) * tile_size)
			var tile_material: StandardMaterial3D = _mint if (x + z) % 2 == 0 else _cream
			_add_box("Tile_%d_%d" % [x, z], Vector3(9.94, 0.40, 9.94), tile_position, tile_material, false)
	_add_collision_box(Vector3(ARENA_SIZE, 0.40, ARENA_SIZE), Vector3(0.0, -0.20, 0.0))
	# A raised rim gives the play space a readable boundary without trapping players.
	_add_box("NorthRim", Vector3(80.0, 0.32, 0.55), Vector3(0.0, 0.06, -39.7), _teal, true)
	_add_box("SouthRim", Vector3(80.0, 0.32, 0.55), Vector3(0.0, 0.06, 39.7), _teal, true)
	_add_box("EastRim", Vector3(0.55, 0.32, 78.9), Vector3(39.7, 0.06, 0.0), _teal, true)
	_add_box("WestRim", Vector3(0.55, 0.32, 78.9), Vector3(-39.7, 0.06, 0.0), _teal, true)

func _make_perimeter() -> void:
	# Four open pavilions make the edges interesting while leaving broad sightlines.
	_make_pavilion(Vector3(-29.0, 0.0, -29.0), _blue, _orange)
	_make_pavilion(Vector3(29.0, 0.0, -29.0), _orange, _blue)
	_make_pavilion(Vector3(-29.0, 0.0, 29.0), _teal, _yellow)
	_make_pavilion(Vector3(29.0, 0.0, 29.0), _yellow, _teal)

	# Friendly low walls and benches along the east/west edges.
	for side: float in [-1.0, 1.0]:
		var x: float = side * 28.0
		for row in range(3):
			var z: float = -9.0 + float(row) * 9.0
			_add_box("BenchSeat", Vector3(5.0, 0.42, 0.9), Vector3(x, 1.15, z), _orange if row % 2 == 0 else _blue, true)
			_add_box("BenchLegA", Vector3(0.40, 1.15, 0.55), Vector3(x - 1.7 * side, 0.58, z), _dark, true)
			_add_box("BenchLegB", Vector3(0.40, 1.15, 0.55), Vector3(x + 1.7 * side, 0.58, z), _dark, true)

func _make_pavilion(center: Vector3, column_material: StandardMaterial3D, roof_material: StandardMaterial3D) -> void:
	var offsets: Array[Vector3] = [Vector3(-3.2, 1.7, -2.6), Vector3(3.2, 1.7, -2.6), Vector3(-3.2, 1.7, 2.6), Vector3(3.2, 1.7, 2.6)]
	for offset in offsets:
		_add_box("PavilionColumn", Vector3(0.72, 3.4, 0.72), center + offset, column_material, true)
	_add_box("PavilionRoof", Vector3(8.0, 0.55, 6.7), center + Vector3(0.0, 3.55, 0.0), roof_material, true)
	_add_box("PavilionTrim", Vector3(8.2, 0.22, 0.35), center + Vector3(0.0, 3.18, -3.2), _yellow, false)
	_add_box("PavilionTrim", Vector3(8.2, 0.22, 0.35), center + Vector3(0.0, 3.18, 3.2), _yellow, false)

func _make_parkour() -> void:
	# Stepped runs at the back and front. Their alternating colors read clearly from the camera.
	for direction: float in [-1.0, 1.0]:
		for step in range(6):
			var y: float = 0.22 + float(step) * 0.32
			var z: float = direction * (17.0 + float(step) * 1.35)
			_add_box("ParkourStep", Vector3(7.0, y + 0.16, 2.35), Vector3(0.0, (y + 0.16) * 0.5, z), _orange if step % 2 == 0 else _teal, true)
	# Two offset jump pads provide a small loop on either side of the lawn.
	for side: float in [-1.0, 1.0]:
		for pad in range(3):
			var p: Vector3 = Vector3(side * (13.0 + float(pad) * 4.0), 0.45 + float(pad) * 0.55, -3.5 + float(pad) * 3.0)
			_add_box("JumpPad", Vector3(3.2, 0.9 + float(pad) * 0.35, 3.2), p, _blue if pad % 2 == 0 else _yellow, true)
	# A small goal arch at the far end.
	_add_box("GoalPostL", Vector3(0.8, 5.0, 0.8), Vector3(-4.8, 2.5, -31.0), _orange, true)
	_add_box("GoalPostR", Vector3(0.8, 5.0, 0.8), Vector3(4.8, 2.5, -31.0), _orange, true)
	_add_box("GoalTop", Vector3(10.4, 0.8, 0.8), Vector3(0.0, 4.6, -31.0), _yellow, true)

func _make_gardens() -> void:
	# Low planters and stylized trees soften the hard-edged course.
	for side: float in [-1.0, 1.0]:
		for row in range(4):
			var x: float = side * (34.0 + float(row % 2) * 1.0)
			var z: float = -18.0 + float(row) * 12.0
			_add_box("Planter", Vector3(2.4, 0.45, 2.4), Vector3(x, 0.23, z), _cream, true)
			_add_box("TreeTrunk", Vector3(0.55, 2.2, 0.55), Vector3(x, 1.45, z), _orange, true)
			_add_box("TreeCrown", Vector3(2.25, 1.7, 2.25), Vector3(x, 3.3, z), _leaf, false)
	# A low, non-blocking central compass pattern.
	_add_box("CompassNorth", Vector3(1.3, 0.08, 7.0), Vector3(0.0, 0.06, -3.5), _yellow, false)
	_add_box("CompassSouth", Vector3(1.3, 0.08, 7.0), Vector3(0.0, 0.06, 3.5), _yellow, false)
	_add_box("CompassEast", Vector3(7.0, 0.08, 1.3), Vector3(3.5, 0.06, 0.0), _yellow, false)
	_add_box("CompassWest", Vector3(7.0, 0.08, 1.3), Vector3(-3.5, 0.06, 0.0), _yellow, false)

func _add_box(box_name: String, size: Vector3, position: Vector3, material: StandardMaterial3D, with_collision: bool) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = box_name
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = material
	mesh_instance.position = position
	add_child(mesh_instance)
	if with_collision:
		_add_collision_box(size, position)
	return mesh_instance

func _add_collision_box(size: Vector3, position: Vector3) -> void:
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	shape_node.position = position
	_world_body.add_child(shape_node)
