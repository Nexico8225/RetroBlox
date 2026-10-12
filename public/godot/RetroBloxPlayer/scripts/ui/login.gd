extends Control
## Login — the front door of the new player. Log in or sign up; that's the
## only way in. The FIRST login saves a session token on disk, and from then
## on every boot auto-signs in with zero typing — you log in once, ever.
## The server is LOCKED to the official RetroBlox platform: it is a label,
## not a field, so it can never be pointed somewhere else.
## v6.0: the ROBLOX LOGIN — a deep backdrop with two soft color glows and
## one WHITE card: the tilted red logo tile, Montserrat everywhere, quiet
## gray wells, and the blue action key. Zero pixel type, zero darkness traps.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VERSION := "6.0"

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
        _add_glow_bg(bg)

        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)

        var card := PanelContainer.new()
        card.custom_minimum_size = Vector2(420, 0)
        # the WHITE card — the Roblox login read: big radius, NO border,
        # one deep soft shadow doing all the separation
        var card_sb := RetroUI.surface(18, Color("ffffff"), 30, 0.5)
        card_sb.shadow_offset = Vector2(0, 10)
        card_sb.content_margin_left = 26.0
        card_sb.content_margin_right = 26.0
        card_sb.content_margin_top = 24.0
        card_sb.content_margin_bottom = 20.0
        card.add_theme_stylebox_override("panel", card_sb)
        center.add_child(card)

        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 10)
        box.custom_minimum_size = Vector2(350, 0)
        card.add_child(box)

        # ---- the logo row: tilted red tile with the white R + the wordmark
        var logo_row := HBoxContainer.new()
        logo_row.alignment = BoxContainer.ALIGNMENT_CENTER
        logo_row.add_theme_constant_override("separation", 10)
        box.add_child(logo_row)
        var tile := TextureRect.new()
        tile.texture = _logo_tile_texture()
        tile.custom_minimum_size = Vector2(44, 44)
        tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
        logo_row.add_child(tile)
        var word := Label.new()
        word.text = "RETROBLOX"
        word.add_theme_font_override("font", RetroUI.gotham(800))
        word.add_theme_font_size_override("font_size", 26)
        word.add_theme_color_override("font_color", Color("15171a"))
        logo_row.add_child(word)

        var sub := Label.new()
        sub.text = "the roblox-style client — v%s" % VERSION
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.add_theme_font_override("font", RetroUI.source(600))
        sub.add_theme_font_size_override("font_size", 12)
        sub.add_theme_color_override("font_color", Color("9aa0a6"))
        box.add_child(sub)

        # mode switch — the quiet segmented control: gray track, WHITE chip
        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 0)
        tabs.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_child(tabs)
        _tab_login = Button.new()
        _tab_login.text = "LOG IN"
        _tab_login.toggle_mode = true
        _tab_login.custom_minimum_size = Vector2(165, 36)
        _tab_login.focus_mode = Control.FOCUS_NONE
        _tab_login.pressed.connect(func() -> void: _set_mode("login"))
        tabs.add_child(_tab_login)
        _tab_signup = Button.new()
        _tab_signup.text = "SIGN UP"
        _tab_signup.toggle_mode = true
        _tab_signup.custom_minimum_size = Vector2(165, 36)
        _tab_signup.focus_mode = Control.FOCUS_NONE
        _tab_signup.pressed.connect(func() -> void: _set_mode("signup"))
        tabs.add_child(_tab_signup)

        _user = LineEdit.new()
        _user.placeholder_text = "Username"
        _user.text = Api.saved_username   # remembered from last time
        _user.custom_minimum_size = Vector2(0, 46)
        _style_light_input(_user)
        box.add_child(_user)

        _pass = LineEdit.new()
        _pass.placeholder_text = "Password"
        _pass.secret = true
        _pass.custom_minimum_size = Vector2(0, 46)
        _style_light_input(_pass)
        box.add_child(_pass)

        _go = Button.new()
        _go.text = "LOG IN"
        _go.theme_type_variation = "BtnBlue"
        _go.custom_minimum_size = Vector2(0, 48)
        _go.pressed.connect(_on_action)
        box.add_child(_go)

        var note := Label.new()
        note.text = "You only log in ONCE — after that you are signed in\nevery time you open RetroBlox, automatically."
        note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        note.add_theme_font_override("font", RetroUI.source(400))
        note.add_theme_font_size_override("font_size", 12)
        note.add_theme_color_override("font_color", Color("6b7076"))
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
        footer.add_theme_font_override("font", RetroUI.source(400))
        footer.add_theme_font_size_override("font_size", 11)
        footer.add_theme_color_override("font_color", Color("b3b8be"))
        box.add_child(footer)

        _user.text_submitted.connect(func(_t: String) -> void: _pass.grab_focus())
        _pass.text_submitted.connect(func(_t: String) -> void: _on_action())
        _set_mode("login")


## The light input wells — the shared theme's LineEdit is the dark client
## well, so the WHITE card gets its own quiet gray face + blue focus ring.
func _style_light_input(field: LineEdit) -> void:
        var normal := RetroUI.surface(10, Color("f2f3f5"), 0, 0.0)
        normal.content_margin_left = 12.0
        normal.content_margin_right = 12.0
        normal.content_margin_top = 10.0
        normal.content_margin_bottom = 10.0
        var focus := normal.duplicate()
        focus.set_border_width_all(2)
        focus.border_color = RetroUI.BLUE
        field.add_theme_stylebox_override("normal", normal)
        field.add_theme_stylebox_override("focus", focus)
        field.add_theme_stylebox_override("read_only", normal)
        field.add_theme_color_override("font_color", Color("15171a"))
        field.add_theme_color_override("font_placeholder_color", Color("9aa0a6"))
        field.add_theme_color_override("caret_color", RetroUI.BLUE)
        field.add_theme_color_override("selection_color", Color(0.0, 0.635, 1.0, 0.25))
        var book: Font = RetroUI.source(400)
        if book != null:
                field.add_theme_font_override("font", book)
                field.add_theme_font_size_override("font_size", 15)


func _set_mode(mode: String) -> void:
        _mode = mode
        _tab_login.button_pressed = mode == "login"
        _tab_signup.button_pressed = mode == "signup"
        _go.text = "LOG IN" if mode == "login" else "CREATE ACCOUNT"
        _status.text = ""
        # the segmented read: active = the WHITE chip with dark ink,
        # quiet = transparent with gray ink — iOS-quiet, Roblox-quiet
        for pair in [[_tab_login, "login"], [_tab_signup, "signup"]]:
                var b: Button = pair[0]
                var on: bool = pair[1] == mode
                var sb := StyleBoxFlat.new()
                sb.bg_color = Color("ffffff") if on else Color(0, 0, 0, 0)
                sb.set_corner_radius_all(9)
                if on:
                        sb.shadow_color = Color(0, 0, 0, 0.18)
                        sb.shadow_size = 5
                        sb.shadow_offset = Vector2(0, 1)
                sb.content_margin_top = 7.0
                sb.content_margin_bottom = 7.0
                for st in ["normal", "hover", "pressed", "hover_pressed"]:
                        b.add_theme_stylebox_override(st, sb)
                for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                        b.add_theme_color_override(st,
                                Color("15171a") if on else Color("6b7076"))
                b.add_theme_font_override("font", RetroUI.gotham(700))
                b.add_theme_font_size_override("font_size", 12)


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


## The backdrop: two HUGE soft color glows (blue lower-left, warm orange
## upper-right) over the deep backdrop — the modern Roblox sign-in mood.
func _add_glow_bg(bg: ColorRect) -> void:
        var size := 560
        var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
        var c := Vector2(size / 2.0, size / 2.0)
        for y in range(size):
                for x in range(size):
                        var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c) / (size / 2.0)
                        var a := clampf(1.0 - d, 0.0, 1.0)
                        img.set_pixel(x, y, Color(1, 1, 1, a * a))   # soft falloff
        var mask := ImageTexture.create_from_image(img)
        for spec: Array in [
                # [color, screen pos, size, alpha]
                [Color("00a2ff"), Vector2(0.12, 0.88), 1.15, 0.16],
                [Color("ff8a3d"), Vector2(0.90, 0.10), 1.0, 0.10],
                [Color("7a4dff"), Vector2(0.85, 0.85), 0.9, 0.08],
        ]:
                var glow := TextureRect.new()
                glow.texture = mask
                glow.modulate = Color((spec[0] as Color).r, (spec[0] as Color).g,
                        (spec[0] as Color).b, float(spec[3]))
                var gsize := float(size) * float(spec[2])
                glow.custom_minimum_size = Vector2(gsize, gsize)
                glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                glow.stretch_mode = TextureRect.STRETCH_SCALE
                glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
                var pos: Vector2 = spec[1]
                glow.offset_left = pos.x * 1280.0 - gsize / 2.0
                glow.offset_top = pos.y * 720.0 - gsize / 2.0
                glow.offset_right = glow.offset_left + gsize
                glow.offset_bottom = glow.offset_top + gsize
                bg.add_child(glow)


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
