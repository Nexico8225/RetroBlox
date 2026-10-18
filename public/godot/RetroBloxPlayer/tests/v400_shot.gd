extends SceneTree

## v4.0 shot — boot the real game as a guest and screenshot the SKID
## client: the People page (portrait MUST render fully dressed), the
## settings page, the HUD pill, and a chat bubble to eyeball the daylight
## look. Also boots the login screen for the daylight card shot.

func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var session: Node = root.get_node("/root/Session")
        session.call("set_guest")
        session.current_place = load("res://scripts/world/places.gd").by_id("baseplate")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        for i in range(30):
                await physics_frame
        var me: Node3D = game.get("player")
        if me == null:
                print("V400_SHOTS_FAIL no player")
                quit(1)
                return
        var fake_pos: Array = [me.global_position.x + 7.0, me.global_position.y, me.global_position.z - 3.0]
        game.call("_reconcile_players", [{
                "userId": "smokefriend", "username": "BubbleBob", "seqId": 7,
                "pos": fake_pos, "heading": 0.6,
        }])
        # the classic bubble — white plate, centered ink
        me.call("show_bubble", "hi")
        for i in range(10):
                await process_frame
        # open the menu on PEOPLE — the light skid window, blue accents
        game.call("_open_menu", "players")
        for i in range(12):
                await process_frame
        var cache: Dictionary = game.get("_portrait_cache")
        var mine = cache.get(session.user_id, null)
        if mine != null:
                print("PORTRAIT_RENDERED %dx%d" % [mine.get_width(), mine.get_height()])
        else:
                print("PORTRAIT_MISSING")
        var shot := root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v400_menu_people.png")
        # settings page too
        game.call("_open_menu", "settings")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v400_menu_settings.png")
        # close the menu, shoot the HUD pill + bubble
        game.call("_toggle_menu")
        for i in range(6):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v400_hud.png")
        print("V400_SHOTS_OK")
        quit(0)
