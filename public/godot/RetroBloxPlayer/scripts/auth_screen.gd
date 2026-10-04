# RetrobloxAuthScreen — the door into RetroBlox, drawn inside the game.
#
# The card itself lives in scenes/auth_screen.tscn — open it in the editor to
# restyle the login UI visually. This script keeps the behavior: what happens
# when you log in or sign up.
#
#   LOG IN  — existing accounts (username + password)
#   SIGN UP — create a brand-new account without ever opening the website;
#             the fresh account's avatar loads immediately via /api/platform/me
# LOGIN ONLY — there is no guest mode: your RetroBlox account IS your player,
# and the multiplayer heartbeat is authenticated with your session token.
# Remembers the last username; a saved token auto-signs-in instantly.
class_name RetrobloxAuthScreen
extends CanvasLayer

# Referenced by FILE PATH, not by global class name — parses correctly on the
# very first open, even before Godot registers global class_names.
const RetrobloxApiScript := preload("res://scripts/retroblox_api.gd")

signal completed(api, username: String, user_id: String, avatar: Dictionary)

const RED := Color("e2231a")
const GREEN := Color("02b757")
const INK := Color("1b2a34")
const MUTED := Color("6b7c86")
const LINK := Color("0d69ac")

# unique names inside scenes/auth_screen.tscn
@onready var _server_edit: LineEdit = %ServerEdit
@onready var _user_edit: LineEdit = %UserEdit
@onready var _pass_edit: LineEdit = %PassEdit
@onready var _confirm_edit: LineEdit = %ConfirmEdit
@onready var _confirm_label: Label = %ConfirmLabel
@onready var _submit_btn: Button = %SubmitBtn
@onready var _status: Label = %Status
@onready var _login_tab_btn: Button = %LoginTabBtn
@onready var _signup_tab_btn: Button = %SignupTabBtn

var _signup_mode := false
var _busy := false


func _ready() -> void:
        _login_tab_btn.pressed.connect(_set_mode.bind(false))
        _signup_tab_btn.pressed.connect(_set_mode.bind(true))
        _submit_btn.pressed.connect(_submit)
        for edit: LineEdit in [_server_edit, _user_edit, _pass_edit, _confirm_edit]:
                edit.text_submitted.connect(_on_field_submitted)
        _set_mode(false)


func _on_field_submitted(_text: String) -> void:
        _submit()


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
                server = "https://retro-blox.vercel.app"
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

        var api := RetrobloxApiScript.new(server)

        var res: Dictionary
        if _signup_mode:
                res = await api.signup(user, passw)
        else:
                res = await api.login(user, passw)
        if not res.get("ok", false):
                var msg := String(res.get("error", "Could not reach the server"))
                # help with the two most common stalls — a 401 usually means
                # "no account yet" or "typo in the password"
                if msg.contains("Incorrect username or password"):
                        msg += "\nNo account yet? Use the Sign Up tab — accounts made on the website work here too."
                _error(msg)
                return

        _status.text = "Welcome, %s — loading your avatar…" % String(res.get("username", user))
        var me: Dictionary = await api.get_me()
        if not me.get("ok", false):
                _error(String(me.get("error", "Could not load the avatar")))
                return

        _status.text = "Ready!"
        var av = me.get("avatar", {})
        completed.emit(api, String(me.get("username", api.username)), String(me.get("userId", api.user_id)), av if av is Dictionary else {})
