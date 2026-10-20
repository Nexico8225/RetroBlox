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
# ---- v15.0 ROLES: players play, GAME DEVS edit ---------------------------
# A GAME DEV = a signed-in user who owns at least one game on the platform
# (any engine counts — a Web game works too). Publishing your first game
# flips this on; the Studio doors and the F2 UI editor open for devs only.
signal dev_ready(is_dev: bool)
var is_dev := false            # resolved by check_dev() — one GET per session
var _dev_checked := false
var avatar: Dictionary = {}        # own /api/platform/me payload ({} for guests)
var avatar_cache: Dictionary = {}  # userId -> avatar payload (remote players)
var current_place: Dictionary = {} # legacy hub pick — empty now: login drops you straight into baseplate
var server_ui_game := ""       # v6.0: the game id whose PUBLISHED UI to fetch (set when a .retroplace with "gameId" opens)


func sign_in(payload: Dictionary, p_user_id: String, p_username: String, p_role: String, p_seq: int = 0) -> void:
        is_guest = false
        user_id = p_user_id
        username = p_username
        role = p_role
        seq_id = p_seq
        # v10.0: sanitize JSON nulls up front — the platform sends
        # "avatarUrl": null for accounts without a site PFP, and Dictionary.get
        # returns that stored null (not the default), which String() can't take
        avatar = _nullless(payload)
        avatar_cache = { p_user_id: _nullless(payload) }
        _dev_checked = false          # a new account — re-ask what it can edit
        is_dev = false


## Deep-copy a JSON payload with every null replaced by "" — recursive, so
## nested dicts (the "avatar" blob) are covered too.
func _nullless(src: Dictionary) -> Dictionary:
        var out: Dictionary = {}
        for k in src.keys():
                var v: Variant = src[k]
                if v == null:
                        out[k] = ""
                elif v is Dictionary:
                        out[k] = _nullless(v)
                elif v is Array:
                        var arr: Array = []
                        for item in v:
                                if item == null:
                                        arr.append("")
                                elif item is Dictionary:
                                        arr.append(_nullless(item))
                                else:
                                        arr.append(item)
                        out[k] = arr
                else:
                        out[k] = v
        return out


func set_guest() -> void:
        is_guest = true
        user_id = ""
        username = "Guest %d" % randi_range(1000, 9999)
        role = ""
        avatar = {}
        current_place = {}
        _dev_checked = true           # guests are players, never game devs
        is_dev = false


func reset() -> void:
        set_guest()
        avatar_cache = {}


## Cache another player's avatar payload so re-entering places is instant.
## v12.3: callers now store the INNER avatar data (colors/body/shirt/...)
## — the shape the dresser and the portrait renderer read directly.
func cache_avatar(p_user_id: String, payload: Dictionary) -> void:
        avatar_cache[p_user_id] = _nullless(payload)


## v10.0: set MY avatar payload (null-sanitized) — used by game.gd when the
## /me payload refreshes mid-session. v12.3: the per-user cache holds the
## INNER avatar data too, so cached_avatar(uid) always dresses directly.
func set_avatar(payload: Dictionary) -> void:
        avatar = _nullless(payload)
        if user_id != "":
                var inner: Variant = avatar.get("avatar", null)
                avatar_cache[user_id] = _nullless(inner if inner is Dictionary else {})


func cached_avatar(p_user_id: String) -> Dictionary:
        var hit: Variant = avatar_cache.get(p_user_id, {})
        return hit if hit is Dictionary else {}


## Ask the platform whether this account is a GAME DEV (owns >= 1 game).
## One GET per session — every later caller gets the cached answer instantly.
## Connect dev_ready BEFORE calling: it always answers, cached or fetched.
func check_dev(force := false) -> void:
        if _dev_checked and not force:
                dev_ready.emit(is_dev)
                return
        _dev_checked = true
        is_dev = false
        if is_guest or user_id.is_empty() or Api.token.is_empty():
                dev_ready.emit(false)
                return
        var res: Dictionary = await Api.get_json("/api/games?creatorId=%s&limit=1" % user_id)
        var games: Variant = res.get("games", []) if res.get("ok", false) else []
        is_dev = typeof(games) == TYPE_ARRAY and not (games as Array).is_empty()
        dev_ready.emit(is_dev)


## The name chip shown in the player list: "Nexico8225 #1".
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
