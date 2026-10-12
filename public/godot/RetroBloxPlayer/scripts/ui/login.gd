extends Control
## Login — the front door of the new player. Log in or sign up; that's the
## only way in. The FIRST login saves a session token on disk, and from then
## on every boot auto-signs in with zero typing — you log in once, ever.
## The server is LOCKED to the official RetroBlox platform: it is a label,
## not a field, so it can never be pointed somewhere else.
## v10.0: THE 2008 CLIENT LOGIN — a real beveled gray window (draggable by
## its title bar, close X and all) on a baseplate-stud backdrop, the tilted
## red tile + bold ARIAL wordmark, folder tabs, WHITE sunken wells with black
## ink, and the CLASSIC GREEN Log In key. The old client, exactly.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VERSION := "10.0"

var _mode := "login"   # login | signup
var _user: LineEdit
var _pass: LineEdit
var _status: Label
var _go: Button
var _offline: Button
var _tab_login: Button
var _tab_signup: Button
var _working := false
var _win: PanelContainer
var _dragging := false
var _drag_off := Vector2.ZERO


func _ready() -> void:
        theme = RetroUI.shared
        RetroUI.apply_cursors()
        _build()
        _try_auto_login()


func _build() -> void:
        # ---- the backdrop: classic gray + a baseplate of soft studs ----
        var bg := ColorRect.new()
        bg.color = RetroUI.BG
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bg)
        _add_studs(bg)

        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)

        # ---- THE WINDOW — a real beveled chrome sheet, draggable ----
        _win = PanelContainer.new()
        _win.custom_minimum_size = Vector2(460, 0)
        _win.add_theme_stylebox_override("panel", RetroUI.raised(4, RetroUI.PANEL))
        center.add_child(_win)

        var col := VBoxContainer.new()
        col.add_theme_constant_override("separation", 0)
        _win.add_child(col)

        # ---- the title bar — "RetroBlox", drag handle, beveled close X ----
        var title_bar := PanelContainer.new()
        title_bar.add_theme_stylebox_override("panel", RetroUI.raised(4, Color("4a4a4a")))
        col.add_child(title_bar)
        var tb := HBoxContainer.new()
        tb.add_theme_constant_override("separation", 8)
        title_bar.add_child(tb)
        var t_logo := TextureRect.new()
        t_logo.texture = _logo_tile_texture()
        t_logo.custom_minimum_size = Vector2(18, 18)
        t_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        t_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        t_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
        tb.add_child(t_logo)
        var t_label := Label.new()
        t_label.text = "RetroBlox"
        t_label.add_theme_font_override("font", RetroUI.gotham(700))
        t_label.add_theme_font_size_override("font_size", 13)
        t_label.add_theme_color_override("font_color", RetroUI.TEXT)
        t_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        tb.add_child(t_label)
        tb.add_child(_spacer_h())
        var x_btn := Button.new()
        x_btn.text = "X"
        x_btn.custom_minimum_size = Vector2(30, 22)
        x_btn.focus_mode = Control.FOCUS_NONE
        x_btn.add_theme_stylebox_override("normal", RetroUI.raised(4, Color("5a5a5a")))
        x_btn.add_theme_stylebox_override("hover", RetroUI.raised(4, RetroUI.RED))
        x_btn.add_theme_stylebox_override("pressed", RetroUI.sunken(4, Color("8a1a14")))
        x_btn.add_theme_color_override("font_color", RetroUI.TEXT)
        x_btn.add_theme_color_override("font_hover_color", Color.WHITE)
        x_btn.add_theme_font_override("font", RetroUI.gotham(700))
        x_btn.add_theme_font_size_override("font_size", 11)
        x_btn.pressed.connect(func() -> void: get_tree().quit())
        tb.add_child(x_btn)
        title_bar.gui_input.connect(_on_title_input)
        title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE

        # ---- the window body ----
        var body_margin := MarginContainer.new()
        body_margin.add_theme_constant_override("margin_left", 34)
        body_margin.add_theme_constant_override("margin_right", 34)
        body_margin.add_theme_constant_override("margin_top", 18)
        body_margin.add_theme_constant_override("margin_bottom", 20)
        col.add_child(body_margin)
        var body := VBoxContainer.new()
        body.name = "Body"
        body.add_theme_constant_override("separation", 10)
        body_margin.add_child(body)

        # ---- the brand row: tilted red tile + ARIAL wordmark ----
        var brand := HBoxContainer.new()
        brand.alignment = BoxContainer.ALIGNMENT_CENTER
        brand.add_theme_constant_override("separation", 12)
        body.add_child(brand)
        var tile := TextureRect.new()
        tile.texture = _logo_tile_texture()
        tile.custom_minimum_size = Vector2(52, 52)
        tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
        brand.add_child(tile)
        var word := Label.new()
        word.text = "RETROBLOX"
        word.add_theme_font_override("font", RetroUI.gotham(800))
        word.add_theme_font_size_override("font_size", 32)
        word.add_theme_color_override("font_color", Color.WHITE)
        word.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
        word.add_theme_constant_override("shadow_offset_x", 0)
        word.add_theme_constant_override("shadow_offset_y", 2)
        brand.add_child(word)

        var sub := Label.new()
        sub.text = "the classic roblox-style client — v%s" % VERSION
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.add_theme_font_override("font", RetroUI.gotham(400))
        sub.add_theme_font_size_override("font_size", 12)
        sub.add_theme_color_override("font_color", RetroUI.MENU_FAINT)
        body.add_child(sub)
        body.add_child(_gap(8))

        # mode switch — classic FOLDER TABS: active = raised bevel, quiet = flat
        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 4)
        tabs.alignment = BoxContainer.ALIGNMENT_CENTER
        body.add_child(tabs)
        _tab_login = Button.new()
        _tab_login.text = "Log In"
        _tab_login.toggle_mode = true
        _tab_login.custom_minimum_size = Vector2(180, 36)
        _tab_login.focus_mode = Control.FOCUS_NONE
        _tab_login.pressed.connect(func() -> void: _set_mode("login"))
        tabs.add_child(_tab_login)
        _tab_signup = Button.new()
        _tab_signup.text = "Sign Up"
        _tab_signup.toggle_mode = true
        _tab_signup.custom_minimum_size = Vector2(180, 36)
        _tab_signup.focus_mode = Control.FOCUS_NONE
        _tab_signup.pressed.connect(func() -> void: _set_mode("signup"))
        tabs.add_child(_tab_signup)
        body.add_child(_gap(6))

        # ---- the WHITE SUNKEN WELLS — the classic form field ----
        _user = LineEdit.new()
        _user.placeholder_text = "Username"
        _user.text = Api.saved_username   # remembered from last time
        _user.custom_minimum_size = Vector2(0, 42)
        body.add_child(_user)

        _pass = LineEdit.new()
        _pass.placeholder_text = "Password"
        _pass.secret = true
        _pass.custom_minimum_size = Vector2(0, 42)
        body.add_child(_pass)

        # ---- THE CLASSIC GREEN KEY ----
        _go = Button.new()
        _go.text = "Log In"
        _go.theme_type_variation = "BtnPrimary"
        _go.custom_minimum_size = Vector2(0, 46)
        _go.pressed.connect(_on_action)
        body.add_child(_go)
        body.add_child(_gap(2))

        var note := Label.new()
        note.text = "You only log in ONCE — after that you are signed in\nevery time you open RetroBlox, automatically."
        note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        note.add_theme_font_override("font", RetroUI.gotham(400))
        note.add_theme_font_size_override("font_size", 12)
        note.add_theme_color_override("font_color", RetroUI.MENU_MUTED)
        body.add_child(note)
        _status = Label.new()
        _status.text = ""
        _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _status.custom_minimum_size = Vector2(0, 40)
        _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        body.add_child(_status)

        # offline escape hatch — appears ONLY when the server cannot be
        # reached, so a dead Wi-Fi day never bricks the player
        _offline = Button.new()
        _offline.text = "Can't connect — play offline instead"
        _offline.theme_type_variation = "BtnGhost"
        _offline.custom_minimum_size = Vector2(0, 30)
        _offline.visible = false
        _offline.pressed.connect(_on_offline)
        body.add_child(_offline)

        var footer := Label.new()
        footer.text = "Server: retro-blox.vercel.app  ·  locked  ·  your PFP loads from your account"
        footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        footer.add_theme_font_override("font", RetroUI.gotham(400))
        footer.add_theme_font_size_override("font_size", 11)
        footer.add_theme_color_override("font_color", RetroUI.MENU_FAINT)
        body.add_child(footer)

        # ---- under the window: the copyright line the old client wore ----
        var legal := Label.new()
        legal.text = "RetroBlox Player v%s  ·  ©2006-2013 RetroBlox — not affiliated with Roblox" % VERSION
        legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        legal.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        legal.grow_vertical = Control.GROW_DIRECTION_BEGIN
        legal.offset_top = -34.0
        legal.offset_bottom = -16.0
        legal.offset_left = -420.0
        legal.offset_right = 420.0
        legal.add_theme_font_override("font", RetroUI.gotham(400))
        legal.add_theme_font_size_override("font_size", 11)
        legal.add_theme_color_override("font_color", Color(1, 1, 1, 0.38))
        add_child(legal)

        _user.text_submitted.connect(func(_t: String) -> void: _pass.grab_focus())
        _pass.text_submitted.connect(func(_t: String) -> void: _on_action())
        _set_mode("login")


func _spacer_h() -> Control:
        var c := Control.new()
        c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        c.mouse_filter = Control.MOUSE_FILTER_IGNORE
        return c


## Title-bar dragging — the old window mover, one finger on the chrome.
func _on_title_input(event: InputEvent) -> void:
        if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
                _dragging = (event as InputEventMouseButton).pressed
                if _dragging:
                        _drag_off = _win.get_global_mouse_position() - _win.global_position
                else:
                        _drag_off = Vector2.ZERO
        elif event is InputEventMouseMotion and _dragging:
                _win.global_position = _win.get_global_mouse_position() - _drag_off


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
        # the classic FOLDER TAB: active = raised bevel face, quiet = flat dark
        for pair in [[_tab_login, "login"], [_tab_signup, "signup"]]:
                var b: Button = pair[0]
                var on: bool = pair[1] == mode
                var sb: StyleBox = RetroUI.raised(4, Color("565656")) if on else RetroUI.flat(4, Color("3f3f3f"))
                sb.content_margin_top = 6.0
                sb.content_margin_bottom = 6.0
                for st in ["normal", "pressed", "hover_pressed"]:
                        b.add_theme_stylebox_override(st, sb)
                var hov: StyleBox = RetroUI.raised(4, Color("606060")) if on else RetroUI.flat(4, Color("4a4a4a"))
                hov.content_margin_top = 6.0
                hov.content_margin_bottom = 6.0
                b.add_theme_stylebox_override("hover", hov)
                for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                        b.add_theme_color_override(st,
                                Color.WHITE if on else RetroUI.MENU_MUTED)
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


## The backdrop: classic gray with a baseplate of soft studs — the tile
## every 2008 place stood on, drawn once in code and tiled edge to edge.
func _add_studs(bg: ColorRect) -> void:
        var tex := _stud_tile_texture()
        var studs := TextureRect.new()
        studs.texture = tex
        studs.stretch_mode = TextureRect.STRETCH_TILE
        studs.mouse_filter = Control.MOUSE_FILTER_IGNORE
        studs.set_anchors_preset(Control.PRESET_FULL_RECT)
        bg.add_child(studs)
        # a quiet darkening so the window pops — the old site's dim canvas
        var shade := ColorRect.new()
        shade.color = Color(0, 0, 0, 0.25)
        shade.set_anchors_preset(Control.PRESET_FULL_RECT)
        shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bg.add_child(shade)


## One 64px stud tile: the raised plastic bump with its light and shadow,
## exactly how the classic baseplate read up close.
func _stud_tile_texture() -> ImageTexture:
        var s := 64
        var big := 2
        var w := s * big
        var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
        var face := Color("333333")
        var stud_c := Color("3d3d3d")
        var hi := Color("4f4f4f")
        var lo := Color("232323")
        img.fill(face)
        var cx := float(w) / 2.0
        var cy := float(w) / 2.0
        var r := 15.0 * big
        var ri := 12.0 * big
        for y in w:
                for x in w:
                        var dx := float(x) + 0.5 - cx
                        var dy := float(y) + 0.5 - cy
                        var d := sqrt(dx * dx + dy * dy)
                        if d <= r:
                                if d > ri:
                                        # the stud's side wall: lit top-left, shaded bottom-right
                                        var t := (dx + dy) / (2.0 * r)
                                        img.set_pixel(x, y, lo.lerp(hi, clampf(0.5 - t, 0.0, 1.0)))
                                else:
                                        img.set_pixel(x, y, stud_c)
        return ImageTexture.create_from_image(img)


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
        # Api.txt everywhere: role can arrive as JSON null, and String(null)
        # hard-crashes with "Invalid call 'String' constructor"
        Session.sign_in(me, Api.txt(me.get("userId", "")), Api.txt(me.get("username", ""), "Player"),
                Api.txt(me.get("role", ""), "user"))
        # v3.6: the game-select hub is retired — sign in and you are instantly
        # playing the classic baseplate
        get_tree().change_scene_to_file("res://scenes/game.tscn")


## Last resort when the platform is unreachable: classic noob, offline chat.
func _on_offline() -> void:
        if _working:
                return
        Session.set_guest()
        get_tree().change_scene_to_file("res://scenes/game.tscn")
