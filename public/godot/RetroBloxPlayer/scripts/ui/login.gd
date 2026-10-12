extends Control
## Login — the front door of the new player. Log in or sign up; that's the
## only way in. The FIRST login saves a session token on disk, and from then
## on every boot auto-signs in with zero typing — you log in once, ever.
## The server is LOCKED to the official RetroBlox platform: it is a label,
## not a field, so it can never be pointed somewhere else.
## v7.0: the CLASSIC LOGIN — a deep backdrop with a faint stud grid, one
## GRAY BEVELED window (light top-left edge, dark bottom-right edge), the
## tilted red logo tile, Arial everywhere, sunken wells, and the classic
## GREEN action key. Zero glass, zero glow — the client you remember.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VERSION := "7.0"

var _mode := "login"   # login | signup
var _user: LineEdit
var _pass: LineEdit
var _status: Label
var _go: Button
var _offline: Button
var _tab_login: Button
var _tab_signup: Button
var _working := false


func _ready() -> void:
        theme = RetroUI.shared
        RetroUI.apply_cursors()
        _build()
        _try_auto_login()


func _build() -> void:
        var bg := ColorRect.new()
        bg.color = RetroUI.BG
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bg)
        _add_stud_bg(bg)

        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)

        # the CLASSIC WINDOW — gray face, bevel edges, hard dark drop shadow
        var card := PanelContainer.new()
        card.custom_minimum_size = Vector2(420, 0)
        var card_sb := RetroUI.raised(6, RetroUI.PANEL, 18, 0.6)
        card_sb.content_margin_left = 22.0
        card_sb.content_margin_right = 22.0
        card_sb.content_margin_top = 0.0
        card_sb.content_margin_bottom = 18.0
        card.add_theme_stylebox_override("panel", card_sb)
        center.add_child(card)

        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 10)
        box.custom_minimum_size = Vector2(350, 0)
        card.add_child(box)

        # ---- the TITLE STRIP — darker face, dark rule under it, the tilted
        # red logo tile + the wordmark in bold white Arial
        var strip := PanelContainer.new()
        var strip_sb := StyleBoxFlat.new()
        strip_sb.bg_color = Color("474747")
        strip_sb.border_width_bottom = 2
        strip_sb.border_color = RetroUI.MENU_EDGE
        strip_sb.content_margin_left = 0.0
        strip_sb.content_margin_right = 0.0
        strip_sb.content_margin_top = 14.0
        strip_sb.content_margin_bottom = 14.0
        strip.add_theme_stylebox_override("panel", strip_sb)
        box.add_child(strip)
        var strip_row := HBoxContainer.new()
        strip_row.alignment = BoxContainer.ALIGNMENT_CENTER
        strip_row.add_theme_constant_override("separation", 10)
        strip.add_child(strip_row)
        var tile := TextureRect.new()
        tile.texture = _logo_tile_texture()
        tile.custom_minimum_size = Vector2(44, 44)
        tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
        strip_row.add_child(tile)
        var word := Label.new()
        word.text = "RETROBLOX"
        word.add_theme_font_override("font", RetroUI.arial(700))
        word.add_theme_font_size_override("font_size", 27)
        word.add_theme_color_override("font_color", Color.WHITE)
        # the classic drop shadow on the wordmark
        word.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
        word.add_theme_constant_override("shadow_offset_x", 0)
        word.add_theme_constant_override("shadow_offset_y", 2)
        strip_row.add_child(word)

        var sub := Label.new()
        sub.text = "the classic roblox-style client — v%s" % VERSION
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.add_theme_font_override("font", RetroUI.arial(400))
        sub.add_theme_font_size_override("font_size", 12)
        sub.add_theme_color_override("font_color", Color("9c9c9c"))
        box.add_child(sub)

        # mode switch — the CHUNKY beveled tabs: active = raised light face,
        # quiet = sunken dark face. Exactly the old client's tab row.
        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 6)
        tabs.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_child(tabs)
        _tab_login = Button.new()
        _tab_login.text = "LOG IN"
        _tab_login.toggle_mode = true
        _tab_login.custom_minimum_size = Vector2(165, 38)
        _tab_login.focus_mode = Control.FOCUS_NONE
        _tab_login.pressed.connect(func() -> void: _set_mode("login"))
        tabs.add_child(_tab_login)
        _tab_signup = Button.new()
        _tab_signup.text = "SIGN UP"
        _tab_signup.toggle_mode = true
        _tab_signup.custom_minimum_size = Vector2(165, 38)
        _tab_signup.focus_mode = Control.FOCUS_NONE
        _tab_signup.pressed.connect(func() -> void: _set_mode("signup"))
        tabs.add_child(_tab_signup)

        _user = LineEdit.new()
        _user.placeholder_text = "Username"
        _user.text = Api.saved_username   # remembered from last time
        _user.custom_minimum_size = Vector2(0, 44)
        _style_well_input(_user)
        box.add_child(_user)

        _pass = LineEdit.new()
        _pass.placeholder_text = "Password"
        _pass.secret = true
        _pass.custom_minimum_size = Vector2(0, 44)
        _style_well_input(_pass)
        box.add_child(_pass)

        _go = Button.new()
        _go.text = "LOG IN"
        _go.theme_type_variation = "BtnPrimary"
        _go.custom_minimum_size = Vector2(0, 48)
        _go.pressed.connect(_on_action)
        box.add_child(_go)

        var note := Label.new()
        note.text = "You only log in ONCE — after that you are signed in\nevery time you open RetroBlox, automatically."
        note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        note.add_theme_font_override("font", RetroUI.arial(400))
        note.add_theme_font_size_override("font_size", 12)
        note.add_theme_color_override("font_color", Color("b0b0b0"))
        box.add_child(note)
        _status = Label.new()
        _status.text = ""
        _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _status.custom_minimum_size = Vector2(0, 44)
        _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        box.add_child(_status)

        # offline escape hatch — appears ONLY when the server cannot be
        # reached, so a dead Wi-Fi day never bricks the player
        _offline = Button.new()
        _offline.text = "Can't connect — play offline instead"
        _offline.flat = true
        _offline.custom_minimum_size = Vector2(0, 30)
        _offline.visible = false
        _offline.pressed.connect(_on_offline)
        box.add_child(_offline)

        var footer := Label.new()
        footer.text = "Server: retro-blox.vercel.app  ·  locked  ·  your avatar loads from your account"
        footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        footer.add_theme_font_override("font", RetroUI.arial(400))
        footer.add_theme_font_size_override("font_size", 11)
        footer.add_theme_color_override("font_color", Color("8f8f8f"))
        box.add_child(footer)

        _user.text_submitted.connect(func(_t: String) -> void: _pass.grab_focus())
        _pass.text_submitted.connect(func(_t: String) -> void: _on_action())
        _set_mode("login")


## The sunken input wells — the classic inset read: dark face, dark top-left
## edge, light bottom-right edge, blue caret + focus ring.
func _style_well_input(field: LineEdit) -> void:
        var normal := RetroUI.sunken(3, RetroUI.WELL)
        normal.content_margin_left = 12.0
        normal.content_margin_right = 12.0
        normal.content_margin_top = 10.0
        normal.content_margin_bottom = 10.0
        var focus := RetroUI.flat(3, RetroUI.WELL)
        focus.set_border_width_all(2)
        focus.border_color = RetroUI.BLUE
        focus.content_margin_left = 12.0
        focus.content_margin_right = 12.0
        focus.content_margin_top = 10.0
        focus.content_margin_bottom = 10.0
        field.add_theme_stylebox_override("normal", normal)
        field.add_theme_stylebox_override("focus", focus)
        field.add_theme_stylebox_override("read_only", normal)
        field.add_theme_color_override("font_color", Color.WHITE)
        field.add_theme_color_override("font_placeholder_color", Color("8a8a8a"))
        field.add_theme_color_override("caret_color", RetroUI.BLUE)
        field.add_theme_color_override("selection_color", Color(0.0, 0.635, 1.0, 0.25))
        var book: Font = RetroUI.arial(400)
        if book != null:
                field.add_theme_font_override("font", book)
                field.add_theme_font_size_override("font_size", 15)


func _set_mode(mode: String) -> void:
        _mode = mode
        _tab_login.button_pressed = mode == "login"
        _tab_signup.button_pressed = mode == "signup"
        _go.text = "LOG IN" if mode == "login" else "CREATE ACCOUNT"
        _status.text = ""
        # the chunky tab read: active = RAISED light face with white ink,
        # quiet = SUNKEN dark face with gray ink
        for pair in [[_tab_login, "login"], [_tab_signup, "signup"]]:
                var b: Button = pair[0]
                var on: bool = pair[1] == mode
                var sb: StyleBox
                if on:
                        sb = RetroUI.raised(3, Color("565656"))
                else:
                        sb = RetroUI.sunken(3, Color("2e2e2e"))
                sb.content_margin_top = 7.0
                sb.content_margin_bottom = 7.0
                for st in ["normal", "hover", "pressed", "hover_pressed"]:
                        b.add_theme_stylebox_override(st, sb)
                for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                        b.add_theme_color_override(st,
                                Color.WHITE if on else Color("a0a0a0"))
                b.add_theme_font_override("font", RetroUI.arial(700))
                b.add_theme_font_size_override("font_size", 13)


## The tilted red logo tile — a rounded square rotated 13 degrees with the
## classic white R knocked out, drawn once in code (no image needed).
func _logo_tile_texture() -> ImageTexture:
        var s := 44
        var big := 4          # supersample for smooth edges
        var w := s * big
        var img := Image.create_empty(w, w, false, Image.FORMAT_RGBA8)
        var red := Color("e2231a")
        var ink := Color("ffffff")
        var half := float(w) / 2.0
        var rad := deg_to_rad(13.0)
        var cs := cos(rad)
        var sn := sin(rad)
        for y in range(w):
                for x in range(w):
                        # rotate the sample point around the center
                        var dx := (float(x) + 0.5) - half
                        var dy := (float(y) + 0.5) - half
                        var rx := dx * cs - dy * sn
                        var ry := dx * sn + dy * cs
                        var bx := half + rx
                        var by := half + ry
                        var inset := w * 0.10
                        var p := Vector2(bx, by)
                        if not RetroUI._in_rounded_px(p,
                                        Rect2(inset, inset, w - inset * 2.0, w - inset * 2.0),
                                        w * 0.16):
                                continue
                        var col := red
                        # the white R: two verticals + two diagonals, knocked
                        # out of the tile — reads instantly at 44px
                        var u := (bx - inset) / (w - inset * 2.0)   # 0..1 across the tile
                        var v := (by - inset) / (w - inset * 2.0)
                        var stroke := 0.11
                        var in_r := false
                        if v > 0.18 and v < 0.82:
                                if u > 0.26 and u < 0.26 + stroke:
                                        in_r = true          # the stem
                                if v < 0.48 and u > 0.26 and u < 0.74:
                                        var bowl := absf(v - 0.33) < stroke * 0.5
                                        var wall := u > 0.74 - stroke
                                        if bowl or wall:
                                                in_r = true  # the bowl
                                if v >= 0.48 and v < 0.82:
                                        var leg := u - 0.26
                                        var slope := (v - 0.48) * 1.25
                                        if absf(leg - slope) < stroke * 0.9 and leg < 0.5:
                                                in_r = true  # the leg
                        if in_r:
                                col = ink
                        img.set_pixel(x, y, col)
        img.resize(s, s, Image.INTERPOLATE_BILINEAR)
        return ImageTexture.create_from_image(img)


## The backdrop: a FAINT STUD GRID — the classic baseplate nod — tiled over
## the deep backdrop, plus soft dark corners (a quiet vignette).
func _add_stud_bg(bg: ColorRect) -> void:
        var tile := 72
        var img := Image.create_empty(tile, tile, false, Image.FORMAT_RGBA8)
        var stud_r := 11.0
        var c := Vector2(tile / 2.0, tile / 2.0)
        for y in range(tile):
                for x in range(tile):
                        var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c)
                        var a := 0.0
                        if d <= stud_r:
                                # the stud: a whisper of a raised circle
                                a = 0.05 if d < stud_r - 1.5 else 0.028
                        img.set_pixel(x, y, Color(1, 1, 1, a))
        var tex := ImageTexture.create_from_image(img)
        var grid := TextureRect.new()
        grid.texture = tex
        grid.stretch_mode = TextureRect.STRETCH_TILE
        grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
        grid.set_anchors_preset(Control.PRESET_FULL_RECT)
        bg.add_child(grid)
        # the vignette: four soft edge shadows — the old client's dark corners
        var vig := GradientTexture2D.new()
        vig.fill = GradientTexture2D.FILL_RADIAL
        vig.fill_from = Vector2(0.5, 0.5)
        vig.fill_to = Vector2(0.5, 0.0)
        vig.width = 64
        vig.height = 64
        var g := Gradient.new()
        g.set_color(0, Color(0, 0, 0, 0.0))
        g.set_color(1, Color(0, 0, 0, 0.5))
        vig.gradient = g
        var veil := TextureRect.new()
        veil.texture = vig
        veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        veil.stretch_mode = TextureRect.STRETCH_SCALE
        veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
        veil.set_anchors_preset(Control.PRESET_FULL_RECT)
        bg.add_child(veil)


func _set_status(text: String, is_error := true) -> void:
        _status.text = text
        _status.add_theme_color_override("font_color", RetroUI.RED if is_error else RetroUI.GREEN)

## Auto sign-in on boot: the saved token (180-day server-side TTL) brings
## the whole account back. The token is ONLY wiped when the server itself
## says it is invalid (401) — a Wi-Fi hiccup never logs you out.
func _try_auto_login() -> void:
        if Api.token == "":
                return
        _working = true
        _set_status("Signing you in…", false)
        var me: Dictionary = await Api.get_me()
        _working = false
        if me.get("ok", false):
                _finish_login(me)
                return
        if int(me.get("status", 0)) == 401:
                Api.clear_session()
                _set_status("Your session expired — log in one more time.")
        else:
                # offline: KEEP the token, offer offline play, retry works
                _offline.visible = true
                _set_status("Could not reach RetroBlox just now. Your saved session was kept — check your internet and press LOG IN to retry.")


func _on_action() -> void:
        if _working:
                return
        var uname := _user.text.strip_edges()
        var pwd := _pass.text
        if uname == "" or pwd == "":
                _set_status("Type your username and password first.")
                return
        _working = true
        _go.disabled = true
        _offline.visible = false
        _set_status("Talking to RetroBlox…", false)
        var res: Dictionary
        if _mode == "login":
                res = await Api.login(uname, pwd)
        else:
                res = await Api.signup(uname, pwd)
        _working = false
        _go.disabled = false
        if not res.get("ok", false):
                _set_status(String(res.get("error", "Could not reach RetroBlox.")))
                # network dead? show the offline hatch (401-style answers keep it hidden)
                if not res.has("status"):
                        _offline.visible = true
                return
        Api.token = String(res.get("token", ""))
        Api.save_session(uname)   # log in once — remembered from now on
        var me: Dictionary = await Api.get_me()
        if me.get("ok", false):
                _finish_login(me)
        else:
                _set_status("Signed in, but the avatar fetch failed — try again.")


func _finish_login(me: Dictionary) -> void:
        Session.sign_in(me, String(me["userId"]), String(me["username"]), String(me.get("role", "user")))
        # v3.6: the game-select hub is retired — sign in and you are instantly
        # playing the classic baseplate
        get_tree().change_scene_to_file("res://scenes/game.tscn")


## Last resort when the platform is unreachable: classic noob, offline chat.
func _on_offline() -> void:
        if _working:
                return
        Session.set_guest()
        get_tree().change_scene_to_file("res://scenes/game.tscn")
