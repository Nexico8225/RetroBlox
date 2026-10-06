extends SceneTree

## Dev tool: dump the imported retroblox_anims.fbx scene structure so kit code can
## target the real bone / mesh names. Usage (after --import):
##   godot --headless --path . --script tests/dump_rig.gd

var _total := AABB()
var _has_any := false

func _init() -> void:
        var packed: PackedScene = load("res://assets/models/retroblox_anims.fbx")
        if packed == null:
                print("RIG_DUMP_FAILED: could not load FBX")
                quit(1)
                return
        var root: Node = packed.instantiate()
        print("=== RIG DUMP: ", root.name, " (", root.get_class(), ") ===")
        _dump(root, 0)
        # combined world-space AABB of every mesh (manual, no tree needed)
        _total = AABB()
        _has_any = false
        _accumulate(root, Transform3D.IDENTITY)
        print("COMBINED_AABB pos=", _total.position, " size=", _total.size)
        print("=== END RIG DUMP ===")
        root.free()
        quit(0)

func _accumulate(node: Node, parent_xform: Transform3D) -> void:
        var xform := parent_xform
        if node is Node3D:
                xform = parent_xform * (node as Node3D).transform
        if node is MeshInstance3D:
                var mi := node as MeshInstance3D
                if mi.mesh != null and mi.visible:
                        var box := xform * mi.mesh.get_aabb()
                        if _has_any:
                                _total = _total.merge(box)
                        else:
                                _total = box
                                _has_any = true
        for child in node.get_children():
                _accumulate(child, xform)

func _dump(node: Node, depth: int) -> void:
        var pad := "  ".repeat(depth)
        var info := "%s%s [%s]" % [pad, node.name, node.get_class()]
        if node is Node3D:
                var n3 := node as Node3D
                info += " pos=%s rot_deg=%s scale=%s" % [n3.position, n3.rotation_degrees, n3.scale]
        if node is MeshInstance3D:
                var mi := node as MeshInstance3D
                var mesh := mi.mesh
                if mesh != null:
                        var aabb := mesh.get_aabb()
                        info += " aabb=%s surfaces=%d skinned=%s" % [aabb, mesh.get_surface_count(), str(mi.skin != null)]
                        for s in range(mesh.get_surface_count()):
                                var mat := mi.get_active_material(s)
                                if mat != null:
                                        info += " mat%d=%s" % [s, mat.resource_name]
        if node is Skeleton3D:
                var sk := node as Skeleton3D
                info += " bones=%d" % sk.get_bone_count()
        if node is AnimationPlayer:
                var ap := node as AnimationPlayer
                info += " anims=%s" % str(ap.get_animation_list())
        print(info)
        if node is Skeleton3D:
                var skel := node as Skeleton3D
                for b in range(skel.get_bone_count()):
                        var rest := skel.get_bone_rest(b)
                        print("%s   bone %d: '%s' rest.origin=%s" % ["  ".repeat(depth + 1), b, skel.get_bone_name(b), rest.origin])
        for child in node.get_children():
                _dump(child, depth + 1)
