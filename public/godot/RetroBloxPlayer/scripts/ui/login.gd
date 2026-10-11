extends Control
## Login — the front door of the new player. Log in or sign up; that's the
## only way in. The FIRST login saves a session token on disk, and from then
## on every boot auto-signs in with zero typing — you log in once, ever.
## The server is LOCKED to the official RetroBlox platform: it is a label,
## not a field, so it can never be pointed somewhere else.
## v5.0: the midnight arcade — a deep navy sky with a code-drawn pixel
## starfield behind one dark card, electric blue accents, pixel type.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VERSION := "5.0"

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
        _add_starfield(bg)

        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)

        var card := PanelContainer.new()
        card.custom_minimum_size = Vector2(430, 0)
        # v5.0: the midnight card — dark face, bold cabinet outline, deep shadow
        var card_sb := StyleBoxFlat.new()
        card_sb.bg_color = Color(0.071, 0.094, 0.149, 0.97)
        card_sb.set_corner_radius_all(14)
        card_sb.border_color = RetroUI.MENU_OUTLINE
        card_sb.set_border_width_all(2)
        card_sb.shadow_color = Color(0, 0, 0, 0.55)
        card_sb.shadow_size = 22
        card_sb.shadow_offset = Vector2(0, 8)
        card_sb.content_margin_left = 24.0
        card_sb.content_margin_right = 24.0
        card_sb.content_margin_top = 22.0
        card_sb.content_margin_bottom = 20.0
        card.add_theme_stylebox_override("panel", card_sb)
        center.add_child(card)

        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 9)
        box.custom_minimum_size = Vector2(360, 0)
        card.add_child(box)

        # your uploaded ReTROBLOX wordmark, straight on white
        if ResourceLoader.exists("res://assets/ui/wordmark.png"):
                var wm := TextureRect.new()
                wm.texture = load("res://assets/ui/wordmark.png")
                wm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
                wm.custom_minimum_size = Vector2(340, 64)
                wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
                box.add_child(wm)
        else:
                var lbl := Label.new()
                lbl.text = "RETROBLOX"
                lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                lbl.theme_type_variation = "H1"
                box.add_child(lbl)

        var sub := Label.new()
        sub.text = "the midnight client — v%s" % VERSION
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var retro: Font = RetroUI.pixel_font()
        if retro != null:
                sub.add_theme_font_override("font", retro)
                sub.add_theme_font_size_override("font_size", 8)
        sub.add_theme_color_override("font_color", RetroUI.MENU_GOLD)
        box.add_child(sub)

        # mode tabs — the segmented control: the active side wears the
        # electric blue chip, the quiet side stays a dark key
        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 0)
        tabs.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_child(tabs)
        _tab_login = Button.new()
        _tab_login.text = "LOG IN"
        _tab_login.toggle_mode = true
        _tab_login.custom_minimum_size = Vector2(170, 36)
        _tab_login.focus_mode = Control.FOCUS_NONE
        _tab_login.pressed.connect(func() -> void: _set_mode("login"))
        tabs.add_child(_tab_login)
        _tab_signup = Button.new()
        _tab_signup.text = "SIGN UP"
        _tab_signup.toggle_mode = true
        _tab_signup.custom_minimum_size = Vector2(170, 36)
        _tab_signup.focus_mode = Control.FOCUS_NONE
        _tab_signup.pressed.connect(func() -> void: _set_mode("signup"))
        tabs.add_child(_tab_signup)

        _user = LineEdit.new()
        _user.placeholder_text = "Username"
        _user.text = Api.saved_username   # remembered from last time
        _user.custom_minimum_size = Vector2(0, 40)
        box.add_child(_user)

        _pass = LineEdit.new()
        _pass.placeholder_text = "Password"
        _pass.secret = true
        _pass.custom_minimum_size = Vector2(0, 40)
        box.add_child(_pass)

        _go = Button.new()
        _go.text = "LOG IN"
        _go.theme_type_variation = "BtnBlue"
        _go.custom_minimum_size = Vector2(0, 46)
        _go.pressed.connect(_on_action)
        box.add_child(_go)

        var note := Label.new()
        note.text = "You only log in ONCE — after that you are signed in\nevery time you open RetroBlox, automatically."
        note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        note.theme_type_variation = "Small"
        note.add_theme_color_override("font_color", RetroUI.MENU_MUTED)
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
        footer.theme_type_variation = "Small"
        footer.add_theme_color_override("font_color", RetroUI.MENU_FAINT)
        box.add_child(footer)

        _user.text_submitted.connect(func(_t: String) -> void: _pass.grab_focus())
        _pass.text_submitted.connect(func(_t: String) -> void: _on_action())
        _set_mode("login")


func _set_mode(mode: String) -> void:
        _mode = mode
        _tab_login.button_pressed = mode == "login"
        _tab_signup.button_pressed = mode == "signup"
        _go.text = "LOG IN" if mode == "login" else "CREATE ACCOUNT"
        _status.text = ""
        # the segmented-tab read: active = electric blue chip, quiet = dark key
        for pair in [[_tab_login, "login"], [_tab_signup, "signup"]]:
                var b: Button = pair[0]
                var on: bool = pair[1] == mode
                var sb := StyleBoxFlat.new()
                sb.bg_color = RetroUI.MENU_ACCENT_SOFT if on else Color("0d1220")
                sb.set_corner_radius_all(9)
                sb.border_color = RetroUI.MENU_ACCENT if on else RetroUI.MENU_EDGE
                sb.set_border_width_all(1 if on else 1)
                sb.content_margin_top = 6.0
                sb.content_margin_bottom = 6.0
                for st in ["normal", "hover", "pressed", "hover_pressed"]:
                        b.add_theme_stylebox_override(st, sb)
                for st in ["font_color", "font_hover_color", "font_pressed_color"]:
                        b.add_theme_color_override(st, RetroUI.MENU_ACCENT_HI if on else RetroUI.MENU_MUTED)
                if RetroUI.pixel_font() != null:
                        b.add_theme_font_override("font", RetroUI.pixel_font())
                b.add_theme_font_size_override("font_size", 8)


## A deep-night pixel starfield, drawn once in code: two sizes of moon-white
## stars, a few electric blue and a few gold, scattered with a fixed seed so
## the sky is the same every boot — the arcade cabinet's backdrop.
func _add_starfield(bg: ColorRect) -> void:
        var w := 320
        var h := 180
        var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
        var rng := RandomNumberGenerator.new()
        rng.seed = 20250101
        for i in range(110):
                var x := rng.randi_range(0, w - 1)
                var y := rng.randi_range(0, h - 1)
                var roll := rng.randf()
                var col := Color(1, 1, 1, rng.randf_range(0.25, 0.85))
                if roll < 0.10:
                        col = Color(0.0, 0.635, 1.0, rng.randf_range(0.5, 0.9))
                elif roll < 0.18:
                        col = Color(0.96, 0.72, 0.24, rng.randf_range(0.45, 0.85))
                img.set_pixel(x, y, col)
                if roll > 0.93 and x < w - 1 and y < h - 1:
                        # a handful of 2-pixel bright stars
                        img.set_pixel(x + 1, y, Color(col.r, col.g, col.b, col.a * 0.55))
                        img.set_pixel(x, y + 1, Color(col.r, col.g, col.b, col.a * 0.55))
        var tex := ImageTexture.create_from_image(img)
        var stars := TextureRect.new()
        stars.texture = tex
        stars.stretch_mode = TextureRect.STRETCH_SCALE
        stars.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        stars.set_anchors_preset(Control.PRESET_FULL_RECT)
        stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bg.add_child(stars)


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
