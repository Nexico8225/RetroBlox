extends Node
## PfpService — the REAL PROFILE PICTURE engine (v8.0).
## Every face this client shows is a real Roblox avatar HEADSHOT, exactly the
## way the Roblox client shows one — never the old 3D-rendered rig snapshot.
##
## Resolution order for (uid, username):
##   1. Bundled override  res://assets/pfp/<username-lower>.png
##      (shipped with the game — Nexico8225's real headshot rides in the kit,
##      so their PFP shows instantly with ZERO network)
##   2. Disk cache        user://pfp_cache/<username-lower>.png  (24h TTL)
##   3. LIVE ROBLOX API   users.roblox.com  ->  thumbnails.roblox.com
##      POST /v1/usernames/users {"usernames":[name]} -> userId
##      GET  /v1/users/avatar-headshot?userIds=ID&size=420x420&format=Png
##      then download the rbxcdn PNG -> disk cache -> texture
##   4. Fallback          the classic smiley head on a per-player color
##      (Roblox's own "no data yet" read) — NEVER a 3D render again.
##
## Guests always wear the fallback smiley. All network happens off the main
## flow (await), nothing blocks a frame, and every fetch is cached in RAM.

const CACHE_TTL := 86400.0        # one day per headshot
const TIMEOUT := 10.0

var _ram: Dictionary = {}         # "uid|uname" -> Texture2D
var _inflight: Dictionary = {}    # "uid|uname" -> bool


## Awaitable: the best profile picture we can get for this player.
## Every result comes back with ROUNDED CORNERS (the client's read).
func fetch(uid: String, uname: String) -> Texture2D:
        var key := "%s|%s" % [uid, uname]
        if _ram.has(key):
                return _ram[key]
        var lower := uname.to_lower().strip_edges()

        # 1. bundled override — the shipped headshot wins instantly
        var bundled := "res://assets/pfp/%s.png" % lower
        if ResourceLoader.exists(bundled):
                var tex: Texture2D = load(bundled)
                if tex != null:
                        tex = rounded(tex)
                        _ram[key] = tex
                        return tex

        # 2. disk cache (24h)
        var cached := _load_cache(lower)
        if cached != null:
                cached = rounded(cached)
                _ram[key] = cached
                return cached

        # 3. the real Roblox thumbnail pipeline
        if not _inflight.get(key, false) and uname.strip_edges() != "":
                _inflight[key] = true
                var live := await _fetch_roblox(lower)
                _inflight.erase(key)
                if live != null:
                        live = rounded(live)
                        _save_cache(lower, live)
                        _ram[key] = live
                        return live

        # 4. the classic fallback smiley
        var fb := fallback_pfp(uname)
        _ram[key] = fb
        return fb


func forget(uid: String, uname: String) -> void:
        _ram.erase("%s|%s" % [uid, uname])


# ---------------------------------------------------------------- internals

func _load_cache(lower: String) -> Texture2D:
        var path := "user://pfp_cache/%s.png" % lower
        if not FileAccess.file_exists(path):
                return null
        var age := 0.0
        var now := Time.get_unix_time_from_system()
        if FileAccess.file_exists(path):
                age = now - float(FileAccess.get_modified_time(path))
        if age > CACHE_TTL:
                return null
        var img := Image.load_from_file(ProjectSettings.globalize_path(path))
        if img == null or img.is_empty():
                return null
        return ImageTexture.create_from_image(img)


func _save_cache(lower: String, tex: Texture2D) -> void:
        DirAccess.make_dir_recursive_absolute("user://pfp_cache")
        var img := tex.get_image()
        if img == null or img.is_empty():
                return
        img.save_png("user://pfp_cache/%s.png" % lower)


## Rounded corners, the client's headshot read (r = 14% of the side).
static func rounded(tex: Texture2D) -> Texture2D:
        if tex == null:
                return null
        var img := tex.get_image()
        if img == null or img.is_empty():
                return tex
        if img.is_compressed():
                img.decompress()
        if img.get_format() != Image.FORMAT_RGBA8:
                img.convert(Image.FORMAT_RGBA8)
        return ImageTexture.create_from_image(_round_image(img))


static func _round_image(img: Image) -> Image:
        var w := img.get_width()
        var h := img.get_height()
        var r := int(minf(float(w), float(h)) * 0.14)
        var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
        var rect := Rect2(0, 0, w, h)
        for y in range(h):
                for x in range(w):
                        if not _in_rr(Vector2(float(x) + 0.5, float(y) + 0.5), rect, float(r)):
                                out.set_pixel(x, y, Color(0, 0, 0, 0))
                        else:
                                out.set_pixel(x, y, img.get_pixel(x, y))
        return out


static func _in_rr(p: Vector2, r: Rect2, rad: float) -> bool:
        if p.x < r.position.x or p.x > r.end.x or p.y < r.position.y or p.y > r.end.y:
                return false
        var hw := r.size.x * 0.5 - rad
        var hh := r.size.y * 0.5 - rad
        var dx := absf(p.x - r.get_center().x) - hw
        var dy := absf(p.y - r.get_center().y) - hh
        dx = maxf(dx, 0.0)
        dy = maxf(dy, 0.0)
        return dx * dx + dy * dy <= rad * rad


## The live pipeline: username -> userId -> headshot URL -> PNG bytes.
func _fetch_roblox(lower: String) -> Texture2D:
        # step 1 — username to userId
        var body := JSON.stringify({"usernames": [lower], "excludeBannedUsers": false})
        var res := await _http_json("https://users.roblox.com/v1/usernames/users",
                ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
        if not res.get("ok", false):
                return null
        var parsed: Variant = JSON.parse_string(String(res.get("body", "")))
        if typeof(parsed) != TYPE_DICTIONARY:
                return null
        var data: Array = parsed.get("data", [])
        if data.is_empty() or typeof(data[0]) != TYPE_DICTIONARY:
                return null
        var rid: float = float(data[0].get("id", 0))
        if rid <= 0.0:
                return null

        # step 2 — userId to headshot URL
        var turl := "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=%d&size=420x420&format=Png&isCircular=false" % int(rid)
        var res2 := await _http_json(turl, [], HTTPClient.METHOD_GET, "")
        if not res2.get("ok", false):
                return null
        var parsed2: Variant = JSON.parse_string(String(res2.get("body", "")))
        if typeof(parsed2) != TYPE_DICTIONARY:
                return null
        var data2: Array = parsed2.get("data", [])
        if data2.is_empty() or typeof(data2[0]) != TYPE_DICTIONARY:
                return null
        var image_url := String(data2[0].get("imageUrl", ""))
        if image_url == "":
                return null

        # step 3 — the PNG itself
        var bytes := await _http_bytes(image_url)
        if bytes.is_empty():
                return null
        var img := Image.new()
        if img.load_png_from_buffer(bytes) != OK:
                return null
        return ImageTexture.create_from_image(_round_image(img))


func _http_json(url: String, headers: Array, method: int, body: String) -> Dictionary:
        var http := HTTPRequest.new()
        http.timeout = TIMEOUT
        http.use_threads = true
        add_child(http)
        var err := http.request(url, headers, method, body if body != "" else null)
        if err != OK:
                http.queue_free()
                return {"ok": false}
        var result: Array = await http.request_completed
        http.queue_free()
        var code: int = result[1]
        return {"ok": code >= 200 and code < 300, "body": result[3].get_string_from_utf8()}


func _http_bytes(url: String) -> PackedByteArray:
        var http := HTTPRequest.new()
        http.timeout = TIMEOUT
        http.use_threads = true
        http.download_chunk_size = 1 << 20
        add_child(http)
        var err := http.request(url)
        if err != OK:
                http.queue_free()
                return PackedByteArray()
        var result: Array = await http.request_completed
        http.queue_free()
        if int(result[1]) < 200 or int(result[1]) >= 300:
                return PackedByteArray()
        return result[3]


## The classic fallback: the YELLOW smiley head centered on a muted
## per-player color square (hashed from the name, Roblox's own read).
static func fallback_pfp(uname: String) -> Texture2D:
        var theme := load("res://scripts/ui/retro_theme.gd")
        var head: Texture2D = theme.call("head_icon")
        if head == null:
                return null
        var side := 160
        var img := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
        var hue := float(hash(uname.to_lower()) % 360) / 360.0
        var bg := Color.from_hsv(hue, 0.28, 0.30)
        img.fill(bg)
        var head_img := head.get_image()
        if head_img != null and not head_img.is_empty():
                head_img.resize(int(side * 0.72), int(side * 0.72), Image.INTERPOLATE_NEAREST)
                var off := int((side - head_img.get_width()) / 2.0)
                img.blend_rect(head_img, Rect2i(0, 0, head_img.get_width(), head_img.get_height()), Vector2i(off, off))
        return ImageTexture.create_from_image(_round_image(img))
