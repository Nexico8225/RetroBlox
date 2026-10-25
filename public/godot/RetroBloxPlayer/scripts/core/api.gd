extends Node
# HTTP client for RetroBlox authentication, avatars, and multiplayer presence.
const SERVER_URL := "https://retro-blox.vercel.app"
const SAVE_PATH := "user://retroblox_session.cfg"
const VERSION := "2.0"
const NEXICO_UID := "cmts80l0k0000mkujqa50flhz"

var token: String = ""
var saved_username: String = ""
var _busy := 0

var _asset_cache: Dictionary = {}
var _image_cache: Dictionary = {}
var _bytes_cache: Dictionary = {}

signal busy_changed(count: int)


func _ready() -> void:
	_load_saved()


func save_session(p_username := "") -> void:
	if p_username != "":
		saved_username = p_username
	var cf := ConfigFile.new()
	cf.set_value("auth", "token", token)
	cf.set_value("auth", "username", saved_username)
	cf.save(SAVE_PATH)


func _load_saved() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		token = String(cf.get_value("auth", "token", ""))
		saved_username = String(cf.get_value("auth", "username", ""))


func clear_session() -> void:
	token = ""
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		cf.erase_section_key("auth", "token")
		cf.save(SAVE_PATH)


func txt(v: Variant, d := "") -> String:
	return v if v is String else d


func _auth_headers() -> PackedStringArray:
	if token == "":
		return PackedStringArray(["User-Agent: RetroBloxPlayer/2.0"])
	return PackedStringArray([
		"Authorization: Bearer %s" % token,
		"User-Agent: RetroBloxPlayer/2.0",
	])


func _do_single_request(method: int, path: String, headers: PackedStringArray, body: String, threaded: bool) -> Array:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	http.use_threads = threaded
	add_child(http)
	var result: Array = []
	var err := http.request(SERVER_URL + path, headers, method, body)
	if err == OK:
		result = await http.request_completed
	http.queue_free()
	return result


func request(method: int, path: String, headers: PackedStringArray = PackedStringArray(), body: String = "") -> Dictionary:
	_busy += 1
	busy_changed.emit(_busy)
	var req_headers := PackedStringArray(headers)
	var has_ua := false
	for h in req_headers:
		if h.to_lower().begins_with("user-agent:"):
			has_ua = true
			break
	if not has_ua:
		req_headers.append("User-Agent: RetroBloxPlayer/2.0")

	var result := await _do_single_request(method, path, req_headers, body, false)
	if result.is_empty() or int(result[1]) == 0:
		# Retry once with threaded mode if non-threaded returned HTTP 0
		result = await _do_single_request(method, path, req_headers, body, true)

	_busy -= 1
	busy_changed.emit(_busy)
	if result.is_empty():
		return { "ok": false, "error": "Could not reach RetroBlox.", "status": 0 }
	var status: int = int(result[1])
	var raw: PackedByteArray = result[3]
	var text := raw.get_string_from_utf8()
	var data: Variant = null
	if text.length() > 0 and (text[0] == "{" or text[0] == "["):
		data = JSON.parse_string(text)
	if status < 200 or status >= 300:
		var msg := "HTTP %d" % status
		if data is Dictionary and data.has("error"):
			msg = txt(data["error"], "HTTP %d" % status)
		return { "ok": false, "error": msg, "status": status }
	if data is Dictionary:
		var d: Dictionary = data
		d["ok"] = true
		return d
	return { "ok": true }


func get_json(path: String) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, path, _auth_headers())


func post_json(path: String, payload: Dictionary, authed := true) -> Dictionary:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if authed:
		headers.append_array(_auth_headers())
	else:
		headers.append("User-Agent: RetroBloxPlayer/2.0")
	return await request(HTTPClient.METHOD_POST, path, headers, JSON.stringify(payload))


func login(p_username: String, p_password: String) -> Dictionary:
	return await post_json("/api/platform/login", {
		"username": p_username,
		"password": p_password,
	}, false)


func signup(p_username: String, p_password: String) -> Dictionary:
	return await post_json("/api/platform/signup", {
		"username": p_username,
		"password": p_password,
	}, false)


func get_me() -> Dictionary:
	return await get_json("/api/platform/me")


func avatar_of(p_user_id: String) -> Dictionary:
	return await get_json("/api/users/%s/avatar" % p_user_id)


func profile_of(p_user_id: String) -> Dictionary:
	return await get_json("/api/users/%s" % p_user_id)


func get_asset(asset_id: String) -> Dictionary:
	if _asset_cache.has(asset_id):
		return _asset_cache[asset_id]
	var res: Dictionary = await get_json("/api/assets/%s" % asset_id)
	if res.get("ok", false):
		_asset_cache[asset_id] = res
	return res


func place_chat_get(place_id: String) -> Dictionary:
	return await get_json("/api/placechat/%s" % place_id)


func place_chat_send(place_id: String, text: String) -> Dictionary:
	return await post_json("/api/placechat/%s" % place_id, { "text": text })


func place_presence(place_id: String, pos: Vector3, heading: float, ping_ms := 0, fps := 0, speaking := false, voice_level := 0.0, voice_b64 := "") -> Dictionary:
	var payload := {
		"x": pos.x, "y": pos.y, "z": pos.z, "heading": heading,
		"ping": ping_ms, "fps": fps,
		"speaking": speaking, "voiceLevel": voice_level,
	}
	if voice_b64 != "":
		payload["voice"] = voice_b64
	return await post_json("/api/placechat/%s" % place_id, payload)


func get_bytes(url_path: String) -> PackedByteArray:
	if _bytes_cache.has(url_path):
		return _bytes_cache[url_path]
	var http := HTTPRequest.new()
	http.timeout = 20.0
	http.use_threads = false
	add_child(http)
	var headers := _auth_headers()
	var err := http.request(SERVER_URL + url_path, headers)
	var result: Array = []
	if err == OK:
		result = await http.request_completed
	http.queue_free()
	if result.is_empty():
		return PackedByteArray()
	var status: int = int(result[1])
	if status < 200 or status >= 300:
		return PackedByteArray()
	var bytes: PackedByteArray = result[3]
	if bytes.size() <= 12 * 1024 * 1024:
		_bytes_cache[url_path] = bytes
	return bytes


func load_image(url: String) -> Image:
	if url == "":
		return null
	if _image_cache.has(url):
		return _image_cache[url]
	var img: Image = null
	if url.begins_with("data:"):
		img = _decode_data_url(url)
	else:
		var bytes := await get_bytes(url)
		if not bytes.is_empty():
			img = image_from_bytes(bytes)
	if img != null:
		_image_cache[url] = img
	return img


func image_from_bytes(bytes: PackedByteArray) -> Image:
	if bytes.size() < 8:
		return null
	var img := Image.new()
	var err := OK
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.size() >= 12 and bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[8] == 0x57:
		err = img.load_webp_from_buffer(bytes)
	else:
		err = img.load_png_from_buffer(bytes)
	if err != OK:
		return null
	return img


func _decode_data_url(url: String) -> Image:
	var comma := url.find(",")
	if comma < 0:
		return null
	var meta := url.substr(0, comma)
	var payload := url.substr(comma + 1)
	if meta.contains("svg"):
		var svg := payload.uri_decode()
		var svg_img := Image.new()
		var svg_err := svg_img.load_svg_from_string(svg)
		return svg_img if svg_err == OK else null
	if meta.contains("base64"):
		var img := Image.new()
		var err := img.load_png_from_buffer(Marshalls.base64_to_raw(payload))
		if err != OK and meta.contains("jpeg"):
			err = img.load_jpg_from_buffer(Marshalls.base64_to_raw(payload))
		return img if err == OK else null
	return null
