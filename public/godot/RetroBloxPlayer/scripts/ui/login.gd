extends Control
## Login — the front door of the new player. Log in, sign up, or play as a
## guest. The server is LOCKED to the official RetroBlox platform: it is a
## label, not a field, so it can never be pointed somewhere else.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VERSION := "2.0"

var _mode := "login"   # login | signup
var _user: LineEdit
var _pass: LineEdit
var _action: Button
var _status: Label
var _go: Button
var _guest: Button
var _tab_login: Button
var _tab_signup: Button
var _working := false


func _ready() -> void:
        theme = RetroUI.shared
        _build()
        _try_auto_login()


func _build() -> void:
        var bg := ColorRect.new()
        bg.color = RetroUI.BG
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bg)

        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)

        var card := PanelContainer.new()
        card.custom_minimum_size = Vector2(430, 0)
        center.add_child(card)

        var box := VBoxContainer.new()
        box.add_theme_constant_override("separation", 8)
        box.custom_minimum_size = Vector2(380, 0)
        card.add_child(box)

        # header band
        var head := PanelContainer.new()
        head.theme_type_variation = "SteelHeader"
        box.add_child(head)
        var head_label := Label.new()
        head_label.text = "RETROBLOX"
        head_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        head_label.theme_type_variation = "H1"
        head_label.add_theme_color_override("font_color", RetroUI.TEXT_INV)
        head.add_child(head_label)

        var sub := Label.new()
        sub.text = "the classic player — v%s" % VERSION
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.theme_type_variation = "Muted"
        box.add_child(sub)

        # mode tabs
        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 8)
        tabs.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_child(tabs)
        _tab_login = Button.new()
        _tab_login.text = "LOG IN"
        _tab_login.toggle_mode = true
        _tab_login.custom_minimum_size = Vector2(150, 34)
        _tab_login.pressed.connect(func() -> void: _set_mode("login"))
        tabs.add_child(_tab_login)
        _tab_signup = Button.new()
        _tab_signup.text = "SIGN UP"
        _tab_signup.toggle_mode = true
        _tab_signup.custom_minimum_size = Vector2(150, 34)
        _tab_signup.pressed.connect(func() -> void: _set_mode("signup"))
        tabs.add_child(_tab_signup)

        _user = LineEdit.new()
        _user.placeholder_text = "Username"
        _user.custom_minimum_size = Vector2(0, 36)
        box.add_child(_user)

        _pass = LineEdit.new()
        _pass.placeholder_text = "Password"
        _pass.secret = true
        _pass.custom_minimum_size = Vector2(0, 36)
        box.add_child(_pass)

        _go = Button.new()
        _go.text = "LOG IN"
        _go.theme_type_variation = "BtnGreen"
        _go.custom_minimum_size = Vector2(0, 46)
        _go.pressed.connect(_on_action)
        box.add_child(_go)

        var or_label := Label.new()
        or_label.text = "— or —"
        or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        or_label.theme_type_variation = "Muted"
        box.add_child(or_label)

        _guest = Button.new()
        _guest.text = "PLAY AS GUEST"
        _guest.theme_type_variation = "BtnBlue"
        _guest.custom_minimum_size = Vector2(0, 38)
        _guest.pressed.connect(_on_guest)
        box.add_child(_guest)

        _status = Label.new()
        _status.text = ""
        _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _status.custom_minimum_size = Vector2(0, 44)
        _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        box.add_child(_status)

        var footer := Label.new()
        footer.text = "Server: retro-blox.vercel.app  ·  locked  ·  your avatar loads from your account"
        footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        footer.theme_type_variation = "Small"
        footer.add_theme_color_override("font_color", RetroUI.TEXT_MUTED)
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


func _set_status(text: String, is_error := true) -> void:
        _status.text = text
        _status.add_theme_color_override("font_color", RetroUI.RED if is_error else RetroUI.GREEN_DARK)


func _try_auto_login() -> void:
        if Api.token == "":
                return
        _working = true
        _set_status("Signing you in…", false)
        var me: Dictionary = await Api.get_me()
        _working = false
        if me.get("ok", false):
                _finish_login(me)
        else:
                Api.clear_session()
                _set_status("")


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
                return
        Api.token = String(res.get("token", ""))
        Api.save_session()
        var me: Dictionary = await Api.get_me()
        if me.get("ok", false):
                _finish_login(me)
        else:
                _set_status("Signed in, but the avatar fetch failed — try again.")


func _finish_login(me: Dictionary) -> void:
        Session.sign_in(me, String(me["userId"]), String(me["username"]), String(me.get("role", "user")))
        get_tree().change_scene_to_file("res://scenes/hub.tscn")


func _on_guest() -> void:
        if _working:
                return
        Session.set_guest()
        get_tree().change_scene_to_file("res://scenes/hub.tscn")
