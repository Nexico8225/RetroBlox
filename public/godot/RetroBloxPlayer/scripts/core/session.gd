extends Node
## Session — who is playing right now (autoload "Session").
##
## Three ways to be in the player:
##   1. signed in  — a real RetroBlox account, avatar loads from the platform
##   2. guest      — classic noob colors, a random Guest number, read-only chat
##   3. (nobody)   — before login, never after boot (auto-login handles it)

var is_guest := true
var user_id := ""
var username := "Guest"
var seq_id := 0
var role := ""
var avatar: Dictionary = {}        # own /api/platform/me payload ({} for guests)
var avatar_cache: Dictionary = {}  # userId -> avatar payload (remote players)
var current_place: Dictionary = {} # the PlaceDef picked in the hub


func sign_in(payload: Dictionary, p_user_id: String, p_username: String, p_role: String) -> void:
        is_guest = false
        user_id = p_user_id
        username = p_username
        role = p_role
        avatar = payload
        avatar_cache = { p_user_id: payload }


func set_guest() -> void:
        is_guest = true
        user_id = ""
        username = "Guest %d" % randi_range(1000, 9999)
        role = ""
        avatar = {}
        current_place = {}


func reset() -> void:
        set_guest()
        avatar_cache = {}


## Cache another player's avatar payload so re-entering places is instant.
func cache_avatar(p_user_id: String, payload: Dictionary) -> void:
        avatar_cache[p_user_id] = payload


func cached_avatar(p_user_id: String) -> Dictionary:
        var hit: Variant = avatar_cache.get(p_user_id, {})
        return hit if hit is Dictionary else {}


## The name chip shown in the hub + player list: "Nexico8225 #1".
func display_tag() -> String:
        if is_guest or seq_id <= 0:
                return username
        return "%s #%d" % [username, seq_id]


## The avatar data blob this client should render for ME.
func my_avatar_data() -> Dictionary:
        if is_guest:
                return {}
        var a: Variant = avatar.get("avatar", {})
        return a if a is Dictionary else {}
