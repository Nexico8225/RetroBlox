# res://scripts/apple_worm/worm_start.gd
@tool
class_name WormStart
extends Node3D

enum Direction { RIGHT, LEFT, UP, DOWN }

@export var initial_length: int = 3
@export var initial_direction: Direction = Direction.RIGHT

var _preview_mesh: MeshInstance3D

func _ready() -> void:
	if not Engine.is_editor_hint():
		position.x = round(position.x)
		position.y = round(position.y)
		position.z = 0.0
	_build_preview()

func _build_preview() -> void:
	if not _preview_mesh:
		_preview_mesh = get_node_or_null("Preview") as MeshInstance3D
	if not _preview_mesh:
		_preview_mesh = MeshInstance3D.new()
		_preview_mesh.name = "Preview"
		add_child(_preview_mesh)
		var box = BoxMesh.new()
		box.size = Vector3(0.85, 0.85, 0.85)
		_preview_mesh.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.82, 0.38, 0.75)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_preview_mesh.material_override = mat

func get_direction_vector() -> Vector2i:
	match initial_direction:
		Direction.RIGHT: return Vector2i.RIGHT
		Direction.LEFT: return Vector2i.LEFT
		Direction.UP: return Vector2i.UP
		Direction.DOWN: return Vector2i.DOWN
	return Vector2i.RIGHT
