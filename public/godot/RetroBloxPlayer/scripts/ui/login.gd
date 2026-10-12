extends Control
## Login — the front door of the new player. Log in or sign up; that's the
## only way in. The FIRST login saves a session token on disk, and from then
## on every boot auto-signs in with zero typing — you log in once, ever.
## The server is LOCKED to the official RetroBlox platform: it is a label,
## not a field, so it can never be pointed somewhere else.
## v8.0: the REAL CLIENT LOGIN — the deep #111316 page, the tilted-square
## logo + bold Montserrat wordmark, dark rounded input wells, and the
## client's WHITE Log In key. No cards, no bevels, no glow — the Roblox read.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VERSION := "8.0"

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
        _add_vignette(bg)

        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)

        var box := VBoxContainer.new()
        box.custom_minimum_size = Vector2(420, 0)
        box.add_theme_constant_override("separation", 10)
        center.add_child(box)

        # ---- the brand row: the tilted-square logo + the wordmark ----
        var brand := HBoxContainer.new()
        brand.alignment = BoxContainer.ALIGNMENT_CENTER
        brand.add_theme_constant_override("separation", 12)
        box.add_child(brand)
        var tile := TextureRect.new()
        tile.texture = _logo_tile_texture()
        tile.custom_minimum_size = Vector2(48, 48)
        tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
        brand.add_child(tile)
        var word := Label.new()
        word.text = "RETROBLOX"
        word.add_theme_font_override("font", RetroUI.gotham(800))
        word.add_theme_font_size_override("font_size", 30)
        word.add_theme_color_override("font_color", Color.WHITE)
        brand.add_child(word)

        var sub := Label.new()
        sub.text = "the classic roblox-style client — v%s" % VERSION
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.add_theme_font_override("font", RetroUI.gotham(400))
        sub.add_theme_font_size_override("font_size", 12)
        sub.add_theme_color_override("font_color", RetroUI.MENU_FAINT)
        box.add_child(sub)
        box.add_child(_gap(10))

        # mode switch — the client's quiet tabs: active = white + underline
        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 8)
        tabs.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_child(tabs)
        _tab_login = Button.new()
        _tab_login.text = "Log In"
        _tab_login.toggle_mode = true
        _tab_login.custom_minimum_size = Vector2(200, 38)
        _tab_login.focus_mode = Control.FOCUS_NONE
        _tab_login.pressed.connect(func() -> void: _set_mode("login"))
        tabs.add_child(_tab_login)
        _tab_signup = Button.new()
        _tab_signup.text = "Sign Up"
        _tab_signup.toggle_mode = true
        _tab_signup.custom_minimum_size = Vector2(200, 38)
        _tab_signup.focus_mode = Control.FOCUS_NONE
        _tab_signup.pressed.connect(func() -> void: _set_mode("signup"))
        tabs.add_child(_tab_signup)
        box.add_child(_gap(6))

        _user = LineEdit.new()
        _user.placeholder_text = "Username"
        _user.text = Api.saved_username   # remembered from last time
        _user.custom_minimum_size = Vector2(0, 46)
        box.add_child(_user)

        _pass = LineEdit.new()
        _pass.placeholder_text = "Password"
        _pass.secret = true
        _pass.custom_minimum_size = Vector2(0, 46)
        box.add_child(_pass)

        _go = Button.new()
        _go.text = "Log In"
        _go.theme_type_variation = "BtnPrimary"
        _go.custom_minimum_size = Vector2(0, 48)
        _go.pressed.connect(_on_action)
        box.add_child(_go)
        box.add_child(_gap(4))

        var note := Label.new()
        note.text = "You only log in ONCE — after that you are signed in\nevery time you open RetroBlox, automatically."
        note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        note.add_theme_font_override("font", RetroUI.gotham(400))
        note.add_theme_font_size_override("font_size", 12)
        note.add_theme_color_override("font_color", Color("8f939a"))
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
        _offline.theme_type_variation = "BtnGhost"
        _offline.custom_minimum_size = Vector2(0, 30)
        _offline.visible = false
        _offline.pressed.connect(_on_offline)
        box.add_child(_offline)

        var footer := Label.new()
        footer.text = "Server: retro-blox.vercel.app  ·  locked  ·  your PFP loads from your account"
        footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        footer.add_theme_font_override("font", RetroUI.gotham(400))
        footer.add_theme_font_size_override("font_size", 11)
        footer.add_theme_color_override("font_color", Color("6a6e74"))
        box.add_child(footer)

        _user.text_submitted.connect(func(_t: String) -> void: _pass.grab_focus())
        _pass.text_submitted.connect(func(_t: String) -> void: _on_action())
        _set_mode("login")


func _gap(h: float) -> Control:
        var c := Control.new()
        c.custom_minimum_size = Vector2(0, h)
        c.mouse_filter = Control.MOUSE_FILTER_IGNORE
        return c


func _set_mode(mode: String) -> void:
        _mode = mode
        _tab_login.button_pressed = mode == "login"
        _tab_signup.button_pressed = mode == "signup"
        _go.text = "Log In" if mode == "login" else "Create Account"
        _status.text = ""
        # the client's tab read: active = white ink + white underline,
        # quiet = muted ink on transparent
        for pair in [[_tab_login, "login"], [_tab_signup, "signup"]]:
                var b: Button = pair[0]
                var on: bool = pair[1] == mode
                var sb := StyleBoxFlat.new()
                sb.bg_color = Color(0, 0, 0, 0)
                sb.set_corner_radius_all(8)
                sb.border_width_bottom = 2
                sb.border_color = Color.WHITE if on else Color(0, 0, 0, 0)
                sb.content_margin_top = 6.0
                sb.content_margin_bottom = 6.0
                for st in ["normal", "pressed", "hover_pressed"]:
                        b.add_theme_stylebox_override(st, sb)
                var hov := sb.duplicate() as StyleBoxFlat
                hov.bg_color = Color(1, 1, 1, 0.06)
                b.add_theme_stylebox_override("hover", hov)
                for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                        b.add_theme_color_override(st,
                                Color.WHITE if on else Color("8f939a"))
                b.add_theme_font_override("font", RetroUI.gotham(600))
                b.add_theme_font_size_override("font_size", 14)


## The tilted-square logo — the Roblox mark's read: a red rounded square,
## rotated, with the square hole knocked out, drawn once in code.
func _logo_tile_texture() -> ImageTexture:
        var s := 48
        var big := 4          # supersample for smooth edges
        var w := s * big
        var img := Image.create_empty(w, w, false, Image.FORMAT_RGBA8)
        var red := Color("e2231a")
        var half := float(w) / 2.0
        var rad := deg_to_rad(14.0)
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
                                        w * 0.14):
                                continue
                        # the square hole, knocked out of the tile
                        var hole := w * 0.13
                        var hp := Rect2(half - hole, half - hole, hole * 2.0, hole * 2.0)
                        if RetroUI._in_rounded_px(p, hp, w * 0.03):
                                continue
                        img.set_pixel(x, y, red)
        img.resize(s, s, Image.INTERPOLATE_BILINEAR)
        return ImageTexture.create_from_image(img)


## The backdrop: a quiet dark vignette — the client page's soft corners.
func _add_vignette(bg: ColorRect) -> void:
        var vig := GradientTexture2D.new()
        vig.fill = GradientTexture2D.FILL_RADIAL
        vig.fill_from = Vector2(0.5, 0.42)
        vig.fill_to = Vector2(0.5, 0.0)
        vig.width = 64
        vig.height = 64
        var g := Gradient.new()
        g.set_color(0, Color(0, 0, 0, 0.0))
        g.set_color(1, Color(0, 0, 0, 0.42))
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
