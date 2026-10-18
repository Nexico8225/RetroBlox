extends Node3D
## ==================================================================
##  PLAYER EDITOR — YOUR AVATAR, YOUR COLORS (v14.0 "STUDIO")
## ==================================================================
##  A whole SCENE for editing your player (open it from the STUDIO hub,
##  the login screen, or the in-game menu's Studio tab):
##
##    · your LIVE 3D avatar stands on the stage — DRAG left/right to
##      spin them around and check every angle
##    · three rows of the 12 retro colors: SKIN (head), SHIRT (torso
##      + arms), PANTS (legs) — click and the rig repaints instantly
##    · SAVE writes user://avatar_colors.json — the colors ride with
##      you into every game (they repaint YOUR rig right after spawn,
##      over the classic noob paint or on top of your site avatar)
##    · TEST PLAY jumps into the game wearing the look
##
##  The rig is the REAL AvatarRig the game plays with — same meshes,
##  same proportions, same animation.

const RETRO := preload("res://scripts/ui/retro_theme.gd")
const W := preload("res://scripts/editor/ui_widgets.gd")
const RIG := preload("res://scripts/player/avatar_rig.gd")

const SAVE_PATH := "user://avatar_colors.json"

const NOOB_SKIN := Color("f5cd30")
const NOOB_SHIRT := Color("0d69ac")
const NOOB_PANTS := Color("7ab53e")

# rows: [label, head/torso+arms/legs, default]
const ROWS := [
        ["SKIN", "skin", NOOB_SKIN],
        ["SHIRT", "shirt", NOOB_SHIRT],
        ["PANTS", "pants", NOOB_PANTS],
]

var rig: Node3D
var colors := {"skin": NOOB_SKIN, "shirt": NOOB_SHIRT, "pants": NOOB_PANTS}
var _spin := false
var _status: Label
var _status_t := 0.0


func _ready() -> void:
        RETRO.apply_cursors()
        _build_stage()
        _load_look()
        _build_ui()
        _apply_look()


# ================================================================ stage

func _build_stage() -> void:
        # a quiet photo studio: soft dark backdrop, one warm key light
        var env := Environment.new()
        env.background_mode = Environment.BG_COLOR
        env.background_color = Color("1a1c22")
        env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        env.ambient_light_color = Color("9fb4c8")
        env.ambient_light_energy = 0.9
        env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
        var we := WorldEnvironment.new()
        we.environment = env
        add_child(we)

        var key := DirectionalLight3D.new()
        key.rotation_degrees = Vector3(-38.0, 24.0, 0.0)
        key.light_energy = 1.15
        key.light_color = Color("fff2da")
        key.shadow_enabled = true
        add_child(key)

        var rim := DirectionalLight3D.new()
        rim.rotation_degrees = Vector3(-12.0, -150.0, 0.0)
        rim.light_energy = 0.5
        rim.light_color = Color("bcd6ff")
        add_child(rim)

        # the round stage platform
        var disc := MeshInstance3D.new()
        var cyl := CylinderMesh.new()
        cyl.top_radius = 3.4
        cyl.bottom_radius = 3.6
        cyl.height = 0.4
        var dmat := StandardMaterial3D.new()
        dmat.albedo_color = Color("3a4150")
        dmat.roughness = 0.85
        cyl.material = dmat
        disc.mesh = cyl
        disc.position.y = -0.2
        add_child(disc)

        # THE avatar — the real rig
        rig = RIG.new()
        add_child(rig)
        rig.setup("YOU")
        rig.paint_noob()

        var cam := Camera3D.new()
        cam.fov = 50.0
        add_child(cam)
        cam.position = Vector3(0, 3.6, 7.6)
        cam.look_at(Vector3(0, 2.3, 0), Vector3.UP)
        cam.current = true


func _load_look() -> void:
        if not FileAccess.file_exists(SAVE_PATH):
                return
        var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
        if f == null:
                return
        var parsed: Variant = JSON.parse_string(f.get_as_text())
        if typeof(parsed) != TYPE_DICTIONARY:
                return
        var d: Dictionary = parsed
        for row in ROWS:
                var key := String(row[1])
                var hex := String(d.get(key, "")).trim_prefix("#")
                if hex.length() == 6 and _hex_ok(hex):
                        colors[key] = Color(hex)


func _hex_ok(hex: String) -> bool:
        for ch in hex.to_lower():
                if not ((ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "f")):
                        return false
        return true


func _apply_look() -> void:
        rig.set_part_color(RIG.HEAD, colors["skin"])
        rig.set_part_color(RIG.TORSO, colors["shirt"])
        rig.set_part_color(RIG.ARM_L, colors["shirt"])
        rig.set_part_color(RIG.ARM_R, colors["shirt"])
        rig.set_part_color(RIG.LEG_L, colors["pants"])
        rig.set_part_color(RIG.LEG_R, colors["pants"])


# ================================================================ save / play

func _on_save() -> void:
        var d := {}
        for row in ROWS:
                d[String(row[1])] = colors[String(row[1])].to_html(false)
        var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
        if f != null:
                f.store_string(JSON.stringify(d))
                f.close()
        _status_flash("SAVED — you wear this look in every game.")


func _on_test_play() -> void:
        _on_save()
        get_tree().change_scene_to_file("res://scenes/game.tscn")


# ================================================================ ui

func _build_ui() -> void:
        var layer := CanvasLayer.new()
        layer.layer = 40
        add_child(layer)
        var root := Control.new()
        root.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.theme = RETRO.shared
        layer.add_child(root)

        # ---- top bar ----
        var bar := PanelContainer.new()
        bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
        bar.custom_minimum_size = Vector2(0, 48)
        var tsb: StyleBox = RETRO.raised(0, Color(0.11, 0.12, 0.14))
        tsb.content_margin_left = 12.0
        tsb.content_margin_right = 12.0
        tsb.content_margin_top = 8.0
        tsb.content_margin_bottom = 8.0
        bar.add_theme_stylebox_override("panel", tsb)
        root.add_child(bar)
        var trow := HBoxContainer.new()
        trow.add_theme_constant_override("separation", 10)
        bar.add_child(trow)
        trow.add_child(_key("BACK", Color("33363b"), func() -> void:
                get_tree().change_scene_to_file("res://scenes/studio.tscn")))
        var title := Label.new()
        title.text = "PLAYER EDITOR"
        title.add_theme_font_override("font", RETRO.gotham(800))
        title.add_theme_font_size_override("font_size", 17)
        title.add_theme_color_override("font_color", Color("c792ea"))
        trow.add_child(title)
        _status = Label.new()
        _status.text = "Drag on the stage to spin your avatar."
        _status.add_theme_font_override("font", RETRO.source(400))
        _status.add_theme_font_size_override("font_size", 12)
        _status.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
        trow.add_child(_status)
        var spring := Control.new()
        spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        trow.add_child(spring)
        trow.add_child(_key("SAVE", Color("1f4a2a"), _on_save))
        trow.add_child(_key("TEST PLAY", Color("0d69ac"), _on_test_play))

        # ---- right color panel ----
        var panel := PanelContainer.new()
        panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
        panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
        panel.grow_vertical = Control.GROW_DIRECTION_BOTH
        panel.offset_right = -12.0
        var psb: StyleBox = RETRO.raised(4, Color(0.13, 0.14, 0.16))
        psb.content_margin_left = 14.0
        psb.content_margin_right = 14.0
        psb.content_margin_top = 12.0
        psb.content_margin_bottom = 12.0
        panel.add_theme_stylebox_override("panel", psb)
        root.add_child(panel)
        var col := VBoxContainer.new()
        col.add_theme_constant_override("separation", 10)
        panel.add_child(col)

        var head := Label.new()
        head.text = "YOUR LOOK"
        head.add_theme_font_override("font", RETRO.gotham(800))
        head.add_theme_font_size_override("font_size", 13)
        head.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
        col.add_child(head)

        for row in ROWS:
                var row_label := String(row[0])
                var key := String(row[1])
                var l := Label.new()
                l.text = row_label
                l.add_theme_font_override("font", RETRO.gotham(700))
                l.add_theme_font_size_override("font_size", 11)
                l.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
                col.add_child(l)
                var grid := GridContainer.new()
                grid.columns = 6
                grid.add_theme_constant_override("h_separation", 5)
                grid.add_theme_constant_override("v_separation", 5)
                col.add_child(grid)
                for hex in W.SWATCHES:
                        var sw := Button.new()
                        sw.custom_minimum_size = Vector2(28, 24)
                        sw.focus_mode = Control.FOCUS_NONE
                        var fsb := StyleBoxFlat.new()
                        fsb.bg_color = Color(String(hex))
                        fsb.set_corner_radius_all(4)
                        fsb.set_border_width_all(1)
                        fsb.border_color = Color(1, 1, 1, 0.25)
                        sw.add_theme_stylebox_override("normal", fsb)
                        var hsb: StyleBox = fsb.duplicate()
                        hsb.set_border_width_all(2)
                        hsb.border_color = Color.WHITE
                        sw.add_theme_stylebox_override("hover", hsb)
                        var picked := String(hex)
                        sw.pressed.connect(func() -> void:
                                colors[key] = Color(picked)
                                _apply_look()
                                _status_flash("%s repainted!" % row_label.capitalize()))
                        grid.add_child(sw)

        var hint := Label.new()
        hint.text = "Colors save to this device and ride with you."
        hint.add_theme_font_override("font", RETRO.source(400))
        hint.add_theme_font_size_override("font_size", 10)
        hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
        col.add_child(hint)


func _key(txt: String, face: Color, handler: Callable) -> Button:
        var b := Button.new()
        b.text = txt
        W._key_style(b, face, 13)
        b.pressed.connect(handler)
        return b


func _status_flash(t: String) -> void:
        _status.text = t
        _status_t = 2.6


# ================================================================ input + frame

func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
                _spin = (event as InputEventMouseButton).pressed
        elif event is InputEventMouseMotion and _spin and rig != null:
                rig.rotation.y += (event as InputEventMouseMotion).relative.x * 0.01


func _process(delta: float) -> void:
        if rig != null and is_instance_valid(rig):
                rig.call("animate", delta, 0.0, true, false)
        if _status_t > 0.0:
                _status_t -= delta
                if _status_t <= 0.0:
                        _status.text = "Drag on the stage to spin your avatar."
