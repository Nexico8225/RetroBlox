extends SceneTree

## v12.2 shot — THE OLD FRONT DOOR: boot the real game and screenshot
## the site's own login page (coaster art + sprite wordmark + blue-frame
## card + RED key), the BLUE GLOSS topbar (the old chat icon), and prove
## THE PROFILE IS SYNCED: the default PFP is the ACCOUNT AVATAR render
## (320x320 headshot), not the letter avatar (144x144).

const PLACES := preload("res://scripts/world/places.gd")

const MY_UID := "cmts80l0k0000mkujqa50flhz"   # Nexico8225's RetroBlox account


func _initialize() -> void:
        DirAccess.make_dir_recursive_absolute("user://shots")
        await process_frame
        var api: Node = root.get_node("/root/Api")
        var session: Node = root.get_node("/root/Session")
        var pfp: Node = root.get_node("/root/Pfp")

        # ---- THE SYNC PROOF: the default PFP for an account with NO
        # uploaded picture must be the AVATAR RENDER (320x320), not the
        # letter avatar (144x144). Sign IN with the REAL site payload
        # (guests wear the letter by design; /me carries the avatar blob). ----
        var me_first: Dictionary = await api.call("avatar_of", MY_UID)
        session.call("sign_in", me_first, MY_UID, "Nexico8225", "admin")
        var face: Texture2D = await pfp.call("fetch", MY_UID, "Nexico8225")
        if face != null:
                print("PFP_SYNC %dx%d %s" % [face.get_width(), face.get_height(),
                        "RENDER_OK" if face.get_width() >= 300 else "STILL_LETTER"])
        else:
                print("PFP_SYNC MISSING")

        # ---- the login page: the site's own front door ----
        var login: Node = load("res://scenes/login.tscn").instantiate()
        root.add_child(login)
        for i in range(6):
                await process_frame
        var shot: Image = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1220_login.png")
        login.queue_free()
        print("LOGIN_SHOT_OK")

        # ---- the game: blue gloss topbar + avatar chip + chat PFP lines ----
        session.current_place = PLACES.by_id("baseplate")
        var me_payload: Dictionary = await api.call("avatar_of", MY_UID)
        if bool(me_payload.get("ok", false)):
                session.call("sign_in", me_payload, MY_UID, "Nexico8225", "user")
                print("SITE_PAYLOAD_OK")
        var game: Node = load("res://scenes/game.tscn").instantiate()
        root.add_child(game)
        for i in range(30):
                await physics_frame
        for i in range(20):
                await process_frame

        var chat_ctl: Control = game.get("chat")
        if chat_ctl != null:
                chat_ctl.call("open")
                chat_ctl.call("add_chat", "Nexico8225", 8, "my face is MY AVATAR now", "", true, MY_UID)
                for i in range(8):
                        await process_frame
        shot = root.get_viewport().get_texture().get_image()
        shot.save_png("user://shots/v1220_hud_chat.png")
        if chat_ctl != null:
                chat_ctl.call("close")

        var hud: CanvasLayer = game.get("hud")
        if hud != null:
                var found := hud.find_child("UserPfp", true, false)
                if found != null and found is TextureRect:
                        var t: Texture2D = (found as TextureRect).texture
                        if t != null:
                                print("TOPBAR_PFP %dx%d %s" % [t.get_width(), t.get_height(),
                                        "RENDER_OK" if t.get_width() >= 300 else "LETTER_FALLBACK"])
        print("V1220_SHOTS_OK")
        quit(0)
