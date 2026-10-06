extends SceneTree

## Quick rig check: does the avatar upgrade to the retroblox_anims.fbx rig?

func _initialize() -> void:
        await process_frame
        var failures := 0
        var RigScript := load("res://scripts/player/avatar_rig.gd")
        var rig: Node3D = RigScript.new()
        root.add_child(rig)
        rig.call("setup", "RigTester")
        await process_frame
        await process_frame
        if rig.is_r6ik():
                print("  ok    rig upgraded to retroblox_anims.fbx")
        else:
                printerr("  FAIL  rig stayed in box mode")
                failures += 1
        var parts: Array = rig.get("parts")
        if parts.size() == 6:
                print("  ok    6 body parts matched")
        else:
                printerr("  FAIL  parts found: %d" % parts.size())
                failures += 1
        # animation smoke: play each clip by name
        for clip in ["Idle", "Walk", "Jump", "Climb", "Sit"]:
                rig.call("play_emote", clip)
                await process_frame
        print("  ok    play_emote ran over all clips")
        # paint + face
        rig.call("set_part_color", 0, Color("f5cd30"))
        var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
        rig.call("set_face", tex, 1.0)
        rig.call("animate", 0.016, 6.0, true)
        print("  ok    paint/face/animate API ran")
        if failures == 0:
                print("== RIG_OK ==")
        else:
                printerr("== RIG_FAILED ==")
        quit(1 if failures > 0 else 0)
