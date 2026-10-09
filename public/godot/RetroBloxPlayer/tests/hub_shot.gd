extends SceneTree

## Screenshot the HUB as a guest — steel header in the pixel voice, the
## pixel-cloud backdrop, retro buttons. Network calls fail gracefully.

func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var session: Node = root.get_node("/root/Session")
        session.call("set_guest")
        var hub: Node = load("res://scenes/hub.tscn").instantiate()
        root.add_child(hub)
        for i in range(20):
                await process_frame
        var shot := root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/hub_retro.png")
        print("HUB_SHOT_OK")
        quit(0)
