# RetrobloxAuthScreen — the door into RetroBlox, drawn inside the game.
#
# 2016-style: blue sky, white card, red RETROBLOX wordmark.
#   LOG IN   — existing accounts (username + password)
#   SIGN UP  — create a brand-new account without ever opening the website;
#              the fresh account's avatar loads immediately via /api/platform/me
#   GUEST    — play without an account (classic noob colors, "Guest-1234")
# Remembers the last username; a saved token auto-signs-in instantly.
class_name RetrobloxAuthScreen
extends CanvasLayer

signal completed(api: RetrobloxApi, username: String, user_id: String, avatar: Dictionary)
signal guest_requested

const RED := Color("e2231a")
const GREEN := Color("02b757")
const INK := Color("1b2a34")
const MUTED := Color("6b7c86")
const LINK := Color("0d69ac")

var _server_edit: LineEdit
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _confirm_edit: LineEdit
var _confirm_label: Label
var _submit_btn: Button
var _status: Label
var _signup_mode := false
var _busy := false


func _ready() -> void:
        layer = 30
        _build()


func _build() -> void:
        var root := Control.new()
        root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        root.mouse_filter = Control.MOUSE_FILTER_STOP
        add_child(root)

        # summer-sky gradient, like the classic login page
        var sky := TextureRect.new()
        sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        var gradient := Gradient.new()
        gradient.colors = PackedColorArray([
                Color("2f8fd6"), Color("6db9e8"), Color("a8d8f0"), Color("8cc571"),
        ])
        gradient.offsets = PackedFloat32Array([0.0, 0.42, 0.62, 1.0])
        var gradient_tex := GradientTexture2D.new()
        gradient_tex.gradient = gradient
        gradient_tex.fill_from = Vector2(0, 0)
        gradient_tex.fill_to = Vector2(0, 1)
        sky.texture = gradient_tex
        sky.stretch_mode = TextureRect.STRETCH_SCALE
        root.add_child(sky)

        var center := CenterContainer.new()
        center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        root.add_child(center)

        var card := PanelContainer.new()
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.97, 0.98, 0.99)
        style.border_color = Color("0d69ac")
        style.set_border_width_all(2)
        style.set_corner_radius_all(10)
        style.content_margin_left = 26
        style.content_margin_right = 26
        style.content_margin_top = 20
        style.content_margin_bottom = 20
        card.add_theme_stylebox_override("panel", style)
        center.add_child(card)

        var box := VBoxContainer.new()
        box.custom_minimum_size = Vector2(380, 0)
        box.add_theme_constant_override("separation", 8)
        card.add_child(box)

        var logo := Label.new()
        logo.text = "RETROBLOX"
        logo.add_theme_font_size_override("font_size", 34)
        logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        logo.add_theme_color_override("font_color", RED)
        box.add_child(logo)

        var sub := Label.new()
        sub.text = "Sign in to wear your account avatar"
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.add_theme_font_size_override("font_size", 12)
        sub.add_theme_color_override("font_color", MUTED)
        box.add_child(sub)

        box.add_child(_spacer(6))

        # --- log in / sign up tabs ---
        var tabs := HBoxContainer.new()
        tabs.add_theme_constant_override("separation", 8)
        tabs.alignment = BoxContainer.ALIGNMENT_CENTER
        box.add_child(tabs)
        _login_tab_btn = Button.new()
        _login_tab_btn.text = "Log In"
        _login_tab_btn.custom_minimum_size = Vector2(150, 34)
        _signup_tab_btn = Button.new()
        _signup_tab_btn.text = "Sign Up"
        _signup_tab_btn.custom_minimum_size = Vector2(150, 34)
        tabs.add_child(_login_tab_btn)
        tabs.add_child(_signup_tab_btn)
        _login_tab_btn.pressed.connect(func(): _set_mode(false))
        _signup_tab_btn.pressed.connect(func(): _set_mode(true))

        box.add_child(_spacer(4))

        _server_edit = _add_field(box, "RetroBlox website", "")
        _user_edit = _add_field(box, "Username", "")
        _pass_edit = _add_field(box, "Password", "")
        _pass_edit.secret = true
        _confirm_label = Label.new()
        _confirm_label.text = "Confirm password"
        _confirm_label.add_theme_font_size_override("font_size", 11)
        _confirm_label.add_theme_color_override("font_color", MUTED)
        box.add_child(_confirm_label)
        _confirm_edit = LineEdit.new()
        _confirm_edit.secret = true
        _confirm_edit.custom_minimum_size = Vector2(0, 30)
        box.add_child(_confirm_edit)

        _submit_btn = Button.new()
        _submit_btn.text = "Log In"
        _submit_btn.custom_minimum_size = Vector2(0, 38)
        _submit_btn.pressed.connect(_submit)
        box.add_child(_submit_btn)

        _status = Label.new()
        _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _status.add_theme_font_size_override("font_size", 11)
        _status.add_theme_color_override("font_color", Color(0.7, 0.12, 0.1))
        box.add_child(_status)

        var guest_btn := Button.new()
        guest_btn.text = "Play as Guest instead"
        guest_btn.flat = true
        guest_btn.add_theme_color_override("font_color", LINK)
        guest_btn.add_theme_font_size_override("font_size", 12)
        guest_btn.pressed.connect(func():
                if not _busy:
                        guest_requested.emit()
        )
        box.add_child(guest_btn)

        var hint := Label.new()
        hint.text = "Your avatar is saved to your RetroBlox account —\nit follows you into every game."
        hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        hint.add_theme_font_size_override("font_size", 10)
        hint.add_theme_color_override("font_color", MUTED)
        box.add_child(hint)

        _set_mode(false)


var _login_tab_btn: Button
var _signup_tab_btn: Button


func _set_mode(signup: bool) -> void:
        _signup_mode = signup
        _submit_btn.text = "Create Account" if signup else "Log In"
        _confirm_label.visible = signup
        _confirm_edit.visible = signup
        _style_tab(_login_tab_btn, not signup)
        _style_tab(_signup_tab_btn, signup)


func _style_tab(button: Button, active: bool) -> void:
        var style := StyleBoxFlat.new()
        style.bg_color = GREEN if active else Color("e4eaee")
        style.set_corner_radius_all(6)
        style.content_margin_top = 6
        style.content_margin_bottom = 6
        button.add_theme_stylebox_override("normal", style)
        var hover := style.duplicate() as StyleBoxFlat
        hover.bg_color = GREEN.lightened(0.12) if active else Color("d5dee4")
        button.add_theme_stylebox_override("hover", hover)
        button.add_theme_stylebox_override("pressed", style)
        button.add_theme_color_override("font_color", Color.WHITE if active else INK)


func _add_field(parent: Control, label_text: String, value: String) -> LineEdit:
        var lab := Label.new()
        lab.text = label_text
        lab.add_theme_font_size_override("font_size", 11)
        lab.add_theme_color_override("font_color", MUTED)
        parent.add_child(lab)
        var edit := LineEdit.new()
        edit.text = value
        edit.custom_minimum_size = Vector2(0, 30)
        edit.text_submitted.connect(func(_t: String) -> void: _submit())
        parent.add_child(edit)
        return edit


func _spacer(h: float) -> Control:
        var c := Control.new()
        c.custom_minimum_size = Vector2(0, h)
        return c


## Pre-fill from config / a previous session.
func set_api_url(url: String) -> void:
        if _server_edit != null:
                _server_edit.text = url

func set_saved_username(username: String) -> void:
        if _user_edit != null:
                _user_edit.text = username

## Neutral status line (used by the silent saved-token sign-in).
func set_status_text(text: String) -> void:
        _status.text = text


func _error(text: String) -> void:
        _status.add_theme_color_override("font_color", Color(0.7, 0.12, 0.1))
        _status.text = text
        _busy = false
        _submit_btn.disabled = false


func _submit() -> void:
        if _busy:
                return
        var server := _server_edit.text.strip_edges()
        var user := _user_edit.text.strip_edges()
        var passw := _pass_edit.text
        if server == "":
                server = "http://localhost:3000"
        if not server.begins_with("http"):
                server = "http://" + server
        if user.is_empty() or passw.is_empty():
                _error("Fill in your username and password.")
                return
        if _signup_mode:
                if _confirm_edit.text != passw:
                        _error("The passwords do not match.")
                        return
                if user.length() < 3 or user.length() > 20:
                        _error("Usernames are 3-20 characters.")
                        return
                if passw.length() < 3:
                        _error("Passwords are at least 3 characters.")
                        return

        _busy = true
        _submit_btn.disabled = true
        _status.add_theme_color_override("font_color", Color(0.2, 0.3, 0.45))
        _status.text = "Creating your account…" if _signup_mode else "Signing in…"

        var api := RetrobloxApi.new(server)

        var res: Dictionary
        if _signup_mode:
                res = await api.signup(user, passw)
        else:
                res = await api.login(user, passw)
        if not res.get("ok", false):
                _error(String(res.get("error", "Could not reach the server")))
                return

        _status.text = "Welcome, %s — loading your avatar…" % String(res.get("username", user))
        var me: Dictionary = await api.get_me()
        if not me.get("ok", false):
                _error(String(me.get("error", "Could not load the avatar")))
                return

        _status.text = "Ready!"
        var av = me.get("avatar", {})
        completed.emit(api, String(me.get("username", api.username)), String(me.get("userId", api.user_id)), av if av is Dictionary else {})
