class_name RetroTheme
extends RefCounted
## v8.0 "REAL BLOX" — the client's ONE voice, rebuilt to speak the REAL
## ROBLOX CLIENT: deep #111316 backdrops, #232527 rounded-8 surfaces with no
## bevels and no borders, black translucent topbar pills, the WHITE primary
## key (Resume / Log In — exactly the client's read), Roblox fountain-blue
## as the single accent, and Montserrat carrying every title, key and name
## (Builder Sans' closest free voice). Profile pictures are REAL Roblox
## avatar headshots via PfpService — never a 3D render again.

const BG := Color("111316")          # the client backdrop (login + menu)
const PANEL := Color("232527")       # the surface (cards, rows, rails)
const PANEL_HOVER := Color("35373b")
const PANEL_DOWN := Color("1b1d21")
const CARD := Color("232527")
const WELL := Color("191b1f")        # inputs / insets
const EDGE := Color("3a3f46")        # the subtle 1px rule between surfaces
const TEXT := Color("ffffff")
const TEXT_MUTED := Color("b8bcc2")
const TEXT_INV := Color("111316")    # ink on the WHITE key
const GREEN := Color("00b06f")       # health green
const RED := Color("f44250")         # the danger red
const BLUE := Color("335fff")        # fountain blue — the ONE accent
const BLUE_HI := Color("5077ff")

const STEEL_TEXTURE_PATH := "res://assets/ui/steel_panel.jpg"   # (legacy, unused)
const CURSOR_ARROW_PATH := "res://assets/ui/cursor_hand.png"      # uploaded RetroBlox Cursor
const CURSOR_HAND_PATH := "res://assets/ui/cursor_pointer.png"    # uploaded RetroBlox Pointer
const PFP_DIR := "res://assets/pfp"    # bundled real headshots (username.png)

# ------------------------------------------------------------- v8.0 client
## The menu's palette — the SAME surfaces, named for the menu callers.

const MENU_BG := Color(0.067, 0.075, 0.086, 0.97)   # #111316 full-screen veil
const MENU_PANEL := Color("232527")                  # surface
const MENU_PANEL_HI := Color("35373b")               # hover / open row
const MENU_EDGE := Color("3a3f46")                   # the quiet rule
const MENU_INK := Color("ffffff")                    # primary text
const MENU_MUTED := Color("b8bcc2")                  # secondary text
const MENU_FAINT := Color("7c8085")                  # hints / version tags
const MENU_ACCENT := Color("335fff")                 # the ONE accent
const MENU_ACCENT_HI := Color("5077ff")
const MENU_ACCENT_DARK := Color("2a4fd1")
const MENU_ACCENT_SOFT := Color(0.2, 0.373, 1.0, 0.16)   # selected row fill
const MENU_RED := Color("f44250")
const MENU_GREEN := Color("00b06f")
const PILL := Color(0.0, 0.0, 0.0, 0.65)             # the topbar pill

# ---------------------------------------------------------------- voices
## ONE family: Montserrat (the Builder Sans stand-in) for titles, buttons,
## names; Source Sans 3 stays for the chat log body; arial() is kept as a
## legacy alias and also speaks Montserrat so every caller matches.

const MONT_PATHS := {
        400: "res://assets/fonts/Montserrat-Regular.ttf",
        500: "res://assets/fonts/Montserrat-Medium.ttf",
        600: "res://assets/fonts/Montserrat-SemiBold.ttf",
        700: "res://assets/fonts/Montserrat-Bold.ttf",
        800: "res://assets/fonts/Montserrat-ExtraBold.ttf",
}
const ARIAL_PATHS := MONT_PATHS      # legacy alias — one family now
const SOURCE_PATHS := {
        400: "res://assets/fonts/SourceSans3-Regular.ttf",
        600: "res://assets/fonts/SourceSans3-Semibold.ttf",
        700: "res://assets/fonts/SourceSans3-Bold.ttf",
}

static var _font_cache: Dictionary = {}


static func arial(weight := 400) -> Font:
        return _voice(MONT_PATHS, 400, weight)


static func gotham(weight := 600) -> Font:
        return _voice(MONT_PATHS, 600, weight)


static func source(weight := 400) -> Font:
        return _voice(SOURCE_PATHS, 400, weight)


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


# ---------------------------------------------------------------- surfaces
## The modern client has NO bevels and NO borders: flat rounded-8 surfaces
## on a deeper backdrop, elevation done with soft shadows only.

static func raised(radius := 8, face := PANEL, shadow := 0, shadow_a := 0.5) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = face
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        if shadow > 0 and shadow_a > 0.0:
                sb.shadow_color = Color(0, 0, 0, shadow_a)
                sb.shadow_size = shadow
                sb.shadow_offset = Vector2(0, 4)
        return sb


static func sunken(radius := 8, face := WELL, border_px := 0, border_col := EDGE) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = face
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        if border_px > 0:
                sb.set_border_width_all(border_px)
                sb.border_color = border_col
        return sb


static func flat(radius := 8, face := PANEL) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = face
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        return sb


## The People card / surface card.
static func card(radius := 8, face := PANEL) -> StyleBoxFlat:
        return flat(radius, face)


## The TOPBAR PILL — black 65%, rounded 8: exactly the real client's read.
static func pill_style() -> StyleBoxFlat:
        var sb := flat(8, PILL)
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
static func wash(alpha: float, radius := 8) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(1, 1, 1, alpha)
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        return sb


## The translucent dark float — chat, tooltips. Rounded 8, no frame.
static func glass(alpha := 0.8, radius := 8) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0, 0, 0, alpha)
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
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


static var _cursors_applied := false


## Build the shared Theme. Scene roots apply it: `theme = RetroTheme.make_theme()`.
static func make_theme() -> Theme:
        var t := Theme.new()
        var title: Font = gotham(700)
        var semi: Font = gotham(600)
        var body: Font = gotham(400)

        # ---- Button — the client's quiet dark key, rounded 8 ----
        t.set_stylebox("normal", "Button", _key_style(Color("2e3136")))
        t.set_stylebox("hover", "Button", _key_style(PANEL_HOVER))
        t.set_stylebox("pressed", "Button", _key_style(PANEL_DOWN))
        t.set_stylebox("disabled", "Button", _key_style(Color("232527")))
        t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
        t.set_color("font_color", "Button", TEXT)
        t.set_color("font_hover_color", "Button", TEXT)
        t.set_color("font_pressed_color", "Button", TEXT_MUTED)
        t.set_color("font_disabled_color", "Button", Color("6a6e74"))
        t.set_font_size("font_size", "Button", 14)
        if semi != null:
                t.set_font("font", "Button", semi)

        # ---- Button variations — the client's fills ----
        var fill_var := func(var_name: String, bg: Color, hover: Color, down: Color,
                        ink: Color, weight := 600) -> void:
                t.set_type_variation(var_name, "Button")
                t.set_stylebox("normal", var_name, _key_style(bg))
                t.set_stylebox("hover", var_name, _key_style(hover))
                t.set_stylebox("pressed", var_name, _key_style(down))
                t.set_color("font_color", var_name, ink)
                t.set_color("font_hover_color", var_name, ink)
                t.set_color("font_pressed_color", var_name, ink)
                var f: Font = gotham(weight)
                if f != null:
                        t.set_font("font", var_name, f)
        # THE WHITE KEY — Resume / Log In, exactly the real client's read
        fill_var.call("BtnPrimary", Color("ffffff"), Color("e2e2e2"), Color("cfcfcf"), TEXT_INV, 700)
        fill_var.call("BtnBlue", BLUE, BLUE_HI, MENU_ACCENT_DARK, Color.WHITE)
        fill_var.call("BtnGreen", GREEN, Color("0bc37f"), Color("00955b"), Color.WHITE)
        fill_var.call("BtnRed", RED, Color("ff5a66"), Color("d13340"), Color.WHITE)
        fill_var.call("BtnDark", PANEL, Color("2e3136"), PANEL_DOWN, TEXT)
        # dark key, red ink — the Leave read
        fill_var.call("BtnDangerDark", PANEL, Color("3a2326"), Color("2a191b"), RED)
        t.set_font_size("font_size", "BtnPrimary", 14)
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

        # ---- Label — white ink, Montserrat everywhere ----
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

        # ---- LineEdit — the dark rounded well, white focus ring ----
        var le := StyleBoxFlat.new()
        le.bg_color = WELL
        le.set_corner_radius_all(8)
        le.anti_aliasing = true
        le.set_border_width_all(1)
        le.border_color = EDGE
        le.content_margin_left = 12.0
        le.content_margin_right = 12.0
        le.content_margin_top = 10.0
        le.content_margin_bottom = 10.0
        var le_focus := le.duplicate() as StyleBoxFlat
        le_focus.set_border_width_all(2)
        le_focus.border_color = Color.WHITE
        t.set_stylebox("normal", "LineEdit", le)
        t.set_stylebox("focus", "LineEdit", le_focus)
        t.set_stylebox("read_only", "LineEdit", le)
        t.set_color("font_color", "LineEdit", TEXT)
        t.set_color("font_placeholder_color", "LineEdit", Color("6a6e74"))
        t.set_color("caret_color", "LineEdit", TEXT)
        t.set_color("selection_color", "LineEdit", Color(0.2, 0.373, 1.0, 0.35))
        t.set_font_size("font_size", "LineEdit", 15)
        if body != null:
                t.set_font("font", "LineEdit", body)

        # ---- Panels — the rounded surface ----
        t.set_stylebox("panel", "PanelContainer", flat(8, PANEL))
        t.set_stylebox("panel", "Panel", flat(8, PANEL))
        t.set_type_variation("Card", "PanelContainer")
        t.set_stylebox("panel", "Card", flat(8, PANEL))
        t.set_type_variation("DarkPanel", "PanelContainer")
        t.set_stylebox("panel", "DarkPanel", flat(8, PANEL))

        # ---- Progress bar (health) ----
        t.set_stylebox("background", "ProgressBar", flat(8, Color(0, 0, 0, 0.65)))
        t.set_stylebox("fill", "ProgressBar", flat(6, GREEN))
        t.set_color("font_color", "ProgressBar", TEXT)

        # ---- Scroll bars — quiet white grabs ----
        var grab := flat(4, Color(1, 1, 1, 0.18))
        var grab_hi := flat(4, Color(1, 1, 1, 0.28))
        for bar in ["VScrollBar", "HScrollBar"]:
                t.set_stylebox("grabber", bar, grab)
                t.set_stylebox("grabber_highlight", bar, grab_hi)
                t.set_stylebox("grabber_pressed", bar, grab_hi)
                t.set_stylebox("scroll", bar, StyleBoxEmpty.new())

        # ---- Tooltips — the dark rounded tip ----
        t.set_stylebox("panel", "TooltipPanel", glass(0.94))
        t.set_color("font_color", "TooltipLabel", TEXT)
        t.set_font_size("font_size", "TooltipLabel", 12)
        if body != null:
                t.set_font("font", "TooltipLabel", body)

        # ---- CheckButton / slider — white ink, blue fill ----
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


static func _key_style(face: Color) -> StyleBoxFlat:
        var sb := flat(8, face)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        return sb


## One shared instance (cheap to reuse across scene changes).
static var shared: Theme = make_theme()
