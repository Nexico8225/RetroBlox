class_name AvatarPortrait
extends RefCounted
## v3.9 CLASSIC CLIENT — the ESC menu player cards wear a REAL picture of
## each player's avatar, the way the People page always has. We build the
## player's actual rig inside a tiny offscreen SubViewport with its own
## camera + lights, render ONE frame at a deliberately LOW resolution, and
## hand the texture back. Drawn nearest-neighbor at 2x, the thumb reads as
## a chunky retro sprite — the avatar itself, not an icon of one.
##
## Everything is disposable: the viewport, rig, camera and lights are freed
## before return, and the host node is only used to park the viewport for
## the couple of frames a render needs. Headless (smoke tests, CI) returns
## null — callers fall back to the classic head icon.

const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")

const RENDER_SIZE := Vector2i(64, 84)   # texel density IS the retro look
const RIG_CENTER_Y := 2.5               # the rig is 5 studs tall, origin at the feet


## Render one avatar portrait. Awaitable (network dressing + a drawn frame).
## `payload` = the /api/users/{id}/avatar shape; {} paints classic noob.
## Returns null when rendering is impossible (headless) or the frame came
## back empty — never a broken texture.
static func render(host: Node, api, payload: Dictionary) -> Texture2D:
        if host == null or not is_instance_valid(host):
                return null
        if DisplayServer.get_name() == "headless":
                return null

        var vp := SubViewport.new()
        vp.name = "PortraitShot"
        vp.size = RENDER_SIZE
        vp.transparent_bg = true
        vp.own_world_3d = true
        # v3.11 FIX: the one-shot render used to be armed HERE — before the
        # rig, lights or camera existed. It captured one EMPTY frame and was
        # never re-armed, so the People cards went portrait-less (the empty
        # dark wells you saw). The shot is armed at the bottom, after the
        # whole stage is built.
        vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
        vp.disable_3d = false
        vp.mesh_lod_threshold = 0.0
        host.add_child(vp)

        # ---- the stage: rig + framing camera + two flat lights ----
        var rig: Node3D = AvatarRigScript.new()
        vp.add_child(rig)
        rig.call("setup", "")
        if not payload.is_empty():
                await AvatarDresserScript.apply(api, rig, payload)
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
        key.rotation_degrees = Vector3(-32, -28, 0)   # front-left-top key
        key.light_energy = 1.15
        vp.add_child(key)
        var fill := DirectionalLight3D.new()
        fill.rotation_degrees = Vector3(-12, 148, 0)  # soft back-right fill
        fill.light_energy = 0.4
        vp.add_child(fill)

        var cam := Camera3D.new()
        cam.fov = 34.0
        cam.position = Vector3(2.0, 3.3, 8.8)         # a hint of 3/4, full body in frame
        vp.add_child(cam)
        cam.look_at_from_position(cam.position, Vector3(0.0, RIG_CENTER_Y, 0.0), Vector3.UP)
        cam.current = true

        # ---- one drawn frame, then snatch the pixels ----
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
        return ImageTexture.create_from_image(img)
