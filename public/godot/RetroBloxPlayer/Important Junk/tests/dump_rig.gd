extends SceneTree

## Dump the retroblox_anims.fbx rig: animation names + mesh names + facing.

func _initialize() -> void:
        await process_frame
        var packed: PackedScene = load("res://assets/models/retroblox_anims.fbx")
        if packed == null:
                printerr("RIG LOAD FAILED")
                quit(1)
                return
        var inst: Node = packed.instantiate()
        print("== ROOT: ", inst.name, " (", inst.get_class(), ")")
        for node in inst.find_children("*", "AnimationPlayer", true, false):
                var ap := node as AnimationPlayer
                print("== ANIMS: ", ap.get_animation_list())
        for node in inst.find_children("*", "MeshInstance3D", true, false):
                var mi := node as MeshInstance3D
                var parent_name: String = mi.get_parent().name if mi.get_parent() != null else "?"
                print("== MESH: node='", mi.name, "' parent='", parent_name, "' mesh='", mi.mesh.resource_name if mi.mesh != null else "null", "'")
        # facing: print the transform of the head part chain vs origin
        for node in inst.find_children("*", "Node3D", true, false):
                var n3 := node as Node3D
                print("== NODE: '", n3.name, "' pos=", n3.position, " rot_deg=", n3.rotation_degrees)
        quit(0)
