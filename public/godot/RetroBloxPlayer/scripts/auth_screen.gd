# RetrobloxAuthScreen — the door into RetroBlox, drawn inside the game.
#
# The card itself lives in scenes/auth_screen.tscn — open it in the editor to
# restyle the login UI visually. This script keeps the behavior: what happens
# when you log in or play as a guest.
#
#   LOG IN   — existing accounts (username + password). Accounts are created
#              on retro-blox.vercel.app; the game only logs you in. There is
#              NO server textbox — the website URL is baked in below (main.gd
#              can still override it for self-hosts via RETROBLOX_API/--api=).
#   GUEST    — play without an account (classic noob colors, "Guest-1234")
# Remembers the last username; a saved token auto-signs-in instantly.
class_name RetrobloxAuthScreen
extends CanvasLayer

# Referenced by FILE PATH, not by global class name — parses correctly on the
# very first open, even before Godot registers global class_names.
const RetrobloxApiScript := preload("res://scripts/retroblox_api.gd")

# The one and only RetroBlox website this build logs into.
const DEFAULT_API_URL := "https://retro-blox.vercel.app"

signal completed(api, username: String, user_id: String, avatar: Dictionary)
signal guest_requested

# unique names inside scenes/auth_screen.tscn
@onready var _user_edit: LineEdit = %UserEdit
@onready var _pass_edit: LineEdit = %PassEdit
@onready var _submit_btn: Button = %SubmitBtn
@onready var _status: Label = %Status

var _api_url: String = DEFAULT_API_URL
var _busy := false


func _ready() -> void:
        _submit_btn.pressed.connect(_submit)
        %GuestBtn.pressed.connect(_guest_pressed)
        for edit: LineEdit in [_user_edit, _pass_edit]:
                edit.text_submitted.connect(_on_field_submitted)
        # UI sounds — the players are nodes under UISounds in the scene
        _submit_btn.pressed.connect(_sfx.bind("ClickSound", 1.0))
        %GuestBtn.pressed.connect(_sfx.bind("ClickSound", 1.0))
        _submit_btn.mouse_entered.connect(_sfx.bind("HoverSound", 1.0))
        %GuestBtn.mouse_entered.connect(_sfx.bind("HoverSound", 1.0))
        # straight into the username field, classic client style
        _user_edit.grab_focus.call_deferred()


## Fire one of the AudioStreamPlayer nodes under UISounds. Missing node or
## stream = silent no-op, so trimming the scene never breaks the login.
func _sfx(sfx_name: String, pitch: float = 1.0) -> void:
        var player := get_node_or_null("UISounds/" + sfx_name) as AudioStreamPlayer
        if player == null or player.stream == null:
                return
        player.pitch_scale = pitch
        player.play()


func _guest_pressed() -> void:
        if not _busy:
                guest_requested.emit()


func _on_field_submitted(_text: String) -> void:
        _submit()


## Which website to log into. There is no textbox on the card on purpose —
## players can't point the client somewhere else by accident. main.gd may
## still pass a self-host URL here (RETROBLOX_API env or --api= flag).
func set_api_url(url: String) -> void:
        if not url.is_empty():
                _api_url = url.strip_edges().trim_suffix("/")


func set_saved_username(username: String) -> void:
        if _user_edit != null and not username.is_empty():
                _user_edit.text = username


## Neutral status line (used by the silent saved-token sign-in).
func set_status_text(text: String) -> void:
        _status.text = text


func _error(text: String) -> void:
        _status.add_theme_color_override("font_color", Color(0.7, 0.12, 0.1))
        _status.text = text
        _sfx("DenySound", randf_range(0.96, 1.04))
        _busy = false
        _submit_btn.disabled = false


func _submit() -> void:
        if _busy:
                return
        var user := _user_edit.text.strip_edges()
        var passw := _pass_edit.text
        if user.is_empty() or passw.is_empty():
                _error("Fill in your username and password.")
                return

        _busy = true
        _submit_btn.disabled = true
        _status.add_theme_color_override("font_color", Color(0.2, 0.3, 0.45))
        _status.text = "Signing in…"

        var api := RetrobloxApiScript.new(_api_url)
        var res: Dictionary = await api.login(user, passw)
        if not res.get("ok", false):
                var msg := String(res.get("error", "Could not reach the server"))
                # the most common stall, answered right on the card: accounts are
                # made on the website, not in the game
                if msg.contains("Incorrect username or password"):
                        msg += "\nNo account yet? Create one free at %s — then log in here." % _api_url.replace("https://", "")
                _error(msg)
                return

        _status.text = "Welcome, %s — loading your avatar…" % String(res.get("username", user))
        var me: Dictionary = await api.get_me()
        if not me.get("ok", false):
                _error(String(me.get("error", "Could not load the avatar")))
                return

        _status.text = "Ready!"
        _sfx("SuccessSound")
        var av = me.get("avatar", {})
        # main.gd takes the baton here: it saves the token, dismisses THIS card
        # and spawns you wearing the account avatar. The card also hides itself
        # right after the signal — a stuck "Ready!" card can never freeze the
        # game again, even if a future refactor forgets the dismissal.
        completed.emit(api, String(me.get("username", api.username)), String(me.get("userId", api.user_id)), av if av is Dictionary else {})
        visible = false
