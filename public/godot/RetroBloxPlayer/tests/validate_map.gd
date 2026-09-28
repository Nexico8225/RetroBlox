extends SceneTree

## Headless validation for the stud-accurate map + movement constants.
## Run: godot --headless --path . --script res://tests/validate_map.gd

var _failures: int = 0


func check(cond: bool, label: String) -> void:
        if cond:
                print("  ok    " + label)
        else:
                _failures += 1
                printerr("  FAIL  " + label)


func _initialize() -> void:
        # wait a frame so root is ready for children
        await process_frame
        print("== RetroBlox map + studs validation ==")
        var PlayerScript := load("res://scripts/player.gd")
        var packed: PackedScene = load("res://scenes/maps/classic_baseplate.tscn")
        check(packed != null, "classic_baseplate.tscn loads")
        if packed == null:
                quit(1)
                return
        var map: Node = packed.instantiate()
        check(map != null, "map instantiates")

        root.add_child(map)
        # one frame so @tool scripts finish building meshes
        await process_frame

        # counts — ints pass by value in GDScript, so collect through arrays
        var parts: Array = []
        var ladders: Array = []
        _walk(map, parts, ladders)
        var spawns := get_nodes_in_group("spawn")
        var climb_areas := get_nodes_in_group("ladder")
        check(parts.size() >= 20, "map has RetroParts (found %d)" % parts.size())
        check(spawns.size() == 4, "map has 4 SpawnLocation pads (found %d)" % spawns.size())
        check(ladders.size() >= 1, "map has a RetroLadder (found %d)" % ladders.size())
        check(climb_areas.size() >= 1, "ladder exposes a ClimbArea on layer 16")

        # spawn logic: pad top + 0.15 — pads are 1 stud thick at center y=0.5.
        # The arena loads its own copy of the map; give it a frame to finish.
        var arena := Node3D.new()
        arena.set_script(load("res://scripts/arena.gd"))
        root.add_child(arena)
        await process_frame
        await process_frame
        var spawn: Vector3 = arena.spawn_point(0)
        check(absf(spawn.y - 1.15) < 0.05, "spawn sits on a pad (y=%.2f, want 1.15)" % spawn.y)
        check(absf(spawn.x) <= 8.0 and absf(spawn.z) <= 8.0, "spawn is near the pads")

        # movement constants — @export tunables with classic-walk + floaty jump
        var probe: CharacterBody3D = PlayerScript.new()
        check(int(probe.walk_speed) == 16, "WalkSpeed 16 studs/s (classic)")
        check(int(probe.jump_speed) == 38, "JumpSpeed 38 studs/s (floaty default)")
        check(absf(probe.gravity - 110.0) < 0.01, "gravity 110 studs/s2 (floaty default)")
        check(absf(probe.max_step - 3.0) < 0.01, "step height 3 studs")
        var jump_apex: float = probe.jump_speed * probe.jump_speed / (2.0 * probe.gravity)
        check(jump_apex > 5.9 and jump_apex < 6.9, "jump apex ~6.4 studs (got %.2f)" % jump_apex)
        check(PlayerScript.STEP_REACH > 1.0, "step reach clears the capsule radius (no edge sticking)")
        check(probe.can_climb, "climbing is on by default")
        probe.free()

        # the avatar is 5 studs
        var avatar_script := load("res://scripts/avatar.gd")
        check(int(avatar_script.RIG_HEIGHT) == 5, "avatar height 5 studs")

        # animations exist on the rig
        var rig: PackedScene = load("res://assets/models/R6IK.fbx")
        var rig_inst: Node = rig.instantiate()
        var anims: PackedStringArray = []
        for node in rig_inst.find_children("*", "AnimationPlayer", true, false):
                anims = (node as AnimationPlayer).get_animation_list()
        check(anims.has("Old_Idle"), "rig has Old_Idle")
        check(anims.has("Old_Walk"), "rig has Old_Walk")
        check(anims.has("Old_Jump"), "rig has Old_Jump")
        check(anims.has("Climb"), "rig has Climb")

        if _failures == 0:
                print("== ALL MAP/STUDS VALIDATION PASSED ==")
        else:
                printerr("== %d FAILURES ==" % _failures)
        quit(1 if _failures > 0 else 0)


## Collect parts and ladders into arrays (references survive recursion).
func _walk(node: Node, parts: Array, ladders: Array) -> void:
        if node is StaticBody3D and node.has_method("_rebuild"):
                parts.append(node)
        if node is RetroLadder:
                ladders.append(node)
        for child in node.get_children():
                _walk(child, parts, ladders)
