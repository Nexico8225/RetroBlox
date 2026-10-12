extends SceneTree

## v12.0 shot — boot the REAL game and screenshot the SITE GLOSS client:
## the centered glass ESC panel (People cards + REAL internet icons), the
## Settings page, the HUD (glass pills), the UI EDITOR, and the OLD login
## page on the real baseplate photo. Plus: the site-avatar PFP render, the
## bubble-fit check, and the stairs verdict.

const PLACES := preload("res://scripts/world/places.gd")

const MY_UID := "cmts80l0k0000mkujqa50flhz"   # Nexico8225's RetroBlox account


func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var api: Node = root.get_node("/root/Api")
        var session: Node = root.get_node("/root/Session")
        # sign in as the REAL account — the avatar payload comes from the
        # live site, so the PFP render + the in-world rig wear the real look
        var me_payload: Dictionary = await api.call("avatar_of", MY_UID)
        if bool(me_payload.get("ok", false)):
                session.call("sign_in", me_payload, MY_UID, "Nexico8225", "user")
                print("SITE_PAYLOAD_OK")
        else:
                session.call("set_guest")
                session.username = "Nexico8225"
                print("SITE_PAYLOAD_MISS (guest fallback)")
        session.current_place = PLACES.by_id("baseplate")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        for i in range(30):
                await physics_frame
        var me: Node3D = game.get("player")
        if me == null:
                print("V1200_SHOTS_FAIL no player")
                quit(1)
                return
        var fake_pos: Array = [me.global_position.x + 7.0, me.global_position.y, me.global_position.z - 3.0]
        game.call("_reconcile_players", [{
                "userId": "smokefriend", "username": "BubbleBob", "seqId": 7,
                "pos": fake_pos, "heading": 0.6,
        }])
        # the bubble-fit check: the exact overflow the screenshot showed
        me.call("show_bubble", "WWWWWWWW WWWWWWWW WWWWWWWW WWWWWWWW hello")
        for i in range(20):
                await process_frame
        var cache: Dictionary = game.get("_portrait_cache")
        var mine = cache.get(session.user_id, null)
        if mine != null:
                var t := mine as Texture2D
                print("PFP_READY %dx%d" % [t.get_width(), t.get_height()])
        else:
                print("PFP_MISSING")

        var shot: Image

        # ---- the centered ESC panel, People page ----
        game.call("_open_menu", "players")
        for i in range(14):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1200_menu_people.png")

        # settings page (MY PICTURE + EDIT THIS UI)
        game.call("_open_menu", "settings")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1200_menu_settings.png")

        # close menu — HUD with glass pills + health + the bubble fit
        game.call("_toggle_menu")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1200_hud.png")

        # ---- the UI EDITOR live ----
        var editor: Node = root.get_node_or_null("/root/UiEditor")
        if editor != null:
                editor.call("set_enabled", true)
                for i in range(8):
                        await process_frame
                shot = root.get_viewport().get_texture().get_image()
                shot.save_png("user://shots/v1200_editor.png")
                editor.call("set_enabled", false)

        # ---- THE STAIRS VERDICT: the real fort risers, straight up ----
        game.set("_menu_open", true)
        me.global_position = Vector3(-12.5, 0.05, 0.0)
        me.set("heading", PI / 2)
        var start_y: float = me.global_position.y
        var saw_climb := false
        for i in range(240):
                me.call("drive", 0.016, Vector2(0.0, -1.0), PI / 2, false, false)
                await physics_frame
                if bool(me.get("climbing")):
                        saw_climb = true
                var gy: float = (me.get("global_position") as Vector3).y
                if bool(me.get("grounded")) and gy > start_y + 1.5:
                        break
        var top_y: float = (me.get("global_position") as Vector3).y
        print("STAIRS_2STUD %s (y %.2f -> %.2f, climb_grip=%s)" % [
                "OK" if top_y > start_y + 1.5 else "FAIL", start_y, top_y, str(saw_climb)])

        # ---- world beauty shot ----
        game.set("_menu_open", false)
        var rig = game.get("camera_rig")
        if rig != null:
                me.global_position = Vector3(-14.0, 2.4, -6.0)
                me.set("heading", 0.0)
                for i in range(40):
                        me.call("drive", 0.016, Vector2(0.0, 0.0), 0.0, false, false)
                        await physics_frame
        for i in range(8):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1200_world.png")

        # ---- the login page ----
        var login: Node = load("res://scenes/login.tscn").instantiate()
        root.add_child(login)
        await process_frame
        await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1200_login.png")
        login.queue_free()
        print("V1200_SHOTS_OK")
        quit(0)
