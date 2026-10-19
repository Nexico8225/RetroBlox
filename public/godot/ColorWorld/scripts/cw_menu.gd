extends CanvasLayer
## ==================================================================
##  CW MENU — the ColorWorld front door.
## ==================================================================
##
##  Shows:
##    * the title + the "made with the RetroBlox SDK" line
##    * BUILT-IN MAPS  (scripts/cw_maps.gd — go add yours there!)
##    * COMMUNITY MAPS (downloaded from /api/colormaps — real GLB maps
##      players uploaded on the website, with their placeholder images)
##    * a small sign-in card so the PLAYER ID (#1, #2 ...) shows up
##
##  signal map_chosen(map_def: Dictionary)  -> colorworld.gd starts the world
## ==================================================================

signal map_chosen(map_def: Dictionary)

# ---------------------------------------------------------------- UI refs
var _status: Label
var _community_box: VBoxContainer
var _login_row: HBoxContainer
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _login_btn: Button
var _who: Label

func _ready() -> void:
        layer = 10
        _build()

# ==================================================================
# UI CONSTRUCTION (all in code — no scene files to break)
# ==================================================================

func _build() -> void:
        # dim backdrop so the menu reads over the last world
        var bg := ColorRect.new()
        bg.color = Color(0.04, 0.09, 0.15, 0.88)
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bg)

        var scroll := ScrollContainer.new()
        scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(scroll)

        var center := CenterContainer.new()
        center.custom_minimum_size = Vector2(0, 600)
        scroll.add_child(center)

        var panel := PanelContainer.new()
        center.add_child(panel)

        var vb := VBoxContainer.new()
        vb.custom_minimum_size = Vector2(520, 0)
        vb.add_theme_constant_override("separation", 10)
        panel.add_child(vb)

        # ---- title ----
        var title := Label.new()
        title.text = "ColorWorld"
        title.add_theme_font_size_override("font_size", 44)
        title.add_theme_color_override("font_color", Color.WHITE)
        title.add_theme_color_override("font_outline_color", Color.BLACK)
        title.add_theme_constant_override("outline_size", 10)
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        vb.add_child(title)

        var sub := Label.new()
        sub.text = "Everything is white — YOU bring the color.\nMade with the RetroBlox SDK (retro-blox.vercel.app)"
        sub.add_theme_font_size_override("font_size", 13)
        sub.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        vb.add_child(sub)

        # ---- built-in maps ----
        vb.add_child(_section_label("BUILT-IN MAPS"))
        for def in CwMaps.all():
                vb.add_child(_map_button(String(def["name"]), String(def["desc"]),
                        func() -> void: map_chosen.emit(def)))

        # ---- community maps ----
        vb.add_child(_section_label("COMMUNITY MAP PLAY"))
        var hint := Label.new()
        hint.text = "Maps players uploaded on the website. Upload yours there too:\nretro-blox.vercel.app/colorworld -> Upload a map (.glb)"
        hint.add_theme_font_size_override("font_size", 11)
        hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
        vb.add_child(hint)
        _status = _small_label("Loading community maps…")
        vb.add_child(_status)
        _community_box = VBoxContainer.new()
        _community_box.add_theme_constant_override("separation", 6)
        vb.add_child(_community_box)

        var refresh := Button.new()
        refresh.text = "Refresh community maps"
        refresh.pressed.connect(_load_community)
        vb.add_child(refresh)

        # ---- sign in (optional — gets you your PLAYER ID) ----
        vb.add_child(_section_label("ACCOUNT (optional)"))
        _who = _small_label("")
        vb.add_child(_who)
        _login_row = HBoxContainer.new()
        _login_row.add_theme_constant_override("separation", 6)
        vb.add_child(_login_row)
        _user_edit = LineEdit.new()
        _user_edit.placeholder_text = "username"
        _user_edit.custom_minimum_size = Vector2(150, 0)
        _login_row.add_child(_user_edit)
        _pass_edit = LineEdit.new()
        _pass_edit.placeholder_text = "password"
        _pass_edit.secret = true
        _pass_edit.custom_minimum_size = Vector2(150, 0)
        _pass_edit.text_submitted.connect(func(_t: String) -> void: _do_login())
        _login_row.add_child(_pass_edit)
        _login_btn = Button.new()
        _login_btn.text = "Sign in"
        _login_btn.pressed.connect(_do_login)
        _login_row.add_child(_login_btn)

        _refresh_account_row()
        _load_community()

# ---------------------------------------------------------------- helpers

func _section_label(t: String) -> Label:
        var l := Label.new()
        l.text = t
        l.add_theme_font_size_override("font_size", 16)
        l.add_theme_color_override("font_color", Color("7fd4ff"))
        return l

func _small_label(t: String) -> Label:
        var l := Label.new()
        l.text = t
        l.add_theme_font_size_override("font_size", 12)
        l.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
        l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        return l

## One map row: big play button + a one-line description.
func _map_button(name: String, desc: String, on_press: Callable) -> Button:
        var b := Button.new()
        b.text = "%s  —  %s" % [name, desc]
        b.add_theme_font_size_override("font_size", 14)
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.custom_minimum_size = Vector2(500, 34)
        b.pressed.connect(on_press)
        return b

# ==================================================================
# COMMUNITY MAPS — GET /api/colormaps, one row per uploaded map.
# Every map has an IMAGE PLACEHOLDER (imageUrl) — we show it when it
# loads, a "</>" glyph box when it doesn't.
# ==================================================================

func _load_community() -> void:
        _status.text = "Loading community maps…"
        for c in _community_box.get_children():
                c.queue_free()
        var res: Dictionary = await CwApi.get_json("/api/colormaps")
        if not res.get("ok", false):
                _status.text = "Could not load community maps: %s" % str(res.get("error", "?"))
                return
        var maps: Array = res.get("maps", [])
        if maps.is_empty():
                _status.text = "No community maps yet — be the first to upload one!"
                return
        _status.text = "%d community map(s)" % maps.size()
        for m in maps:
                _community_box.add_child(_community_row(m))

func _community_row(m: Dictionary) -> Control:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)

        # the image placeholder (custom image or a "</>" box)
        var img := TextureRect.new()
        img.custom_minimum_size = Vector2(64, 64)
        img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        img.stretch_mode = TextureRect.STRETCH_SCALE
        row.add_child(img)
        var img_url: String = CwApi.txt(m.get("imageUrl"), "")
        if img_url != "":
                _load_placeholder(img, img_url)

        var col := VBoxContainer.new()
        col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(col)
        var name_l := Label.new()
        name_l.text = "%s  by %s" % [CwApi.txt(m.get("name"), "?"), CwApi.txt(m.get("uploader", {}).get("username", "?"), "?")]
        name_l.add_theme_font_size_override("font_size", 13)
        col.add_child(name_l)
        var plays_l := Label.new()
        plays_l.text = "played %d time(s)" % int(m.get("plays", 0))
        plays_l.add_theme_font_size_override("font_size", 10)
        plays_l.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
        col.add_child(plays_l)

        var play := Button.new()
        play.text = "Play"
        play.custom_minimum_size = Vector2(80, 0)
        var map_id := CwApi.txt(m.get("id"), "")
        var map_name := CwApi.txt(m.get("name"), "Community map")
        play.pressed.connect(func() -> void: _play_community(map_id, map_name))
        row.add_child(play)
        return row

## Download the map's placeholder image async; leave the empty box on fail.
func _load_placeholder(img: TextureRect, url: String) -> void:
        var res: Dictionary = await CwApi.download_bytes(url)
        if res.get("ok", false) and is_instance_valid(img):
                var tex := CwApi.image_texture_from_bytes(res["bytes"])
                if tex != null:
                        img.texture = tex
                        img.color = Color.WHITE
                else:
                        img.texture = null
                        img.color = Color(0.1, 0.2, 0.3)
        elif is_instance_valid(img):
                img.color = Color(0.1, 0.2, 0.3)

## Download the community map's GLB -> parse it -> play it (see colorworld.gd
## for the glue that converts the parsed scene into paintable white meshes).
func _play_community(map_id: String, map_name: String) -> void:
        _status.text = "Downloading %s…" % map_name
        var res: Dictionary = await CwApi.download_bytes("/api/files/" + map_id)
        if not res.get("ok", false):
                _status.text = "Download failed: %s" % str(res.get("error", "?"))
                return
        _status.text = "Building %s…" % map_name
        var world_def := CwGlb.to_map_def(map_name, res["bytes"])
        if world_def.is_empty():
                _status.text = "That GLB could not be parsed — try re-exporting it as glTF Binary."
                return
        map_chosen.emit(world_def)

# ==================================================================
# ACCOUNT — optional sign-in. Signed-in players get their PLAYER ID
# (#1, #2 ...) next to their name, SDK style, and their plays count.
# ==================================================================

func _do_login() -> void:
        var uname := _user_edit.text.strip_edges()
        var pwd := _pass_edit.text
        if uname == "" or pwd == "":
                _who.text = "Write your username and password first!"
                return
        _login_btn.disabled = true
        _who.text = "Signing in…"
        var res: Dictionary = await CwApi.login(uname, pwd)
        _login_btn.disabled = false
        if not res.get("ok", false):
                _who.text = str(res.get("error", "Could not sign in."))
                return
        _pass_edit.text = ""
        _refresh_account_row()

func _refresh_account_row() -> void:
        if CwApi.signed_in():
                _who.text = "Signed in: %s   (Player ID: #%d)" % [CwApi.display_tag(), CwApi.seq_id]
                _login_row.visible = false
        else:
                _who.text = "Playing as a Guest — sign in to earn plays on your maps!"
                _login_row.visible = true
