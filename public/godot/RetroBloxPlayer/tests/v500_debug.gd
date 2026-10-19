extends SceneTree

## v5.0 stairs DEBUG — walk the real fort riser and print the player's
## physics state frame by frame to see exactly which probe bails.

const PLACES := preload("res://scripts/world/places.gd")

func _initialize() -> void:
        await process_frame
        var session: Node = root.get_node("/root/Session")
        session.call("set_guest")
        session.current_place = PLACES.by_id("baseplate")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        for i in range(30):
                await physics_frame
        var me: Node3D = game.get("player")
        game.set("_menu_open", true)
        me.global_position = Vector3(-12.5, 0.05, 0.0)
        me.set("heading", PI / 2)
        for i in range(150):
                me.call("drive", 0.016, Vector2(0.0, -1.0), PI / 2, false, false)
                await physics_frame
                if i % 10 == 0 or i > 60:
                        var gp: Vector3 = me.get("global_position")
                        print("f%03d pos(%.2f, %.2f, %.2f) wall=%s grounded=%s rise=%.2f vel(%.1f, %.1f)" % [
                                i, gp.x, gp.y, gp.z, str(me.call("is_on_wall")),
                                str(me.get("grounded")), me.get("_rise_left"),
                                (me.get("velocity") as Vector3).x, (me.get("velocity") as Vector3).y])
                var gy: float = (me.get("global_position") as Vector3).y
                if gy > 1.5:
                        print("CLIMBED y=%.2f at frame %d" % [gy, i])
                        break
        quit(0)
