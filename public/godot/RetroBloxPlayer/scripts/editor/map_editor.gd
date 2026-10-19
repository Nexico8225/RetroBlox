extends Node3D
## ==================================================================
##  MAP EDITOR — BUILD YOUR WORLD BRICK BY BRICK (v14.0 "STUDIO")
## ==================================================================
##  A whole SCENE for building maps (open it from the STUDIO hub, the
##  login screen (the STUDIO button):
##
##    · LEFT CLICK  — does the selected tool: ADD a brick / PAINT a
##                    brick with the current color / DELETE a brick
##    · RIGHT DRAG  — orbit the camera · WHEEL — zoom · WASD/QE — pan
##    · the BOTTOM bar: 12 retro colors, 5 brick sizes, materials
##      (plastic/neon/metal/wood/grass/dirt) and groups (spawn, kill,
##      ladder, goal, checkpoint, bounce)
##    · SAVE — your map becomes "My Place" in the game AND persists to
##      user://my_map.json (IndexedDB on the web, so it survives)
##    · TEST PLAY — jumps straight into YOUR map
##    · SAVE FILE — desktop: exports a .retroplace game file you can
##      share (that is the same file "Open Game File" in the Studio eats)
##
##  Bricks are built by the REAL world builder, so the editor shows the
##  exact studs, materials and shapes you get in play.

const RETRO := preload("res://scripts/ui/retro_theme.gd")
const W := preload("res://scripts/editor/ui_widgets.gd")
const WB := preload("res://scripts/world/world_builder.gd")
const MP := preload("res://scripts/world/my_place.gd")

const SAVE_PATH := "user://my_map.json"
const PLATE := 64.0

const TOOLS := ["add", "paint", "delete"]
const SIZES := [
        ["BRICK", Vector3(4, 1.2, 2)], ["CUBE", Vector3(2, 2, 2)],
        ["PLATE", Vector3(8, 1.2, 8)], ["TILE", Vector3(4, 0.4, 4)],
        ["PILLAR", Vector3(2, 4, 2)],
]
const MATERIALS := ["plastic", "neon", "metal", "wood", "grass", "dirt"]
const GROUPS := ["", "spawn", "kill", "ladder", "goal", "checkpoint", "bounce"]

# ---- world ----------------------------------------------------------------
var parts: Array = []
var _holders: Dictionary = {}       # id -> Node3D (the built brick)
var _tex: ImageTexture
var _throw_spawns: Array[Vector3] = []
var _seq := 0

# ---- editor state ---------------------------------------------------------
var tool := "add"
var color := "c4281c"
var size := Vector3(4, 1.2, 2)
var material := "plastic"
var group := ""

# ---- camera ---------------------------------------------------------------
var cam: Camera3D
var cam_target := Vector3.ZERO
var cam_yaw := -0.7
var cam_pitch := -0.5
var cam_dist := 26.0
var _orbiting := false

# ---- ui -------------------------------------------------------------------
var _status: Label
var _status_t := 0.0
var _tool_btns: Dictionary = {}
var _file_dialog: FileDialog


func _ready() -> void:
        RETRO.apply_cursors()
        _build_world()
        _build_ui()
        _load_map()
        _rebuild_all()


# ================================================================ world

func _build_world() -> void:
        # the same VIVRANT sky treatment the game uses
        var env := Environment.new()
        var sky := Sky.new()
        var sky_mat := ProceduralSkyMaterial.new()
        sky_mat.sky_top_color = Color("2f86d6")
        sky_mat.sky_horizon_color = Color("bfe0f5")
        sky_mat.ground_bottom_color = Color("2a5d38")
        sky_mat.ground_horizon_color = Color("bfe0f5")
        sky.sky_material = sky_mat
        env.background_mode = Environment.BG_SKY
        env.sky = sky
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        env.ambient_light_energy = 0.74
        env.ambient_light_sky_contribution = 0.68
        env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
        var we := WorldEnvironment.new()
        we.environment = env
        add_child(we)

        var sun := DirectionalLight3D.new()
        sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
        sun.light_energy = 1.14
        sun.light_color = Color("fff3d6")
        sun.shadow_enabled = true
        add_child(sun)

        # the big editable baseplate (a real part — clickable, paintable)
        _tex = WB.stud_texture()
        _upsert_part("baseplate", {
                "p": [0, -0.6, 0], "s": [PLATE, 1.2, PLATE], "c": "a3a2a5",
        })

        cam = Camera3D.new()
        cam.fov = 70.0
        add_child(cam)
        cam.current = true


func _load_map() -> void:
        if FileAccess.file_exists(SAVE_PATH):
                var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
                if f != null:
                        var parsed: Variant = JSON.parse_string(f.get_as_text())
                        if typeof(parsed) == TYPE_DICTIONARY:
                                var raw: Array = (parsed as Dictionary).get("parts", [])
                                if typeof(raw) == TYPE_ARRAY:
                                        parts = _sanitize(raw)
                                        _status_flash("Loaded your saved map (%d bricks)." % parts.size())
                                        return
        # never saved? start from the template so the stage is alive
        var def: Dictionary = MP.build()
        var seeded: Array = []
        for part in def.get("parts", []):
                # the editor HAS its own big baseplate — skip the template's
                # giant ground slab (no group, wider than the plate) to avoid
                # two floors z-fighting; everything else comes along
                var s: Array = part.get("s", [0, 0, 0])
                var big := float(s[0]) >= 60.0 or float(s[2]) >= 60.0
                if big and String(part.get("g", "")) == "":
                        continue
                seeded.append(part)
        parts = _sanitize(seeded)
        _status_flash("Started from the My Place template — make it yours!")


## Only keep the keys the world builder actually eats; generate ids.
func _sanitize(raw: Array) -> Array:
        var out: Array = []
        for r in raw:
                if typeof(r) != TYPE_DICTIONARY:
                        continue
                var d: Dictionary = r
                var p: Variant = d.get("p")
                var s: Variant = d.get("s")
                if typeof(p) != TYPE_ARRAY or typeof(s) != TYPE_ARRAY:
                        continue
                var part := {
                        "id": String(d.get("id", _next_id())),
                        "p": [float(p[0]), float(p[1]), float(p[2])],
                        "s": [float(s[0]), float(s[1]), float(s[2])],
                        "c": String(d.get("c", "a3a2a5")).trim_prefix("#"),
                        "m": String(d.get("m", "plastic")),
                        "g": String(d.get("g", "")),
                }
                if part["g"] == "":
                        part.erase("g")
                out.append(part)
        return out


func _next_id() -> String:
        _seq += 1
        return "b_%d_%d" % [int(Time.get_unix_time_from_system()) % 1000000, _seq]


# ================================================================ bricks

## Build (or rebuild) one brick holder via the REAL world builder.
func _upsert_part(id: String, part: Dictionary) -> void:
        if _holders.has(id) and is_instance_valid(_holders[id]):
                _holders[id].queue_free()
        var holder := Node3D.new()
        holder.name = id
        holder.set_meta("part_id", id)
        add_child(holder)
        WB._build_part(holder, part, _tex, _throw_spawns)
        _holders[id] = holder


func _rebuild_all() -> void:
        for h in _holders.values():
                if is_instance_valid(h) and String(h.name) != "baseplate":
                        h.queue_free()
        var keep := {}
        if _holders.has("baseplate") and is_instance_valid(_holders["baseplate"]):
                keep["baseplate"] = _holders["baseplate"]
        _holders = keep
        for part in parts:
                var id := String(part.get("id", ""))
                if id == "":
                        id = _next_id()
                        part["id"] = id
                _upsert_part(id, part)
        _ensure_spawn()


func _ensure_spawn() -> void:
        for part in parts:
                if String(part.get("g", "")) == "spawn":
                        return
        var spawn := {
                "id": _next_id(), "p": [0, 0.6, 8], "s": [6, 1.2, 6],
                "c": "4b974b", "g": "spawn",
        }
        parts.append(spawn)
        _upsert_part(String(spawn["id"]), spawn)


func _part_by_id(id: String) -> Dictionary:
        for part in parts:
                if String(part.get("id", "")) == id:
                        return part
        return {}


func _holder_of(node: Node) -> Node:
        var n := node
        while n != null:
                if n.has_meta("part_id"):
                        return n
                n = n.get_parent()
        return null


# ================================================================ tools

func _ray_hit() -> Dictionary:
        var mouse := get_viewport().get_mouse_position()
        var from := cam.project_ray_origin(mouse)
        var dir := cam.project_ray_normal(mouse)
        var q := PhysicsRayQueryParameters3D.create(from, from + dir * 500.0, 1)
        var hit := get_world_3d().direct_space_state.intersect_ray(q)
        return hit


func _apply_tool() -> void:
        var hit := _ray_hit()
        if hit.is_empty():
                return
        match tool:
                "add": _tool_add(hit)
                "paint": _tool_paint(hit)
                "delete": _tool_delete(hit)


func _tool_add(hit: Dictionary) -> void:
        var n: Vector3 = hit.get("normal", Vector3.UP)
        var size_u := size
        var half := absf(n.x) * size_u.x * 0.5 + absf(n.y) * size_u.y * 0.5 + absf(n.z) * size_u.z * 0.5
        var at: Vector3 = hit.get("position", Vector3.ZERO) + n * half
        at.x = roundf(at.x)
        at.z = roundf(at.z)
        var part := {
                "id": _next_id(),
                "p": [at.x, at.y, at.z],
                "s": [size_u.x, size_u.y, size_u.z],
                "c": color,
                "m": material,
        }
        if group != "":
                part["g"] = group
        parts.append(part)
        _upsert_part(String(part["id"]), part)
        _status_flash("Brick placed at %d, %d, %d" % [int(at.x), int(at.y), int(at.z)])


func _tool_paint(hit: Dictionary) -> void:
        var holder := _holder_of(hit.get("collider"))
        if holder == null or String(holder.name) == "baseplate":
                return
        var part := _part_by_id(String(holder.get_meta("part_id")))
        if part.is_empty():
                return
        part["c"] = color
        _upsert_part(String(part["id"]), part)


func _tool_delete(hit: Dictionary) -> void:
        var holder := _holder_of(hit.get("collider"))
        if holder == null or String(holder.name) == "baseplate":
                _status_flash("The baseplate stays — delete your bricks instead.")
                return
        var id := String(holder.get_meta("part_id"))
        for i in range(parts.size()):
                if String(parts[i].get("id", "")) == id:
                        parts.remove_at(i)
                        break
        holder.queue_free()
        _holders.erase(id)
        _status_flash("Brick deleted.")


# ================================================================ save / export / play

func _map_def() -> Dictionary:
        _ensure_spawn()
        return {
                "format": "retroblox-place-1",
                "name": "My Place",
                "sky_top": "3d8fd1", "sky_horizon": "bfe0f5", "sky_ground": "2a5d38",
                "parts": parts,
        }


func _on_save() -> void:
        var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
        if f != null:
                f.store_string(JSON.stringify(_map_def()))
                f.close()
        _status_flash("SAVED — play the game and pick MY PLACE to walk your map.")


func _on_export() -> void:
        if OS.has_feature("web"):
                _status_flash("Desktop only — on the web your map auto-saves.")
                return
        if _file_dialog == null:
                _file_dialog = FileDialog.new()
                _file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
                _file_dialog.access = FileDialog.ACCESS_FILESYSTEM
                _file_dialog.filters = ["*.retroplace ; RetroBlox game file"]
                _file_dialog.current_file = "my-place.retroplace"
                _file_dialog.file_selected.connect(_write_game_file)
                add_child(_file_dialog)
        _file_dialog.popup_centered(Vector2i(720, 480))


func _write_game_file(path: String) -> void:
        var f := FileAccess.open(path, FileAccess.WRITE)
        if f == null:
                _status_flash("Could not write there — pick another folder.")
                return
        f.store_string(JSON.stringify(_map_def()))
        f.close()
        _status_flash("Game file saved — share it! (Studio > Open Game File)")


func _on_test_play() -> void:
        _on_save()
        var def := _map_def()
        def["id"] = "myplace"
        def["name"] = "My Place"
        def["desc"] = "The map YOU built in the Map Editor."
        Session.current_place = def
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
        title.text = "MAP EDITOR"
        title.add_theme_font_override("font", RETRO.gotham(800))
        title.add_theme_font_size_override("font_size", 17)
        title.add_theme_color_override("font_color", Color("ffb14d"))
        trow.add_child(title)
        _status = Label.new()
        _status.text = "ADD: click the world to place a brick."
        _status.add_theme_font_override("font", RETRO.source(400))
        _status.add_theme_font_size_override("font_size", 12)
        _status.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
        trow.add_child(_status)
        var spring := Control.new()
        spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        trow.add_child(spring)
        trow.add_child(_key("SAVE", Color("1f4a2a"), _on_save))
        trow.add_child(_key("SAVE FILE", Color("33363b"), _on_export))
        trow.add_child(_key("TEST PLAY", Color("0d69ac"), _on_test_play))

        # ---- left tool rail ----
        var rail := PanelContainer.new()
        rail.set_anchors_preset(Control.PRESET_CENTER_LEFT)
        rail.grow_vertical = Control.GROW_DIRECTION_BOTH
        rail.offset_left = 8.0
        var rsb: StyleBox = RETRO.raised(4, Color(0.13, 0.14, 0.16))
        rsb.content_margin_left = 8.0
        rsb.content_margin_right = 8.0
        rsb.content_margin_top = 8.0
        rsb.content_margin_bottom = 8.0
        rail.add_theme_stylebox_override("panel", rsb)
        root.add_child(rail)
        var rcol := VBoxContainer.new()
        rcol.add_theme_constant_override("separation", 6)
        rail.add_child(rcol)
        var tool_defs := [["add", "ADD", "1f4a2a"], ["paint", "PAINT", "8a5a1f"], ["delete", "DEL", "5a1f24"]]
        for td in tool_defs:
                var b := _key(String(td[1]), Color(String(td[2])), func() -> void: _pick_tool(String(td[0])))
                b.custom_minimum_size = Vector2(86, 0)
                _tool_btns[String(td[0])] = b
                rcol.add_child(b)
        _pick_tool("add")

        # ---- bottom build bar ----
        var bottom := PanelContainer.new()
        bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
        bottom.offset_left = 8.0
        bottom.offset_right = -8.0
        bottom.offset_bottom = -8.0
        var bsb: StyleBox = RETRO.raised(4, Color(0.13, 0.14, 0.16))
        bsb.content_margin_left = 12.0
        bsb.content_margin_right = 12.0
        bsb.content_margin_top = 8.0
        bsb.content_margin_bottom = 8.0
        bottom.add_theme_stylebox_override("panel", bsb)
        root.add_child(bottom)
        var brow := HBoxContainer.new()
        brow.add_theme_constant_override("separation", 10)
        bottom.add_child(brow)

        # colors
        var ccol := VBoxContainer.new()
        ccol.add_theme_constant_override("separation", 3)
        brow.add_child(ccol)
        ccol.add_child(_mini_label("COLOR"))
        var crow := HBoxContainer.new()
        crow.add_theme_constant_override("separation", 4)
        ccol.add_child(crow)
        for hex in W.SWATCHES:
                var sw := Button.new()
                sw.custom_minimum_size = Vector2(26, 26)
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
                sw.pressed.connect(func() -> void: _pick_color(picked))
                crow.add_child(sw)

        # sizes
        var scol := VBoxContainer.new()
        scol.add_theme_constant_override("separation", 3)
        brow.add_child(scol)
        scol.add_child(_mini_label("SIZE"))
        var srow := HBoxContainer.new()
        srow.add_theme_constant_override("separation", 4)
        scol.add_child(srow)
        for sd in SIZES:
                var b := _key(String(sd[0]), Color("2a2d33"), func() -> void: _pick_size(sd[1]))
                b.toggle_mode = true
                srow.add_child(b)

        # material + group
        var mcol := VBoxContainer.new()
        mcol.add_theme_constant_override("separation", 3)
        brow.add_child(mcol)
        mcol.add_child(_mini_label("MATERIAL"))
        var mat := OptionButton.new()
        for m in MATERIALS:
                mat.add_item(String(m).capitalize())
        mat.custom_minimum_size = Vector2(110, 0)
        mat.item_selected.connect(func(i: int) -> void: material = MATERIALS[i])
        mcol.add_child(mat)

        var gcol := VBoxContainer.new()
        gcol.add_theme_constant_override("separation", 3)
        brow.add_child(gcol)
        gcol.add_child(_mini_label("GROUP"))
        var grp := OptionButton.new()
        grp.add_item("— none —")
        for i in range(1, GROUPS.size()):
                grp.add_item(GROUPS[i])
        grp.custom_minimum_size = Vector2(120, 0)
        grp.item_selected.connect(func(i: int) -> void: group = GROUPS[i])
        gcol.add_child(grp)

        var hcol := VBoxContainer.new()
        hcol.add_theme_constant_override("separation", 3)
        hcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        brow.add_child(hcol)
        hcol.add_child(_mini_label("HOW TO BUILD"))
        var help := Label.new()
        help.text = "LEFT CLICK = tool  ·  RIGHT DRAG = orbit  ·  WHEEL = zoom  ·  WASD/QE = pan"
        help.add_theme_font_override("font", RETRO.source(400))
        help.add_theme_font_size_override("font_size", 11)
        help.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
        hcol.add_child(help)


func _mini_label(txt: String) -> Label:
        var l := Label.new()
        l.text = txt
        l.add_theme_font_override("font", RETRO.gotham(700))
        l.add_theme_font_size_override("font_size", 10)
        l.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
        return l


func _key(txt: String, face: Color, handler: Callable) -> Button:
        var b := Button.new()
        b.text = txt
        W._key_style(b, face, 13)
        b.pressed.connect(handler)
        return b


func _pick_tool(t: String) -> void:
        tool = t
        for key in _tool_btns.keys():
                var b: Button = _tool_btns[key]
                var face := Color("2a2d33")
                if key == t:
                        face = Color("1f4a2a") if t == "add" else (Color("8a5a1f") if t == "paint" else Color("5a1f24"))
                W._key_style(b, face, 13)
        match t:
                "add": _status_flash("ADD: click the world to place a brick.")
                "paint": _status_flash("PAINT: click any brick to recolor it.")
                "delete": _status_flash("DELETE: click a brick to remove it.")


func _pick_color(hex: String) -> void:
        color = hex


func _pick_size(v: Vector3) -> void:
        size = v


func _status_flash(t: String) -> void:
        _status.text = t
        _status_t = 3.0


# ================================================================ input + frame

func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_RIGHT:
                        _orbiting = mb.pressed
                elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
                        _apply_tool()
                elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
                        cam_dist = clampf(cam_dist - 2.0, 6.0, 90.0)
                elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
                        cam_dist = clampf(cam_dist + 2.0, 6.0, 90.0)
        elif event is InputEventMouseMotion and _orbiting:
                var mm := event as InputEventMouseMotion
                cam_yaw -= mm.relative.x * 0.005
                cam_pitch = clampf(cam_pitch - mm.relative.y * 0.004, -1.35, 0.5)


func _process(delta: float) -> void:
        # WASD pans the orbit target across the plate, QE raise/lower
        var pan := Vector2(
                Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
                Input.get_action_strength("move_back") - Input.get_action_strength("move_forward"))
        if pan != Vector2.ZERO:
                var fwd := Vector3(sin(cam_yaw), 0, cos(cam_yaw)).normalized()
                var right := Vector3(fwd.z, 0, -fwd.x)
                cam_target += (-right * pan.x + fwd * -pan.y) * cam_dist * delta * 1.2
        if Input.is_key_pressed(KEY_E):
                cam_target.y += cam_dist * delta
        if Input.is_key_pressed(KEY_Q):
                cam_target.y = maxf(cam_target.y - cam_dist * delta, -2.0)
        cam_target.x = clampf(cam_target.x, -PLATE, PLATE)
        cam_target.z = clampf(cam_target.z, -PLATE, PLATE)

        var basis := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
        cam.position = cam_target + basis * Vector3(0, 0, cam_dist)
        if cam.position.y < 1.5:
                cam.position.y = 1.5
        cam.look_at(cam_target + Vector3(0, 1.0, 0), Vector3.UP)

        if _status_t > 0.0:
                _status_t -= delta
                if _status_t <= 0.0:
                        match tool:
                                "add": _status.text = "ADD: click the world to place a brick."
                                "paint": _status.text = "PAINT: click any brick to recolor it."
                                "delete": _status.text = "DELETE: click a brick to remove it."
