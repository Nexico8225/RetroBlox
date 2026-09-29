extends SceneTree

## Guards the obby feel: auto-ladder detection (1-3 studs deep + ~1 stud
## gap = climbable, with no script or special node), animation loop modes
## (the "animation sometimes does not play" regression), and the ladder
## jump-off direction resolver. Run with:
##   godot --headless --path . --script res://tests/probe_obby.gd

const ArenaScript := preload("res://scripts/arena.gd")
const LadderScene := preload("res://scenes/ladder.tscn")
const AvatarScene := preload("res://scenes/avatar.tscn")
const PlayerScene := preload("res://scenes/player.tscn")


func _make_part(parent: Node, part_name: String, pos: Vector3, part_size: Vector3) -> RetroPart:
        var part := RetroPart.new()
        part.name = part_name
        part.size = part_size
        part.color = Color("a3a2a5")
        parent.add_child(part)
        part.global_position = pos
        return part


func _ladder_group_children(of: Node) -> Array:
        var found: Array = []
        for child in of.get_children():
                if child is Area3D and child.is_in_group("ladder"):
                        found.append(child)
        return found


func _initialize() -> void:
        await process_frame
        var failures: Array = []

        # ---- a real arena: environment + map + auto-ladder pass ----
        var world := Node3D.new()
        world.name = "ProbeArena"
        world.set_script(ArenaScript)
        root.add_child(world)
        await process_frame
        await process_frame

        var map_root: Node = world.get("_map_root")
        if map_root == null:
                print("FAIL: arena has no map root")
                quit(1)
                return

        # ---- the classic test rig: a wall, then rungs hanging off it ----
        # wall occupies z in [4.5, 5.5]; its open face points at -Z
        _make_part(map_root, "Wall", Vector3(0.0, 6.0, 5.0), Vector3(12.0, 12.0, 1.0))
        # GOOD rung: 2 studs deep, exactly 1 stud of air to the wall
        var good := _make_part(map_root, "GoodRung", Vector3(0.0, 4.0, 2.5), Vector3(4.0, 0.6, 2.0))
        # FLUSH rung: touches the wall (no gap) — must stay a plain part
        var flush := _make_part(map_root, "FlushRung", Vector3(6.0, 4.0, 3.5), Vector3(4.0, 0.6, 2.0))
        # TOO DEEP rung: 4 studs of part — past the 1-3 stud rule
        var deep := _make_part(map_root, "DeepRung", Vector3(-6.0, 4.0, 1.5), Vector3(4.0, 0.6, 4.0))
        # a REAL truss ladder — must keep exactly its own climb zone
        var truss := LadderScene.instantiate() as Node3D
        truss.name = "Truss"
        map_root.add_child(truss)
        truss.global_position = Vector3(12.0, 4.0, 0.0)

        await world._auto_ladder_pass()

        # 1. the good rung became climbable, pointing away from the wall
        var good_zone: Area3D = good.find_children("AutoClimbArea*", "Area3D", false, false).front() as Area3D
        if good_zone == null or not (good_zone as Area3D).is_in_group("ladder"):
                failures.append("good rung (1 stud gap, 2 studs deep) did not become climbable")
        elif (good_zone as Area3D).get_meta("outward", Vector3.ZERO) != Vector3.FORWARD:
                failures.append("good rung climb direction is not away from the wall")
        else:
                print("ok: good rung auto-climbable, outward ", (good_zone as Area3D).get_meta("outward"))

        # 2. the flush rung stays a normal part
        if not flush.find_children("AutoClimbArea*", "Area3D", false, false).is_empty():
                failures.append("flush rung (no gap) must NOT be climbable")
        else:
                print("ok: flush rung not climbable")

        # 3. the 4-stud-deep rung stays a normal part
        if not deep.find_children("AutoClimbArea*", "Area3D", false, false).is_empty():
                failures.append("4-stud-deep rung must NOT be climbable")
        else:
                print("ok: deep rung not climbable")

        # 4. the truss keeps its own zone and got no duplicate
        var truss_zones := _ladder_group_children(truss)
        if truss_zones.size() != 1:
                failures.append("truss should have exactly 1 climb zone, has %d" % truss_zones.size())
        elif truss.find_child("AutoClimbArea", false, false) != null:
                failures.append("truss must not receive an auto climb zone")
        else:
                print("ok: truss ladder keeps its own climb zone")

        # 5. the pass is idempotent — a second run grants nothing new
        await world._auto_ladder_pass()
        var good_zones := _ladder_group_children(good)
        if good_zones.size() != 1:
                failures.append("second auto-ladder pass duplicated the climb zone (%d)" % good_zones.size())
        else:
                print("ok: auto-ladder pass is idempotent")

        # ---- animation loop modes on the real rig ----
        var avatar := AvatarScene.instantiate()
        root.add_child(avatar)
        await process_frame
        var anim_player := avatar.get("_anim_player") as AnimationPlayer
        if anim_player == null:
                print("SKIP: R6IK rig not imported in this checkout — box fallback active")
        else:
                var climb := anim_player.get_animation(&"Climb")
                var walk := anim_player.get_animation(&"Old_Walk")
                var jump := anim_player.get_animation(&"Old_Jump")
                if climb == null or climb.loop_mode != Animation.LOOP_LINEAR:
                        failures.append("Climb clip does not loop (frozen-animation regression)")
                else:
                        print("ok: Climb clip loops")
                if walk == null or walk.loop_mode != Animation.LOOP_LINEAR:
                        failures.append("Old_Walk clip does not loop")
                else:
                        print("ok: Old_Walk clip loops")
                if jump == null or jump.loop_mode != Animation.LOOP_NONE:
                        failures.append("Old_Jump clip must hold its last frame, not loop")
                else:
                        print("ok: Old_Jump holds (no loop)")
        avatar.queue_free()

        # ---- the ladder jump-off resolver: rotated ladders resolve right ----
        var player := PlayerScene.instantiate()
        root.add_child(player)
        player.initialize(1, "Probe")
        var rotated_post := _make_part(root, "RotatedPost", Vector3(50.0, 2.0, 50.0), Vector3(2.0, 4.0, 2.0))
        rotated_post.rotation_degrees = Vector3(0.0, 90.0, 0.0)
        var fake_zone := Area3D.new()
        fake_zone.add_to_group("ladder")
        fake_zone.set_meta("outward", Vector3.BACK)  # local +Z = the climbable face
        rotated_post.add_child(fake_zone)
        var resolved: Vector3 = player._ladder_outward_of(fake_zone)
        # local +Z rotated 90° around Y points at +X in the world
        if resolved.distance_to(Vector3.RIGHT) > 0.01:
                failures.append("jump-off direction wrong for a rotated ladder: %s" % resolved)
        else:
                print("ok: jump-off direction resolves through rotations")
        player.queue_free()

        if failures.is_empty():
                print("OBBY PROBE OK")
                quit(0)
        else:
                for failure in failures:
                        print("FAIL: ", failure)
                quit(1)
