extends SceneTree

## v4.0 avatar pipeline verification — dress a rig with Nexico8225's REAL
## account payload (classic face + RetroBlox Logo t-shirt + Golden Dominus
## GLB hat) and photograph BOTH the ESC-menu portrait and the in-game rig.
## The portrait must show the face, the torso decal AND the hat; the game
## rig must wear the t-shirt decal on its torso front.

const PORTRAIT := preload("res://scripts/ui/avatar_portrait.gd")
const DRESSER := preload("res://scripts/player/avatar_dresser.gd")
const RIG := preload("res://scripts/player/avatar_rig.gd")

const PAYLOAD := {
        "body": "body_01", "head": "head_01", "shirt": "shirt_01", "pants": "pants_01",
        "accessories": ["tshirt_1", "hat_1"],
        "colors": null, "faceScale": 1.0,
}

func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var host := Node3D.new()
        root.add_child(host)

        # ---- 1) the ESC-menu portrait (await_all path) ----
        var api: Node = root.get_node("/root/Api")
        var tex: Texture2D = await PORTRAIT.render(host, api, PAYLOAD)
        if tex == null:
                print("AVATAR_FAIL portrait null")
                quit(1)
                return
        tex.get_image().save_png("user://shots/v400_avatar_portrait.png")
        print("AVATAR_PORTRAIT_OK %dx%d" % [tex.get_width(), tex.get_height()])

        # ---- 2) the in-game rig (parallel path) + a light stage shot ----
        var rig: Node3D = RIG.new()
        host.add_child(rig)
        rig.call("setup", "Nexico8225")
        await DRESSER.apply(api, rig, PAYLOAD, true)
        # a floor + camera + light so the shot reads
        var floor_mesh := MeshInstance3D.new()
        var plane := PlaneMesh.new()
        plane.size = Vector2(40, 40)
        floor_mesh.mesh = plane
        host.add_child(floor_mesh)
        var sun := DirectionalLight3D.new()
        sun.rotation_degrees = Vector3(-45, -30, 0)
        host.add_child(sun)
        var world_env := WorldEnvironment.new()
        var env := Environment.new()
        env.background_mode = Environment.BG_COLOR
        env.background_color = Color("bfe0f5")
        env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        env.ambient_light_color = Color(0.9, 0.93, 1.0)
        env.ambient_light_energy = 0.7
        world_env.environment = env
        host.add_child(world_env)
        var cam := Camera3D.new()
        cam.fov = 40.0
        # the rig faces -Z — park the camera at the FRONT to see the face,
        # the t-shirt decal and the Dominus head-on
        cam.position = Vector3(0, 3.0, -9.5)
        host.add_child(cam)
        cam.look_at_from_position(cam.position, Vector3(0, 2.5, 0), Vector3.UP)
        cam.current = true
        # let the parallel decal/GLB streams finish, then shoot
        for i in range(40):
                await process_frame
        await RenderingServer.frame_post_draw
        var img := root.get_viewport().get_texture().get_image()
        img.save_png("user://shots/v400_avatar_ingame.png")
        print("AVATAR_INGAME_OK")
        quit(0)
