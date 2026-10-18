extends Node
## ==================================================================
##  CW API — the one HTTP door to the RetroBlox platform.
##  (autoload as "CwApi" — see project.godot)
##
##  This is the ColorWorld copy of the RetroBlox SDK's core/api.gd —
##  SAME contract, trimmed to what a paint game needs:
##
##    POST /api/platform/login   {username,password} -> {token,userId,username,seqId}
##    GET  /api/platform/me      Bearer token -> your profile + PLAYER ID (seqId)
##    GET  /api/colormaps        community maps list (name, mapUrl, imageUrl)
##    GET  /api/files/{fileId}   raw bytes (map GLBs, placeholder images)
##    POST /api/games/{id}/play  "I am playing this game" counter
##
##  Everything is plain HTTP + JSON against https://retro-blox.vercel.app
##  — the same API the website and the full RetroBlox SDK use.
## ==================================================================

## Where the platform lives. Change this ONLY if you self-host RetroBlox.
const SERVER_URL := "https://retro-blox.vercel.app"

# ---------------------------------------------------------------- session
var token := ""
var user_id := ""
var username := "Guest"
var seq_id := 0          # the short human PLAYER ID (#1, #2 ... join order)
var is_guest := true

func signed_in() -> bool:
        return not is_guest and token != ""

## "Nexico8225 #1" — the name tag with the Player ID, SDK style.
func display_tag() -> String:
        if is_guest or seq_id <= 0:
                return username
        return "%s #%d" % [username, seq_id]

func sign_out() -> void:
        token = ""
        user_id = ""
        username = "Guest"
        seq_id = 0
        is_guest = true

# ---------------------------------------------------------------- requests

## The single request door. Returns the JSON as a Dictionary with "ok": true,
## or { "ok": false, "error": "a human message" }. Never crashes on nulls.
func request(method: int, path: String, headers: PackedStringArray = PackedStringArray(), body: String = "") -> Dictionary:
        var http := HTTPRequest.new()
        http.timeout = 20.0
        http.use_threads = true
        add_child(http)
        var result: Array = []
        var err := http.request(SERVER_URL + path, headers, method, body)
        if err == OK:
                result = await http.request_completed
        http.queue_free()
        if result.is_empty():
                var why := error_string(err)
                if err == ERR_TIMEOUT:
                        why = "the request timed out — check your internet and try again"
                return { "ok": false, "error": "Could not reach RetroBlox (%s)." % why }
        var status: int = result[1]
        var raw: PackedByteArray = result[3]
        var text := raw.get_string_from_utf8()
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

func _auth_headers() -> PackedStringArray:
        if token == "":
                return PackedStringArray()
        return PackedStringArray(["Authorization: Bearer %s" % token])

func get_json(path: String) -> Dictionary:
        return await request(HTTPClient.METHOD_GET, path, _auth_headers())

func post_json(path: String, payload: Dictionary, authed := true) -> Dictionary:
        var headers := PackedStringArray(["Content-Type: application/json"])
        if authed:
                headers.append_array(_auth_headers())
        return await request(HTTPClient.METHOD_POST, path, headers, JSON.stringify(payload))

# ---------------------------------------------------------------- platform

## Sign in with a RetroBlox account. Fills token + username + PLAYER ID.
func login(p_username: String, p_password: String) -> Dictionary:
        var res := await post_json("/api/platform/login",
                { "username": p_username, "password": p_password }, false)
        if not res.get("ok", false):
                return res
        token = str(res.get("token", ""))
        user_id = str(res.get("userId", ""))
        username = str(res.get("username", "Player"))
        seq_id = int(res.get("seqId", 0))
        is_guest = false
        return res

## "I am playing this game" — powers the play counter on the game page.
## Needs a signed-in account; guests are skipped silently.
func play_ping(game_id: String) -> void:
        if not signed_in() or game_id == "":
                return
        await post_json("/api/games/%s/play" % game_id, {})

# ---------------------------------------------------------------- downloads

## Download RAW bytes (a map GLB, a placeholder image). Returns
## { "ok": true, "bytes": PackedByteArray } or { "ok": false, "error": ... }.
func download_bytes(path: String) -> Dictionary:
        var http := HTTPRequest.new()
        http.timeout = 60.0
        http.use_threads = true
        http.download_chunk_size = 1 << 20
        add_child(http)
        var result: Array = []
        var err := http.request(SERVER_URL + path, PackedStringArray(), HTTPClient.METHOD_GET)
        if err == OK:
                result = await http.request_completed
        var bytes := http.get_result() if err == OK else PackedByteArray()
        http.queue_free()
        if result.is_empty() or int(result[0]) != OK:
                return { "ok": false, "error": "Download failed (%s)." % error_string(err) }
        var status: int = result[1]
        if status < 200 or status >= 300:
                return { "ok": false, "error": "Download got HTTP %d." % status }
        if bytes.is_empty():
                return { "ok": false, "error": "Download came back empty." }
        return { "ok": true, "bytes": bytes }

## Decode image bytes (PNG/JPG/WebP) into a texture for the map cards.
func image_texture_from_bytes(bytes: PackedByteArray) -> ImageTexture:
        var img := Image.new()
        var err := img.load_png_from_buffer(bytes)
        if err != OK:
                err = img.load_jpg_from_buffer(bytes)
        if err != OK:
                err = img.load_webp_from_buffer(bytes)
        if err != OK:
                return null
        return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- payload hygiene

## JSON nulls crash GDScript's typed calls ("String(null)" is invalid) —
## run EVERY payload string through this.
func txt(v: Variant, d := "") -> String:
        return v if v is String else d
