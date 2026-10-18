# RetrobloxApi — the one HTTP door to the RetroBlox platform.
# Same contract the Unity SDK uses:
#   POST /api/platform/login        {username,password} -> {token,userId,username}
#   GET  /api/platform/me           Bearer token -> user + account-wide avatar
#   GET  /api/users/{id}/avatar     public avatar payload (any player)
#   GET  /api/assets/{assetId}      asset service: color / image / model for an id
#   GET  /api/files/{fileId}        raw asset bytes (images, GLB models, audio)
# The avatar belongs to the RetroBlox ACCOUNT: dress it on the website and
# every game (Unity, Godot, anything) spawns you wearing exactly this.
class_name RetrobloxApi
extends RefCounted

var base_url: String
var token: String = ""
var user_id: String = ""
var username: String = ""

# toggle verbose logging of every request
var debug := false


func _init(p_base_url: String) -> void:
        base_url = p_base_url.strip_edges().trim_suffix("/")


# ---------------------------------------------------------------- requests

func _request(method: int, path: String, headers: PackedStringArray = PackedStringArray(), body: String = "") -> Dictionary:
        var http := HTTPRequest.new()
        http.timeout = 20.0
        http.use_threads = true
        (Engine.get_main_loop() as SceneTree).root.add_child(http)
        var err := http.request(base_url + path, headers, method, body)
        if err != OK:
                http.queue_free()
                return { "ok": false, "error": "Could not reach the server (%s)" % error_string(err) }
        var result: Array = await http.request_completed
        http.queue_free()
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
        return res


## GET /api/platform/me — the signed-in player + their account avatar.
func get_me() -> Dictionary:
        return await _request(HTTPClient.METHOD_GET, "/api/platform/me", _auth_headers())


## GET /api/users/{id}/avatar — any player's avatar (public, no token needed).
func get_avatar(user_id_or_empty: String = "") -> Dictionary:
        var path := "/api/platform/me" if token != "" else "/api/users/%s/avatar" % user_id_or_empty
        if token != "" and user_id_or_empty != "":
                path = "/api/users/%s/avatar" % user_id_or_empty
        var headers := _auth_headers() if token != "" else PackedStringArray()
        return await _request(HTTPClient.METHOD_GET, path, headers)


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
        var bytes := get_bytes(url)
        if bytes.is_empty():
                return null
        return image_from_bytes(bytes)


func image_from_bytes(bytes: PackedByteArray) -> Image:
        if bytes.size() < 8:
                return null
        # PNG signature
        if bytes[0] == 0x89 and bytes[1] == 0x50:
                return Image.load_png_from_buffer(bytes)
        # JPEG signature
        if bytes[0] == 0xFF and bytes[1] == 0xD8:
                return Image.load_jpg_from_buffer(bytes)
        # WEBP
        if bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[8] == 0x57:
                return Image.load_webp_from_buffer(bytes)
        return Image.load_png_from_buffer(bytes)


func _decode_data_url(url: String) -> Image:
        var comma := url.find(",")
        if comma < 0:
                return null
        var meta := url.substr(0, comma)
        var payload := url.substr(comma + 1)
        if meta.contains("svg"):
                var svg := payload.uri_decode()
                return Image.load_svg_from_string(svg)
        if meta.contains("base64"):
                var img := Image.new()
                var err := img.load_png_from_buffer(Marshalls.base64_to_raw(payload))
                if err != OK and meta.contains("jpeg"):
                        err = img.load_jpg_from_buffer(Marshalls.base64_to_raw(payload))
                return img if err == OK else null
        return null
