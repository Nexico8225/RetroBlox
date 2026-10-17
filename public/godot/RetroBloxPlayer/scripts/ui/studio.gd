extends Control
## ==================================================================
##  RETROBLOX STUDIO — FOUR SCENES, ONE HOME (v14.0 "STUDIO")
## ==================================================================
##  The game is ORGANIZED now: every thing you can touch lives in its
##  own scene, and this hub is the way in:
##
##      PLAY GAME      -> scenes/game.tscn        (the world, live)
##      UI EDITOR      -> scenes/ui_editor.tscn   (drag & drop your HUD)
##      MAP EDITOR     -> scenes/map_editor.tscn  (build brick by brick)
##      PLAYER EDITOR  -> scenes/player_editor.tscn (paint your avatar)
##
##  Plus: OPEN GAME FILE loads a .retroplace game file (the thing you
##  GET when you download a game on the site) and drops you into it.
##
##  Reached from the login screen, and from the in-game menu's Studio
##  tab. Everything saves to this device and rides with you.

const RETRO := preload("res://scripts/ui/retro_theme.gd")

const CARDS := [
        ["PLAY GAME", "Jump into the world — and every place YOU made.", "3e9c35", "res://scenes/game.tscn"],
        ["UI EDITOR", "Drag & drop widgets to rebuild the client UI.", "0d69ac", "res://scenes/ui_editor.tscn"],
        ["MAP EDITOR", "Build maps brick by brick — spawn, lava, bounce.", "e8752a", "res://scenes/map_editor.tscn"],
        ["PLAYER EDITOR", "Paint your avatar's skin, shirt and pants.", "6b327c", "res://scenes/player_editor.tscn"],
]

var _status: Label
var _file_dialog: FileDialog


func _ready() -> void:
        RETRO.apply_cursors()
        _build()


func _build() -> void:
        var bg := ColorRect.new()
        bg.color = Color("15161a")
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bg)

        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)

        var col := VBoxContainer.new()
        col.alignment = BoxContainer.ALIGNMENT_CENTER
        col.add_theme_constant_override("separation", 16)
        center.add_child(col)

        # ---- the wordmark ----
        var word := Label.new()
        word.text = "RETROBLOX STUDIO"
        word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        word.add_theme_font_override("font", RETRO.gotham(800))
        word.add_theme_font_size_override("font_size", 40)
        word.add_theme_color_override("font_color", Color.WHITE)
        word.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
        word.add_theme_constant_override("shadow_offset_x", 3)
        word.add_theme_constant_override("shadow_offset_y", 4)
        col.add_child(word)

        var sub := Label.new()
        sub.text = "Four scenes. Every thing, editable."
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        sub.add_theme_font_override("font", RETRO.source(400))
        sub.add_theme_font_size_override("font_size", 14)
        sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
        col.add_child(sub)

        # ---- the 2x2 card grid ----
        var grid := GridContainer.new()
        grid.columns = 2
        grid.add_theme_constant_override("h_separation", 14)
        grid.add_theme_constant_override("v_separation", 14)
        col.add_child(grid)
        for card in CARDS:
                grid.add_child(_card(String(card[0]), String(card[1]), Color(String(card[2])), String(card[3])))

        # ---- the footer row: game file + back ----
        var row := HBoxContainer.new()
        row.alignment = BoxContainer.ALIGNMENT_CENTER
        row.add_theme_constant_override("separation", 10)
        col.add_child(row)
        if not OS.has_feature("web"):
                var open := Button.new()
                open.text = "OPEN GAME FILE"
                _key(open, Color("5a461f"), 13)
                open.pressed.connect(_on_open_file)
                row.add_child(open)
        var back := Button.new()
        back.text = "BACK TO LOGIN"
        _key(back, Color("33363b"), 13)
        back.pressed.connect(func() -> void:
                get_tree().change_scene_to_file("res://scenes/login.tscn"))
        row.add_child(back)

        _status = Label.new()
        _status.text = ""
        _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _status.add_theme_font_override("font", RETRO.source(400))
        _status.add_theme_font_size_override("font_size", 12)
        _status.add_theme_color_override("font_color", Color("7fd18b"))
        col.add_child(_status)


func _card(title: String, desc: String, face: Color, scene: String) -> Button:
        var b := Button.new()
        b.custom_minimum_size = Vector2(300, 120)
        b.focus_mode = Control.FOCUS_NONE
        var sb: StyleBox = RETRO.raised(6, face.darkened(0.35))
        sb.content_margin_left = 18.0
        sb.content_margin_right = 18.0
        sb.content_margin_top = 14.0
        sb.content_margin_bottom = 14.0
        b.add_theme_stylebox_override("normal", sb)
        var hb: StyleBox = RETRO.raised(6, face.darkened(0.15))
        hb.content_margin_left = 18.0
        hb.content_margin_right = 18.0
        hb.content_margin_top = 14.0
        hb.content_margin_bottom = 14.0
        b.add_theme_stylebox_override("hover", hb)
        b.add_theme_stylebox_override("pressed", RETRO.sunken(6, face.darkened(0.5)))
        var col := VBoxContainer.new()
        col.set_anchors_preset(Control.PRESET_FULL_RECT)
        col.alignment = BoxContainer.ALIGNMENT_CENTER
        col.add_theme_constant_override("separation", 6)
        col.mouse_filter = Control.MOUSE_FILTER_IGNORE
        b.add_child(col)
        var t := Label.new()
        t.text = title
        t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        t.add_theme_font_override("font", RETRO.gotham(800))
        t.add_theme_font_size_override("font_size", 22)
        t.add_theme_color_override("font_color", Color.WHITE)
        t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
        t.add_theme_constant_override("shadow_offset_x", 2)
        t.add_theme_constant_override("shadow_offset_y", 2)
        t.mouse_filter = Control.MOUSE_FILTER_IGNORE
        col.add_child(t)
        var d := Label.new()
        d.text = desc
        d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        d.custom_minimum_size = Vector2(270, 0)
        d.add_theme_font_override("font", RETRO.source(400))
        d.add_theme_font_size_override("font_size", 12)
        d.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
        d.mouse_filter = Control.MOUSE_FILTER_IGNORE
        col.add_child(d)
        var bar := ColorRect.new()
        bar.color = face
        bar.custom_minimum_size = Vector2(0, 4)
        bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        col.add_child(bar)
        b.pressed.connect(func() -> void:
                get_tree().change_scene_to_file(scene))
        return b


func _key(b: Button, face: Color, fsize: int) -> void:
        var sb: StyleBox = RETRO.raised(4, face)
        sb.content_margin_left = 14.0
        sb.content_margin_right = 14.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        b.add_theme_stylebox_override("normal", sb)
        var hb: StyleBox = RETRO.raised(4, face.lightened(0.12))
        hb.content_margin_left = 14.0
        hb.content_margin_right = 14.0
        hb.content_margin_top = 8.0
        hb.content_margin_bottom = 8.0
        b.add_theme_stylebox_override("hover", hb)
        b.add_theme_stylebox_override("pressed", RETRO.sunken(4, face.darkened(0.2)))
        b.add_theme_font_override("font", RETRO.gotham(700))
        b.add_theme_font_size_override("font_size", fsize)
        b.add_theme_color_override("font_color", Color.WHITE)
        b.add_theme_color_override("font_hover_color", Color.WHITE)
        b.add_theme_color_override("font_pressed_color", Color.WHITE)
        b.focus_mode = Control.FOCUS_NONE


# ================================================================ game files

func _on_open_file() -> void:
        if _file_dialog == null:
                _file_dialog = FileDialog.new()
                _file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
                _file_dialog.access = FileDialog.ACCESS_FILESYSTEM
                _file_dialog.filters = ["*.retroplace, *.json ; RetroBlox game files"]
                _file_dialog.file_selected.connect(_open_game_file)
                add_child(_file_dialog)
        _file_dialog.popup_centered(Vector2i(720, 480))


## A .retroplace is a saved map, downloadable from any game page on the
## site. Load it, hand it to the game as the current place, play.
func _open_game_file(path: String) -> void:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                _status.text = "Could not read that file."
                return
        var parsed: Variant = JSON.parse_string(f.get_as_text())
        if typeof(parsed) != TYPE_DICTIONARY:
                _status.text = "Not a RetroBlox game file (no JSON inside)."
                return
        var d: Dictionary = parsed
        var parts: Variant = d.get("parts", [])
        if typeof(parts) != TYPE_ARRAY or (parts as Array).is_empty():
                _status.text = "Not a RetroBlox game file (no bricks inside)."
                return
        var def := {
                "id": "imported",
                "name": String(d.get("name", path.get_file().get_basename())),
                "desc": "Loaded from a .retroplace game file.",
                "sky_top": String(d.get("sky_top", "3d8fd1")),
                "sky_horizon": String(d.get("sky_horizon", "bfe0f5")),
                "sky_ground": String(d.get("sky_ground", "2a5d38")),
                "void_y": -40.0,
                "parts": parts,
        }
        Session.current_place = def
        get_tree().change_scene_to_file("res://scenes/game.tscn")
