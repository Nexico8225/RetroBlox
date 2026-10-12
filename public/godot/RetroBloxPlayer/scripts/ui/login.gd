extends Control
## Login — the front door of the new player. Log in or sign up; that's the
## only way in. The FIRST login saves a session token on disk, and from then
## on every boot auto-signs in with zero typing — you log in once, ever.
## The server is LOCKED to the official RetroBlox platform: it is a label,
## not a field, so it can never be pointed somewhere else.
##
## v11.0 — THE OLD LOGIN PAGE, BACK BY POPULAR DEMAND: the white card, the
## tilted red tile, the big RETROBLOX wordmark, the two classic tabs
## (Log In / Sign Up), the soft wells and the big CLASSIC GREEN key. The
## churned window experiments are over. What's new is honest: the backdrop
## is now a REAL photograph of the classic baseplate (shipped with the kit,
## downloaded from the web) instead of a code-drawn grid.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VERSION := "12.0"

## the card's palette (the old page's light voice, against the dark chrome)
const CARD_BG := Color("f6f7f8")
const CARD_EDGE := Color("d5d9dd")
const WELL_BG := Color("ffffff")
const WELL_EDGE := Color("c3c9cf")
const INK := Color("1f2427")
const INK_MUTED := Color("6a7178")

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
        # ---- the backdrop: the REAL classic baseplate photograph ----
        var bg := ColorRect.new()
        bg.color = Color("2b2f33")
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bg)
        _add_backdrop(bg)

        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)

        # ---- THE CARD — the old white sheet, rounded, quietly shadowed ----
        var card := PanelContainer.new()
        card.custom_minimum_size = Vector2(430, 0)
        card.add_theme_stylebox_override("panel", _card_style())
        center.add_child(card)

        var body_margin := MarginContainer.new()
        body_margin.add_theme_constant_override("margin_left", 36)
        body_margin.add_theme_constant_override("margin_right", 36)
        body_margin.add_theme_constant_override("margin_top", 26)
        body_margin.add_theme_constant_override("margin_bottom", 24)
        card.add_child(body_margin)
        var body := VBoxContainer.new()
        body.add_theme_constant_override("separation", 10)
        body_margin.add_child(body)

        # ---- the brand row: tilted red tile + the RETROBLOX wordmark ----
        var brand := HBoxContainer.new()
        brand.alignment = BoxContainer.ALIGNMENT_CENTER
        brand.add_theme_constant_override("separation", 12)
        body.add_child(brand)
        var tile := TextureRect.new()
        tile.texture = _logo_tile_texture()
        tile.custom_minimum_size = Vector2(54, 54)
        tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
        brand.add_child(tile)
        var word := Label.new()
        word.text = "RETROBLOX"
        word.add_theme_font_override("font", RetroUI.gotham(800))
        word.add_theme_font_size_override("font_size", 33)
        word.add_theme_color_override("font_color", INK)
        brand.add_child(word)

        var sub := Label.new()
        sub.text = "the classic roblox-style client — v%s" % VERSION
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.add_theme_font_override("font", RetroUI.gotham(400))
        sub.add_theme_font_size_override("font_size", 12)
        sub.add_theme_color_override("font_color", INK_MUTED)
        body.add_child(sub)
        body.add_child(_gap(8))

        # ---- the classic TABS — Log In / Sign Up, the old pair ----
        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 8)
        tabs.alignment = BoxContainer.ALIGNMENT_CENTER
        body.add_child(tabs)
        _tab_login = Button.new()
        _tab_login.text = "Log In"
        _tab_login.toggle_mode = true
        _tab_login.custom_minimum_size = Vector2(170, 36)
        _tab_login.focus_mode = Control.FOCUS_NONE
        _tab_login.pressed.connect(func() -> void: _set_mode("login"))
        tabs.add_child(_tab_login)
        _tab_signup = Button.new()
        _tab_signup.text = "Sign Up"
        _tab_signup.toggle_mode = true
        _tab_signup.custom_minimum_size = Vector2(170, 36)
        _tab_signup.focus_mode = Control.FOCUS_NONE
        _tab_signup.pressed.connect(func() -> void: _set_mode("signup"))
        tabs.add_child(_tab_signup)
        body.add_child(_gap(4))

        # ---- the WHITE WELLS — the classic form fields ----
        _user = LineEdit.new()
        _user.placeholder_text = "Username"
        _user.text = Api.saved_username   # remembered from last time
        _user.custom_minimum_size = Vector2(0, 42)
        _style_well(_user)
        body.add_child(_user)

        _pass = LineEdit.new()
        _pass.placeholder_text = "Password"
        _pass.secret = true
        _pass.custom_minimum_size = Vector2(0, 42)
        _style_well(_pass)
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
        note.add_theme_color_override("font_color", INK_MUTED)
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
        footer.text = "Server: retro-blox.vercel.app  ·  locked  ·  your avatar loads from your account"
        footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        footer.add_theme_font_override("font", RetroUI.gotham(400))
        footer.add_theme_font_size_override("font_size", 11)
        footer.add_theme_color_override("font_color", INK_MUTED)
        body.add_child(footer)

        # ---- under the card: the copyright line the old client wore ----
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
        legal.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
        add_child(legal)

        _user.text_submitted.connect(func(_t: String) -> void: _pass.grab_focus())
        _pass.text_submitted.connect(func(_t: String) -> void: _on_action())
        _set_mode("login")


## The backdrop photograph: the classic baseplate, cover-fitted, gently
## dimmed so the white card pops — the image the old site's own login sat on.
func _add_backdrop(bg: ColorRect) -> void:
        var tex := RetroUI.login_backdrop()
        if tex != null:
                var photo := TextureRect.new()
                photo.texture = tex
                photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
                photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
                photo.set_anchors_preset(Control.PRESET_FULL_RECT)
                bg.add_child(photo)
        # a quiet darkening so the card pops — the old site's dim canvas
        var shade := ColorRect.new()
        shade.color = Color(0, 0, 0, 0.38)
        shade.set_anchors_preset(Control.PRESET_FULL_RECT)
        shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bg.add_child(shade)


## The white card: rounded 10, hairline edge, one soft drop shadow.
func _card_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = CARD_BG
        sb.set_corner_radius_all(10)
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = CARD_EDGE
        sb.shadow_color = Color(0, 0, 0, 0.45)
        sb.shadow_size = 22
        sb.shadow_offset = Vector2(0, 6)
        sb.content_margin_left = 0.0
        sb.content_margin_right = 0.0
        sb.content_margin_top = 0.0
        sb.content_margin_bottom = 0.0
        return sb


## The light wells: white face, gray hairline, ink caret, blue focus ring.
func _style_well(w: LineEdit) -> void:
        var normal := StyleBoxFlat.new()
        normal.bg_color = WELL_BG
        normal.set_corner_radius_all(6)
        normal.set_border_width_all(1)
        normal.border_color = WELL_EDGE
        normal.content_margin_left = 12.0
        normal.content_margin_right = 12.0
        normal.content_margin_top = 6.0
        normal.content_margin_bottom = 6.0
        var focus := normal.duplicate() as StyleBoxFlat
        focus.border_color = RetroUI.BLUE
        focus.set_border_width_all(2)
        w.add_theme_stylebox_override("normal", normal)
        w.add_theme_stylebox_override("focus", focus)
        w.add_theme_color_override("font_color", INK)
        w.add_theme_color_override("font_placeholder_color", Color(INK_MUTED, 0.75))
        w.add_theme_color_override("caret_color", RetroUI.BLUE)
        w.add_theme_color_override("selection_color", Color(RetroUI.BLUE, 0.35))
        if RetroUI.gotham(400) != null:
                w.add_theme_font_override("font", RetroUI.gotham(400))
        w.add_theme_font_size_override("font_size", 15)


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
        # the classic segmented chips: active = white with the blue ring,
        # quiet = flat gray — exactly how the old page's tabs read
        for pair in [[_tab_login, "login"], [_tab_signup, "signup"]]:
                var b: Button = pair[0]
                var on: bool = pair[1] == mode
                var sb := StyleBoxFlat.new()
                sb.bg_color = Color.WHITE if on else Color("e4e7ea")
                sb.set_corner_radius_all(6)
                sb.set_border_width_all(1)
                sb.border_color = RetroUI.BLUE if on else WELL_EDGE
                sb.content_margin_top = 6.0
                sb.content_margin_bottom = 6.0
                b.add_theme_stylebox_override("normal", sb)
                var hb := sb.duplicate() as StyleBoxFlat
                if not on:
                        hb.bg_color = Color("eef0f2")
                b.add_theme_stylebox_override("hover", hb)
                b.add_theme_stylebox_override("pressed", sb)
                b.add_theme_stylebox_override("hover_pressed", sb)
                for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                        b.add_theme_color_override(st, INK if on else INK_MUTED)
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


func _set_status(text: String, is_error := true) -> void:
        _status.text = text
        _status.add_theme_color_override("font_color",
                Color("b3261e") if is_error else RetroUI.GREEN)


## Auto sign-in on boot: the saved token (180-day server-side TTL) brings
## the whole account back. The token is ONLY wiped when the server itself
## says it is invalid (401) — a Wi-Fi hiccup never logs you out.
func _try_auto_login() -> void:
        if Api.token == "":
                return
        _working = true
        _set_status("Logging you in…", false)
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
