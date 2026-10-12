class_name RetroTheme
extends RefCounted
## v10.0 "2008 CLIENT" — the client speaks the OLD LANGUAGE again, and this
## time it is the engine, not a coat of paint: every surface is a real 9-patch
## BEVEL (a code-drawn texture — light top-left rim, dark bottom-right rim,
## exactly how the 2008-2013 client's gray chrome was built), corners are
## SQUARE, the one voice is ARIAL (Liberation Sans, the metric stand-in),
## the primary key is the CLASSIC GREEN, danger is ROBLOX RED, and inputs are
## WHITE sunken wells with black ink. The whole client re-skins from this one
## file — every surface the player draws comes through these calls.

const BG := Color("2b2b2b")          # the client backdrop (login + menu veil)
const PANEL := Color("3b3b3b")       # the beveled chrome face
const PANEL_HOVER := Color("4a4a4a")
const PANEL_DOWN := Color("2f2f2f")
const CARD := Color("333333")
const WELL := Color("222222")        # inputs / insets
const EDGE := Color("565656")        # the 1px rule between surfaces
const TEXT := Color("f2f2f2")
const TEXT_MUTED := Color("c2c2c2")
const TEXT_INV := Color("ffffff")    # ink on the GREEN key
const GREEN := Color("00aa00")       # the CLASSIC green (2006 site green)
const GREEN_FACE := Color("3e9c35")  # the primary key's bevel face
const RED := Color("e2231a")         # the ROBLOX red
const BLUE := Color("00a2ff")        # the classic Roblox blue accent
const BLUE_HI := Color("33b5ff")

const BEVEL_LIGHT := Color("6e6e6e") # the light top-left rim
const BEVEL_DARK := Color("141414")  # the dark bottom-right rim

const STEEL_TEXTURE_PATH := "res://assets/ui/steel_panel.jpg"   # (legacy, unused)
const CURSOR_ARROW_PATH := "res://assets/ui/cursor_hand.png"      # uploaded RetroBlox Cursor
const CURSOR_HAND_PATH := "res://assets/ui/cursor_pointer.png"    # uploaded RetroBlox Pointer
const PFP_DIR := "res://assets/pfp"    # bundled real headshots (username.png)

# ------------------------------------------------------------- menu palette
## The menu's palette — the SAME surfaces, named for the menu callers.

const MENU_BG := Color(0.129, 0.129, 0.129, 0.96)    # the veil behind the panel
const MENU_PANEL := Color("3b3b3b")                  # beveled chrome surface
const MENU_PANEL_HI := Color("4a4a4a")               # hover / open row
const MENU_EDGE := Color("565656")                   # the quiet rule
const MENU_INK := Color("f2f2f2")                    # primary text
const MENU_MUTED := Color("c2c2c2")                  # secondary text
const MENU_FAINT := Color("8f8f8f")                  # hints / version tags
const MENU_ACCENT := Color("00a2ff")                 # the classic blue accent
const MENU_ACCENT_HI := Color("33b5ff")
const MENU_ACCENT_DARK := Color("0086c9")
const MENU_ACCENT_SOFT := Color(0.0, 0.635, 1.0, 0.18)   # selected row fill
const MENU_RED := Color("e2231a")
const MENU_GREEN := Color("00aa00")
const PILL := Color(0.0, 0.0, 0.0, 0.62)             # the topbar pill

# ---------------------------------------------------------------- voices
## ONE family, the way the old client wore it: ARIAL. Liberation Sans is the
## metric-perfect free stand-in; bold carries titles, keys and names.
## gotham()/source() stay as aliases so every caller matches.

const ARIAL_PATHS := {
        400: "res://assets/fonts/LiberationSans-Regular.ttf",
        500: "res://assets/fonts/LiberationSans-Regular.ttf",
        600: "res://assets/fonts/LiberationSans-Bold.ttf",
        700: "res://assets/fonts/LiberationSans-Bold.ttf",
        800: "res://assets/fonts/LiberationSans-Bold.ttf",
}
const MONT_PATHS := ARIAL_PATHS       # legacy alias — one family now
const SOURCE_PATHS := ARIAL_PATHS     # legacy alias — one family now

static var _font_cache: Dictionary = {}


static func arial(weight := 400) -> Font:
        return _voice(ARIAL_PATHS, 400, weight)


static func gotham(weight := 600) -> Font:
        return _voice(ARIAL_PATHS, 600, weight)


static func source(weight := 400) -> Font:
        return _voice(ARIAL_PATHS, 400, weight)


static func _voice(paths: Dictionary, fallback: int, weight: int) -> Font:
        var key := int(paths.hash()) + weight * 7919
        if _font_cache.has(key):
                return _font_cache[key]
        var w := weight
        if not paths.has(w):
                w = fallback
        var path: String = paths[w]
        var f: Font = null
        if ResourceLoader.exists(path):
                f = load(path)
        _font_cache[key] = f
        return f


# ---------------------------------------------------------------- the bevel
## The 2008 chrome: a 9-patch texture — 2px light top+left rim, 2px dark
## bottom+right rim, 1px inner shade where they meet the face. Baked once per
## face color and cached; `sunken` swaps the rims so wells read INSET.

static var _bevel_cache: Dictionary = {}

const _BEVEL_PX := 3        # texture rim width (2px bevel + 1px inner shade)


static func _bake_bevel(face: Color, inverted: bool) -> ImageTexture:
        var s := _BEVEL_PX
        var size := 48
        var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
        # the rims DERIVE from the face — gray chrome gets the classic gray
        # rims, the green key gets green rims, exactly like the old buttons
        var light := face.lerp(Color(1, 1, 1), 0.30)
        var dark := face.lerp(Color(0, 0, 0), 0.58)
        if inverted:
                var tmp := light
                light = dark
                dark = tmp
        # the inner shade line where the rim meets the face
        var shade := face.lerp(Color(0, 0, 0), 0.25)
        var shine := face.lerp(Color(1, 1, 1), 0.14)
        for y in size:
                for x in size:
                        var c := face
                        var edge_l := x < s
                        var edge_t := y < s
                        var edge_r := x >= size - s
                        var edge_b := y >= size - s
                        if edge_b or edge_r:
                                # bottom/right wins the corner pixels — the
                                # classic bevel's dark edge cuts the corner
                                c = dark
                        elif edge_t or edge_l:
                                c = light
                        elif x == s - 1 or y == s - 1:
                                c = shade   # inner top/left shade (inside the frame)
                        elif x == size - s or y == size - s:
                                c = shine   # inner bottom/right glow (inside the frame)
                        img.set_pixel(x, y, c)
        return ImageTexture.create_from_image(img)


## A raised bevel box in `face` — the chunky gray chrome of the old client.
static func raised(radius := 4, face := PANEL, shadow := 0, shadow_a := 0.5) -> StyleBoxTexture:
        var key := "r|%s" % face.to_html()
        if _bevel_cache.has(key):
                return _bevel_cache[key]
        var sb := StyleBoxTexture.new()
        sb.texture = _bake_bevel(face, false)
        sb.texture_margin_left = _BEVEL_PX
        sb.texture_margin_top = _BEVEL_PX
        sb.texture_margin_right = _BEVEL_PX
        sb.texture_margin_bottom = _BEVEL_PX
        _bevel_cache[key] = sb
        return sb


## A sunken bevel box — rims swapped so the face reads INSET (wells, cards).
static func sunken(radius := 4, face := WELL, border_px := 0, border_col := EDGE) -> StyleBox:
        var key := "s|%s" % face.to_html()
        if _bevel_cache.has(key):
                return _bevel_cache[key]
        var sb := StyleBoxTexture.new()
        sb.texture = _bake_bevel(face, true)
        sb.texture_margin_left = _BEVEL_PX
        sb.texture_margin_top = _BEVEL_PX
        sb.texture_margin_right = _BEVEL_PX
        sb.texture_margin_bottom = _BEVEL_PX
        if border_px > 0:
                sb.set_border_width_all(border_px)
                sb.modulate_color = border_col
        _bevel_cache[key] = sb
        return sb


## Flat surface — the quiet 1px-ruled panel (cards, rows). Square corners.
static func flat(radius := 4, face := PANEL) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = face
        sb.set_corner_radius_all(mini(radius, 2))
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = face.lerp(Color(0, 0, 0), 0.35)
        return sb


## The People card / surface card.
static func card(radius := 4, face := PANEL) -> StyleBox:
        return raised(radius, face)


## The TOPBAR PILL — beveled translucent black over the 3D world.
static func pill_style() -> StyleBox:
        var sb := raised(4, PILL)
        sb.content_margin_left = 6.0
        sb.content_margin_right = 6.0
        sb.content_margin_top = 4.0
        sb.content_margin_bottom = 4.0
        return sb


## Legacy aliases — kept so older callers keep compiling.
static func surface(radius := 8, face := PANEL, shadow := 0, shadow_a := 0.5) -> StyleBox:
        return raised(radius, face, shadow, shadow_a)


static func well(radius := 8, face := WELL) -> StyleBox:
        return sunken(radius, face)


## Hover wash — a white overlay on dark faces.
static func wash(alpha: float, radius := 4) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(1, 1, 1, alpha)
        sb.set_corner_radius_all(mini(radius, 2))
        sb.anti_aliasing = true
        return sb


## The translucent dark float — chat, tooltips. Thin light frame.
static func glass(alpha := 0.8, radius := 4) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0, 0, 0, alpha)
        sb.set_corner_radius_all(mini(radius, 2))
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = Color(1, 1, 1, 0.14)
        return sb


# ---------------------------------------------------------------- retro bits

static var _icon_cache: Dictionary = {}

## The classic YELLOW smiley head — the PFP fallback's face, drawn chunky
## on purpose (it is the one intentional pixel voice left in the client).
static func head_icon() -> ImageTexture:
        if _icon_cache.has("head"):
                return _icon_cache["head"]
        var w := 18
        var img := Image.create_empty(w, w, false, Image.FORMAT_RGBA8)
        var face := Color("f5cd30")
        var face_edge := Color("d9ae1c")
        var ink := Color(0.16, 0.13, 0.04)
        for y in range(w):
                for x in range(w):
                        var p := Vector2(float(x) + 0.5, float(y) + 0.5)
                        if not _in_rounded_px(p, Rect2(1, 1, 16, 16), 4.0):
                                continue
                        var col := face
                        # a whisper of shading: darker bottom/right rim
                        if x >= 13 or y >= 13:
                                col = face_edge
                        img.set_pixel(x, y, col)
        for eye_x in [5, 11]:
                for dy in range(3):
                        img.set_pixel(eye_x, 6 + dy, ink)
                        img.set_pixel(eye_x + 1, 6 + dy, ink)
        # the smile: a chunky pixel arc
        for sx in range(5, 13):
                img.set_pixel(sx, 12, ink)
        img.set_pixel(4, 11, ink)
        img.set_pixel(13, 11, ink)
        # 4x nearest upscale — chunky pixels survive LINEAR filtering clean
        img.resize(w * 4, w * 4, Image.INTERPOLATE_NEAREST)
        var tex := ImageTexture.create_from_image(img)
        _icon_cache["head"] = tex
        return tex


## Small ACTION icons, drawn 2x and downscaled so the edges land smooth,
## in ANY ink you ask: a play triangle (Resume), a reset arrow, a door
## (Leave), a power symbol (Log Out), the people crowd, a gear, the chat
## bubble and a tiny star.
static func icon_texture(kind: String, ink := Color(1, 1, 1, 0.96)) -> ImageTexture:
        var cache_key := "icon_" + kind + "_" + ink.to_html()
        if _icon_cache.has(cache_key):
                return _icon_cache[cache_key]
        var s := 2                       # supersample factor
        var w := 18 * s
        var img := Image.create_empty(w, w, false, Image.FORMAT_RGBA8)
        # every stroke paints an s x s block — the 2x canvas keeps the
        # shapes identical while the downscale anti-aliases every edge
        var px := func(x: int, y: int) -> void:
                for dy in range(s):
                        for dx in range(s):
                                img.set_pixel(x * s + dx, y * s + dy, ink)
        match kind:
                "play":
                        for x in range(4, 14):
                                var half := int(round(float(x - 4) * 5.0 / 9.0))
                                for y in range(9 - half, 9 + half + 1):
                                        px.call(x, y)
                "door":
                        for x in range(4, 14):
                                px.call(x, 2)
                                px.call(x, 15)
                        for y in range(2, 16):
                                px.call(4, y)
                                px.call(13, y)
                                px.call(6, y)
                        px.call(11, 9)
                        px.call(11, 10)
                "reset":
                        var center := Vector2(9.0, 9.5)
                        for y in range(18):
                                for x in range(18):
                                        var d := Vector2(float(x) + 0.5, float(y) + 0.5) - center
                                        var r := d.length()
                                        if r < 3.6 or r > 5.6:
                                                continue
                                        var ang := atan2(-d.y, d.x)
                                        if ang < 0:
                                                ang += TAU
                                        if ang > 0.55 and ang < 5.5:
                                                px.call(x, y)
                        for ay in range(2, 7):
                                for ax in range(8, 8 + ay - 1):
                                        px.call(ax, ay)
                "power":
                        var center := Vector2(9.0, 10.0)
                        for y in range(18):
                                for x in range(18):
                                        var d := Vector2(float(x) + 0.5, float(y) + 0.5) - center
                                        var r := d.length()
                                        if r < 3.8 or r > 5.8:
                                                continue
                                        var ang := atan2(-d.y, d.x)
                                        if absf(ang - PI / 2.0) < 0.6:
                                                continue   # the gap at the TOP
                                        px.call(x, y)
                        for y in range(2, 9):
                                px.call(8, y)
                                px.call(9, y)
                "people":
                        for hx in [4, 10]:
                                for ey in range(2):
                                        for ex in range(2):
                                                px.call(hx + ex, 4 + ey)
                                px.call(hx - 1, 5)
                                px.call(hx + 2, 5)
                        for sx in range(3, 8):
                                px.call(sx, 9)
                        for sx in range(9, 14):
                                px.call(sx, 9)
                        for sx in range(3, 15):
                                px.call(sx, 12)
                                px.call(sx, 13)
                "gear":
                        var gc := Vector2(9.0, 9.0)
                        for y in range(18):
                                for x in range(18):
                                        var d := Vector2(float(x) + 0.5, float(y) + 0.5) - gc
                                        var r := d.length()
                                        var ang := atan2(d.y, d.x)
                                        var tooth := absf(fposmod(ang / PI * 4.0, 1.0) - 0.5) > 0.28
                                        if (r >= 3.0 and r <= 5.4) or (tooth and r >= 2.0 and r <= 6.4):
                                                if r > 1.8:
                                                        px.call(x, y)
                "chat":
                        for y in range(3, 12):
                                for x in range(2, 16):
                                        var p := Vector2(float(x) + 0.5, float(y) + 0.5)
                                        if _in_rounded_px(p, Rect2(2, 3, 14, 9), 3.0):
                                                px.call(x, y)
                        for t in range(3):
                                for x in range(6 + t, 11 - t):
                                        px.call(x, 12 + t)
                "star":
                        px.call(9, 4)
                        px.call(9, 5)
                        for sx in range(6, 13):
                                px.call(sx, 7)
                        px.call(7, 8)
                        px.call(11, 8)
                        px.call(6, 9)
                        px.call(12, 9)
                        for sx in range(7, 12):
                                px.call(sx, 10)
                        px.call(9, 11)
                        px.call(9, 12)
                # ---- v9.0: the REAL CLIENT's chrome glyphs ----------------
                "hamburger":
                        for row in [4, 9, 14]:
                                for x in range(3, 15):
                                        px.call(x, row)
                                        px.call(x, row + 1)
                "gallery":
                        for y in range(3, 15):
                                for x in range(2, 16):
                                        if y == 3 or y == 14 or x == 2 or x == 15:
                                                px.call(x, y)
                        # the sun + the mountain inside the frame
                        px.call(6, 6)
                        px.call(7, 6)
                        px.call(6, 7)
                        px.call(7, 7)
                        for m in range(5):
                                for x in range(4 + m, 9 + m):
                                        px.call(x, 12 - m)
                "flag":
                        for y in range(2, 16):
                                px.call(4, y)
                        for y in range(3, 10):
                                for x in range(5, 14):
                                        px.call(x, y)
                "help":
                        var hc := Vector2(9.0, 6.0)
                        for y in range(18):
                                for x in range(18):
                                        var d := Vector2(float(x) + 0.5, float(y) + 0.5) - hc
                                        var r := d.length()
                                        if r >= 3.0 and r <= 5.0 and d.y < 1.5:
                                                px.call(x, y)
                        px.call(8, 9)
                        px.call(9, 9)
                        px.call(10, 10)
                        px.call(9, 11)
                        px.call(8, 12)
                        px.call(9, 12)
                        px.call(8, 15)
                        px.call(9, 15)
                "plus":
                        for x in range(4, 15):
                                px.call(x, 8)
                                px.call(x, 9)
                        for y in range(4, 15):
                                px.call(8, y)
                                px.call(9, y)
                "grid":
                        for cell in [[3, 3], [10, 3], [3, 10], [10, 10]]:
                                for y in range(cell[1], cell[1] + 5):
                                        for x in range(cell[0], cell[0] + 5):
                                                if y == cell[1] or y == cell[1] + 4 or x == cell[0] or x == cell[0] + 4:
                                                        px.call(x, y)
                "list":
                        for row in [4, 9, 14]:
                                px.call(3, row)
                                px.call(4, row)
                                for x in range(7, 15):
                                        px.call(x, row)
                "pencil":
                        for i in range(9):
                                px.call(5 + i, 13 - i)
                                px.call(6 + i, 13 - i)
                        for tip in range(3):
                                px.call(4 + tip, 13 + tip - 1)
                        px.call(4, 15)
                        px.call(3, 14)
                "globe":
                        var gc2 := Vector2(9.0, 9.0)
                        for y in range(18):
                                for x in range(18):
                                        var d := Vector2(float(x) + 0.5, float(y) + 0.5) - gc2
                                        var r := d.length()
                                        if r >= 6.0 and r <= 7.4:
                                                px.call(x, y)
                                        elif r < 6.0 and (x == 8 or x == 9 or (y >= 8 and y <= 9 and absf(d.x) < 6.0)):
                                                px.call(x, y)
                "close":
                        for i in range(10):
                                px.call(4 + i, 4 + i)
                                px.call(4 + i, 13 - i)
                "invite":
                        for hx in [3, 8]:
                                for ey in range(2):
                                        for ex in range(2):
                                                px.call(hx + ex, 4 + ey)
                        for sx in range(2, 7):
                                px.call(sx, 9)
                        for sx in range(7, 12):
                                px.call(sx, 9)
                        for sx in range(2, 12):
                                px.call(sx, 12)
                        for py in range(6, 12):
                                px.call(14, py)
                        px.call(13, 7)
                        px.call(15, 7)
                        px.call(14, 6)
                        px.call(14, 8)
        img.resize(18, 18, Image.INTERPOLATE_BILINEAR)
        var tex := ImageTexture.create_from_image(img)
        _icon_cache[cache_key] = tex
        return tex


## v11.0 — REAL INTERNET ICONS. The kit ships actual icon PNGs downloaded
## from the web (Icons8 + Pixabay — see the README credits): menu burger,
## settings gear, people crowd, chat bubble, respawn arrow, close badge.
## `icon_png` loads them once, caches, and — when a file is missing — falls
## back to the code-drawn glyph so the client never shows a hole.
static func icon_png(kind: String, fallback_ink := Color(1, 1, 1, 0.96)) -> Texture2D:
        var key := "png_" + kind
        if _icon_cache.has(key):
                return _icon_cache[key]
        var path := "res://assets/icons/%s.png" % kind
        if ResourceLoader.exists(path):
                var tex: Texture2D = load(path)
                if tex != null:
                        _icon_cache[key] = tex
                        return tex
        return icon_texture(kind, fallback_ink)


## The same internet icon, resized to a key-sized square (footer keys and
## other small seats — the raw 140px PNG would fill the whole button).
static func icon_png_sized(kind: String, px: int) -> Texture2D:
        var key := "png_%s_%d" % [kind, px]
        if _icon_cache.has(key):
                return _icon_cache[key]
        var src := icon_png(kind)
        if src == null:
                return null
        var img := src.get_image()
        if img == null or img.is_empty():
                return src
        if img.is_compressed():
                img.decompress()
        img.resize(px, px, Image.INTERPOLATE_LANCZOS)
        var tex := ImageTexture.create_from_image(img)
        _icon_cache[key] = tex
        return tex


## The real login backdrop — the classic baseplate photograph shipped with
## the kit (assets/ui/login_backdrop.jpg), loaded once.
static func login_backdrop() -> Texture2D:
        var key := "login_backdrop"
        if _icon_cache.has(key):
                return _icon_cache[key]
        var path := "res://assets/ui/login_backdrop.jpg"
        if ResourceLoader.exists(path):
                var tex: Texture2D = load(path)
                if tex != null:
                        _icon_cache[key] = tex
                        return tex
        return null


## Rounded-rect membership for the pixel-art helpers above.
static func _in_rounded_px(p: Vector2, r: Rect2, rad: float) -> bool:
        if p.x < r.position.x or p.x > r.end.x or p.y < r.position.y or p.y > r.end.y:
                return false
        var hw := r.size.x * 0.5 - rad
        var hh := r.size.y * 0.5 - rad
        var dx := absf(p.x - r.get_center().x) - hw
        var dy := absf(p.y - r.get_center().y) - hh
        dx = maxf(dx, 0.0)
        dy = maxf(dy, 0.0)
        return dx * dx + dy * dy <= rad * rad


## The uploaded RetroBlox cursors: the white classic hand everywhere the
## pointer normally is, and the Pointer variant on buttons/links. Applied
## once per run (login and game both call this on ready).
static func apply_cursors() -> void:
        if _cursors_applied:
                return
        if not (ResourceLoader.exists(CURSOR_ARROW_PATH) and ResourceLoader.exists(CURSOR_HAND_PATH)):
                return
        var arrow: Texture2D = load(CURSOR_ARROW_PATH)
        var hand: Texture2D = load(CURSOR_HAND_PATH)
        if arrow == null or hand == null:
                return
        # hotspots from the .cur files: hand points from its fingertip
        Input.set_custom_mouse_cursor(arrow, Input.CURSOR_ARROW, Vector2(2, 1))
        Input.set_custom_mouse_cursor(hand, Input.CURSOR_POINTING_HAND, Vector2(3, 1))
        Input.set_custom_mouse_cursor(hand, Input.CURSOR_IBEAM, Vector2(3, 1))
        _cursors_applied = true


static var _cursors_applied := false


## Build the shared Theme. Scene roots apply it: `theme = RetroTheme.make_theme()`.
static func make_theme() -> Theme:
        var t := Theme.new()
        var title: Font = gotham(700)
        var semi: Font = gotham(600)
        var body: Font = gotham(400)

        # ---- Button — the classic key: raised bevel, sinks when pressed ----
        t.set_stylebox("normal", "Button", _key(false, Color("4a4a4a")))
        t.set_stylebox("hover", "Button", _key(false, Color("565656")))
        t.set_stylebox("pressed", "Button", _key(true, Color("383838")))
        t.set_stylebox("disabled", "Button", _key(false, Color("3a3a3a")))
        t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
        t.set_color("font_color", "Button", TEXT)
        t.set_color("font_hover_color", "Button", Color(1, 1, 1))
        t.set_color("font_pressed_color", "Button", TEXT_MUTED)
        t.set_color("font_disabled_color", "Button", Color("7a7a7a"))
        t.set_font_size("font_size", "Button", 14)
        if semi != null:
                t.set_font("font", "Button", semi)

        # ---- Button variations — the classic fills ----
        var fill_var := func(var_name: String, bg: Color, hover: Color, down: Color,
                        ink: Color, weight := 600) -> void:
                t.set_type_variation(var_name, "Button")
                t.set_stylebox("normal", var_name, _key(false, bg))
                t.set_stylebox("hover", var_name, _key(false, hover))
                t.set_stylebox("pressed", var_name, _key(true, down))
                t.set_color("font_color", var_name, ink)
                t.set_color("font_hover_color", var_name, ink)
                t.set_color("font_pressed_color", var_name, ink)
                var f: Font = gotham(weight)
                if f != null:
                        t.set_font("font", var_name, f)
        # THE CLASSIC GREEN KEY — Log In / Resume, the 2006 site green
        fill_var.call("BtnPrimary", GREEN_FACE, Color("49b03f"), Color("2f7a29"), Color.WHITE, 700)
        fill_var.call("BtnBlue", Color("1a7ab8"), Color("2090d6"), Color("135c8c"), Color.WHITE)
        fill_var.call("BtnGreen", GREEN, Color("1cc41c"), Color("008000"), Color.WHITE)
        fill_var.call("BtnRed", RED, Color("f13b32"), Color("a81a14"), Color.WHITE)
        fill_var.call("BtnDark", PANEL, PANEL_HOVER, PANEL_DOWN, TEXT)
        # dark key, red ink — the Leave read
        fill_var.call("BtnDangerDark", Color("3a3a3a"), Color("4a3030"), Color("302424"), RED)
        t.set_font_size("font_size", "BtnPrimary", 15)
        t.set_font_size("font_size", "BtnBlue", 14)
        t.set_font_size("font_size", "BtnDark", 14)

        t.set_type_variation("BtnGhost", "Button")
        t.set_stylebox("normal", "BtnGhost", wash(0.0))
        t.set_stylebox("hover", "BtnGhost", wash(0.08))
        t.set_stylebox("pressed", "BtnGhost", wash(0.12))
        t.set_color("font_color", "BtnGhost", TEXT_MUTED)
        t.set_color("font_hover_color", "BtnGhost", TEXT)
        t.set_color("font_pressed_color", "BtnGhost", TEXT)
        t.set_font_size("font_size", "BtnGhost", 14)
        if semi != null:
                t.set_font("font", "BtnGhost", semi)

        # ---- Label — white ink, ARIAL everywhere ----
        t.set_color("font_color", "Label", TEXT)
        t.set_font_size("font_size", "Label", 14)
        if body != null:
                t.set_font("font", "Label", body)
        if title != null:
                t.set_type_variation("H1", "Label")
                t.set_font("font", "H1", title)
                t.set_font_size("font_size", "H1", 20)
                t.set_type_variation("Title", "Label")
                t.set_font("font", "Title", title)
                t.set_font_size("font_size", "Title", 17)
                t.set_type_variation("H2", "Label")
                t.set_font("font", "H2", gotham(600))
                t.set_font_size("font_size", "H2", 15)
                t.set_type_variation("Name", "Label")
                t.set_font("font", "Name", gotham(600))
                t.set_font_size("font_size", "Name", 13)
        for pair in [["Small", 12], ["Muted", 12], ["Sub", 11]]:
                t.set_type_variation(String(pair[0]), "Label")
                t.set_font_size("font_size", String(pair[0]), int(pair[1]))
        t.set_type_variation("Muted", "Label")
        t.set_color("font_color", "Muted", TEXT_MUTED)
        t.set_type_variation("Sub", "Label")
        t.set_color("font_color", "Sub", MENU_FAINT)
        t.set_type_variation("Small", "Label")
        t.set_color("font_color", "Small", TEXT_MUTED)
        t.set_type_variation("Inverse", "Label")
        t.set_color("font_color", "Inverse", TEXT_INV)
        t.set_type_variation("InverseSmall", "Label")
        t.set_color("font_color", "InverseSmall", TEXT_INV)
        t.set_font_size("font_size", "InverseSmall", 12)
        t.set_type_variation("Error", "Label")
        t.set_color("font_color", "Error", RED)
        t.set_font_size("font_size", "Error", 13)

        # ---- LineEdit — the WHITE SUNKEN WELL, black ink: the classic form ----
        var le := StyleBoxFlat.new()
        le.bg_color = Color("f4f4f4")
        le.set_corner_radius_all(0)
        le.set_border_width_all(2)
        le.border_color = Color("8a8a8a")   # the inset rim (light face, dark edge)
        le.content_margin_left = 10.0
        le.content_margin_right = 10.0
        le.content_margin_top = 8.0
        le.content_margin_bottom = 8.0
        var le_focus := le.duplicate() as StyleBoxFlat
        le_focus.border_color = Color("2f2f2f")
        t.set_stylebox("normal", "LineEdit", le)
        t.set_stylebox("focus", "LineEdit", le_focus)
        t.set_stylebox("read_only", "LineEdit", le)
        t.set_color("font_color", "LineEdit", Color("1c1c1c"))
        t.set_color("font_placeholder_color", "LineEdit", Color("909090"))
        t.set_color("caret_color", "LineEdit", Color("1c1c1c"))
        t.set_color("selection_color", "LineEdit", Color(0.0, 0.635, 1.0, 0.4))
        t.set_font_size("font_size", "LineEdit", 15)
        if body != null:
                t.set_font("font", "LineEdit", body)

        # ---- Panels — the beveled chrome sheet ----
        t.set_stylebox("panel", "PanelContainer", raised(4, PANEL))
        t.set_stylebox("panel", "Panel", flat(4, PANEL))
        t.set_type_variation("Card", "PanelContainer")
        t.set_stylebox("panel", "Card", raised(4, PANEL))
        t.set_type_variation("DarkPanel", "PanelContainer")
        t.set_stylebox("panel", "DarkPanel", raised(4, PANEL))

        # ---- Progress bar (health) — sunken track, classic green fill ----
        t.set_stylebox("background", "ProgressBar", sunken(4, Color(0, 0, 0, 0.72)))
        t.set_stylebox("fill", "ProgressBar", raised(4, GREEN))
        t.set_color("font_color", "ProgressBar", TEXT)

        # ---- Scroll bars — quiet white grabs ----
        var grab := flat(4, Color(1, 1, 1, 0.18))
        var grab_hi := flat(4, Color(1, 1, 1, 0.28))
        for bar in ["VScrollBar", "HScrollBar"]:
                t.set_stylebox("grabber", bar, grab)
                t.set_stylebox("grabber_highlight", bar, grab_hi)
                t.set_stylebox("grabber_pressed", bar, grab_hi)
                t.set_stylebox("scroll", bar, StyleBoxEmpty.new())

        # ---- Tooltips — the dark beveled tip ----
        t.set_stylebox("panel", "TooltipPanel", glass(0.94))
        t.set_color("font_color", "TooltipLabel", TEXT)
        t.set_font_size("font_size", "TooltipLabel", 12)
        if body != null:
                t.set_font("font", "TooltipLabel", body)

        # ---- CheckButton / slider — white ink, classic blue fill ----
        t.set_color("font_color", "CheckButton", TEXT)
        t.set_color("font_hover_color", "CheckButton", TEXT)
        t.set_color("font_pressed_color", "CheckButton", TEXT)
        t.set_font_size("font_size", "CheckButton", 13)
        if body != null:
                t.set_font("font", "CheckButton", body)
        var grabber := flat(4, BLUE)
        t.set_stylebox("slider", "HSlider", flat(4, EDGE))
        t.set_stylebox("grabber_area", "HSlider", grabber)
        t.set_stylebox("grabber_area_highlight", "HSlider", grabber)

        return t


## One key: raised (normal) or sunken (pressed) bevel in `face`, with the
## chunky content margins the old keys wore.
static func _key(pushed: bool, face: Color) -> StyleBox:
        var sb := sunken(4, face) if pushed else raised(4, face)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        return sb


## One shared instance (cheap to reuse across scene changes).
static var shared: Theme = make_theme()
