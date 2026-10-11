class_name RetroTheme
extends RefCounted
## v4.0 "SKID" — the client's ONE voice, restyled as the 2016 daylight site:
## clean white cards on soft gray, near-black ink, ONE bright accent
## (RetroBlox blue #00A2FF), round corners and soft shadows everywhere.
## Two type voices: a clean sans (Liberation Bold — the 2016 site look)
## carries titles, buttons and body text; the Press Start 2P pixel voice
## stays as the retro garnish (stats, clocks, keycaps, version tags).
## Everything is built in code so the whole client shares one place to restyle.

const BG := Color("e9eff5")          # soft daylight backdrop (login)
const PANEL := Color("ffffff")       # clean white panel face
const PANEL_HOVER := Color("f5f8fa")
const PANEL_DOWN := Color("e7edf3")
const CARD := Color("ffffff")        # card face
const WELL := Color("ffffff")        # input well white
const EDGE_LIGHT := Color("ffffff")
const EDGE_DARK := Color("c7d0da")   # the quiet gray border
const HEADER := Color("2e6da4")      # (legacy steel-blue, kept harmless)
const HEADER_DARK := Color("20517a")
const TEXT := Color("1e2733")        # near-black ink
const TEXT_MUTED := Color("5d6875")
const TEXT_INV := Color("ffffff")
const GREEN := Color("2bb24c")       # health fill + success
const GREEN_HI := Color("3ec95f")
const GREEN_DARK := Color("1e8f3a")
const RED := Color("e2231a")         # danger
const RED_DARK := Color("b91a12")
const BLUE := Color("00a2ff")        # THE accent
const BLUE_HI := Color("33b5ff")
const BLUE_DARK := Color("0091e6")
const GOLD := Color("e2b23a")
const LINK := Color("0091d5")

const PIXEL_FONT_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"
const CLEAN_FONT_PATH := "res://assets/fonts/LiberationSans-Bold.ttf"
const CLEAN_BOOK_PATH := "res://assets/fonts/LiberationSans-Regular.ttf"
const STEEL_TEXTURE_PATH := "res://assets/ui/steel_panel.jpg"
const CURSOR_ARROW_PATH := "res://assets/ui/cursor_hand.png"      # uploaded RetroBlox Cursor
const CURSOR_HAND_PATH := "res://assets/ui/cursor_pointer.png"   # uploaded RetroBlox Pointer

static var _pixel_font: Font = null
static var _clean_font: Font = null
static var _clean_book: Font = null
static var _steel_tex: Texture2D = null
static var _cursors_applied := false


## The retro pixel voice — the small retro garnish (null-safe everywhere).
static func pixel_font() -> Font:
        if _pixel_font == null and ResourceLoader.exists(PIXEL_FONT_PATH):
                _pixel_font = load(PIXEL_FONT_PATH)
        return _pixel_font


## The clean 2016 voice — Liberation Bold carries titles and buttons.
static func clean_font() -> Font:
        if _clean_font == null and ResourceLoader.exists(CLEAN_FONT_PATH):
                _clean_font = load(CLEAN_FONT_PATH)
        return _clean_font


## The clean book weight — body text and inputs.
static func clean_book() -> Font:
        if _clean_book == null and ResourceLoader.exists(CLEAN_BOOK_PATH):
                _clean_book = load(CLEAN_BOOK_PATH)
        return _clean_book


## The brushed-steel plate — legacy, null when the file is missing.
static func steel_texture() -> Texture2D:
        if _steel_tex == null and ResourceLoader.exists(STEEL_TEXTURE_PATH):
                _steel_tex = load(STEEL_TEXTURE_PATH)
        return _steel_tex


# ---------------------------------------------------------------- v4.0 skid
## The client window's ONE palette — light & clean, as chosen: white glass
## faces, near-black ink, a quiet gray border, soft shadows, ROUND corners,
## and RetroBlox blue as the single bright accent (active states, the
## primary key, links). No gradients anywhere.

const MENU_BG := Color(0.995, 0.998, 1.0, 0.97)      # the window face — white glass
const MENU_PANEL := Color(0.949, 0.961, 0.976)       # #F2F5F8 — rail / footer faces
const MENU_PANEL_HI := Color(0.906, 0.929, 0.953)    # hover faces #E7EDF3
const MENU_EDGE := Color(0.78, 0.825, 0.87)          # the quiet gray border
const MENU_INK := Color("1d2632")                    # primary text — near-black
const MENU_MUTED := Color("5c6673")                  # secondary text
const MENU_FAINT := Color("97a1ad")                  # hints / version tags
const MENU_ACCENT := Color("00a2ff")                 # the ONE bright accent
const MENU_ACCENT_HI := Color("33b5ff")
const MENU_ACCENT_DARK := Color("0091e6")
const MENU_ACCENT_SOFT := Color("e3f4ff")            # active chip fill
const MENU_RED := Color("e2231a")
const MENU_GREEN := Color("2bb24c")


## One light surface — white face, quiet gray border, ROUND corners.
## The whole window is built from this: window, bars, cards, wells.
static func mono_surface(radius := 12, face := MENU_BG, outline := MENU_EDGE,
                outline_w := 1) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = face
        sb.set_border_width_all(outline_w)
        sb.border_color = outline
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        return sb


# ---------------------------------------------------------------- retro bits

static var _bevel_cache: Dictionary = {}

## A TRUE classic keycap, drawn pixel by pixel (16x16, cached): 1px outline,
## a 2px LIGHT top/left edge and a 2px DARK bottom/right edge on `bg` —
## the raised bevel. `pressed` flips it so the face sinks. Used by the hint
## keycaps and the animation keys (light gray caps in v4.0).
static func bevel_texture(bg: Color, pressed := false) -> StyleBoxTexture:
        var key := "%s_%s" % [bg.to_html(false), pressed]
        if _bevel_cache.has(key):
                return _bevel_cache[key]
        var w := 16
        var img := Image.create_empty(w, w, false, Image.FORMAT_RGBA8)
        var light := bg.lightened(0.34)
        var light_hi := bg.lightened(0.52)
        var dark := bg.darkened(0.46)
        var dark_lo := bg.darkened(0.2)
        var outline := bg.darkened(0.62)
        for y in range(w):
                for x in range(w):
                        var col := bg
                        if x == 0 or y == 0 or x == w - 1 or y == w - 1:
                                col = outline
                        elif pressed:
                                # sunk keycap: dark bevel top/left, light below
                                if x <= 2 or y <= 2:
                                        col = dark
                                elif x >= w - 3 or y >= w - 3:
                                        col = light
                        else:
                                # raised keycap: light bevel top/left, dark below
                                if x <= 1 or y <= 1:
                                        col = light_hi
                                elif x == 2 or y == 2:
                                        col = light
                                elif x >= w - 2 or y >= w - 2:
                                        col = dark
                                elif x == w - 3 or y == w - 3:
                                        col = dark_lo
                        img.set_pixel(x, y, col)
        var sb := StyleBoxTexture.new()
        sb.texture = ImageTexture.create_from_image(img)
        for side in ["left", "right", "top", "bottom"]:
                sb.set("texture_margin_" + side, 3.0)
        _bevel_cache[key] = sb
        return sb


## The classic YELLOW smiley head — the 2016 People-page fallback. Drawn in
## code; holds every portrait seat until the real render lands.
static func head_icon() -> ImageTexture:
        if _bevel_cache.has("head"):
                return _bevel_cache["head"]
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
        var tex := ImageTexture.create_from_image(img)
        _bevel_cache["head"] = tex
        return tex


## Small ACTION icons, drawn pixel by pixel, in ANY ink you ask (cache is
## keyed by kind + color): a play triangle (Resume), a reset arrow, a door
## (Leave), a power symbol (Log Out), the people crowd, a gear, and the
## chat bubble for the topbar pill.
static func icon_texture(kind: String, ink := Color(1, 1, 1, 0.96)) -> ImageTexture:
        var cache_key := "icon_" + kind + "_" + ink.to_html()
        if _bevel_cache.has(cache_key):
                return _bevel_cache[cache_key]
        var w := 18
        var img := Image.create_empty(w, w, false, Image.FORMAT_RGBA8)
        match kind:
                "play":
                        # the classic play triangle
                        for x in range(4, 14):
                                var half := int(round(float(x - 4) * 5.0 / 9.0))
                                for y in range(9 - half, 9 + half + 1):
                                        img.set_pixel(x, y, ink)
                "door":
                        # a doorway with frame + knob
                        for x in range(4, 14):
                                img.set_pixel(x, 2, ink)
                                img.set_pixel(x, 15, ink)
                        for y in range(2, 16):
                                img.set_pixel(4, y, ink)
                                img.set_pixel(13, y, ink)
                                img.set_pixel(6, y, ink)
                        img.set_pixel(11, 9, ink)
                        img.set_pixel(11, 10, ink)
                "reset":
                        # a circular arrow: arc + chunky arrowhead at the top
                        var center := Vector2(9.0, 9.5)
                        for y in range(w):
                                for x in range(w):
                                        var d := Vector2(float(x) + 0.5, float(y) + 0.5) - center
                                        var r := d.length()
                                        if r < 3.6 or r > 5.6:
                                                continue
                                        var ang := atan2(-d.y, d.x)   # 0 = right, CCW
                                        if ang < 0:
                                                ang += TAU
                                        if ang > 0.55 and ang < 5.5:
                                                img.set_pixel(x, y, ink)
                        # the arrowhead: a wedge riding the top of the arc
                        for ay in range(2, 7):
                                for ax in range(8, 8 + ay - 1):
                                        img.set_pixel(ax, ay, ink)
                "power":
                        var center := Vector2(9.0, 10.0)
                        for y in range(w):
                                for x in range(w):
                                        var d := Vector2(float(x) + 0.5, float(y) + 0.5) - center
                                        var r := d.length()
                                        if r < 3.8 or r > 5.8:
                                                continue
                                        var ang := atan2(-d.y, d.x)
                                        if absf(ang - PI / 2.0) < 0.6:
                                                continue   # the gap at the TOP
                                        img.set_pixel(x, y, ink)
                        for y in range(2, 9):
                                img.set_pixel(8, y, ink)
                                img.set_pixel(9, y, ink)
                "people":
                        # two chunky heads + shoulders, the People tab mark
                        for hx in [4, 10]:
                                for ey in range(2):
                                        for ex in range(2):
                                                img.set_pixel(hx + ex, 4 + ey, ink)
                                # round the heads: side pixels
                                img.set_pixel(hx - 1, 5, ink)
                                img.set_pixel(hx + 2, 5, ink)
                        # shoulders: a bar under each head
                        for sx in range(3, 8):
                                img.set_pixel(sx, 9, ink)
                        for sx in range(9, 14):
                                img.set_pixel(sx, 9, ink)
                        # a shared body bar
                        for sx in range(3, 15):
                                img.set_pixel(sx, 12, ink)
                                img.set_pixel(sx, 13, ink)
                "gear":
                        # an 8-tooth gear around a hole
                        var gc := Vector2(9.0, 9.0)
                        for y in range(w):
                                for x in range(w):
                                        var d := Vector2(float(x) + 0.5, float(y) + 0.5) - gc
                                        var r := d.length()
                                        var ang := atan2(d.y, d.x)
                                        var tooth := absf(fposmod(ang / PI * 4.0, 1.0) - 0.5) > 0.28
                                        if (r >= 3.0 and r <= 5.4) or (tooth and r >= 2.0 and r <= 6.4):
                                                if r > 1.8:
                                                        img.set_pixel(x, y, ink)
                "chat":
                        # a chunky filled speech bubble + tail — the pill's chat key
                        for y in range(3, 12):
                                for x in range(2, 16):
                                        var p := Vector2(float(x) + 0.5, float(y) + 0.5)
                                        if _in_rounded_px(p, Rect2(2, 3, 14, 9), 3.0):
                                                img.set_pixel(x, y, ink)
                        for t in range(3):
                                for x in range(6 + t, 11 - t):
                                        img.set_pixel(x, 12 + t, ink)
        var tex := ImageTexture.create_from_image(img)
        _bevel_cache[cache_key] = tex
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


static func _flat(bg: Color, border: Color, width := 2, radius := 3) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = bg
        sb.set_border_width_all(width)
        sb.border_color = border
        sb.set_corner_radius_all(radius)
        sb.anti_aliasing = true
        return sb


static func _panel_style() -> StyleBoxFlat:
        var sb := _flat(PANEL, EDGE_DARK, 1, 10)
        sb.shadow_color = Color(0.12, 0.2, 0.3, 0.10)
        sb.shadow_size = 8
        sb.shadow_offset = Vector2(0, 3)
        return sb


static func _card_style() -> StyleBoxFlat:
        var sb := _flat(CARD, EDGE_DARK, 1, 10)
        sb.shadow_color = Color(0.12, 0.2, 0.3, 0.08)
        sb.shadow_size = 6
        sb.shadow_offset = Vector2(0, 2)
        return sb


static func _header_style() -> StyleBox:
        # legacy brushed steel (unused by the v4.0 surfaces, kept for the theme)
        var tex := steel_texture()
        if tex != null:
                var sb := StyleBoxTexture.new()
                sb.texture = tex
                sb.modulate_color = Color(0.5, 0.6, 0.72)
                sb.content_margin_left = 12.0
                sb.content_margin_right = 12.0
                sb.content_margin_top = 8.0
                sb.content_margin_bottom = 8.0
                return sb
        var sb2 := _flat(HEADER, HEADER_DARK, 2, 3)
        sb2.border_width_bottom = 3
        return sb2


static func _button_style(bg: Color, edge: Color) -> StyleBoxFlat:
        var sb := _flat(bg, edge, 1, 8)
        sb.content_margin_left = 12.0
        sb.content_margin_right = 12.0
        sb.content_margin_top = 6.0
        sb.content_margin_bottom = 6.0
        return sb


static func _well_style() -> StyleBoxFlat:
        var sb := _flat(WELL, EDGE_DARK, 1, 8)
        sb.content_margin_left = 8.0
        sb.content_margin_right = 8.0
        sb.content_margin_top = 5.0
        sb.content_margin_bottom = 5.0
        return sb


## Build the shared Theme. Scene roots apply it: `theme = RetroTheme.make_theme()`.
static func make_theme() -> Theme:
        var t := Theme.new()
        var pixel: Font = pixel_font()
        var clean: Font = clean_font()
        var book: Font = clean_book()

        # ---- Button — the clean white key: quiet gray border, ink text ----
        t.set_stylebox("normal", "Button", _button_style(PANEL, EDGE_DARK))
        t.set_stylebox("hover", "Button", _button_style(PANEL_HOVER, EDGE_DARK))
        t.set_stylebox("pressed", "Button", _button_style(PANEL_DOWN, EDGE_DARK))
        t.set_stylebox("disabled", "Button", _button_style(Color("eef2f6"), Color("d4dce4")))
        var focus := _flat(Color(0, 0, 0, 0), BLUE, 2, 8)
        t.set_stylebox("focus", "Button", focus)
        t.set_color("font_color", "Button", TEXT)
        t.set_color("font_hover_color", "Button", TEXT)
        t.set_color("font_pressed_color", "Button", TEXT)
        t.set_color("font_disabled_color", "Button", Color("9aa5b1"))
        t.set_font_size("font_size", "Button", 13)
        if clean != null:
                t.set_font("font", "Button", clean)

        # ---- Button variations — the accent fills (blue primary, green play) ----
        var fill_var := func(var_name: String, bg: Color, hover: Color, down: Color) -> void:
                t.set_type_variation(var_name, "Button")
                t.set_stylebox("normal", var_name, _flat(bg, Color(0, 0, 0, 0.08), 1, 9))
                t.set_stylebox("hover", var_name, _flat(hover, Color(0, 0, 0, 0.08), 1, 9))
                t.set_stylebox("pressed", var_name, _flat(down, Color(0, 0, 0, 0.08), 1, 9))
                t.set_color("font_color", var_name, Color.WHITE)
                t.set_color("font_hover_color", var_name, Color.WHITE)
                t.set_color("font_pressed_color", var_name, Color.WHITE)
        fill_var.call("BtnBlue", BLUE, BLUE_HI, BLUE_DARK)
        fill_var.call("BtnGreen", GREEN, GREEN_HI, GREEN_DARK)
        fill_var.call("BtnRed", RED, Color("ea4a42"), RED_DARK)
        t.set_stylebox("disabled", "BtnGreen", _flat(Color("9ed4ab"), Color(0, 0, 0, 0.05), 1, 9))
        t.set_color("font_disabled_color", "BtnGreen", Color("f2f8f3"))
        t.set_font_size("font_size", "BtnGreen", 15)
        t.set_font_size("font_size", "BtnBlue", 15)

        t.set_type_variation("BtnGhost", "Button")
        t.set_stylebox("normal", "BtnGhost", _button_style(Color(0, 0, 0, 0.05), Color(0, 0, 0, 0.10)))
        t.set_stylebox("hover", "BtnGhost", _button_style(Color(0, 0, 0, 0.09), Color(0, 0, 0, 0.14)))
        t.set_stylebox("pressed", "BtnGhost", _button_style(Color(0, 0, 0, 0.13), Color(0, 0, 0, 0.16)))
        t.set_color("font_color", "BtnGhost", TEXT)
        t.set_color("font_hover_color", "BtnGhost", TEXT)
        t.set_color("font_pressed_color", "BtnGhost", TEXT)
        t.set_font_size("font_size", "BtnGhost", 12)

        # ---- Label — ink by default, clean book for body ----
        t.set_color("font_color", "Label", TEXT)
        t.set_font_size("font_size", "Label", 14)
        if book != null:
                t.set_font("font", "Label", book)
        for pair in [["H1", 20], ["H2", 15], ["Small", 12]]:
                t.set_type_variation(String(pair[0]), "Label")
                t.set_font_size("font_size", String(pair[0]), int(pair[1]))
                if String(pair[0]) != "Small" and clean != null:
                        t.set_font("font", String(pair[0]), clean)
        t.set_type_variation("Muted", "Label")
        t.set_color("font_color", "Muted", TEXT_MUTED)
        t.set_font_size("font_size", "Muted", 12)
        t.set_type_variation("Inverse", "Label")
        t.set_color("font_color", "Inverse", TEXT_INV)
        t.set_type_variation("InverseSmall", "Label")
        t.set_color("font_color", "InverseSmall", TEXT_INV)
        t.set_font_size("font_size", "InverseSmall", 12)
        t.set_type_variation("Error", "Label")
        t.set_color("font_color", "Error", RED)
        if pixel != null:
                # the retro garnish voice — stats, clocks, keycaps, versions
                t.set_type_variation("Retro", "Label")
                t.set_font("font", "Retro", pixel)
                t.set_font_size("font_size", "Retro", 8)

        # ---- LineEdit — white well, quiet border, blue caret ----
        t.set_stylebox("normal", "LineEdit", _well_style())
        var focus_well := _flat(WELL, BLUE, 2, 8)
        focus_well.content_margin_left = 8.0
        focus_well.content_margin_right = 8.0
        focus_well.content_margin_top = 5.0
        focus_well.content_margin_bottom = 5.0
        t.set_stylebox("focus", "LineEdit", focus_well)
        t.set_stylebox("read_only", "LineEdit", _well_style())
        t.set_color("font_color", "LineEdit", TEXT)
        t.set_color("font_placeholder_color", "LineEdit", Color("9aa5b1"))
        t.set_color("caret_color", "LineEdit", BLUE)
        t.set_color("selection_color", "LineEdit", Color("b9e2ff", 0.65))
        t.set_font_size("font_size", "LineEdit", 15)
        if book != null:
                t.set_font("font", "LineEdit", book)

        # ---- Panels ----
        t.set_stylebox("panel", "PanelContainer", _panel_style())
        t.set_stylebox("panel", "Panel", _panel_style())
        t.set_type_variation("Card", "PanelContainer")
        t.set_stylebox("panel", "Card", _card_style())
        t.set_type_variation("DarkPanel", "PanelContainer")
        t.set_stylebox("panel", "DarkPanel", _flat(Color("223140", 0.92), Color("0e1a24"), 2, 4))
        t.set_type_variation("SteelHeader", "PanelContainer")
        t.set_stylebox("panel", "SteelHeader", _header_style())

        # ---- Progress bar (health) ----
        var bg_bar := _flat(Color("e7edf3"), Color("d4dce4"), 1, 3)
        t.set_stylebox("background", "ProgressBar", bg_bar)
        var fill_bar := _flat(GREEN, Color(0, 0, 0, 0), 0, 3)
        t.set_stylebox("fill", "ProgressBar", fill_bar)
        t.set_color("font_color", "ProgressBar", TEXT)

        # ---- Scroll bars (chunky light steel) ----
        var grab := _flat(Color("c3cdd7"), Color("a8b4c0"), 1, 4)
        var grab_hi := _flat(Color("aebccd"), Color("a8b4c0"), 1, 4)
        var trough := _flat(Color("f0f4f8"), Color("dde4ea"), 1, 4)
        for bar in ["VScrollBar", "HScrollBar"]:
                t.set_stylebox("grabber", bar, grab)
                t.set_stylebox("grabber_highlight", bar, grab_hi)
                t.set_stylebox("grabber_pressed", bar, grab_hi)
                t.set_stylebox("scroll", bar, trough)

        # ---- Tooltips — white card, ink text ----
        t.set_stylebox("panel", "TooltipPanel", _flat(Color("ffffff"), EDGE_DARK, 1, 8))
        t.set_color("font_color", "TooltipLabel", TEXT)
        t.set_font_size("font_size", "TooltipLabel", 12)

        # ---- CheckButton / slider grabs — ink text, blue fill ----
        t.set_color("font_color", "CheckButton", TEXT)
        t.set_color("font_hover_color", "CheckButton", TEXT)
        t.set_color("font_pressed_color", "CheckButton", TEXT)
        t.set_font_size("font_size", "CheckButton", 13)
        if book != null:
                t.set_font("font", "CheckButton", book)
        var grabber := _flat(BLUE, Color(0, 0, 0, 0), 0, 5)
        t.set_stylebox("slider", "HSlider", _flat(Color("e7edf3"), Color(0, 0, 0, 0), 0, 4))
        t.set_stylebox("grabber_area", "HSlider", grabber)
        t.set_stylebox("grabber_area_highlight", "HSlider", grabber)

        return t


## One shared instance (cheap to reuse across scene changes).
static var shared: Theme = make_theme()
