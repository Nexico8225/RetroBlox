extends Control
## Hub — pick a place, see your avatar spin in live 3D, see who is online.
## Your look loads straight from your RetroBlox account: guests wear the
## classic noob colors until they sign up.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")
const PlacesScript := preload("res://scripts/world/places.gd")

var _user_chip: Label
var _avatar_view: SubViewportContainer
var _avatar_viewport: SubViewport
var _avatar_rig: Node3D
var _places_box: VBoxContainer
var _online_labels: Dictionary = {}
var _refresh_left := 0.0


func _ready() -> void:
        theme = RetroUI.shared
        RetroUI.apply_cursors()
        _build()
        _dress_preview()
        _refresh_online()


# the music box is gone (you asked!) — the hub is quiet now, just wind-free
# UI clicks (the Tix chime retired with the coins)


func _process(delta: float) -> void:
        if _avatar_rig != null and is_instance_valid(_avatar_rig):
                _avatar_rig.rotation.y += delta * 0.7
        _refresh_left -= delta
        if _refresh_left <= 0.0:
                _refresh_left = 10.0
                _refresh_online()


func _build() -> void:
        var bg := ColorRect.new()
        bg.color = RetroUI.BG
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bg)

        # the pixel-cloud backdrop — a real internet image, darkened to sit
        # under the steel UI like the old skybox menus used to
        if ResourceLoader.exists("res://assets/ui/clouds_bg.jpg"):
                var clouds := TextureRect.new()
                clouds.texture = load("res://assets/ui/clouds_bg.jpg")
                clouds.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                clouds.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
                clouds.set_anchors_preset(Control.PRESET_FULL_RECT)
                clouds.modulate = Color(0.7, 0.78, 0.9, 1.0)
                clouds.mouse_filter = Control.MOUSE_FILTER_IGNORE
                add_child(clouds)

        # the owner's uploaded ReTROBLOX wordmark, proud over the clouds
        if ResourceLoader.exists("res://assets/ui/wordmark.png"):
                var brand := TextureRect.new()
                brand.texture = load("res://assets/ui/wordmark.png")
                brand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                brand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
                brand.set_anchors_preset(Control.PRESET_CENTER_TOP)
                brand.custom_minimum_size = Vector2(320, 77)
                brand.size = Vector2(320, 77)
                brand.offset_left = -160.0
                brand.offset_right = 160.0
                brand.offset_top = 10.0
                brand.offset_bottom = 87.0
                brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
                add_child(brand)

        var root := VBoxContainer.new()
        root.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.offset_left = 16.0
        root.offset_right = -16.0
        root.offset_top = 12.0
        root.offset_bottom = -12.0
        root.add_theme_constant_override("separation", 12)
        add_child(root)

        # ---- steel header ----
        var header := PanelContainer.new()
        header.theme_type_variation = "SteelHeader"
        root.add_child(header)
        var head_box := HBoxContainer.new()
        head_box.add_theme_constant_override("separation", 12)
        header.add_child(head_box)
        var logo := Label.new()
        logo.text = "RETROBLOX"
        logo.theme_type_variation = "H1"
        logo.add_theme_color_override("font_color", RetroUI.TEXT_INV)
        head_box.add_child(logo)
        var tagline := Label.new()
        tagline.text = "places · avatar · chat"
        tagline.theme_type_variation = "InverseSmall"
        tagline.add_theme_color_override("font_color", Color(0.75, 0.86, 0.95, 0.9))
        tagline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        head_box.add_child(tagline)
        var spacer := Control.new()
        spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        head_box.add_child(spacer)
        _user_chip = Label.new()
        _user_chip.theme_type_variation = "Inverse"
        _user_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        head_box.add_child(_user_chip)
        var logout := Button.new()
        logout.text = "LOG OUT"
        logout.theme_type_variation = "BtnGhost"
        logout.pressed.connect(_on_logout)
        head_box.add_child(logout)

        # ---- main split ----
        var split := HBoxContainer.new()
        split.size_flags_vertical = Control.SIZE_EXPAND_FILL
        split.add_theme_constant_override("separation", 12)
        root.add_child(split)

        # left card: your avatar in 3D
        var avatar_card := PanelContainer.new()
        avatar_card.theme_type_variation = "Card"
        split.add_child(avatar_card)
        var avatar_box := VBoxContainer.new()
        avatar_box.add_theme_constant_override("separation", 8)
        avatar_card.add_child(avatar_box)
        var av_title := Label.new()
        av_title.text = "YOUR AVATAR"
        av_title.add_theme_color_override("font_color", RetroUI.HEADER_DARK)
        av_title.add_theme_font_size_override("font_size", 15)
        avatar_box.add_child(av_title)
        _avatar_view = SubViewportContainer.new()
        _avatar_view.stretch = true
        _avatar_view.custom_minimum_size = Vector2(270, 320)
        _avatar_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
        avatar_box.add_child(_avatar_view)
        _avatar_viewport = SubViewport.new()
        _avatar_viewport.own_world_3d = true
        _avatar_viewport.transparent_bg = false
        _avatar_viewport.msaa_3d = Viewport.MSAA_2X
        _avatar_view.add_child(_avatar_viewport)
        var sky_env := WorldEnvironment.new()
        var env := Environment.new()
        var sky := Sky.new()
        var sky_mat := ProceduralSkyMaterial.new()
        sky_mat.sky_top_color = Color("3d8fd1")
        sky_mat.sky_horizon_color = Color("bfe0f5")
        sky.sky_material = sky_mat
        env.background_mode = Environment.BG_SKY
        env.sky = sky
        sky_env.environment = env
        _avatar_viewport.add_child(sky_env)
        var sun := DirectionalLight3D.new()
        sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
        sun.light_energy = 0.85
        _avatar_viewport.add_child(sun)
        var cam := Camera3D.new()
        cam.position = Vector3(0.0, 3.6, 9.0)
        cam.fov = 55.0
        _avatar_viewport.add_child(cam)
        cam.look_at_from_position(cam.position, Vector3(0.0, 2.5, 0.0))
        _avatar_rig = AvatarRigScript.new()
        _avatar_viewport.add_child(_avatar_rig)

        var av_note := Label.new()
        av_note.text = "Guests wear noob colors — sign up on the website to dress up."
        av_note.theme_type_variation = "Muted"
        av_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        av_note.visible = Session.is_guest
        avatar_box.add_child(av_note)

        # right card: places
        var places_card := PanelContainer.new()
        places_card.theme_type_variation = "Card"
        places_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        split.add_child(places_card)
        var places_box := VBoxContainer.new()
        places_box.add_theme_constant_override("separation", 10)
        places_card.add_child(places_box)
        var pl_title := Label.new()
        pl_title.text = "PLACES"
        pl_title.add_theme_color_override("font_color", RetroUI.HEADER_DARK)
        pl_title.add_theme_font_size_override("font_size", 15)
        places_box.add_child(pl_title)
        _places_box = VBoxContainer.new()
        _places_box.add_theme_constant_override("separation", 8)
        places_box.add_child(_places_box)
        for def in PlacesScript.all():
                _places_box.add_child(_place_row(def))

        # ---- footer ----
        var footer := Label.new()
        footer.text = "WASD move · SPACE jump · SHIFT shift-lock · ENTER chat · P players · ESC menu — chat is live across the internet"
        footer.theme_type_variation = "Muted"
        footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        root.add_child(footer)


func _place_row(def: Dictionary) -> PanelContainer:
        var row := PanelContainer.new()
        var sb := StyleBoxFlat.new()
        sb.bg_color = RetroUI.PANEL
        sb.set_border_width_all(2)
        sb.border_color = RetroUI.EDGE_DARK
        sb.set_corner_radius_all(4)
        sb.content_margin_left = 12.0
        sb.content_margin_right = 12.0
        sb.content_margin_top = 10.0
        sb.content_margin_bottom = 10.0
        row.add_theme_stylebox_override("panel", sb)
        var box := HBoxContainer.new()
        box.add_theme_constant_override("separation", 12)
        row.add_child(box)

        # place tile
        var tile := ColorRect.new()
        tile.color = Color(def.get("tile", "888888"))
        tile.custom_minimum_size = Vector2(64, 64)
        box.add_child(tile)

        var text_box := VBoxContainer.new()
        text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        text_box.add_theme_constant_override("separation", 2)
        box.add_child(text_box)
        var name_label := Label.new()
        name_label.text = String(def.get("name", "Place"))
        name_label.add_theme_font_size_override("font_size", 17)
        text_box.add_child(name_label)
        var desc := Label.new()
        desc.text = String(def.get("desc", ""))
        desc.theme_type_variation = "Muted"
        desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        text_box.add_child(desc)
        var online := Label.new()
        online.theme_type_variation = "Muted"
        online.text = "checking who is in…"
        text_box.add_child(online)
        _online_labels[String(def["id"])] = online

        var play := Button.new()
        play.text = "PLAY"
        play.theme_type_variation = "BtnGreen"
        play.custom_minimum_size = Vector2(120, 56)
        play.pressed.connect(func() -> void: _on_play(def))
        box.add_child(play)
        return row


func _dress_preview() -> void:
        _user_chip.text = Session.display_tag()
        if Session.is_guest:
                return
        var payload := Session.my_avatar_data()
        if payload.is_empty():
                var me: Dictionary = await Api.get_me()
                if me.get("ok", false):
                        Session.avatar = me
                        payload = Session.my_avatar_data()
        await AvatarDresserScript.apply(Api, _avatar_rig, payload)


func _refresh_online() -> void:
        for def in PlacesScript.all():
                var place_id := String(def["id"])
                var label: Label = _online_labels.get(place_id)
                if label == null or not is_instance_valid(label):
                        continue
                var res: Dictionary = await Api.place_chat_get(place_id)
                if not is_instance_valid(label):
                        continue
                var count := (res.get("players", []) as Array).size()
                if res.get("ok", false):
                        if count == 0:
                                label.text = "nobody in yet — be the first"
                        else:
                                label.text = "%d online now" % count
                else:
                        label.text = ""


func _on_play(def: Dictionary) -> void:
        Session.current_place = def
        get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_logout() -> void:
        Api.clear_session()
        Session.reset()
        get_tree().change_scene_to_file("res://scenes/login.tscn")
