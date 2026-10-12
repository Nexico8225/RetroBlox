class_name RetroTheme
extends RefCounted
## v6.0 "BLOX" — the client's ONE voice, rebuilt as the REAL ROBLOX CLIENT:
## near-black rounded surfaces (#1B1D20 family) with big soft shadows and NO
## borders (elevation does the work), Montserrat carrying every title, button
## and name (the Gotham SSm voice), Source Sans 3 for chat and body copy, a
## WHITE primary button with dark ink (Resume), and one Roblox blue accent.
## The pixel-cabinet era is gone — nothing here is chunky, nothing blinds,
## it just reads like the real thing.

const BG := Color("0e1013")          # deep backdrop (login + loading veil)
const PANEL := Color("232528")       # the elevated face (cards, keys)
const PANEL_HOVER := Color("2e3033")
const PANEL_DOWN := Color("191b1e")
const CARD := Color("232528")        # card face
const WELL := Color("191b1e")        # input well / portrait inset
const TEXT := Color("ffffff")        # primary ink
const TEXT_MUTED := Color("b9bcc1")  # secondary ink
const TEXT_INV := Color("15171a")    # ink on WHITE fills
const GREEN := Color("00b06f")       # health fill + success
const RED := Color("ff4a4a")         # danger
const BLUE := Color("00a2ff")        # THE accent

const STEEL_TEXTURE_PATH := "res://assets/ui/steel_panel.jpg"   # (legacy, unused)
const CURSOR_ARROW_PATH := "res://assets/ui/cursor_hand.png"      # uploaded RetroBlox Cursor
const CURSOR_HAND_PATH := "res://assets/ui/cursor_pointer.png"    # uploaded RetroBlox Pointer

# ---------------------------------------------------------------- v6.0 blox
## The client window's ONE palette — the Roblox client read: near-black faces,
## white ink, muted grays, NO outlines (shadows separate surfaces), Roblox
## blue as the single accent and red only for danger.

const MENU_BG := Color(0.106, 0.114, 0.125, 0.97)   # #1B1D20 — the window face
const MENU_PANEL := Color("232528")                 # rail / footer faces
const MENU_PANEL_HI := Color("2e3033")              # hover faces
const MENU_EDGE := Color("313438")                  # hairline (wells only)
const MENU_INK := Color("ffffff")                   # primary text — white
const MENU_MUTED := Color("b9bcc1")                 # secondary text
const MENU_FAINT := Color("82868c")                 # hints / version tags
const MENU_ACCENT := Color("00a2ff")                # the ONE accent
const MENU_ACCENT_HI := Color("33b5ff")
const MENU_ACCENT_DARK := Color("0089db")
const MENU_ACCENT_SOFT := Color(0.0, 0.635, 1.0, 0.14)   # selected chip fill
const MENU_RED := Color("ff4a4a")
const MENU_GREEN := Color("00b06f")


# ---------------------------------------------------------------- the voices
## Two open voices stand in for Roblox's own:
##   gotham()  — Montserrat, the Gotham SSm stand-in: titles, buttons, names.
##   source()  — Source Sans 3, the classic chat voice: chat log, body copy.
## Static weights ship per file (variable-font coordinates proved flaky in
## engine, so every weight is its own honest TTF).

const GOTHAM_PATHS := {
        400: "res://assets/fonts/Montserrat-Regular.ttf",
        500: "res://assets/fonts/Montserrat-Medium.ttf",
        600: "res://assets/fonts/Montserrat-SemiBold.ttf",
        700: "res://assets/fonts/Montserrat-Bold.ttf",
        800: "res://assets/fonts/Montserrat-ExtraBold.ttf",
}
const SOURCE_PATHS := {
        400: "res://assets/fonts/SourceSans3-Regular.ttf",
        600: "res://assets/fonts/SourceSans3-Semibold.ttf",
        700: "res://assets/fonts/SourceSans3-Bold.ttf",
}

static var _voice_cache: Dictionary = {}
static var _cursors_applied := false


## The Gotham voice — titles and buttons (weight 400..800).
static func gotham(weight := 600) -> Font:
        return _voice(GOTHAM_PATHS, 700, weight)


## The Source Sans voice — chat, body copy, stats (weight 400..700).
static func source(weight := 400) -> Font:
        return _voice(SOURCE_PATHS, 400, weight)


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
## ONE surface — the Roblox elevation read: a near-black rounded face with a
## big soft shadow and NO border. The whole window is built from this.
static func surface(radius := 12, face := MENU_BG, shadow := 16, shadow_a := 0.42) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = face
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        if shadow > 0:
                sb.shadow_color = Color(0, 0, 0, shadow_a)
                sb.shadow_size = shadow
                sb.shadow_offset = Vector2(0, 4)
        return sb


## Legacy one-voice surface (kept for callers that want a hairline border).
static func mono_surface(radius := 12, face := MENU_BG, outline := MENU_EDGE,
                outline_w := 0) -> StyleBoxFlat:
        var sb := surface(radius, face, 0, 0.0)
        if outline_w > 0:
                sb.set_border_width_all(outline_w)
                sb.border_color = outline
        return sb


## An input well — the quiet inset face for typing and portrait seats.
static func well(radius := 10, face := WELL) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = face
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        return sb


## A soft white wash (hover state on dark pills).
static func wash(alpha: float, radius := 10) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(1, 1, 1, alpha)
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
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
## (the Roblox glyph read, not chunky pixels), in ANY ink you ask: a play
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
        var title: Font = gotham(700)
        var semi: Font = gotham(600)
        var body: Font = source(400)
        var book: Font = source(600)

        # ---- Button — the dark key: elevated face, NO border, white ink ----
        t.set_stylebox("normal", "Button", _key_style(PANEL))
        t.set_stylebox("hover", "Button", _key_style(PANEL_HOVER))
        t.set_stylebox("pressed", "Button", _key_style(PANEL_DOWN))
        t.set_stylebox("disabled", "Button", _key_style(Color("1d1f23")))
        t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
        t.set_color("font_color", "Button", TEXT)
        t.set_color("font_hover_color", "Button", TEXT)
        t.set_color("font_pressed_color", "Button", TEXT_MUTED)
        t.set_color("font_disabled_color", "Button", Color("6b7076"))
        t.set_font_size("font_size", "Button", 13)
        if semi != null:
                t.set_font("font", "Button", semi)

        # ---- Button variations — the fills (white primary, blue, green, red) ----
        var fill_var := func(var_name: String, bg: Color, hover: Color, down: Color,
                        ink: Color) -> void:
                t.set_type_variation(var_name, "Button")
                t.set_stylebox("normal", var_name, _key_style(bg))
                t.set_stylebox("hover", var_name, _key_style(hover))
                t.set_stylebox("pressed", var_name, _key_style(down))
                t.set_color("font_color", var_name, ink)
                t.set_color("font_hover_color", var_name, ink)
                t.set_color("font_pressed_color", var_name, ink)
        # the WHITE primary — Roblox's Resume key: white face, dark ink
        fill_var.call("BtnWhite", Color("ffffff"), Color("e8e9ea"), Color("d5d7d9"), TEXT_INV)
        fill_var.call("BtnBlue", BLUE, MENU_ACCENT_HI, MENU_ACCENT_DARK, Color.WHITE)
        fill_var.call("BtnGreen", GREEN, Color("1ec582"), Color("00955c"), Color.WHITE)
        fill_var.call("BtnRed", RED, Color("ff6b6b"), Color("d93b3b"), Color.WHITE)
        t.set_font_size("font_size", "BtnWhite", 14)
        t.set_font_size("font_size", "BtnBlue", 14)
        if title != null:
                t.set_font("font", "BtnWhite", title)
                t.set_font("font", "BtnBlue", title)

        t.set_type_variation("BtnGhost", "Button")
        t.set_stylebox("normal", "BtnGhost", wash(0.05, 10))
        t.set_stylebox("hover", "BtnGhost", wash(0.10, 10))
        t.set_stylebox("pressed", "BtnGhost", wash(0.14, 10))
        t.set_color("font_color", "BtnGhost", TEXT_MUTED)
        t.set_color("font_hover_color", "BtnGhost", TEXT)
        t.set_color("font_pressed_color", "BtnGhost", TEXT)
        t.set_font_size("font_size", "BtnGhost", 13)
        if semi != null:
                t.set_font("font", "BtnGhost", semi)

        # ---- Label — white ink, Source Sans body, Montserrat titles ----
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
        if semi != null:
                t.set_type_variation("H2", "Label")
                t.set_font("font", "H2", semi)
                t.set_font_size("font_size", "H2", 15)
                t.set_type_variation("Name", "Label")
                t.set_font("font", "Name", semi)
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

        # ---- LineEdit — quiet well, blue caret, NO border until focus ----
        t.set_stylebox("normal", "LineEdit", well(10))
        var focus_well := well(10)
        focus_well.set_border_width_all(2)
        focus_well.border_color = BLUE
        t.set_stylebox("focus", "LineEdit", focus_well)
        t.set_stylebox("read_only", "LineEdit", well(10))
        t.set_color("font_color", "LineEdit", TEXT)
        t.set_color("font_placeholder_color", "LineEdit", MENU_FAINT)
        t.set_color("caret_color", "LineEdit", BLUE)
        t.set_color("selection_color", "LineEdit", Color(0.0, 0.635, 1.0, 0.35))
        t.set_font_size("font_size", "LineEdit", 15)
        if body != null:
                t.set_font("font", "LineEdit", body)

        # ---- Panels ----
        t.set_stylebox("panel", "PanelContainer", surface(12, PANEL))
        t.set_stylebox("panel", "Panel", surface(12, PANEL))
        t.set_type_variation("Card", "PanelContainer")
        t.set_stylebox("panel", "Card", surface(14, CARD, 10, 0.3))
        t.set_type_variation("DarkPanel", "PanelContainer")
        t.set_stylebox("panel", "DarkPanel", surface(12, MENU_BG))

        # ---- Progress bar (health) ----
        t.set_stylebox("background", "ProgressBar", well(9))
        t.set_stylebox("fill", "ProgressBar", well(9, GREEN))
        t.set_color("font_color", "ProgressBar", TEXT)

        # ---- Scroll bars — quiet rounded steel ----
        var grab := wash(0.14, 5)
        var grab_hi := wash(0.22, 5)
        for bar in ["VScrollBar", "HScrollBar"]:
                t.set_stylebox("grabber", bar, grab)
                t.set_stylebox("grabber_highlight", bar, grab_hi)
                t.set_stylebox("grabber_pressed", bar, grab_hi)
                t.set_stylebox("scroll", bar, StyleBoxEmpty.new())

        # ---- Tooltips — near-black card, white ink ----
        t.set_stylebox("panel", "TooltipPanel", surface(8, Color("101215"), 8, 0.4))
        t.set_color("font_color", "TooltipLabel", TEXT)
        t.set_font_size("font_size", "TooltipLabel", 12)
        if body != null:
                t.set_font("font", "TooltipLabel", body)

        # ---- CheckButton / slider grabs — white ink, blue fill ----
        t.set_color("font_color", "CheckButton", TEXT)
        t.set_color("font_hover_color", "CheckButton", TEXT)
        t.set_color("font_pressed_color", "CheckButton", TEXT)
        t.set_font_size("font_size", "CheckButton", 13)
        if body != null:
                t.set_font("font", "CheckButton", body)
        var grabber := well(4, BLUE)
        t.set_stylebox("slider", "HSlider", well(4, Color("313438")))
        t.set_stylebox("grabber_area", "HSlider", grabber)
        t.set_stylebox("grabber_area_highlight", "HSlider", grabber)

        return t


static func _key_style(face: Color) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = face
        sb.set_corner_radius_all(10)
        sb.anti_aliasing = true
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        return sb


## One shared instance (cheap to reuse across scene changes).
static var shared: Theme = make_theme()
