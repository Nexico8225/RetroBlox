extends Node
## Api — the one HTTP door to the RetroBlox platform (autoload "Api").
##
## Every feature of the new player rides on these endpoints, the same
## contracts the website and the SDK use:
##   POST /api/platform/login    {username,password} -> {token,userId,username}
##   POST /api/platform/signup   {username,password} -> {token,userId,username}
##   GET  /api/platform/me       Bearer -> your user + account avatar
##   GET  /api/users/{id}/avatar public avatar payload (any player)
##   GET  /api/assets/{assetId}  resolve an asset id (color / image / model)
##   GET  /api/files/{fileId}    raw bytes (images, GLB models)
##   GET/POST /api/placechat/{placeId}  in-game chat + presence (new)
##
## The server URL is a CONSTANT on purpose: the player is RetroBlox's own
## client and always talks to the official platform.

const SERVER_URL := "https://retro-blox.vercel.app"
const SAVE_PATH := "user://retroblox_session.cfg"
const VERSION := "2.0"

var token: String = ""
var saved_username: String = ""   # remembered so the login field pre-fills
var _busy := 0

# session caches — the avatar dresses INSTANTLY on rejoin/respawn because
# every asset json, image and model downloaded once is remembered here
var _asset_cache: Dictionary = {}   # asset id -> resolve Dictionary
var _image_cache: Dictionary = {}   # url -> Image
var _bytes_cache: Dictionary = {}   # url -> PackedByteArray

signal busy_changed(count: int)


func _ready() -> void:
        _load_saved()


# ---------------------------------------------------------------- session disk

## The token is what keeps you logged in — once saved, every future boot
## auto-signs in with zero typing. The username is remembered too, just so
## the login field pre-fills if the token ever expires.
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


# ---------------------------------------------------------------- requests

func _auth_headers() -> PackedStringArray:
        if token == "":
                return PackedStringArray()
        return PackedStringArray(["Authorization: Bearer %s" % token])


## The single request door. Returns a Dictionary with "ok" plus the JSON
## payload, or "ok": false + a human "error" message.
func request(method: int, path: String, headers: PackedStringArray = PackedStringArray(), body: String = "") -> Dictionary:
        var http := HTTPRequest.new()
        http.timeout = 20.0
        http.use_threads = true
        add_child(http)
        _busy += 1
        busy_changed.emit(_busy)
        var result: Array = []
        var err := http.request(SERVER_URL + path, headers, method, body)
        if err == OK:
                result = await http.request_completed
        http.queue_free()
        _busy -= 1
        busy_changed.emit(_busy)
        if result.is_empty():
                var why := error_string(err)
                if err == ERR_TIMEOUT:
                        why = "the request timed out — check your internet and try again"
                return { "ok": false, "error": "Could not reach RetroBlox (%s)." % why }
        var status: int = result[1]
        var raw: PackedByteArray = result[3]
        var text := raw.get_string_from_utf8()
        # only parse when it actually looks like JSON — an HTML error page from a
        # proxy should surface as "HTTP <status>", not a parser stack trace
        var data: Variant = null
        if text.length() > 0 and (text[0] == "{" or text[0] == "["):
                data = JSON.parse_string(text)
        if status < 200 or status >= 300:
                var msg := "HTTP %d" % status
                if data is Dictionary and data.has("error"):
                        msg = String(data["error"])
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
        return await request(HTTPClient.METHOD_POST, path, headers, JSON.stringify(payload))


# ---------------------------------------------------------------- platform

## Exchange username + password for a session token.
func login(p_username: String, p_password: String) -> Dictionary:
        return await post_json("/api/platform/login", {
                "username": p_username,
                "password": p_password,
        }, false)


## Create a brand-new RetroBlox account without leaving the game.
func signup(p_username: String, p_password: String) -> Dictionary:
        return await post_json("/api/platform/signup", {
                "username": p_username,
                "password": p_password,
        }, false)


## The signed-in player + their account-wide avatar (and emotes).
func get_me() -> Dictionary:
        return await get_json("/api/platform/me")


## Any player's avatar — public, no token needed.
func avatar_of(p_user_id: String) -> Dictionary:
        return await get_json("/api/users/%s/avatar" % p_user_id)


## A player's public profile (username, seqId, bio, online).
func profile_of(p_user_id: String) -> Dictionary:
        return await get_json("/api/users/%s" % p_user_id)


## Resolve an asset id into render data (colors, images, GLB models, finish).
## Cached per session: the same asset asked twice costs zero network.
func get_asset(asset_id: String) -> Dictionary:
        if _asset_cache.has(asset_id):
                return _asset_cache[asset_id]
        var res: Dictionary = await get_json("/api/assets/%s" % asset_id)
        if res.get("ok", false):
                _asset_cache[asset_id] = res
        return res


# ---------------------------------------------------------------- place chat

## Latest chat lines + everyone currently in the place.
func place_chat_get(place_id: String) -> Dictionary:
        return await get_json("/api/placechat/%s" % place_id)


## Send one chat line.
func place_chat_send(place_id: String, text: String) -> Dictionary:
        return await post_json("/api/placechat/%s" % place_id, { "text": text })


## Presence heartbeat: "I am here, at this spot, facing this way."
func place_presence(place_id: String, pos: Vector3, heading: float) -> Dictionary:
        return await post_json("/api/placechat/%s" % place_id, {
                "x": pos.x, "y": pos.y, "z": pos.z, "heading": heading,
        })


# ---------------------------------------------------------------- raw data

## Download raw bytes (GLB models etc.) — pass the path the API returned.
## Cached so a rejoin never re-downloads a model.
func get_bytes(url_path: String) -> PackedByteArray:
        if _bytes_cache.has(url_path):
                return _bytes_cache[url_path]
        var http := HTTPRequest.new()
        http.timeout = 30.0
        http.use_threads = true
        add_child(http)
        var headers := _auth_headers()
        var err := http.request(SERVER_URL + url_path, headers)
        var result: Array = []
        if err == OK:
                result = await http.request_completed
        http.queue_free()
        if result.is_empty():
                return PackedByteArray()
        var status: int = result[1]
        if status < 200 or status >= 300:
                return PackedByteArray()
        var bytes: PackedByteArray = result[3]
        if bytes.size() <= 12 * 1024 * 1024:   # remember anything sane-sized
                _bytes_cache[url_path] = bytes
        return bytes


## Decode whatever the platform served into a Godot Image.
## Handles /api/files binaries (PNG/JPG/WEBP) AND the data: URLs the
## built-in faces use (SVG / PNG base64). Cached per URL — a re-dress
## paints from memory instead of the network.
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
