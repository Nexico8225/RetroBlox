@tool
class_name RetroPart
extends StaticBody3D

## One classic studded part — THE building block for RetroBlox maps.
##
## Drop scenes/part.tscn into your map, then set size + color in the
## inspector. Everything is in STUDS (1 unit = 1 stud, a player is 5 studs
## tall). Players walk over any part up to 3 studs tall, so staircases just
## work: stack 1-stud steps and they climb them automatically.
##
## The mesh + collision are built by this script — the same code runs in
## the editor (it is a @tool) and in the running game.

@export var size := Vector3(4.0, 1.0, 2.0):
        set(value):
                size = Vector3(maxf(value.x, 0.05), maxf(value.y, 0.05), maxf(value.z, 0.05))
                _rebuild()
@export var color := Color("a3a2a5"):
        set(value):
                color = value
                _rebuild()
@export var can_collide := true:
        set(value):
                can_collide = value
                _rebuild()

var _mesh: MeshInstance3D
var _shape_node: CollisionShape3D
var _shape: BoxShape3D
var _box: BoxMesh
var _material: Material


func _ready() -> void:
        collision_layer = 1
        collision_mask = 0
        _rebuild()


## Studded plastic: a shader that multiplies the stud grid onto up-facing
## surfaces in world space. Falls back to plain plastic if the shader has
## not been imported yet (fresh project, first open).
func _make_material() -> Material:
        var shader: Shader = null
        if ResourceLoader.exists("res://assets/studs/part_studs.gdshader"):
                shader = load("res://assets/studs/part_studs.gdshader")
        if shader == null:
                var std := StandardMaterial3D.new()
                std.roughness = 0.82
                return std
        var mat := ShaderMaterial.new()
        mat.shader = shader
        mat.set_shader_parameter("albedo", color)
        if ResourceLoader.exists("res://assets/studs/stud_tile.png"):
                mat.set_shader_parameter("stud_tex", load("res://assets/studs/stud_tile.png"))
        return mat


func _set_material_color() -> void:
        if _material is ShaderMaterial:
                (_material as ShaderMaterial).set_shader_parameter("albedo", color)
        elif _material is StandardMaterial3D:
                (_material as StandardMaterial3D).albedo_color = color


func _rebuild() -> void:
        if not is_inside_tree():
                return
        if _mesh == null:
                _mesh = MeshInstance3D.new()
                _mesh.name = "Mesh"
                add_child(_mesh)
        if _shape_node == null:
                _shape_node = CollisionShape3D.new()
                _shape_node.name = "Collision"
                add_child(_shape_node)
                _shape = BoxShape3D.new()
                _shape_node.shape = _shape
        if _box == null:
                _box = BoxMesh.new()
                _mesh.mesh = _box
        if _material == null:
                _material = _make_material()
                _mesh.material_override = _material
        _box.size = size
        _shape.size = size
        _set_material_color()
        _shape_node.disabled = not can_collide
