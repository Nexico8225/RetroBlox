extends Node
# Stores current logged-in player session, user ID, and cached avatar data.
var is_guest := true
var user_id := ""
var username := "Guest"
var seq_id := 0
var role := ""
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
var place_id: String = "baseplate"
var launch_game_id: String = ""
var launch_pkg_url: String = ""
var streamed_ram_package: Dictionary = {}


func _ready() -> void:
	_apply_window_icon()
	_register_custom_url_protocol()
	_parse_launch_protocol_args()


func _register_custom_url_protocol() -> void:
	if Engine.is_editor_hint() or OS.get_name() != "Windows":
		return
	var exe_path: String = OS.get_executable_path().replace("/", "\\")
	if exe_path == "":
		return
	OS.execute("reg", ["add", "HKCU\\Software\\Classes\\retroblox", "/ve", "/d", "URL:RetroBlox Protocol", "/f"], [], false)
	OS.execute("reg", ["add", "HKCU\\Software\\Classes\\retroblox", "/v", "URL Protocol", "/d", "", "/f"], [], false)
	OS.execute("reg", ["add", "HKCU\\Software\\Classes\\retroblox\\shell\\open\\command", "/ve", "/d", "\"%s\" \"%%1\"" % exe_path, "/f"], [], false)


func _parse_launch_protocol_args() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		var s: String = String(arg).strip_edges().trim_prefix('"').trim_suffix('"')
		if s.begins_with("retroblox://"):
			var q_idx: int = s.find("?")
			if q_idx >= 0:
				var query: String = s.substr(q_idx + 1)
				for pair in query.split("&", false):
					var kv: PackedStringArray = pair.split("=", true, 1)
					if kv.size() == 2:
						var k: String = kv[0].uri_decode()
						var v: String = kv[1].uri_decode()
						if k == "gameId" or k == "game":
							launch_game_id = v
							place_id = v
							server_ui_game = v
						elif k == "token" and v != "":
							Api.token = v
							Api.save_session()
						elif k == "pkgUrl" or k == "fileUrl":
							launch_pkg_url = v
						elif k == "username" and v != "":
							Api.saved_username = v
		elif s.begins_with("--game-id="):
			launch_game_id = s.substr(10)
			place_id = launch_game_id
			server_ui_game = launch_game_id
		elif s.begins_with("--token="):
			Api.token = s.substr(8)
			Api.save_session()
		elif s.begins_with("--pkg-url="):
			launch_pkg_url = s.substr(10)


func _apply_window_icon() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_ICON):
		var icon_tex = load("res://assets/RetroBloxLogo.png")
		if icon_tex is Texture2D:
			var icon_img: Image = (icon_tex as Texture2D).get_image()
			if icon_img != null and not icon_img.is_empty():
				DisplayServer.set_icon(icon_img)


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


func cache_avatar(p_user_id: String, payload: Dictionary) -> void:
		avatar_cache[p_user_id] = _nullless(payload)


func set_avatar(payload: Dictionary) -> void:
		avatar = _nullless(payload)
		if user_id != "":
				var inner: Variant = avatar.get("avatar", null)
				avatar_cache[user_id] = _nullless(inner if inner is Dictionary else {})


func cached_avatar(p_user_id: String) -> Dictionary:
		var hit: Variant = avatar_cache.get(p_user_id, {})
		return hit if hit is Dictionary else {}


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


func display_tag() -> String:
		if is_guest or seq_id <= 0:
				return username
		return "%s #%d" % [username, seq_id]


func my_avatar_data() -> Dictionary:
		if is_guest:
				return {}
		var a: Variant = avatar.get("avatar", {})
		return a if a is Dictionary else {}
