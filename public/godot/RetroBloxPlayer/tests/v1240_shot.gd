extends SceneTree

## v12.4 shot — NO PFP, JUST AVATARS: boot the real game, open the ESC menu,
## and prove every card hosts a LIVE 3D AvatarViewer stage; then DRAG one
## and prove the yaw actually rotated (the free-look you asked for).

const PLACES := preload("res://scripts/world/places.gd")

const MY_UID := "cmts80l0k0000mkujqa50flhz"   # Nexico8225's RetroBlox account


func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var api: Node = root.get_node("/root/Api")
        var session: Node = root.get_node("/root/Session")

        # ---- sign in with the REAL site payload ----
        var me_payload: Dictionary = await api.call("avatar_of", MY_UID)
        if bool(me_payload.get("ok", false)):
                session.call("sign_in", me_payload, MY_UID, "Nexico8225", "user")
                print("SITE_PAYLOAD_OK")
        else:
                print("SITE_PAYLOAD_MISS (offline — shots still run)")

        # ---- the game ----
        session.current_place = PLACES.by_id("baseplate")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        for i in range(30):
                await physics_frame
        for i in range(20):
                await process_frame

        # open the ESC menu on the People page and let the stages dress
        game.call("_toggle_menu")
        for i in range(120):
                await process_frame

        var viewers: Dictionary = game.get("_viewers")
        var live := 0
        for uid in viewers.keys():
                var v = viewers[uid]
                if v != null and is_instance_valid(v) and v.get("_vp") != null:
                        live += 1
        print("MENU_VIEWERS %d live stages" % live)

        # ---- DRAG-ROTATE: feed a real press + drag through the stage's own
        # input handler (synthetic events can't cross the window transform,
        # but the handler IS the thing under test) ----
        var rotated := false
        for uid in viewers.keys():
                var v = viewers[uid]
                if v == null or not is_instance_valid(v):
                        continue
                var yaw0: float = v.get("_yaw")
                var press := InputEventMouseButton.new()
                press.button_index = MOUSE_BUTTON_LEFT
                press.pressed = true
                press.position = Vector2(40.0, 40.0)
                v.call("_gui_input", press)
                for step in range(10):
                        var move := InputEventMouseMotion.new()
                        move.position = Vector2(40.0 + float(step + 1) * 14.0, 40.0)
                        move.relative = Vector2(14.0, 0.0)
                        v.call("_gui_input", move)
                        await process_frame
                var release := InputEventMouseButton.new()
                release.button_index = MOUSE_BUTTON_LEFT
                release.pressed = false
                release.position = Vector2(180.0, 40.0)
                v.call("_gui_input", release)
                await process_frame
                var yaw1: float = v.get("_yaw")
                var grabbed: bool = v.get("_grabbed")
                print("DRAG_YAW %.3f -> %.3f (delta %.3f, grabbed=%s)" % [yaw0, yaw1, yaw1 - yaw0, grabbed])
                rotated = absf(yaw1 - yaw0) > 0.05 and grabbed
                break

        shot_frame("v1240_menu.png")
        print("DRAG_ROTATE %s" % ("OK" if rotated else "DEAD"))
        print("V1240_SHOTS_OK")
        quit(0)


func shot_frame(name: String) -> void:
        var img: Image = root.get_viewport().get_texture().get_image()
        if img != null and not img.is_empty():
                img.save_png("user://shots/" + name)
                print("SHOT_SAVED " + name)
