class_name RetroTheme
extends RefCounted
## v7.0 "CLASSIC" — the client's ONE voice, rebuilt as the 2008-2013 ROBLOX
## CLIENT: gray beveled panels with a light top-left edge and a dark
## bottom-right edge (the old 3D read), Arial carrying every title, button
## and name (Liberation Sans is the metric-perfect Arial stand-in), the
## classic GREEN action key, ROBLOX red for danger and the one Roblox blue
## accent. Chunky on purpose. Nothing glassy, nothing borderless-modern —
## it reads like the client you remember.

const BG := Color("14161b")          # deep backdrop (login + loading veil)
const PANEL := Color("3b3b3b")       # the classic window face
const PANEL_HOVER := Color("4a4a4a")
const PANEL_DOWN := Color("2c2c2c")
const CARD := Color("333333")        # card face
const WELL := Color("222222")        # sunken input / portrait inset
const TEXT := Color("ffffff")        # primary ink
const TEXT_MUTED := Color("c8c8c8")  # secondary ink
const TEXT_INV := Color("101208")    # ink on bright fills
const GREEN := Color("00aa00")       # classic health green
const RED := Color("e2231a")         # the ROBLOX red
const BLUE := Color("00a2ff")        # THE accent

const STEEL_TEXTURE_PATH := "res://assets/ui/steel_panel.jpg"   # (legacy, unused)
const CURSOR_ARROW_PATH := "res://assets/ui/cursor_hand.png"      # uploaded RetroBlox Cursor
const CURSOR_HAND_PATH := "res://assets/ui/cursor_pointer.png"    # uploaded RetroBlox Pointer

# ------------------------------------------------------------- v7.0 classic
## The client window's ONE palette — the classic client read: gray beveled
## faces, white ink, muted grays, ROBLOX red for danger, the classic green
## for the action key, Roblox blue as the single selection accent.

const MENU_BG := Color(0.231, 0.231, 0.231, 0.98)   # #3B3B3B — the window face
const MENU_PANEL := Color("3b3b3b")                 # rail / footer faces
const MENU_PANEL_HI := Color("4a4a4a")              # hover / open faces
const MENU_EDGE := Color("191919")                  # the dark frame line
const MENU_INK := Color("ffffff")                   # primary text — white
const MENU_MUTED := Color("c8c8c8")                 # secondary text
const MENU_FAINT := Color("9c9c9c")                 # hints / version tags
const MENU_ACCENT := Color("00a2ff")                # the ONE accent
const MENU_ACCENT_HI := Color("33b5ff")
const MENU_ACCENT_DARK := Color("0077b3")
const MENU_ACCENT_SOFT := Color(0.0, 0.635, 1.0, 0.16)   # selected chip fill
const MENU_RED := Color("e2231a")                   # the ROBLOX red
const MENU_GREEN := Color("00aa00")                 # the classic health green

## The bevel texture engine — the WHOLE retro read lives here. TWO 32px
## 9-patch textures are generated once in code: a RAISED one (light
## top-left rim, dark bottom-right rim) and a SUNKEN one (inverted). Every
## beveled surface is a StyleBoxTexture wearing one of them, TINTED to its
## face color via modulate (the texture encodes face = 160 gray, light rim
## = 235, dark rim = 55 — modulate = face/160 colors the whole thing). The
## 9-patch margins keep the rounded corners crisp at any size.


# ---------------------------------------------------------------- the voices
## ONE voice stands in for the classic client's Arial:
##   arial()   — Liberation Sans, the metric-perfect Arial: EVERYTHING.
## gotham() and source() stay as working aliases so every caller (titles,
## buttons, chat, body copy) keeps compiling — they all speak Arial now.

const ARIAL_PATHS := {
        400: "res://assets/fonts/LiberationSans-Regular.ttf",
        700: "res://assets/fonts/LiberationSans-Bold.ttf",
}
const GOTHAM_PATHS := ARIAL_PATHS   # legacy alias — the voice is Arial now
const SOURCE_PATHS := ARIAL_PATHS

static var _voice_cache: Dictionary = {}
static var _cursors_applied := false


## The classic Arial voice — titles, buttons, names, chat (weight 400/700).
static func arial(weight := 400) -> Font:
        return _voice(ARIAL_PATHS, 400, 700 if weight >= 600 else 400)


## Legacy alias — the Gotham slot now speaks Arial (bold for >= 600).
static func gotham(weight := 600) -> Font:
        return arial(weight)


## Legacy alias — the chat/body voice speaks Arial too.
static func source(weight := 400) -> Font:
        return arial(weight)


static func _voice(paths: Dictionary, fallback: int, weight: int) -> Font:
        var key := "%d_%d" % [paths.hash(), weight]
        if _voice_cache.has(key):
                return _voice_cache[key]
        var path: String = paths.get(weight, paths[fallback])
        var font: Font = null
        if ResourceLoader.exists(path):
                font = load(path)
        _voice_cache[key] = font
        return font


# ---------------------------------------------------------------- surfaces
## The bevel engine — FOUR voices:
##   raised()  light top-left rim / dark bottom-right rim → keys, windows
##   sunken()  the inverse                               → input wells, insets
##   flat()    face only (StyleBoxFlat)                  → strips, fills
##   wash()    the white hover veil                      → quiet hover states
## The rims come from the generated 9-patch textures; the face color arrives
## through modulate. Shadow params are accepted (and ignored) so older
## callers keep compiling — windows that need a drop shadow park one on a
## wrapper panel (game.gd does exactly that).

const _BEVEL_TEX_FACE := 160.0     # the gray the texture's face encodes
const _BEVEL_TEX_LIGHT := 236.0    # the top-left rim gray
const _BEVEL_TEX_DARK := 52.0      # the bottom-right rim gray

static var _raised_tex: ImageTexture
static var _sunken_tex: ImageTexture

static func _bevel_texture(sunken: bool) -> ImageTexture:
        var s := 32
        var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
        var rad := 7.0
        var rect := Rect2(0, 0, s, s)
        var center := rect.get_center()
        var half := rect.size * 0.5
        for y in range(s):
                for x in range(s):
                        var p := Vector2(x + 0.5, y + 0.5)
                        # rounded-box SDF: negative inside, positive outside
                        var q := (p - center).abs() - (half - Vector2(rad, rad))
                        var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() \
                                + minf(maxf(q.x, q.y), 0.0) - rad
                        if d > 0.0:
                                continue
                        var v := _BEVEL_TEX_FACE
                        if d >= -2.6:
                                # the rim band: top-left half = light, bottom-right = dark
                                var light_side := (x + y) < s
                                if sunken:
                                        light_side = not light_side
                                v = _BEVEL_TEX_LIGHT if light_side else _BEVEL_TEX_DARK
                        var g := v / 255.0
                        img.set_pixel(x, y, Color(g, g, g, 1.0))
        return ImageTexture.create_from_image(img)


static func _bevel_box(sunken: bool, face: Color, radius := 4) -> StyleBoxTexture:
        if _raised_tex == null:
                _raised_tex = _bevel_texture(false)
        if _sunken_tex == null:
                _sunken_tex = _bevel_texture(true)
        var sb := StyleBoxTexture.new()
        sb.texture = _sunken_tex if sunken else _raised_tex
        var m := 12.0
        sb.texture_margin_left = m
        sb.texture_margin_top = m
        sb.texture_margin_right = m
        sb.texture_margin_bottom = m
        # tint the whole 9-patch so the FACE lands on `face` and the rims
        # land lighter/darker versions of it — the old client's colored keys
        var k := face.r / (_BEVEL_TEX_FACE / 255.0)
        var kg := face.g / (_BEVEL_TEX_FACE / 255.0)
        var kb := face.b / (_BEVEL_TEX_FACE / 255.0)
        sb.modulate_color = Color(minf(k, 1.6), minf(kg, 1.6), minf(kb, 1.6), face.a)
        sb.content_margin_left = 8.0
        sb.content_margin_right = 8.0
        sb.content_margin_top = 6.0
        sb.content_margin_bottom = 6.0
        return sb


static func raised(radius := 4, face := PANEL, shadow := 0, shadow_a := 0.5) -> StyleBoxTexture:
        return _bevel_box(false, face, radius)


static func sunken(radius := 4, face := WELL) -> StyleBoxTexture:
        return _bevel_box(true, face, radius)


## A face with NO edges — strips, bars, the nav chip, hover fills.
static func flat(radius := 4, face := PANEL) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = face
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        return sb


## Legacy one-voice surface — now the raised key (kept for callers).
static func surface(radius := 4, face := PANEL, shadow := 0, shadow_a := 0.5) -> StyleBox:
        return raised(radius, face)


## Legacy well — now the sunken inset (kept for callers).
static func well(radius := 4, face := WELL) -> StyleBox:
        return sunken(radius, face)


## A soft white wash (hover state on dark faces).
static func wash(alpha: float, radius := 4) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(1, 1, 1, alpha)
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        return sb


## The classic translucent chat float — dark glass with ONE thin light frame
## (the 2013 client's chat read: quiet, edged, never beveled).
static func glass(alpha := 0.8, radius := 4) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.06, 0.06, 0.06, alpha)
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = Color(1, 1, 1, 0.14)
        return sb


# ---------------------------------------------------------------- retro bits

static var _icon_cache: Dictionary = {}

## The classic YELLOW smiley head — the People-page fallback, drawn chunky
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


## Small ACTION icons, drawn 2x and downscaled so the edges land smooth
## (the classic glyph read, not chunky pixels), in ANY ink you ask: a play
## triangle (Resume), a reset arrow, a door (Leave), a power symbol
## (Log Out), the people crowd, a gear, the chat bubble and a tiny star.
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
        img.resize(18, 18, Image.INTERPOLATE_BILINEAR)
        var tex := ImageTexture.create_from_image(img)
        _icon_cache[cache_key] = tex
        return tex


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


## Build the shared Theme. Scene roots apply it: `theme = RetroTheme.make_theme()`.
static func make_theme() -> Theme:
        var t := Theme.new()
        var title: Font = arial(700)
        var body: Font = arial(400)

        # ---- Button — the classic key: raised gray face, white ink ----
        t.set_stylebox("normal", "Button", _key_style(PANEL))
        t.set_stylebox("hover", "Button", _key_style(PANEL_HOVER))
        t.set_stylebox("pressed", "Button", sunken(3, PANEL_DOWN))
        t.set_stylebox("disabled", "Button", _key_style(Color("2f2f2f")))
        t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
        t.set_color("font_color", "Button", TEXT)
        t.set_color("font_hover_color", "Button", TEXT)
        t.set_color("font_pressed_color", "Button", TEXT_MUTED)
        t.set_color("font_disabled_color", "Button", Color("7d7d7d"))
        t.set_font_size("font_size", "Button", 13)
        if title != null:
                t.set_font("font", "Button", title)

        # ---- Button variations — the classic fills ----
        var fill_var := func(var_name: String, bg: Color, hover: Color, down: Color,
                        ink: Color) -> void:
                t.set_type_variation(var_name, "Button")
                t.set_stylebox("normal", var_name, _key_style(bg))
                t.set_stylebox("hover", var_name, _key_style(hover))
                t.set_stylebox("pressed", var_name, sunken(3, down))
                t.set_color("font_color", var_name, ink)
                t.set_color("font_hover_color", var_name, ink)
                t.set_color("font_pressed_color", var_name, ink)
        # the CLASSIC GREEN primary — the old site's action key
        fill_var.call("BtnPrimary", Color("3e9c35"), Color("49b23f"), Color("2a7322"), Color.WHITE)
        fill_var.call("BtnBlue", Color("1877cf"), Color("2a8ae0"), Color("0f5ca3"), Color.WHITE)
        fill_var.call("BtnGreen", Color("3e9c35"), Color("49b23f"), Color("2a7322"), Color.WHITE)
        fill_var.call("BtnRed", RED, Color("f0402f"), Color("a51511"), Color.WHITE)
        t.set_font_size("font_size", "BtnPrimary", 14)
        t.set_font_size("font_size", "BtnBlue", 14)
        if title != null:
                t.set_font("font", "BtnPrimary", title)
                t.set_font("font", "BtnBlue", title)

        t.set_type_variation("BtnGhost", "Button")
        t.set_stylebox("normal", "BtnGhost", wash(0.05, 3))
        t.set_stylebox("hover", "BtnGhost", wash(0.10, 3))
        t.set_stylebox("pressed", "BtnGhost", wash(0.14, 3))
        t.set_color("font_color", "BtnGhost", TEXT_MUTED)
        t.set_color("font_hover_color", "BtnGhost", TEXT)
        t.set_color("font_pressed_color", "BtnGhost", TEXT)
        t.set_font_size("font_size", "BtnGhost", 13)
        if title != null:
                t.set_font("font", "BtnGhost", title)

        # ---- Label — white ink, Arial everywhere (the classic voice) ----
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
                t.set_font("font", "H2", title)
                t.set_font_size("font_size", "H2", 15)
                t.set_type_variation("Name", "Label")
                t.set_font("font", "Name", title)
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

        # ---- LineEdit — sunken classic well, blue caret on focus ----
        t.set_stylebox("normal", "LineEdit", sunken(3))
        var focus_well := StyleBoxFlat.new()
        focus_well.bg_color = WELL
        focus_well.set_corner_radius_all(3)
        focus_well.set_border_width_all(2)
        focus_well.border_color = BLUE
        t.set_stylebox("focus", "LineEdit", focus_well)
        t.set_stylebox("read_only", "LineEdit", sunken(3))
        t.set_color("font_color", "LineEdit", TEXT)
        t.set_color("font_placeholder_color", "LineEdit", Color("8a8a8a"))
        t.set_color("caret_color", "LineEdit", BLUE)
        t.set_color("selection_color", "LineEdit", Color(0.0, 0.635, 1.0, 0.35))
        t.set_font_size("font_size", "LineEdit", 15)
        if body != null:
                t.set_font("font", "LineEdit", body)

        # ---- Panels — the classic window face ----
        t.set_stylebox("panel", "PanelContainer", raised(4, PANEL))
        t.set_stylebox("panel", "Panel", raised(4, PANEL))
        t.set_type_variation("Card", "PanelContainer")
        t.set_stylebox("panel", "Card", sunken(4, CARD))
        t.set_type_variation("DarkPanel", "PanelContainer")
        t.set_stylebox("panel", "DarkPanel", raised(4, MENU_PANEL))

        # ---- Progress bar (health) ----
        t.set_stylebox("background", "ProgressBar", sunken(3))
        t.set_stylebox("fill", "ProgressBar", flat(2, GREEN))
        t.set_color("font_color", "ProgressBar", TEXT)

        # ---- Scroll bars — quiet gray steel ----
        var grab := flat(3, Color(1, 1, 1, 0.18))
        var grab_hi := flat(3, Color(1, 1, 1, 0.28))
        for bar in ["VScrollBar", "HScrollBar"]:
                t.set_stylebox("grabber", bar, grab)
                t.set_stylebox("grabber_highlight", bar, grab_hi)
                t.set_stylebox("grabber_pressed", bar, grab_hi)
                t.set_stylebox("scroll", bar, StyleBoxEmpty.new())

        # ---- Tooltips — the classic dark tip with a thin light frame ----
        t.set_stylebox("panel", "TooltipPanel", glass(0.94, 3))
        t.set_color("font_color", "TooltipLabel", TEXT)
        t.set_font_size("font_size", "TooltipLabel", 12)
        if body != null:
                t.set_font("font", "TooltipLabel", body)

        # ---- CheckButton / slider grabs — white ink, green fill ----
        t.set_color("font_color", "CheckButton", TEXT)
        t.set_color("font_hover_color", "CheckButton", TEXT)
        t.set_color("font_pressed_color", "CheckButton", TEXT)
        t.set_font_size("font_size", "CheckButton", 13)
        if body != null:
                t.set_font("font", "CheckButton", body)
        var grabber := flat(3, GREEN)
        t.set_stylebox("slider", "HSlider", sunken(2, Color("1a1a1a")))
        t.set_stylebox("grabber_area", "HSlider", grabber)
        t.set_stylebox("grabber_area_highlight", "HSlider", grabber)

        return t


static func _key_style(face: Color) -> StyleBoxTexture:
        var sb := raised(3, face)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        return sb


## One shared instance (cheap to reuse across scene changes).
static var shared: Theme = make_theme()
