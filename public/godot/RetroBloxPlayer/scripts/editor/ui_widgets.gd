extends RefCounted
class_name UiWidgets
## ==================================================================
##  UIWIDGETS — the bricks of the UI EDITOR (v14.0 "STUDIO")
## ==================================================================
##  Every widget you drag onto the stage is one of SIX kinds, built by
##  ONE factory — the editor previews it and the real game HUD spawns
##  the exact same thing, so what you see while editing is what plays.
##
##  A widget is a plain Dictionary (easy to save, easy to hand-edit):
##      id     "w_12345"
##      kind   "button" | "label" | "panel" | "textbox" | "healthbar" | "money"
##      x, y   position on the stage (top-left), pixels
##      w, h   size, pixels
##      text   the label / button text / typed default
##      size   font size
##      color  hex WITHOUT # — the widget's accent
##
##  IN THE GAME:
##      button     press it -> a toast pops ("YOU PRESSED: ...")
##      healthbar  FILLS WITH YOUR ACTUAL HEALTH, live
##      textbox    type into it (Enter pops the text as a toast)
##      money      a counter — press buttons with "+$" to grow it
##      label/panel pure style, yours to arrange

const RETRO := preload("res://scripts/ui/retro_theme.gd")

const KINDS: Array = ["button", "label", "panel", "textbox", "healthbar", "money"]

## The shared 12-color retro palette (same family as the paint brush)
const SWATCHES: Array = [
        "f2f3f3", "1b2a34", "c4281c", "e8752a", "f5cd30", "4b974b",
        "009999", "0d69ac", "6b327c", "e8bac8", "7c5c46", "635f62",
]

const DEFAULT_SIZE := {"button": [150.0, 42.0], "label": [160.0, 26.0], "panel": [220.0, 120.0],
        "textbox": [190.0, 36.0], "healthbar": [200.0, 20.0], "money": [110.0, 30.0]}


static func kind_title(kind: String) -> String:
        match kind:
                "button": return "Button"
                "label": return "Label"
                "panel": return "Panel"
                "textbox": return "Text Box"
                "healthbar": return "Health Bar"
                "money": return "Money"
        return kind.capitalize()


## Build ONE Control from a widget dict. Used by the editor (live preview)
## and by spawn_all (the real game HUD) — one look, everywhere.
static func build(w: Dictionary) -> Control:
        var kind := String(w.get("kind", "label"))
        var text := String(w.get("text", ""))
        var hex := String(w.get("color", "0d69ac"))
        var accent := Color(hex)
        var fsize := int(w.get("size", 16))
        var node: Control
        match kind:
                "button":
                        var b := Button.new()
                        b.text = text if text != "" else "PRESS ME"
                        _key_style(b, accent, fsize)
                        node = b
                "label":
                        var l := Label.new()
                        l.text = text if text != "" else "YOUR TEXT"
                        l.add_theme_font_override("font", RETRO.gotham(700))
                        l.add_theme_font_size_override("font_size", fsize)
                        l.add_theme_color_override("font_color", accent)
                        l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
                        l.add_theme_constant_override("shadow_offset_x", 1)
                        l.add_theme_constant_override("shadow_offset_y", 2)
                        node = l
                "panel":
                        var p := Panel.new()
                        var sb := StyleBoxFlat.new()
                        sb.bg_color = Color(accent.r, accent.g, accent.b, 0.82)
                        sb.set_corner_radius_all(8)
                        sb.set_border_width_all(1)
                        sb.border_color = Color(1, 1, 1, 0.16)
                        p.add_theme_stylebox_override("panel", sb)
                        p.mouse_filter = Control.MOUSE_FILTER_STOP
                        node = p
                "textbox":
                        var t := LineEdit.new()
                        t.placeholder_text = "type here..."
                        t.text = text
                        var well: StyleBox = RETRO.sunken(4, Color(0.10, 0.10, 0.11))
                        well.content_margin_left = 10.0
                        well.content_margin_right = 10.0
                        t.add_theme_stylebox_override("normal", well)
                        t.add_theme_stylebox_override("focus", RETRO.sunken(4, Color(0.13, 0.13, 0.15)))
                        t.add_theme_color_override("font_color", Color.WHITE)
                        t.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.35))
                        t.add_theme_font_override("font", RETRO.source(400))
                        t.add_theme_font_size_override("font_size", maxi(fsize, 13))
                        node = t
                "healthbar":
                        var hp := ProgressBar.new()
                        hp.min_value = 0.0
                        hp.max_value = 100.0
                        hp.value = 80.0
                        hp.show_percentage = false
                        var bg: StyleBox = RETRO.sunken(3, Color(0.09, 0.09, 0.10))
                        var fill: StyleBox = RETRO.raised(0, accent)
                        hp.add_theme_stylebox_override("background", bg)
                        hp.add_theme_stylebox_override("fill", fill)
                        hp.set_meta("custom_health", true)
                        node = hp
                "money":
                        var m := Label.new()
                        m.text = text if text != "" else "$ 0"
                        m.add_theme_font_override("font", RETRO.gotham(800))
                        m.add_theme_font_size_override("font_size", fsize)
                        m.add_theme_color_override("font_color", Color("3fdc6a"))
                        m.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
                        m.add_theme_constant_override("outline_size", 4)
                        node = m
                _:
                        var x := Label.new()
                        x.text = "?"
                        node = x
        if kind != "money" and kind != "label":
                node.custom_minimum_size = Vector2(float(w.get("w", 150.0)), float(w.get("h", 40.0)))
        node.position = Vector2(float(w.get("x", 40.0)), float(w.get("y", 40.0)))
        node.size = node.custom_minimum_size
        node.set_meta("cfg", w)
        return node


## Spawn every saved widget into a live surface. `root` is the Control (or
## CanvasLayer — anything that can add_child) the HUD lives on; `game` is
## the running game node (optional) that buttons/healthbars wire into.
static func spawn_all(root: Node, game: Node = null) -> Array:
        for child in root.get_children():
                if child is Control and child.name == "CustomWidgets":
                        child.queue_free()
        var layer := Control.new()
        layer.name = "CustomWidgets"
        layer.set_anchors_preset(Control.PRESET_FULL_RECT)
        layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(layer)
        var out: Array = []
        for w in UiConfig.widgets:
                var node := build(w)
                layer.add_child(node)
                out.append(node)
                if node is Button and game != null and game.has_method("_custom_widget_action"):
                        var txt: String = (node as Button).text
                        (node as Button).pressed.connect(func() -> void: game._custom_widget_action(txt))
                elif node is LineEdit and game != null:
                        var le := node as LineEdit
                        le.text_submitted.connect(func(t: String) -> void:
                                if game.has_method("_custom_widget_action"):
                                        game._custom_widget_action("typed: %s" % t)
                                le.clear())
        return out


## One classic beveled key (the editor's own chrome uses it too)
static func _key_style(b: Button, face: Color, fsize: int) -> void:
        var sb: StyleBox = RETRO.raised(4, face)
        sb.content_margin_left = 12.0
        sb.content_margin_right = 12.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        b.add_theme_stylebox_override("normal", sb)
        var hb: StyleBox = RETRO.raised(4, face.lightened(0.12))
        hb.content_margin_left = 12.0
        hb.content_margin_right = 12.0
        hb.content_margin_top = 8.0
        hb.content_margin_bottom = 8.0
        b.add_theme_stylebox_override("hover", hb)
        b.add_theme_stylebox_override("pressed", RETRO.sunken(4, face.darkened(0.2)))
        b.add_theme_font_override("font", RETRO.gotham(700))
        b.add_theme_font_size_override("font_size", fsize)
        var lum := face.get_luminance()
        var ink := Color(0.08, 0.09, 0.10) if lum > 0.6 else Color.WHITE
        for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
                b.add_theme_color_override(st, ink)
        b.focus_mode = Control.FOCUS_NONE
