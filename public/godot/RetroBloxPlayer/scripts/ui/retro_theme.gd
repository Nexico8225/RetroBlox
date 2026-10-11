class_name RetroTheme
extends RefCounted
## The new player's retro look — the same "2006 Steel" family the website
## wears: grey beveled panels on deep steel navy, chunky buttons, inset
## input wells, steel-blue header bars. Headers and buttons speak in the
## Press Start 2P pixel voice (an internet Google Font), the header bars
## and menu cards wear a real brushed-steel texture (an internet image).
## Everything is built in code so the whole client shares one place to restyle.

const BG := Color("1c2733")          # deep steel navy backdrop
const PANEL := Color("c8d2dc")       # classic grey panel face
const PANEL_HOVER := Color("d8e2ea")
const PANEL_DOWN := Color("aebbc7")
const CARD := Color("dde6ee")        # lighter card face
const WELL := Color("f4f8fb")        # input well white
const EDGE_LIGHT := Color("f2f7fb")
const EDGE_DARK := Color("51626f")
const HEADER := Color("2e6da4")      # steel blue header bar
const HEADER_DARK := Color("20517a")
const TEXT := Color("1a242e")
const TEXT_MUTED := Color("51626f")
const TEXT_INV := Color("eaf2f8")
const GREEN := Color("3fa14a")
const GREEN_HI := Color("4cbf59")
const GREEN_DARK := Color("2c7034")
const RED := Color("c0392b")
const RED_DARK := Color("8f2a20")
const BLUE := Color("1b6fae")
const GOLD := Color("e2b23a")
const LINK := Color("1b5e9e")


const PIXEL_FONT_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"
const STEEL_TEXTURE_PATH := "res://assets/ui/steel_panel.jpg"
const CURSOR_ARROW_PATH := "res://assets/ui/cursor_hand.png"      # uploaded RetroBlox Cursor
const CURSOR_HAND_PATH := "res://assets/ui/cursor_pointer.png"   # uploaded RetroBlox Pointer

static var _pixel_font: Font = null
static var _steel_tex: Texture2D = null
static var _cursors_applied := false


## The retro pixel voice — null when the font file is missing, so every
## caller can degrade gracefully.
static func pixel_font() -> Font:
        if _pixel_font == null and ResourceLoader.exists(PIXEL_FONT_PATH):
                _pixel_font = load(PIXEL_FONT_PATH)
        return _pixel_font


## The brushed-steel plate — null when the texture file is missing.
static func steel_texture() -> Texture2D:
        if _steel_tex == null and ResourceLoader.exists(STEEL_TEXTURE_PATH):
                _steel_tex = load(STEEL_TEXTURE_PATH)
        return _steel_tex


# ---------------------------------------------------------------- v3.11 mono client
## The ESC menu's ONE palette — BLACK & WHITE, as asked: translucent ink
## faces, white ink, a BOLD WHITE outline, ROUND corners, and ZERO
## gradients (the whole gloss engine is deleted). Pixel type on smooth
## modern glass — retro and modern at once.
const MENU_BG := Color(0.043, 0.047, 0.06, 0.84)     # the window face — translucent ink
const MENU_PANEL := Color(1, 1, 1, 0.05)             # raised surfaces — white glass
const MENU_PANEL_HI := Color(1, 1, 1, 0.11)          # hover faces
const MENU_EDGE_DARK := Color(0, 0, 0, 0.82)         # ink outline
const MENU_EDGE_HI := Color(0.93, 0.94, 0.97, 0.85)  # the BOLD WHITE outline
const MENU_INK := Color("f4f5f7")                    # primary text — white
const MENU_MUTED := Color(0.71, 0.73, 0.77)          # secondary text
const MENU_FAINT := Color(0.44, 0.46, 0.5)           # hints / version tag


## One monochrome surface — translucent ink face, bold white outline, ROUND
## corners. The whole menu is built from this: window, bars, cards, wells.
static func mono_surface(radius := 12, face := MENU_BG, outline := MENU_EDGE_HI,
                outline_w := 2) -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = face
        sb.set_border_width_all(outline_w)
        sb.border_color = outline
        sb.set_corner_radius_all(radius)
        return sb


# ---------------------------------------------------------------- v3.8 polish

static var _bevel_cache: Dictionary = {}

## A TRUE classic bevel, drawn pixel by pixel (16x16, cached): 1px near-black
## outline, a 2px LIGHT top/left edge and a 2px DARK bottom/right edge on
## `bg` — the raised 2006 keycap look. `pressed` flips the bevel so the face
## sinks (dark top/left, light bottom/right). Returned as a StyleBoxTexture
## with 3px texture margins so the edges never smear when stretched.
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
        var outline := Color(0.09, 0.11, 0.13)
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


## The classic smiley HEAD — a chunky WHITE blocky face with two dark eyes
## and a pixel smile, drawn in code (strict black & white). Kept as the
## portrait FALLBACK (no rig, headless) and for tiny list contexts.
static func head_icon() -> ImageTexture:
        if _bevel_cache.has("head"):
                return _bevel_cache["head"]
        var w := 18
        var img := Image.create_empty(w, w, false, Image.FORMAT_RGBA8)
        var face := Color("e9ecf1")
        var face_edge := Color("b9bec7")
        var ink := Color(0.1, 0.11, 0.13)
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


## Small retro ACTION icons, drawn pixel by pixel in white — a play triangle
## (Resume), a reset arrow, a door (Leave), a power symbol (Log Out), a
## two-head crowd (People tab) and a gear (Settings tab).
static func icon_texture(kind: String) -> ImageTexture:
        if _bevel_cache.has("icon_" + kind):
                return _bevel_cache["icon_" + kind]
        var w := 18
        var img := Image.create_empty(w, w, false, Image.FORMAT_RGBA8)
        var ink := Color(1, 1, 1, 0.96)
        match kind:
                "play":
                        # classic green-light play triangle
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
                        # the ↻ arrowhead: a wedge riding the top of the arc
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
        var tex := ImageTexture.create_from_image(img)
        _bevel_cache["icon_" + kind] = tex
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
        sb.anti_aliasing = false
        return sb


static func _panel_style() -> StyleBoxFlat:
        var sb := _flat(PANEL, EDGE_DARK, 2, 4)
        sb.border_width_top = 2
        sb.border_width_bottom = 3
        return sb


static func _card_style() -> StyleBoxFlat:
        return _flat(CARD, EDGE_DARK, 2, 4)


static func _header_style() -> StyleBox:
        # real brushed steel on the header bars, darkened to hold white text
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
        var sb := _flat(bg, edge, 2, 4)
        sb.content_margin_left = 12.0
        sb.content_margin_right = 12.0
        sb.content_margin_top = 6.0
        sb.content_margin_bottom = 6.0
        return sb


static func _well_style() -> StyleBoxFlat:
        var sb := _flat(WELL, EDGE_DARK, 2, 3)
        sb.content_margin_left = 8.0
        sb.content_margin_right = 8.0
        sb.content_margin_top = 5.0
        sb.content_margin_bottom = 5.0
        return sb


## Build the shared Theme. Scene roots apply it: `theme = RetroTheme.make_theme()`.
static func make_theme() -> Theme:
        var t := Theme.new()
        var pixel: Font = pixel_font()

        # ---- Button (default grey bevel, pixel voice) ----
        t.set_stylebox("normal", "Button", _button_style(PANEL, EDGE_DARK))
        t.set_stylebox("hover", "Button", _button_style(PANEL_HOVER, EDGE_DARK))
        t.set_stylebox("pressed", "Button", _button_style(PANEL_DOWN, EDGE_DARK))
        t.set_stylebox("disabled", "Button", _button_style(Color("b3c0cb"), Color("8d9daa")))
        var focus := _flat(Color(0, 0, 0, 0), BLUE, 2, 4)
        t.set_stylebox("focus", "Button", focus)
        t.set_color("font_color", "Button", TEXT)
        t.set_color("font_hover_color", "Button", TEXT)
        t.set_color("font_pressed_color", "Button", TEXT)
        t.set_color("font_disabled_color", "Button", Color("6d7d8a"))
        t.set_font_size("font_size", "Button", 11)
        if pixel != null:
                t.set_font("font", "Button", pixel)

        # ---- Button variations — v3.11: FLAT rounded keys (gradients gone) ----
        var flat_var := func(var_name: String, bg: Color, hover: Color, down: Color) -> void:
                t.set_type_variation(var_name, "Button")
                t.set_stylebox("normal", var_name, _flat(bg, MENU_EDGE_DARK, 2, 10))
                t.set_stylebox("hover", var_name, _flat(hover, MENU_EDGE_DARK, 2, 10))
                t.set_stylebox("pressed", var_name, _flat(down, MENU_EDGE_DARK, 2, 10))
                t.set_color("font_color", var_name, Color.WHITE)
                t.set_color("font_hover_color", var_name, Color.WHITE)
                t.set_color("font_pressed_color", var_name, Color.WHITE)
                t.set_constant("outline_size", var_name, 2)
                t.set_color("font_outline_color", var_name, MENU_EDGE_DARK)
        flat_var.call("BtnGreen", GREEN, GREEN_HI, GREEN_DARK)
        flat_var.call("BtnRed", RED, Color("d94a3a"), RED_DARK)
        flat_var.call("BtnBlue", BLUE, Color("2a85c9"), Color("134f7c"))
        t.set_stylebox("disabled", "BtnGreen", _flat(Color("8fae94"), MENU_EDGE_DARK, 2, 10))
        t.set_color("font_disabled_color", "BtnGreen", Color("e9f2ea"))
        t.set_font_size("font_size", "BtnGreen", 15)

        t.set_type_variation("BtnGhost", "Button")
        t.set_stylebox("normal", "BtnGhost", _button_style(Color(0, 0, 0, 0.18), Color(1, 1, 1, 0.35)))
        t.set_stylebox("hover", "BtnGhost", _button_style(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.5)))
        t.set_stylebox("pressed", "BtnGhost", _button_style(Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.5)))
        t.set_color("font_color", "BtnGhost", TEXT_INV)
        t.set_color("font_hover_color", "BtnGhost", Color.WHITE)
        t.set_color("font_pressed_color", "BtnGhost", Color.WHITE)
        t.set_font_size("font_size", "BtnGhost", 12)

        # ---- Label ----
        t.set_color("font_color", "Label", TEXT)
        t.set_font_size("font_size", "Label", 14)
        for pair in [["H1", 18], ["H2", 13], ["Small", 11]]:
                t.set_type_variation(String(pair[0]), "Label")
                t.set_font_size("font_size", String(pair[0]), int(pair[1]))
                if String(pair[0]) != "Small" and pixel != null:
                        t.set_font("font", String(pair[0]), pixel)
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

        # ---- LineEdit ----
        t.set_stylebox("normal", "LineEdit", _well_style())
        t.set_stylebox("focus", "LineEdit", _well_style())
        t.set_stylebox("read_only", "LineEdit", _well_style())
        t.set_color("font_color", "LineEdit", TEXT)
        t.set_color("font_placeholder_color", "LineEdit", Color("93a3af"))
        t.set_color("caret_color", "LineEdit", BLUE)
        t.set_color("selection_color", "LineEdit", Color("9ec9ea", 0.6))
        t.set_font_size("font_size", "LineEdit", 15)

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
        var bg_bar := _flat(Color("16222d"), Color("0e1a24"), 2, 3)
        t.set_stylebox("background", "ProgressBar", bg_bar)
        var fill_bar := _flat(RED, Color(0, 0, 0, 0), 0, 3)
        t.set_stylebox("fill", "ProgressBar", fill_bar)
        t.set_color("font_color", "ProgressBar", TEXT_INV)

        # ---- Scroll bars (chunky steel) ----
        var grab := _flat(Color("8fa2b1"), EDGE_DARK, 1, 3)
        var grab_hi := _flat(Color("aebfcc"), EDGE_DARK, 1, 3)
        var trough := _flat(Color("31404e"), Color("223140"), 1, 3)
        for bar in ["VScrollBar", "HScrollBar"]:
                t.set_stylebox("grabber", bar, grab)
                t.set_stylebox("grabber_highlight", bar, grab_hi)
                t.set_stylebox("grabber_pressed", bar, grab_hi)
                t.set_stylebox("scroll", bar, trough)

        # ---- Tooltips ----
        t.set_stylebox("panel", "TooltipPanel", _flat(Color("16222d"), Color("0e1a24"), 1, 3))
        t.set_color("font_color", "TooltipLabel", TEXT_INV)
        t.set_font_size("font_size", "TooltipLabel", 12)

        return t


## One shared instance (cheap to reuse across scene changes).
static var shared: Theme = make_theme()
