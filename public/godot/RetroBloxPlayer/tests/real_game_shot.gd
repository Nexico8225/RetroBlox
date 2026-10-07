extends SceneTree

## Boot the REAL game scene as a guest in Cloud Kingdom and screenshot the
## real HUD (game.gd's _build_hud, not a replica).

func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var session: Node = root.get_node("/root/Session")
        session.call("set_guest")
        session.current_place = load("res://scripts/world/places.gd").by_id("cloudkingdom")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        # let it build HUD + settle physics
        for i in range(30):
                await physics_frame
        var hud: CanvasLayer = game.get("hud")
        print("HUD: ", hud != null, " children=", hud.get_child_count() if hud != null else 0)
        var shot := root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/real_game_hud.png")
        # open the menu (settings tab) and shoot it too
        game.call("_open_menu", "settings")
        for i in range(5):
                await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/real_game_settings.png")
        print("REAL_GAME_SHOTS_OK")
        quit(0)
