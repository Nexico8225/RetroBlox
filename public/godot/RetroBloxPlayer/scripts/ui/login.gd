extends Control
## Login — v12.3 SIMPLE. One flat sky, one bold RETROBLOX wordmark, one
## clean card: username, password, the red Log In key. Nothing else —
## simple UI beats busy UI every time.
##
## LOG IN ONLY: the account-creation form is GONE (you asked). An
## account is made on the website, once — the player just signs you in.
## The FIRST login saves a session token on disk; every boot after that
## auto-signs in with zero typing. The server is LOCKED to the official
## RetroBlox platform — a label, not a field.
##
## The server answers with the site's SPECIFIC errors ("No account named
## X exists here yet" vs "Wrong password for X"), so a wrong password can
## never again read as a mystery.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VERSION := "1"

## the login palette (the site's own colors, quieted down)
const SKY := Color("63b3ec")              # the flat sky behind everything
const CARD_TOP := Color("ffffff")         # card face
const CARD_FRAME := Color("1e78c8")       # the 3px blue frame
const INK_HEAD := Color("1c3a52")         # the headline
const LABEL_INK := Color("43505c")        # the uppercase field labels
const WELL_EDGE := Color("b9c6d0")        # the well border
const INK := Color("1c2733")              # typed ink
const RED_TOP := Color("f0392f")          # the Log In key gradient
const RED_BOT := Color("b81b13")
const WORD_SHADOW := Color("a8231c")      # the wordmark's hard drop shadow

var _user: LineEdit
var _pass: LineEdit
var _err: PanelContainer
var _err_label: Label
var _info: Label
var _go: Button
var _offline: Button
var _working := false


func _ready() -> void:
        theme = RetroUI.shared
        RetroUI.apply_cursors()
        _build()
        _try_auto_login()


func _build() -> void:
        # ---- the stage: ONE flat sky — no photo, no noise ----
        var bg := ColorRect.new()
        bg.color = SKY
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bg)

        # ---- the column: wordmark on top, the card under it ----
        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)
        var col := VBoxContainer.new()
        col.alignment = BoxContainer.ALIGNMENT_CENTER
        col.add_theme_constant_override("separation", 10)
        center.add_child(col)

        # ---- THE WORDMARK — simple: bold white text, one hard shadow ----
        var word := Label.new()
        word.text = "RETROBLOX"
        word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        word.add_theme_font_override("font", RetroUI.gotham(800))
        word.add_theme_font_size_override("font_size", 44)
        word.add_theme_color_override("font_color", Color.WHITE)
        word.add_theme_color_override("font_shadow_color", WORD_SHADOW)
        word.add_theme_constant_override("shadow_offset_x", 3)
        word.add_theme_constant_override("shadow_offset_y", 4)
        col.add_child(word)

        var gap := Control.new()
        gap.custom_minimum_size = Vector2(0, 10)
        gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
        col.add_child(gap)

        # ---- THE CARD — one clean sheet with the blue frame ----
        var card := PanelContainer.new()
        card.custom_minimum_size = Vector2(400, 0)
        card.add_theme_stylebox_override("panel", _card_style())
        col.add_child(card)

        var body := VBoxContainer.new()
        body.add_theme_constant_override("separation", 13)
        card.add_child(body)

        var h1 := Label.new()
        h1.text = "Login and start having fun"
        h1.add_theme_font_override("font", RetroUI.gotham(800))
        h1.add_theme_font_size_override("font_size", 19)
        h1.add_theme_color_override("font_color", INK_HEAD)
        body.add_child(h1)

        # ---- USERNAME — the site's uppercase label + white well ----
        body.add_child(_field_label("USERNAME"))
        _user = LineEdit.new()
        _user.placeholder_text = "e.g. Nexico8225"
        _user.text = Api.saved_username   # remembered from last time
        _user.max_length = 20
        _user.custom_minimum_size = Vector2(0, 40)
        _style_well(_user)
        body.add_child(_user)

        # ---- PASSWORD ----
        body.add_child(_field_label("PASSWORD"))
        _pass = LineEdit.new()
        _pass.placeholder_text = "Password"
        _pass.secret = true
        _pass.custom_minimum_size = Vector2(0, 40)
        _style_well(_pass)
        body.add_child(_pass)

        # ---- THE ERROR BANNER — the site's AuthError, inside the card ----
        _err = PanelContainer.new()
        _err.add_theme_stylebox_override("panel", _error_style())
        _err.visible = false
        body.add_child(_err)
        _err_label = Label.new()
        _err_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _err_label.add_theme_font_override("font", RetroUI.gotham(600))
        _err_label.add_theme_font_size_override("font_size", 12)
        _err_label.add_theme_color_override("font_color", Color("ffd9d6"))
        _err.add_child(_err_label)

        # ---- THE RED LOG IN KEY — the site's exact gradient ----
        _go = Button.new()
        _go.text = "Log In"
        _go.custom_minimum_size = Vector2(0, 46)
        _go.focus_mode = Control.FOCUS_NONE
        _go.add_theme_stylebox_override("normal", _red_key())
        var red_hover := _red_key()
        red_hover.modulate_color = Color(1.06, 1.06, 1.06)
        _go.add_theme_stylebox_override("hover", red_hover)
        _go.add_theme_stylebox_override("pressed", _red_key())
        _go.add_theme_stylebox_override("hover_pressed", _red_key())
        _go.add_theme_font_override("font", RetroUI.gotham(700))
        _go.add_theme_font_size_override("font_size", 15)
        _go.add_theme_color_override("font_color", Color.WHITE)
        _go.add_theme_color_override("font_hover_color", Color.WHITE)
        _go.add_theme_color_override("font_pressed_color", Color.WHITE)
        _go.pressed.connect(_on_action)
        body.add_child(_go)

        # ---- quiet helper lines + the offline escape hatch ----
        _info = Label.new()
        _info.text = ""
        _info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _info.add_theme_font_override("font", RetroUI.gotham(400))
        _info.add_theme_font_size_override("font_size", 12)
        _info.add_theme_color_override("font_color", Color("5a6b7b"))
        body.add_child(_info)

        _offline = Button.new()
        _offline.text = "Can't connect — play offline instead"
        _offline.theme_type_variation = "BtnGhost"
        _offline.custom_minimum_size = Vector2(0, 30)
        _offline.visible = false
        _offline.pressed.connect(_on_offline)
        body.add_child(_offline)

        var footer := Label.new()
        footer.text = "Accounts live on retro-blox.vercel.app  ·  your avatar loads from your account"
        footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        footer.add_theme_font_override("font", RetroUI.gotham(400))
        footer.add_theme_font_size_override("font_size", 11)
        footer.add_theme_color_override("font_color", INK_HEAD)
        body.add_child(footer)

        # ---- under everything: the copyright line ----
        var legal := Label.new()
        legal.text = "RetroBlox Player v%s  ·  ©2006-2013 RetroBlox — not affiliated with Roblox" % VERSION
        legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        legal.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        legal.grow_vertical = Control.GROW_DIRECTION_BEGIN
        legal.offset_top = -30.0
        legal.offset_bottom = -14.0
        legal.offset_left = -420.0
        legal.offset_right = 420.0
        legal.add_theme_font_override("font", RetroUI.gotham(400))
        legal.add_theme_font_size_override("font_size", 11)
        legal.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
        add_child(legal)

        _user.text_submitted.connect(func(_t: String) -> void: _pass.grab_focus())
        _pass.text_submitted.connect(func(_t: String) -> void: _on_action())


## The card: white sheet, 3px blue frame, rounded 12, one deep shadow —
## the site's exact `border: 3px solid #1e78c8` read.
func _card_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = CARD_TOP
        sb.set_corner_radius_all(12)
        sb.anti_aliasing = true
        sb.set_border_width_all(3)
        sb.border_color = CARD_FRAME
        sb.shadow_color = Color(0.06, 0.2, 0.34, 0.4)
        sb.shadow_size = 24
        sb.shadow_offset = Vector2(0, 10)
        sb.content_margin_left = 30.0
        sb.content_margin_right = 30.0
        sb.content_margin_top = 24.0
        sb.content_margin_bottom = 26.0
        return sb


## The site's field label: tiny, uppercase, bold, quiet steel ink.
func _field_label(txt: String) -> Label:
        var l := Label.new()
        l.text = txt
        l.add_theme_font_override("font", RetroUI.gotham(700))
        l.add_theme_font_size_override("font_size", 11)
        l.add_theme_color_override("font_color", LABEL_INK)
        return l


## The white wells: white face, gray 2px border, ink caret, blue focus ring —
## the site's INPUT style to the pixel.
func _style_well(w: LineEdit) -> void:
        var normal := StyleBoxFlat.new()
        normal.bg_color = Color.WHITE
        normal.set_corner_radius_all(8)
        normal.set_border_width_all(2)
        normal.border_color = WELL_EDGE
        normal.content_margin_left = 12.0
        normal.content_margin_right = 12.0
        normal.content_margin_top = 8.0
        normal.content_margin_bottom = 8.0
        var focus := normal.duplicate() as StyleBoxFlat
        focus.border_color = CARD_FRAME
        focus.set_border_width_all(2)
        w.add_theme_stylebox_override("normal", normal)
        w.add_theme_stylebox_override("focus", focus)
        w.add_theme_color_override("font_color", INK)
        w.add_theme_color_override("font_placeholder_color", Color(LABEL_INK, 0.6))
        w.add_theme_color_override("caret_color", CARD_FRAME)
        w.add_theme_color_override("selection_color", Color(CARD_FRAME, 0.25))
        if RetroUI.gotham(400) != null:
                w.add_theme_font_override("font", RetroUI.gotham(400))
        w.add_theme_font_size_override("font_size", 14)


## The RED Log In key — the site's exact gradient (#f0392f → #b81b13).
func _red_key() -> StyleBoxTexture:
        return RetroUI.gloss(RED_TOP, RED_BOT, RED_BOT.darkened(0.3), 8)


## The error banner — the site's AuthError read, docked inside the card.
func _error_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("2a0f0d")
        sb.set_corner_radius_all(8)
        sb.set_border_width_all(1)
        sb.border_color = Color("ff6259")
        sb.content_margin_left = 12.0
        sb.content_margin_right = 12.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        return sb


func _show_error(text: String) -> void:
        _err_label.text = text
        _err.visible = text != ""


func _set_info(text: String) -> void:
        _info.text = text


## Auto sign-in on boot: the saved token (180-day server-side TTL) brings
## the whole account back. The token is ONLY wiped when the server itself
## says it is invalid (401) — a Wi-Fi hiccup never logs you out.
func _try_auto_login() -> void:
        if Api.token == "":
                return
        _working = true
        _set_info("Logging you in…")
        var me: Dictionary = await Api.get_me()
        _working = false
        if me.get("ok", false):
                _finish_login(me)
                return
        if int(me.get("status", 0)) == 401:
                Api.clear_session()
                _set_info("Your session expired — log in one more time.")
        else:
                # offline: KEEP the token, offer offline play, retry works
                _offline.visible = true
                _set_info("Could not reach RetroBlox just now. Your saved session was kept — check your internet and press LOG IN to retry.")


func _on_action() -> void:
        if _working:
                return
        var uname := _user.text.strip_edges()
        var pwd := _pass.text
        if uname == "" or pwd == "":
                _show_error("Write your username and password first!")
                return
        _working = true
        _go.disabled = true
        _offline.visible = false
        _show_error("")
        _set_info("Talking to RetroBlox…")
        var res: Dictionary = await Api.login(uname, pwd)
        _working = false
        _go.disabled = false
        if not res.get("ok", false):
                # the server's OWN words — "No account named X exists here
                # yet" vs "Wrong password for X" — land here verbatim
                _show_error(String(res.get("error", "Could not reach RetroBlox.")))
                _set_info("")
                # network dead? show the offline hatch (401-style answers keep it hidden)
                if not res.has("status"):
                        _offline.visible = true
                return
        Api.token = String(res.get("token", ""))
        Api.save_session(uname)   # log in once — remembered from now on
        _set_info("Welcome back, %s…" % uname)
        var me: Dictionary = await Api.get_me()
        if me.get("ok", false):
                _finish_login(me)
        else:
                _show_error("Signed in, but the avatar fetch failed — try again.")


func _finish_login(me: Dictionary) -> void:
        # Api.txt everywhere: role can arrive as JSON null, and String(null)
        # hard-crashes with "Invalid call 'String' constructor"
        Session.sign_in(me, Api.txt(me.get("userId", "")), Api.txt(me.get("username", ""), "Player"),
                Api.txt(me.get("role", ""), "user"))
        # sign in and you are instantly playing the classic baseplate
        get_tree().change_scene_to_file("res://scenes/game.tscn")


## Last resort when the platform is unreachable: classic noob, offline chat.
func _on_offline() -> void:
        if _working:
                return
        Session.set_guest()
        get_tree().change_scene_to_file("res://scenes/game.tscn")
