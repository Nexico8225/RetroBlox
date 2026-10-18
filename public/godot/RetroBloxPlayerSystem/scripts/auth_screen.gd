# RetrobloxAuthScreen — the door into RetroBlox, drawn inside the game.
#
# The card lives in scenes/auth_screen.tscn — open it in the editor to
# restyle the login UI visually. This script keeps the behavior:
#
#   LOG IN   — existing accounts (username + password). Accounts are made
#              on retro-blox.vercel.app; the platform URL is BAKED IN.
#   GUEST    — play without an account (classic noob colors, "Guest-1234").
#
# Remembers the last username; a saved token auto-signs-in instantly.
# IMPORTANT: this script must match the scene EXACTLY — the unique nodes
# are %UserEdit, %PassEdit, %SubmitBtn, %Status, %GuestBtn (login-only card,
# no server box, no sign-up tab). Referencing nodes the scene does not have
# crashes _ready and leaves the player frozen on this card forever.
class_name RetrobloxAuthScreen
extends CanvasLayer

# Referenced by FILE PATH, not by global class name — parses correctly on the
# very first open, even before Godot registers global class_names.
const RetrobloxApiScript := preload("res://scripts/retroblox_api.gd")

signal completed(api, username: String, user_id: String, avatar: Dictionary)
signal guest_requested
signal watchdog_expired

const RED := Color(0.7, 0.12, 0.1)
const BUSY := Color(0.2, 0.3, 0.45)

# the ONE platform, baked in. Override for self-hosts via RETROBLOX_API
# or --api= (main.gd forwards it here through set_api_url).
var _api_url := "https://retro-blox.vercel.app"
var _busy := false

# unique names inside scenes/auth_screen.tscn
@onready var _user_edit: LineEdit = %UserEdit
@onready var _pass_edit: LineEdit = %PassEdit
@onready var _submit_btn: Button = %SubmitBtn
@onready var _status: Label = %Status
@onready var _guest_btn: Button = %GuestBtn


func _ready() -> void:
        _submit_btn.pressed.connect(_submit)
        _guest_btn.pressed.connect(_guest_pressed)
        for edit: LineEdit in [_user_edit, _pass_edit]:
                edit.text_submitted.connect(_on_field_submitted)
        for button: Button in [_submit_btn, _guest_btn]:
                button.mouse_entered.connect(_on_hover)
                button.pressed.connect(_on_click)
        # the classic entrance: the card fades/pops in
        var anim := get_node_or_null("UIAnim") as AnimationPlayer
        if anim != null and anim.has_animation("card_in"):
                anim.play("card_in")


# ---------------------------------------------------------------- ui feedback

func _on_hover() -> void:
        _play("HoverSound")


func _on_click() -> void:
        _play("ClickSound")


func _play(sound_name: String) -> void:
        var node := get_node_or_null("UISounds/" + sound_name) as AudioStreamPlayer
        if node != null and node.stream != null:
                node.play()


func _error(text: String) -> void:
        _status.add_theme_color_override("font_color", RED)
        _status.text = text
        _busy = false
        _submit_btn.disabled = false
        _play("DenySound")


# ---------------------------------------------------------------- public api

## The platform the card signs in to (main.gd forwards the baked URL).
func set_api_url(url: String) -> void:
        if not url.is_empty():
                _api_url = url

## Pre-fill from a previous session.
func set_saved_username(username: String) -> void:
        if _user_edit != null:
                _user_edit.text = username

## Neutral status line (used by the silent saved-token sign-in).
func set_status_text(text: String) -> void:
        _status.text = text


# ---------------------------------------------------------------- flow

func _guest_pressed() -> void:
        if not _busy:
                _play("ClickSound")
                guest_requested.emit()


func _on_field_submitted(_text: String) -> void:
        _submit()


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
        _status.add_theme_color_override("font_color", BUSY)
        _status.text = "Signing in…"

        var api := RetrobloxApiScript.new(_api_url)
        var res: Dictionary = await api.login(user, passw)
        if not res.get("ok", false):
                var msg := String(res.get("error", "Could not reach the server"))
                # help with the two most common stalls — a 401 usually means
                # "no account yet" or "typo in the password"
                if msg.contains("Incorrect username or password"):
                        msg += "\nNo account yet? Create one free on retro-blox.vercel.app, then log in here."
                _error(msg)
                return

        _status.text = "Welcome, %s — loading your avatar…" % String(res.get("username", user))
        var me: Dictionary = await api.get_me()
        if not me.get("ok", false):
                _error(String(me.get("error", "Could not load the avatar")))
                return

        _status.text = "Ready!"
        _play("SuccessSound")
        var av = me.get("avatar", {})
        completed.emit(api, String(me.get("username", api.username)), String(me.get("userId", api.user_id)), av if av is Dictionary else {})
        _arm_watchdog()


## Last-resort handoff guard: the moment "Ready!" shows, the game has one
## second to take over and close this card. If the card is somehow still on
## screen (a lost signal, a handler that bailed), we shout watchdog_expired
## and main.gd forces the game to start. Nobody waits on a frozen login.
func _arm_watchdog() -> void:
        var timer := get_tree().create_timer(1.0)
        timer.timeout.connect(_fire_watchdog)


func _fire_watchdog() -> void:
        if is_inside_tree() and visible:
                watchdog_expired.emit()
