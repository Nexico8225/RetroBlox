@tool
class_name RetroLadder
extends RetroPart

## A classic TrussPart-style climbable ladder. Solid like a part, but while
## you touch it you can climb: push forward to go up, back to go down,
## SPACE to jump off. The rig's Climb animation plays while you climb.
##
## Default size is the classic truss 2 x 12 x 1. Make sure the top overlaps
## the platform edge so players can crest over onto it.

@export var rungs := true:
        set(value):
                rungs = value
                _rebuild_rungs()


var _rung_root: Node3D
var _climb_area: Area3D


func _ready() -> void:
        super()
        _make_climb_area()
        _rebuild_rungs()


## The climb zone — an Area3D a little larger than the part, on collision
## layer 16 (the "ladder" layer the player's sensor listens on).
func _make_climb_area() -> void:
        if _climb_area != null:
                _climb_area.queue_free()
        _climb_area = Area3D.new()
        _climb_area.name = "ClimbArea"
        _climb_area.collision_layer = 16
        _climb_area.collision_mask = 0
        _climb_area.monitoring = false
        _climb_area.add_to_group("ladder")
        # the rungs decorate the +Z face — publish that as the climbable
        # direction so the player can leap AWAY from the ladder on jump.
        # The zone is ±1 stud taller than the part: stacked rung zones must
        # OVERLAP vertically, or a climb hopping between two rungs flickers
        # off between them and the ride stutters instead of chaining.
        _climb_area.set_meta("outward", Vector3.BACK)
        var shape_node := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size + Vector3(1.2, 2.0, 1.6)
        shape_node.shape = shape
        _climb_area.add_child(shape_node)
        add_child(_climb_area)


func _rebuild_rungs() -> void:
        if not is_inside_tree():
                return
        if _rung_root != null:
                _rung_root.queue_free()
        if _climb_area != null:
                var shape_node := _climb_area.get_child(0) as CollisionShape3D
                if shape_node != null:
                        (shape_node.shape as BoxShape3D).size = size + Vector3(1.2, 2.0, 1.6)
        if not rungs:
                return
        # darker grey so trusses read as climbable at a glance
        color = Color("63666a")
        _rung_root = Node3D.new()
        _rung_root.name = "Rungs"
        add_child(_rung_root)
        # horizontal rungs every 1 stud on the front face (decorative only)
        var count := int(size.y / 1.0)
        for i in range(maxi(count, 1)):
                var rung := MeshInstance3D.new()
                var box := BoxMesh.new()
                box.size = Vector3(size.x * 0.92, 0.18, 0.18)
                rung.mesh = box
                var mat := StandardMaterial3D.new()
                mat.albedo_color = Color("4a4d52")
                mat.roughness = 0.85
                rung.material_override = mat
                rung.position = Vector3(0.0, -size.y * 0.5 + 0.5 + float(i) * 1.0, size.z * 0.5 + 0.02)
                _rung_root.add_child(rung)
