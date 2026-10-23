extends Control
## ==================================================================
##  UI EDITOR SCENE — DRAG. DROP. DONE. (v14.0 "STUDIO")
## ==================================================================
##  A whole SCENE for editing the client UI (run it from the STUDIO hub,
##  login screen (the STUDIO button):
##
##    · the LEFT shelf holds WIDGETS — grab one, DRAG it onto the stage,
##      release: a real Button / Label / Panel / TextBox / Health Bar /
##      Money counter is born where you dropped it
##    · click a widget to select — DRAG it anywhere, edit it in the
##      right panel: X / Y / W / H, text, font size, 12 retro colors
##    · SAVE writes user://ui_config.json — the real game HUD spawns
##      the exact same widgets (buttons pop toasts, the health bar
##      fills with YOUR health)
##    · TEST PLAY jumps into the game to see it live
##
##  This is the full-screen sibling of the in-game F2 editor (they share
##  UiConfig, so layouts made in either place ride together).

const RETRO := preload("res://scripts/ui/retro_theme.gd")
const W := preload("res://scripts/editor/ui_widgets.gd")

const GREEN_SEL := Color("38ff8c")
const GRID_STEP := 24.0

# ---- layout refs ----------------------------------------------------------
var _top_bar: PanelContainer
var _status: Label
var _palette_box: VBoxContainer
var _stage: Control
var _widgets_root: Control
var _props: PanelContainer
var _outline: Panel
var _toast_t := 0.0

# ---- state ----------------------------------------------------------------
var _sel_id := ""                 # selected widget id ("" = none)
var _drag_id := ""                # widget being dragged
var _press_id := ""               # widget under the mouse on press
var _press_at := Vector2.ZERO
var _drag_off := Vector2.ZERO
var _drag_moved := false
var _ghost_kind := ""             # widget kind being dragged from the shelf
var _ghost: Control

# ---- props controls -------------------------------------------------------
var _x_spin: SpinBox
var _y_spin: SpinBox
var _w_spin: SpinBox
var _h_spin: SpinBox
var _text_edit: LineEdit
var _size_spin: SpinBox
var _swatch_row: GridContainer
var _props_empty: Label
var _props_body: VBoxContainer


func _ready() -> void:
        RETRO.apply_cursors()
        _build()
        _rebuild_stage()


# ================================================================ build

func _build() -> void:
        var bg := ColorRect.new()
        bg.color = Color("15161a")
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bg)

        # ---- top bar ----
        _top_bar = PanelContainer.new()
        _top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
        _top_bar.custom_minimum_size = Vector2(0, 48)
        var tsb: StyleBox = RETRO.raised(0, Color(0.11, 0.12, 0.14))
        tsb.content_margin_left = 12.0
        tsb.content_margin_right = 12.0
        tsb.content_margin_top = 8.0
        tsb.content_margin_bottom = 8.0
        _top_bar.add_theme_stylebox_override("panel", tsb)
        add_child(_top_bar)

        var trow := HBoxContainer.new()
        trow.add_theme_constant_override("separation", 10)
        _top_bar.add_child(trow)

        trow.add_child(_key("BACK", Color("33363b"), func() -> void:
                get_tree().change_scene_to_file("res://scenes/studio.tscn")))

        var title := Label.new()
        title.text = "UI EDITOR"
        title.add_theme_font_override("font", RETRO.gotham(800))
        title.add_theme_font_size_override("font_size", 17)
        title.add_theme_color_override("font_color", RETRO.BLUE_HI)
        trow.add_child(title)

        _status = Label.new()
        _status.text = "Drag a widget from the shelf onto the stage."
        _status.add_theme_font_override("font", RETRO.source(400))
        _status.add_theme_font_size_override("font_size", 12)
        _status.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
        trow.add_child(_status)

        var spring := Control.new()
        spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        trow.add_child(spring)

        trow.add_child(_key("RESET", Color("6b327c"), _on_reset))
        trow.add_child(_key("SAVE", Color("1f4a2a"), _on_save))
        trow.add_child(_key("TEST PLAY", Color("0d69ac"), func() -> void:
                _on_save()
                get_tree().change_scene_to_file("res://scenes/game.tscn")))

        # ---- main row: shelf | stage | props ----
        var row := HBoxContainer.new()
        row.set_anchors_preset(Control.PRESET_FULL_RECT)
        row.offset_top = 52.0
        row.offset_bottom = -8.0
        row.add_theme_constant_override("separation", 8)
        add_child(row)

        # LEFT — the widget shelf
        var shelf := PanelContainer.new()
        shelf.custom_minimum_size = Vector2(148, 0)
        var ssb: StyleBox = RETRO.sunken(4, Color(0.09, 0.10, 0.12))
        ssb.content_margin_left = 8.0
        ssb.content_margin_right = 8.0
        ssb.content_margin_top = 8.0
        ssb.content_margin_bottom = 8.0
        shelf.add_theme_stylebox_override("panel", ssb)
        row.add_child(shelf)
        _palette_box = VBoxContainer.new()
        _palette_box.add_theme_constant_override("separation", 7)
        shelf.add_child(_palette_box)
        var shelf_t := Label.new()
        shelf_t.text = "WIDGETS"
        shelf_t.add_theme_font_override("font", RETRO.gotham(700))
        shelf_t.add_theme_font_size_override("font_size", 11)
        shelf_t.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
        _palette_box.add_child(shelf_t)
        for kind in W.KINDS:
                _palette_box.add_child(_shelf_chip(String(kind)))
        var tip := Label.new()
        tip.text = "Grab one.\nDrop it on\nthe stage."
        tip.add_theme_font_override("font", RETRO.source(400))
        tip.add_theme_font_size_override("font_size", 10)
        tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
        _palette_box.add_child(tip)

        # CENTER — the stage
        var stage_holder := PanelContainer.new()
        stage_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        stage_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
        var hsb: StyleBox = RETRO.sunken(4, Color(0.07, 0.08, 0.09))
        stage_holder.add_theme_stylebox_override("panel", hsb)
        row.add_child(stage_holder)
        _stage = Control.new()
        _stage.name = "Stage"
        _stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
        _stage.clip_contents = true
        _stage.draw.connect(_draw_grid)
        stage_holder.add_child(_stage)
        _widgets_root = Control.new()
        _widgets_root.name = "WidgetsRoot"
        _widgets_root.set_anchors_preset(Control.PRESET_FULL_RECT)
        _widgets_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _stage.add_child(_widgets_root)
        _outline = Panel.new()
        _outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var osb := StyleBoxFlat.new()
        osb.bg_color = Color(0, 0, 0, 0)
        osb.set_border_width_all(2)
        osb.border_color = GREEN_SEL
        osb.set_corner_radius_all(5)
        _outline.add_theme_stylebox_override("panel", osb)
        _outline.visible = false
        _stage.add_child(_outline)

        # RIGHT — properties
        _props = PanelContainer.new()
        _props.custom_minimum_size = Vector2(238, 0)
        var psb: StyleBox = RETRO.sunken(4, Color(0.09, 0.10, 0.12))
        psb.content_margin_left = 10.0
        psb.content_margin_right = 10.0
        psb.content_margin_top = 8.0
        psb.content_margin_bottom = 8.0
        _props.add_theme_stylebox_override("panel", psb)
        row.add_child(_props)
        var pcol := VBoxContainer.new()
        pcol.add_theme_constant_override("separation", 6)
        _props.add_child(pcol)
        var props_t := Label.new()
        props_t.text = "PROPERTIES"
        props_t.add_theme_font_override("font", RETRO.gotham(700))
        props_t.add_theme_font_size_override("font_size", 11)
        props_t.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
        pcol.add_child(props_t)

        _props_empty = Label.new()
        _props_empty.text = "Nothing selected.\n\nClick a widget on\nthe stage to edit\nits position, text,\nsize and color."
        _props_empty.add_theme_font_override("font", RETRO.source(400))
        _props_empty.add_theme_font_size_override("font_size", 11)
        _props_empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
        pcol.add_child(_props_empty)

        _props_body = VBoxContainer.new()
        _props_body.add_theme_constant_override("separation", 6)
        pcol.add_child(_props_body)
        _x_spin = _spin_row(_props_body, "X")
        _y_spin = _spin_row(_props_body, "Y")
        _w_spin = _spin_row(_props_body, "W", 20.0, 2000.0)
        _h_spin = _spin_row(_props_body, "H", 16.0, 2000.0)
        _size_spin = _spin_row(_props_body, "Font", 8.0, 72.0)
        _x_spin.value_changed.connect(func(v: float) -> void: _on_prop("x", v))
        _y_spin.value_changed.connect(func(v: float) -> void: _on_prop("y", v))
        _w_spin.value_changed.connect(func(v: float) -> void: _on_prop("w", v))
        _h_spin.value_changed.connect(func(v: float) -> void: _on_prop("h", v))
        _size_spin.value_changed.connect(func(v: float) -> void: _on_prop("size", int(v)))

        var text_row := HBoxContainer.new()
        text_row.add_theme_constant_override("separation", 6)
        var tl := Label.new()
        tl.text = "Text"
        tl.custom_minimum_size = Vector2(38, 0)
        tl.add_theme_font_override("font", RETRO.source(600))
        tl.add_theme_font_size_override("font_size", 12)
        tl.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
        text_row.add_child(tl)
        _text_edit = LineEdit.new()
        _text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _text_edit.add_theme_font_size_override("font_size", 12)
        _text_edit.text_submitted.connect(func(t: String) -> void: _on_text(t))
        _text_edit.text_changed.connect(func(_t: String) -> void: _on_text(_text_edit.text))
        text_row.add_child(_text_edit)
        _props_body.add_child(text_row)

        var ct := Label.new()
        ct.text = "COLOR"
        ct.add_theme_font_override("font", RETRO.gotham(700))
        ct.add_theme_font_size_override("font_size", 11)
        ct.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
        _props_body.add_child(ct)
        _swatch_row = GridContainer.new()
        _swatch_row.columns = 6
        _swatch_row.add_theme_constant_override("h_separation", 5)
        _swatch_row.add_theme_constant_override("v_separation", 5)
        _props_body.add_child(_swatch_row)
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
                var hsb2: StyleBox = fsb.duplicate()
                hsb2.set_border_width_all(2)
                hsb2.border_color = Color.WHITE
                sw.add_theme_stylebox_override("hover", hsb2)
                var picked_hex := String(hex)
                sw.pressed.connect(func() -> void: _on_color(picked_hex))
                _swatch_row.add_child(sw)

        var del := Button.new()
        del.text = "DELETE WIDGET"
        del.pressed.connect(_on_delete)
        W._key_style(del, Color("5a1f24"), 12)
        _props_body.add_child(del)


func _draw_grid() -> void:
        var size := _stage.size
        var from := Vector2.ZERO
        while from.y < size.y:
                from.x = 0.0
                while from.x < size.x:
                        _stage.draw_rect(Rect2(from, Vector2(1.6, 1.6)), Color(1, 1, 1, 0.06))
                        from.x += GRID_STEP
                from.y += GRID_STEP


func _spin_row(parent: VBoxContainer, title: String, mn := -4000.0, mx := 4000.0) -> SpinBox:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 6)
        var l := Label.new()
        l.text = title
        l.custom_minimum_size = Vector2(38, 0)
        l.add_theme_font_override("font", RETRO.source(600))
        l.add_theme_font_size_override("font_size", 12)
        l.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
        row.add_child(l)
        var s := SpinBox.new()
        s.min_value = mn
        s.max_value = mx
        s.step = 1.0
        s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        s.add_theme_font_size_override("font_size", 12)
        parent.add_child(row)
        return s


func _key(txt: String, face: Color, handler: Callable) -> Button:
        var b := Button.new()
        b.text = txt
        W._key_style(b, face, 13)
        b.pressed.connect(handler)
        return b


## One draggable shelf chip
func _shelf_chip(kind: String) -> Button:
        var b := Button.new()
        b.text = W.kind_title(kind)
        b.focus_mode = Control.FOCUS_NONE
        W._key_style(b, Color("2a2d33"), 12)
        b.gui_input.connect(func(ev: InputEvent) -> void:
                if ev is InputEventMouseButton:
                        var mb := ev as InputEventMouseButton
                        if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
                                _begin_ghost(kind))
        return b


# ================================================================ stage

func _rebuild_stage() -> void:
        for child in _widgets_root.get_children():
                child.queue_free()
        for w in UiConfig.widgets:
                var node := W.build(w)
                _widgets_root.add_child(node)
                var id := String(w.get("id", ""))
                node.gui_input.connect(func(ev: InputEvent) -> void: _widget_input(id, ev))
        _select(_sel_id)


func _widget_node(id: String) -> Control:
        for child in _widgets_root.get_children():
                if child.has_meta("cfg") and String((child.get_meta("cfg") as Dictionary).get("id", "")) == id:
                        return child
        return null


func _widget_input(id: String, ev: InputEvent) -> void:
        if not (ev is InputEventMouseButton):
                return
        var mb := ev as InputEventMouseButton
        if mb.button_index != MOUSE_BUTTON_LEFT:
                return
        if mb.pressed:
                _select(id)
                _press_id = id
                _press_at = mb.global_position
                _drag_moved = false
        else:
                _press_id = ""
                if _drag_id != "":
                        _drag_id = ""
                        _status_flash("Moved.")


# ================================================================ selection + props

func _select(id: String) -> void:
        _sel_id = id
        var w := UiConfig.widget_by_id(id)
        var empty := w.is_empty()
        _props_empty.visible = empty
        _props_body.visible = not empty
        _outline.visible = not empty
        if empty:
                return
        _x_spin.set_value_no_signal(float(w.get("x", 0.0)))
        _y_spin.set_value_no_signal(float(w.get("y", 0.0)))
        _w_spin.set_value_no_signal(float(w.get("w", 100.0)))
        _h_spin.set_value_no_signal(float(w.get("h", 40.0)))
        _size_spin.set_value_no_signal(float(w.get("size", 16)))
        _text_edit.text = String(w.get("text", ""))


func _on_prop(key: String, v: float) -> void:
        if _sel_id == "":
                return
        UiConfig.update_widget(_sel_id, key, v)
        var node := _widget_node(_sel_id)
        if node == null:
                return
        var w := UiConfig.widget_by_id(_sel_id)
        node.set_meta("cfg", w)
        if key == "size":
                _rebuild_stage()   # font size lives inside the built controls
        elif key == "x" or key == "y":
                node.position = Vector2(float(w.get("x", 0.0)), float(w.get("y", 0.0)))
        else:
                node.custom_minimum_size = Vector2(float(w.get("w", 100.0)), float(w.get("h", 40.0)))
                node.size = node.custom_minimum_size


func _on_text(t: String) -> void:
        if _sel_id == "":
                return
        UiConfig.update_widget(_sel_id, "text", t)
        _rebuild_stage()


func _on_color(hex: String) -> void:
        if _sel_id == "":
                return
        UiConfig.update_widget(_sel_id, "color", hex)
        _rebuild_stage()


func _on_delete() -> void:
        if _sel_id == "":
                return
        UiConfig.remove_widget(_sel_id)
        _select("")
        _rebuild_stage()
        _status_flash("Deleted.")


func _on_save() -> void:
        UiConfig.save_config()
        _status_flash("SAVED — your UI rides with you into every game.")


## RESET — the revert button: wipe every move/edit/widget this device
## saved and rebuild the stage bare. The stock HUD comes back next boot.
func _on_reset() -> void:
        UiConfig.clear_all()
        _rebuild_stage()
        _status_flash("RESET — your UI edits are gone, stock HUD restored.")


func _status_flash(t: String) -> void:
        _status.text = t
        _toast_t = 2.6


# ================================================================ ghost drag (shelf -> stage)

func _begin_ghost(kind: String) -> void:
        _ghost_kind = kind
        if _ghost != null:
                _ghost.queue_free()
        _ghost = Panel.new()
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("0d69ac", 0.65)
        sb.set_corner_radius_all(6)
        sb.set_border_width_all(2)
        sb.border_color = Color("6fc4ff")
        (_ghost as Panel).add_theme_stylebox_override("panel", sb)
        _ghost.custom_minimum_size = Vector2(120, 36)
        _ghost.size = Vector2(120, 36)
        _ghost.z_index = 50
        _ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var gl := Label.new()
        gl.text = W.kind_title(kind)
        gl.add_theme_font_override("font", RETRO.gotham(700))
        gl.add_theme_font_size_override("font_size", 12)
        gl.add_theme_color_override("font_color", Color.WHITE)
        gl.set_anchors_preset(Control.PRESET_CENTER)
        gl.grow_horizontal = Control.GROW_DIRECTION_BOTH
        gl.grow_vertical = Control.GROW_DIRECTION_BOTH
        gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _ghost.add_child(gl)
        add_child(_ghost)


func _drop_ghost() -> void:
        var kind := _ghost_kind
        _ghost_kind = ""
        if _ghost != null:
                _ghost.queue_free()
                _ghost = null
        if kind == "":
                return
        var at := _stage.get_local_mouse_position()
        var dims: Array = [160.0, 40.0]
        if (W.DEFAULT_SIZE as Dictionary).has(kind):
                dims = W.DEFAULT_SIZE[kind]
        at.x = maxf(4.0, minf(at.x - float(dims[0]) * 0.5, _stage.size.x - float(dims[0]) - 4.0))
        at.y = maxf(4.0, minf(at.y - float(dims[1]) * 0.5, _stage.size.y - float(dims[1]) - 4.0))
        var id := UiConfig.add_widget(kind, at)
        _rebuild_stage()
        _select(id)
        _status_flash("%s dropped — drag it anywhere!" % W.kind_title(kind))


# ================================================================ per-frame

func _process(delta: float) -> void:
        if _toast_t > 0.0:
                _toast_t -= delta
                if _toast_t <= 0.0:
                        _status.text = "Drag a widget from the shelf onto the stage."

        # ghost follows the mouse; release = drop
        if _ghost_kind != "" and _ghost != null:
                _ghost.global_position = get_global_mouse_position() + Vector2(-60, -18)
                if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
                        _drop_ghost()
                return

        # press -> drag with a small threshold so clicks stay clicks
        if _press_id != "" and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
                _press_id = ""
                _drag_id = ""
        elif _press_id != "" and not _drag_moved:
                if get_global_mouse_position().distance_to(_press_at) > 6.0:
                        _drag_id = _press_id
                        _drag_moved = true
                        var node := _widget_node(_drag_id)
                        if node != null:
                                _drag_off = get_global_mouse_position() - node.global_position
        if _drag_id != "":
                var node := _widget_node(_drag_id)
                if node != null:
                        var target := get_global_mouse_position() - _drag_off
                        var local := _stage.get_global_transform().affine_inverse() * target
                        node.position = local
                        UiConfig.update_widget(_drag_id, "x", snap(local.x))
                        UiConfig.update_widget(_drag_id, "y", snap(local.y))
                        if _sel_id == _drag_id:
                                _x_spin.set_value_no_signal(snap(local.x))
                                _y_spin.set_value_no_signal(snap(local.y))

        # the selection outline hugs the selected widget
        if _sel_id != "":
                var node := _widget_node(_sel_id)
                if node != null:
                        var inv := _stage.get_global_transform().affine_inverse()
                        var top_left: Vector2 = inv * (node.global_position - Vector2(3, 3))
                        var bottom_right: Vector2 = inv * (node.global_position + node.size + Vector2(3, 3))
                        _outline.position = top_left
                        _outline.size = bottom_right - top_left


func snap(v: float) -> float:
        return roundf(v / 2.0) * 2.0
