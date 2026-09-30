# RetrobloxApi — the one HTTP door to the RetroBlox platform.
# Same contract the website and the Unity SDK use:
#   POST /api/platform/login     {username,password} -> {token,userId,username}
#   POST /api/platform/signup    {username,password} -> {token,userId,username}
#   GET  /api/platform/me        Bearer token -> user + account-wide avatar
#   GET  /api/users/{id}/avatar  public avatar payload (any player)
#   GET  /api/assets/{assetId}   asset service: color / image / model for an id
#   GET  /api/files/{fileId}     raw asset bytes (images, GLB models, audio)
# The avatar belongs to the RetroBlox ACCOUNT: dress it on the website (or
# sign up right inside this player) and every game spawns you wearing it.
class_name RetrobloxApi
extends RefCounted

var base_url: String
var token: String = ""
var user_id: String = ""
var username: String = ""
# remembered on a successful login/signup so the player is auto-signed-in
# next launch (saved ONLY in their own user:// profile, never sent anywhere)
var password: String = ""

# toggle verbose logging of every request
var debug := false


func _init(p_base_url: String) -> void:
        base_url = p_base_url.strip_edges().trim_suffix("/")


# ---------------------------------------------------------------- requests

func _request(method: HTTPClient.Method, path: String, headers: PackedStringArray = PackedStringArray(), body: String = "") -> Dictionary:
        var http := HTTPRequest.new()
        http.timeout = 30.0
        http.use_threads = true
        (Engine.get_main_loop() as SceneTree).root.add_child(http)
        var err := http.request(base_url + path, headers, method, body)
        if err != OK:
                http.queue_free()
                return { "ok": false, "error": "Could not reach the server (%s)" % error_string(err) }
        var result: Array = await http.request_completed
        http.queue_free()
        # Network-level failure (DNS, TLS, timeout, reset): result[1] is 0 —
        # say WHY instead of a cryptic "HTTP 0".
        if int(result[0]) != OK:
                var why := error_string(int(result[0]))
                if int(result[0]) == ERR_TIMEOUT:
                        why = "the request timed out — check your internet, then try again"
                return { "ok": false, "error": "Could not reach %s (%s). Check your internet connection, then try again." % [base_url, why] }
        var status: int = result[1]
        var raw: PackedByteArray = result[3]
        var text := raw.get_string_from_utf8()
        if debug:
                print("[RetroBlox] %s %s -> %d %s" % [method, path, status, text.substr(0, 200)])
        var data: Variant = JSON.parse_string(text) if text.length() > 0 else null
        if status < 200 or status >= 300:
                var msg := "HTTP %d" % status
                if data is Dictionary and data.has("error"):
                        msg = String(data["error"])
                return { "ok": false, "error": msg }
        if data is Dictionary:
                var d: Dictionary = data
                d["ok"] = true
                return d
        return { "ok": true }


func _auth_headers() -> PackedStringArray:
        return PackedStringArray(["Authorization: Bearer %s" % token])


# ---------------------------------------------------------------- endpoints

## POST /api/platform/login — exchange username + password for a session token.
func login(p_username: String, p_password: String) -> Dictionary:
        var body := JSON.stringify({ "username": p_username, "password": p_password })
        var res := await _request(
                HTTPClient.METHOD_POST, "/api/platform/login",
                PackedStringArray(["Content-Type: application/json"]), body
        )
        if res.get("ok", false):
                token = String(res.get("token", ""))
                user_id = String(res.get("userId", ""))
                username = String(res.get("username", ""))
                password = p_password
        return res


## POST /api/platform/signup — create an account WITHOUT leaving the game.
func signup(p_username: String, p_password: String, p_birthday := "", p_gender := "") -> Dictionary:
        var body := JSON.stringify({
                "username": p_username,
                "password": p_password,
                "birthday": p_birthday,
                "gender": p_gender,
        })
        var res := await _request(
                HTTPClient.METHOD_POST, "/api/platform/signup",
                PackedStringArray(["Content-Type: application/json"]), body
        )
        if res.get("ok", false):
                token = String(res.get("token", ""))
                user_id = String(res.get("userId", ""))
                username = String(res.get("username", ""))
                password = p_password
        return res


## GET /api/platform/me — the signed-in player + their account avatar.
func get_me() -> Dictionary:
        return await _request(HTTPClient.METHOD_GET, "/api/platform/me", _auth_headers())


## GET /api/users/{id}/avatar — any player's avatar (public, no token needed).
func get_avatar(p_user_id: String) -> Dictionary:
        return await _request(HTTPClient.METHOD_GET, "/api/users/%s/avatar" % p_user_id)


## GET /api/assets/{assetId} — resolve an asset id into what to render.
func get_asset(asset_id: String) -> Dictionary:
        return await _request(HTTPClient.METHOD_GET, "/api/assets/%s" % asset_id)


## GET raw bytes (images / GLB models) — pass the path the API returned
## (like /api/files/abc123 or /retro/default-face.png).
func get_bytes(url_path: String) -> PackedByteArray:
        var http := HTTPRequest.new()
        http.timeout = 30.0
        http.use_threads = true
        (Engine.get_main_loop() as SceneTree).root.add_child(http)
        var headers := _auth_headers() if token != "" else PackedStringArray()
        var err := http.request(base_url + url_path, headers)
        if err != OK:
                http.queue_free()
                return PackedByteArray()
        var result: Array = await http.request_completed
        http.queue_free()
        var status: int = result[1]
        if status < 200 or status >= 300:
                return PackedByteArray()
        return result[3]


# ---------------------------------------------------------------- images

## Decode whatever the platform served into a Godot Image.
## Handles /api/files binaries (PNG/JPG/WEBP) AND the data: URLs the
## built-in faces use (SVG / PNG base64).
func load_image(url: String) -> Image:
        if url == "":
                return null
        if url.begins_with("data:"):
                return _decode_data_url(url)
        var bytes := await get_bytes(url)
        if bytes.is_empty():
                return null
        return image_from_bytes(bytes)


func image_from_bytes(bytes: PackedByteArray) -> Image:
        # load_*_from_buffer are INSTANCE methods — make an Image, then decode into it.
        if bytes.size() < 8:
                return null
        var img := Image.new()
        var err := OK
        # PNG signature
        if bytes[0] == 0x89 and bytes[1] == 0x50:
                err = img.load_png_from_buffer(bytes)
        # JPEG signature
        elif bytes[0] == 0xFF and bytes[1] == 0xD8:
                err = img.load_jpg_from_buffer(bytes)
        # WEBP signature (RIFF....WEBP) — needs at least 12 bytes
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
