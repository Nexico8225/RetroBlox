extends Node
## PfpService — the REAL PROFILE PICTURE engine (v12.1).
## Every face this client shows IS the player's retro-blox.vercel.app
## PROFILE PICTURE — exactly what the website itself shows:
##
##   a player signs up  ->  they wear the DEFAULT PFP (the letter avatar:
##   first letter of the name, white, on a stable color from their name)
##   they upload one    ->  avatarUrl points at it and EVERY client loads it.
##
## Resolution order for (uid, username):
##   0. CUSTOM PFP     the URL the player set in this client's own Settings
##                     (saved in ui_config — this wins over EVERYTHING)
##   1. SITE PFP       the account's avatarUrl: mine arrives via
##                     /api/platform/me at login, everyone else's via the
##                     public GET /api/users/{id}/pfp
##   2. DEFAULT PFP    the site's letter avatar, drawn in code (same
##                     palette as the website) — no network, instant
##
## A small disk cache (user://pfp_cache_v13) keeps fetched site pictures
## warm for 6h. All network happens off the main flow (await), nothing
## blocks a frame, and every fetch is cached in RAM. peek() answers
## INSTANTLY (RAM or default letter) for chat lines that cannot wait.

const CACHE_TTL := 21600.0        # six hours per fetched site picture
const TIMEOUT := 10.0

signal pfp_changed(uid: String)   # v9.0: a custom/site PFP landed — repaint seats

var _ram: Dictionary = {}         # "uid|uname" -> Texture2D
var _inflight: Dictionary = {}    # "uid|uname" -> bool

# ---- v9.0: the account's own face ---------------------------------------
var site_pfp_url: String = ""     # MY avatarUrl from /api/platform/me
var custom_pfp_url: String = ""   # URL the user typed in the Editor (wins)
var _custom_tex: Texture2D = null # the decoded custom/site texture


## Called by the UI Editor — the player's OWN picture URL. Wins over all.
func set_custom_pfp(url: String) -> void:
        custom_pfp_url = url.strip_edges()
        _custom_tex = null
        _ram.clear()
        if custom_pfp_url != "":
                _apply_source_texture(custom_pfp_url)
        else:
                pfp_changed.emit(Session.user_id)


## Called at login — the account's avatarUrl from /api/platform/me
## (the SAME picture the website shows). A data-URL decodes inline.
func set_site_pfp(url: String) -> void:
        var u := url.strip_edges()
        if u == site_pfp_url:
                return
        site_pfp_url = u
        _ram.clear()
        if custom_pfp_url == "" and u != "":
                _apply_source_texture(u)


## Resolve a source URL (http or data-URL) into the held texture.
func _apply_source_texture(url: String) -> void:
        var tex := await decode_any(url)
        if tex != null:
                _custom_tex = tex
                pfp_changed.emit(Session.user_id)


## Awaitable: any image URL — data:...;base64 or https:// — as a texture.
func decode_any(url: String) -> Texture2D:
        if url.begins_with("data:"):
                var img := _image_from_data_url(url)
                if img == null:
                        return null
                return ImageTexture.create_from_image(img)
        var lower := url.to_lower()
        var bytes := await _http_bytes(url)
        if bytes.is_empty():
                return null
        var img := Image.new()
        if lower.contains(".png") or bytes.size() > 8 and bytes[0] == 0x89:
                if img.load_png_from_buffer(bytes) != OK:
                        return null
        elif lower.contains(".jpg") or lower.contains(".jpeg") or (bytes.size() > 3 and bytes[0] == 0xFF and bytes[1] == 0xD8):
                if img.load_jpg_from_buffer(bytes) != OK:
                        return null
        elif lower.contains(".webp"):
                if img.load_webp_from_buffer(bytes) != OK:
                        return null
        else:
                # try png then jpg — the extension lied
                if img.load_png_from_buffer(bytes) != OK and img.load_jpg_from_buffer(bytes) != OK:
                        return null
        if img.is_empty():
                return null
        return ImageTexture.create_from_image(img)


## "data:image/png;base64,AAA..." -> Image
static func _image_from_data_url(url: String) -> Image:
        var comma := url.find(",")
        if comma < 0:
                return null
        var b64 := url.substr(comma + 1)
        var buf := Marshalls.base64_to_raw(b64)
        if buf.is_empty():
                return null
        var img := Image.new()
        if img.load_png_from_buffer(buf) == OK:
                return img
        if img.load_jpg_from_buffer(buf) == OK:
                return img
        if img.load_webp_from_buffer(buf) == OK:
                return img
        return null


## Awaitable: the player's SITE profile picture — custom URL, then the
## account's avatarUrl, then the DEFAULT letter avatar (the exact thing
## retro-blox.vercel.app shows for accounts without a picture).
func fetch(uid: String, uname: String) -> Texture2D:
        var key := "%s|%s" % [uid, uname]
        if _ram.has(key):
                return _ram[key]
        var lower := uname.to_lower().strip_edges()

        # 0. MY OWN picture — the custom URL wins over everything
        if uid == Session.user_id and _custom_tex != null:
                _ram[key] = _custom_tex
                return _custom_tex

        # 1. the disk cache — v13 namespace (older folders held renders and
        # pre-v11 bacon bytes; a fresh name guarantees they can never resurface)
        var cached := _load_cache(lower)
        if cached != null:
                cached = rounded(cached)
                _ram[key] = cached
                return cached

        # 2. THE SITE PFP — the account's avatarUrl. Mine rides the session
        # (/api/platform/me); everyone else's comes from the public endpoint
        # GET /api/users/{id}/pfp. A null avatarUrl means the DEFAULT pfp.
        var url := site_pfp_url if uid == Session.user_id else ""
        if url == "" and not Session.is_guest:
                var res: Dictionary = await Api.get_json("/api/users/%s/pfp" % uid)
                if res.get("ok", false):
                        url = Api.txt(res.get("avatarUrl", ""))
        if url != "":
                var site := await decode_any(url)
                if site != null:
                        _save_cache(lower, site)
                        site = rounded(site)
                        _ram[key] = site
                        return site

        # 3. THE DEFAULT PFP — the site's letter avatar, drawn in code
        var fb := default_pfp(uname)
        _ram[key] = fb
        return fb


## INSTANT answer for seats that cannot wait on the network (chat lines,
## badges): the RAM cache if it is warm, otherwise the DEFAULT letter
## avatar — which IS the correct picture for anyone without a site PFP.
func peek(uid: String, uname: String) -> Texture2D:
        var key := "%s|%s" % [uid, uname]
        if _ram.has(key):
                return _ram[key]
        if uid == Session.user_id and _custom_tex != null:
                return _custom_tex
        return default_pfp(uname)


## The site's DEFAULT profile picture: the letter avatar (first letter on
## a stable color) — the exact look retro-blox.vercel.app gives every new
## account. Falls back to the classic smiley only if drawing fails.
func default_pfp(uname: String) -> Texture2D:
        var theme := load("res://scripts/ui/retro_theme.gd")
        var letter: Texture2D = theme.call("letter_avatar", uname)
        if letter != null:
                return rounded(letter)
        return fallback_pfp(uname)


func forget(uid: String, uname: String) -> void:
        _ram.erase("%s|%s" % [uid, uname])


# ---------------------------------------------------------------- internals

func _load_cache(lower: String) -> Texture2D:
        var path := "user://pfp_cache_v13/%s.png" % lower
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
        DirAccess.make_dir_recursive_absolute("user://pfp_cache_v13")
        var img := tex.get_image()
        if img == null or img.is_empty():
                return
        img.save_png("user://pfp_cache_v13/%s.png" % lower)


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


## The last-resort fallback: the YELLOW smiley head centered on a muted
## per-player color square (only used if the letter avatar cannot draw).
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
