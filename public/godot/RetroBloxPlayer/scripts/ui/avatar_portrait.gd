class_name AvatarPortrait
extends RefCounted
# Renders 2D headshot portraits for player cards.
const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")

const RENDER_SIZE := Vector2i(320, 448)   # 5x the old shot — crisp, never pixelated
const HEADSHOT_SIZE := Vector2i(320, 320) # v11.0: the square PFP framing (head + shoulders)
const RIG_CENTER_Y := 2.5               # the rig is 5 studs tall, origin at the feet


static func render(host: Node, api, payload: Dictionary, headshot := false) -> Texture2D:
        if host == null or not is_instance_valid(host):
                return null
        if DisplayServer.get_name() == "headless":
                return null

        var vp := SubViewport.new()
        vp.name = "PortraitShot"
        vp.size = HEADSHOT_SIZE if headshot else RENDER_SIZE
        vp.transparent_bg = true
        vp.own_world_3d = true
        # v5.0: 4x MSAA in the shot itself — edges land smooth even before
        # the card scales the texture down.
        vp.msaa_3d = Viewport.MSAA_4X
        # v3.11 FIX: the one-shot render used to be armed HERE — before the
        # rig, lights or camera existed. It captured one EMPTY frame and was
        # never re-armed, so the People cards went portrait-less (the empty
        # dark wells you saw). The shot is armed at the bottom, after the
        # whole stage is built.
        vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
        vp.disable_3d = false
        vp.mesh_lod_threshold = 0.0
        host.add_child(vp)

        var rig: Node3D = AvatarRigScript.new()
        vp.add_child(rig)
        rig.call("setup", "")
        if not payload.is_empty():
                # v4.0: await_all=TRUE — the dresser streams shirt/face/UGC in
                # parallel and used to return after the COLOR paint only, so
                # the one-shot snapshot raced the downloads and the cards
                # showed a plain noob (no face, no t-shirt, no hat). The shot
                # now waits for every stream to land before it photographs.
                await AvatarDresserScript.apply(api, rig, payload, true)
                if not is_instance_valid(vp):
                        return null
        # the nameplate would photobomb the shot — keep it off
        rig.call("set_display_name", "")

        var env := WorldEnvironment.new()
        var e := Environment.new()
        e.background_mode = Environment.BG_COLOR
        e.background_color = Color(0, 0, 0, 0)
        e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        e.ambient_light_color = Color(0.9, 0.93, 1.0)
        e.ambient_light_energy = 0.85
        env.environment = e
        vp.add_child(env)

        var key := DirectionalLight3D.new()
        key.rotation_degrees = Vector3(-32, 152, 0)   # front-left-top key (the rig faces -Z)
        key.light_energy = 1.2
        vp.add_child(key)
        var fill := DirectionalLight3D.new()
        fill.rotation_degrees = Vector3(-12, -28, 0)  # soft back-right rim fill
        fill.light_energy = 0.5
        vp.add_child(fill)

        var cam := Camera3D.new()
        cam.fov = 34.0
        # v4.0: the rig FACES -Z (its front wall — where the face decal and
        # the t-shirt hang) — the old camera sat at +Z and photographed
        # everyone's BACK. That's why the People cards never showed a face!
        # Park at front-left 3/4 so the face, torso decal and UGC all read.
        # v11.0 HEADSHOT: pull close and aim at the head + shoulders — the
        # square PFP framing the topbar pill and the People cards wear.
        if headshot:
                # v12.0 REFRAME: the old framing zoomed INTO the helmet — the
                # hat filled the square and the PFP read as "not my avatar".
                # Pull back so the HEAD + HAT + SHOULDERS fit with margins,
                # exactly the framing a profile picture needs.
                cam.position = Vector3(-1.2, 4.45, -4.55)
                vp.add_child(cam)
                cam.look_at_from_position(cam.position, Vector3(0.05, 4.22, 0.0), Vector3.UP)
        else:
                cam.position = Vector3(-2.0, 3.3, -8.8)
                vp.add_child(cam)
                cam.look_at_from_position(cam.position, Vector3(0.0, RIG_CENTER_Y, 0.0), Vector3.UP)
        cam.current = true

        # v3.11: let every child actually ENTER the tree first, THEN arm the
        # one-shot render and wait for a full drawn frame. A retry covers
        # drivers that need one extra beat — the card always ends up with a
        # real picture or keeps the head icon, never a blank.
        var img: Image = null
        for attempt in 2:
                await host.get_tree().process_frame
                if not is_instance_valid(vp):
                        return null
                vp.render_target_update_mode = SubViewport.UPDATE_ONCE
                await RenderingServer.frame_post_draw
                if not is_instance_valid(vp):
                        return null
                img = vp.get_texture().get_image()
                if img != null and not img.is_empty():
                        break
        vp.queue_free()
        if img == null or img.is_empty():
                return null
        img.convert(Image.FORMAT_RGBA8)
        # v12.0: the headshot lands on the SITE's light paper (the old shot
        # kept a transparent bg, so the chip + dark wells made it read as a
        # black square — the exact reason it looked like nothing loaded)
        if headshot:
                img = _paper_backdrop(img)
        return ImageTexture.create_from_image(img)


static func _paper_backdrop(shot: Image) -> Image:
        var w := shot.get_width()
        var h := shot.get_height()
        var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
        var top := Color("dce8f4")
        var bottom := Color("eef3f9")
        for y in range(h):
                var row := top.lerp(bottom, float(y) / float(maxi(h - 1, 1)))
                for x in range(w):
                        out.set_pixel(x, y, row)
        out.blend_rect(shot, Rect2i(0, 0, w, h), Vector2i(0, 0))
        return out
