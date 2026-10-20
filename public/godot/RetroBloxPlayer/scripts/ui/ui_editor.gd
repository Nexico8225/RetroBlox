extends CanvasLayer
## UiEditor — "MAKE IT SO I CAN EDIT ANYTHING MYSELF" (v9.0 autoload "UiEditor").
## The player's OWN editor. Press F2 (or Settings > Edit UI) and EVERYTHING
## becomes editable:
##   - click any registered element -> drag to move it, scale it, edit its text
##   - "+ Add Label" drops YOUR OWN text detail anywhere on screen
##   - Global UI Scale slider zooms the whole client
##   - MY PICTURE: paste any PFP URL (data or web) and wear it everywhere
##   - Save writes user://ui_config.json — your layout boots with you
##   - Reset All wipes back to factory
##
## The editor lives on layer 90 so it sits over every HUD surface, and it
## never shows unless the player asks for it.

signal edit_mode_changed(on: bool)

const RETRO := preload("res://scripts/ui/retro_theme.gd")

var enabled := false

# ---- registry -------------------------------------------------------------
var _registered: Array = []        # [{id, node, base_pos, base_scale, text_ok}]
var _selected: int = -1

# ---- chrome ---------------------------------------------------------------
var _root: Control
var _panel: PanelContainer
var _prop_box: VBoxContainer
var _title_l: Label
var _x_spin: SpinBox
var _y_spin: SpinBox
var _scale_spin: SpinBox
var _text_edit: LineEdit
var _text_row: HBoxContainer
var _scale_ui_spin: SpinBox
var _labels_box: VBoxContainer
var _hint: Label
var _sel_outline: Panel

var _dragging := false
var _locked_note: Label          # "GAME DEVS ONLY" banner (v15.0 role gate)
var _drag_off := Vector2.ZERO
var _drag_dx := 0.0
var _drag_dy := 0.0
var _pick_layer: Control

const EDITOR_LAYER := 90


func _ready() -> void:
        layer = EDITOR_LAYER
        _build_chrome()
        _apply_boot()


# ---------------------------------------------------------------- registry

## Register any Control as editable. `text_ok` lets the Editor expose its
## text. Called by game.gd for every HUD surface it builds.
func register(id: String, node: Control, text_ok := false) -> void:
        if node == null or not is_instance_valid(node):
                return
        for r in _registered:
                if r["id"] == id and is_instance_valid(r["node"]):
                        return
        _registered.append({
                "id": id, "node": node,
                "base_pos": node.position,
                "base_scale": node.scale.x,
                "text_ok": text_ok,
        })
        node.ready.connect(func() -> void: apply_edit(id), CONNECT_DEFERRED)
        apply_edit(id)


func _entry(id: String) -> Dictionary:
        for r in _registered:
                if r["id"] == id:
                        return r
        return {}


## Apply a saved edit (position delta + scale + text) to one element.
func apply_edit(id: String) -> void:
        var e: Dictionary = _entry(id)
        if e.is_empty() or not is_instance_valid(e["node"]):
                return
        var node: Control = e["node"]
        var edit: Dictionary = UiConfig.edit_for(id)
        if edit.is_empty():
                return
        var dx := float(edit.get("dx", 0.0))
        var dy := float(edit.get("dy", 0.0))
        var sc := float(edit.get("scale", 1.0))
        node.position = (e["base_pos"] as Vector2) + Vector2(dx, dy)
        if absf(sc - 1.0) > 0.001:
                node.scale = Vector2(sc, sc)
        var txt := String(edit.get("text", ""))
        if txt != "" and e["text_ok"]:
                if node is Button:
                        (node as Button).text = txt
                elif node is Label:
                        (node as Label).text = txt


## Re-apply every saved edit (boot + viewport resize).
func apply_all() -> void:
        for r in _registered:
                if is_instance_valid(r["node"]):
                        apply_edit(r["id"])


## The custom labels the player added — one floating Label each.
func spawn_labels() -> void:
        var layer_root := _labels_root()
        for child in layer_root.get_children():
                child.queue_free()
        for lb in UiConfig.labels:
                var id := String(lb.get("id", ""))
                var l := Label.new()
                l.name = id
                l.text = String(lb.get("text", "detail"))
                l.add_theme_font_override("font", RETRO.gotham(700))
                l.add_theme_font_size_override("font_size", int(lb.get("size", 18)))
                l.add_theme_color_override("font_color", Color(String(lb.get("color", "#ffffff"))))
                l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
                l.add_theme_constant_override("shadow_offset_x", 1)
                l.add_theme_constant_override("shadow_offset_y", 1)
                l.mouse_filter = Control.MOUSE_FILTER_STOP
                l.position = Vector2(float(lb.get("x", 40.0)), float(lb.get("y", 40.0)))
                l.gui_input.connect(func(ev: InputEvent) -> void:
                        if enabled and ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
                                        and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
                                select_label(id))
                layer_root.add_child(l)


func _labels_root() -> Control:
        var root := _root.get_node_or_null("CustomLabels") as Control
        if root == null:
                root = Control.new()
                root.name = "CustomLabels"
                root.set_anchors_preset(Control.PRESET_FULL_RECT)
                root.mouse_filter = Control.MOUSE_FILTER_IGNORE
                _root.add_child(root)
        return root


func label_node(id: String) -> Label:
        var root := _labels_root()
        return root.get_node_or_null(id) as Label


func _apply_boot() -> void:
        # the global scale rides the root window's content scale
        get_tree().root.content_scale_factor = UiConfig.ui_scale
        spawn_labels()


# ---------------------------------------------------------------- toggle

func set_enabled(on: bool) -> void:
        if enabled == on:
                return
        enabled = on
        _root.visible = on
        edit_mode_changed.emit(on)
        if on:
                _refresh_props()
                _hint.text = "EDIT MODE — click an element to select · drag to move · Save keeps it forever"
                select(_first_selectable())
        else:
                _selected = -1
                if _sel_outline != null:
                        _sel_outline.visible = false
                # a saved edit may have moved things — re-assert the layout
                apply_all()


func _refresh_props() -> void:
        pass


func _first_selectable() -> int:
        for i in range(_registered.size()):
                if is_instance_valid(_registered[i]["node"]):
                        return i
        return -1


func toggle() -> void:
        set_enabled(not enabled)


## v15.0: the banner a PLAYER sees when they press F2 — one sentence that
## says who edits and exactly how to unlock it.
func _show_locked() -> void:
        if _locked_note == null or not is_instance_valid(_locked_note):
                _locked_note = Label.new()
                _locked_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                _locked_note.add_theme_font_override("font", RETRO.gotham(700))
                _locked_note.add_theme_font_size_override("font_size", 16)
                _locked_note.add_theme_color_override("font_color", Color.WHITE)
                _locked_note.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
                _locked_note.add_theme_constant_override("shadow_offset_x", 2)
                _locked_note.add_theme_constant_override("shadow_offset_y", 2)
        _locked_note.text = "GAME DEVS ONLY — the UI editor is an editor scene. Players play; game devs edit.\nPublish any game on retro-blox.vercel.app (a Web game counts) and it unlocks here."
        if _locked_note.get_parent() == null:
                _root.add_child(_locked_note)
        _locked_note.set_anchors_preset(Control.PRESET_CENTER_TOP)
        _locked_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _locked_note.offset_top = 90.0
        _locked_note.visible = true
        var t := get_tree().create_timer(5.0)
        t.timeout.connect(func() -> void:
                if _locked_note != null and is_instance_valid(_locked_note):
                        _locked_note.visible = false)


func _unhandled_key_input(event: InputEvent) -> void:
        if event is InputEventKey and event.is_pressed() and not event.is_echo():
                if (event as InputEventKey).keycode == KEY_F2:
                        # v15.0 ROLES: the UI editor is an editor scene — game
                        # devs edit the UI, players play. Session.check_dev()
                        # answers once per session (one GET, then cached).
                        if not Session.is_dev:
                                Session.check_dev()
                                if not Session.is_dev:
                                        _show_locked()
                                        get_viewport().set_input_as_handled()
                                        return
                        toggle()
                        get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- chrome

func _build_chrome() -> void:
        _root = Control.new()
        _root.name = "UiEditor"
        _root.set_anchors_preset(Control.PRESET_FULL_RECT)
        _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _root.visible = false
        add_child(_root)

        # ---- the pick layer: a full-rect catcher ABOVE every HUD surface.
        # In edit mode it takes ALL mouse input, so clicks never reach the
        # game UI — instead it hit-tests the registry and drags selections.
        _pick_layer = Control.new()
        _pick_layer.name = "PickLayer"
        _pick_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
        _pick_layer.mouse_filter = Control.MOUSE_FILTER_STOP
        _pick_layer.gui_input.connect(_on_pick_input)
        _root.add_child(_pick_layer)

        # the selection outline — one Panel that hugs the selected element
        _sel_outline = Panel.new()
        _sel_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0, 0, 0, 0)
        sb.set_border_width_all(2)
        sb.border_color = Color("38ff8c")
        sb.set_corner_radius_all(6)
        _sel_outline.add_theme_stylebox_override("panel", sb)
        _sel_outline.visible = false
        _root.add_child(_sel_outline)

        # ---- the editor panel (top-right) ----
        _panel = PanelContainer.new()
        _panel.name = "EditorPanel"
        _panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
        _panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
        _panel.offset_right = -14.0
        _panel.offset_top = 14.0
        _panel.custom_minimum_size = Vector2(280, 0)
        # v10.0: the editor is a classic beveled window too — green accents
        var psb: StyleBox = RETRO.raised(4, Color(0.16, 0.16, 0.16, 0.97))
        psb.content_margin_left = 14.0
        psb.content_margin_right = 14.0
        psb.content_margin_top = 12.0
        psb.content_margin_bottom = 12.0
        _panel.add_theme_stylebox_override("panel", psb)
        _root.add_child(_panel)

        var col := VBoxContainer.new()
        col.add_theme_constant_override("separation", 8)
        _panel.add_child(col)

        _title_l = Label.new()
        _title_l.text = "UI EDITOR"
        _title_l.add_theme_font_override("font", RETRO.gotham(800))
        _title_l.add_theme_font_size_override("font_size", 15)
        _title_l.add_theme_color_override("font_color", RETRO.GREEN)
        col.add_child(_title_l)

        _hint = Label.new()
        _hint.text = "Click an element, then edit it."
        _hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _hint.add_theme_font_override("font", RETRO.source(400))
        _hint.add_theme_font_size_override("font_size", 12)
        _hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
        col.add_child(_hint)

        # ---- per-element properties ----
        _prop_box = VBoxContainer.new()
        _prop_box.add_theme_constant_override("separation", 6)
        col.add_child(_prop_box)

        _x_spin = _spin_row(_prop_box, "X")
        _y_spin = _spin_row(_prop_box, "Y")
        _scale_spin = _spin_row(_prop_box, "Scale", 0.4, 3.0, 0.05)
        _x_spin.value_changed.connect(func(v: float) -> void: _on_move(v, -1.0))
        _y_spin.value_changed.connect(func(v: float) -> void: _on_move(-1.0, v))
        _scale_spin.value_changed.connect(func(v: float) -> void: _on_elem_scale(v))

        _text_row = HBoxContainer.new()
        _text_row.add_theme_constant_override("separation", 6)
        var tl := Label.new()
        tl.text = "Text"
        tl.custom_minimum_size = Vector2(52, 0)
        tl.add_theme_font_override("font", RETRO.source(600))
        tl.add_theme_font_size_override("font_size", 12)
        tl.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
        _text_row.add_child(tl)
        _text_edit = LineEdit.new()
        _text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _text_edit.add_theme_font_size_override("font_size", 12)
        _text_edit.text_submitted.connect(func(t: String) -> void: _on_text(t))
        _text_row.add_child(_text_edit)
        _prop_box.add_child(_text_row)

        var del := Button.new()
        del.text = "Delete this label"
        del.visible = false
        del.pressed.connect(_on_delete_label)
        _style_key(del, Color("5a1f24"))
        _prop_box.add_child(del)
        _prop_box.set_meta("del_btn", del)

        col.add_child(_hspace(4))

        # ---- global controls ----
        var gs_l := Label.new()
        gs_l.text = "GLOBAL UI SCALE"
        gs_l.add_theme_font_override("font", RETRO.gotham(700))
        gs_l.add_theme_font_size_override("font_size", 11)
        gs_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
        col.add_child(gs_l)
        _scale_ui_spin = _spin_row(col, "Zoom", 0.6, 1.6, 0.05)
        _scale_ui_spin.value = UiConfig.ui_scale
        _scale_ui_spin.value_changed.connect(func(v: float) -> void:
                UiConfig.ui_scale = v
                get_tree().root.content_scale_factor = v)

        var add := Button.new()
        add.text = "+ Add Label (my detail)"
        add.pressed.connect(_on_add_label)
        _style_key(add, Color("1f4a2a"))
        col.add_child(add)

        _labels_box = VBoxContainer.new()
        _labels_box.add_theme_constant_override("separation", 4)
        col.add_child(_labels_box)


        col.add_child(_hspace(4))

        # ---- save / reset / done ----
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 6)
        col.add_child(row)
        var save := Button.new()
        save.text = "Save"
        save.pressed.connect(_on_save)
        _style_key(save, Color("1f4a2a"))
        save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(save)
        var reset := Button.new()
        reset.text = "Reset All"
        reset.pressed.connect(_on_reset)
        _style_key(reset, Color("5a1f24"))
        reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(reset)
        var done := Button.new()
        done.text = "Done (F2)"
        done.pressed.connect(func() -> void: set_enabled(false))
        _style_key(done, Color("33363b"))
        done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(done)


func _hspace(h: int) -> Control:
        var c := Control.new()
        c.custom_minimum_size = Vector2(0, h)
        return c


func _spin_row(parent: VBoxContainer, title: String, mn := -100000.0, mx := 100000.0, step := 1.0) -> SpinBox:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 6)
        var l := Label.new()
        l.text = title
        l.custom_minimum_size = Vector2(52, 0)
        l.add_theme_font_override("font", RETRO.source(600))
        l.add_theme_font_size_override("font_size", 12)
        l.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
        row.add_child(l)
        var s := SpinBox.new()
        s.min_value = mn
        s.max_value = mx
        s.step = step
        s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        s.add_theme_font_size_override("font_size", 12)
        row.add_child(s)
        parent.add_child(row)
        return s


func _style_key(b: Button, face: Color) -> void:
        # v10.0: classic beveled keys — raised, hover lightens, press sinks
        var sb: StyleBox = RETRO.raised(4, face)
        sb.content_margin_left = 10.0
        sb.content_margin_right = 10.0
        sb.content_margin_top = 6.0
        sb.content_margin_bottom = 6.0
        b.add_theme_stylebox_override("normal", sb)
        var hb: StyleBox = RETRO.raised(4, face.lightened(0.12))
        hb.content_margin_left = 10.0
        hb.content_margin_right = 10.0
        hb.content_margin_top = 6.0
        hb.content_margin_bottom = 6.0
        b.add_theme_stylebox_override("hover", hb)
        b.add_theme_stylebox_override("pressed", RETRO.sunken(4, face.darkened(0.2)))
        b.add_theme_font_override("font", RETRO.gotham(600))
        b.add_theme_font_size_override("font_size", 12)
        b.add_theme_color_override("font_color", Color.WHITE)
        b.add_theme_color_override("font_hover_color", Color.WHITE)
        b.add_theme_color_override("font_pressed_color", Color.WHITE)
        b.focus_mode = Control.FOCUS_NONE


# ---------------------------------------------------------------- selection

func select(idx: int) -> void:
        if idx < 0 or idx >= _registered.size() or not is_instance_valid(_registered[idx]["node"]):
                _selected = -1
                _prop_box.visible = false
                if _sel_outline != null:
                        _sel_outline.visible = false
                return
        _selected = idx
        var node: Control = _registered[idx]["node"]
        _prop_box.visible = true
        _title_l.text = "EDIT: " + String(_registered[idx]["id"])
        var edit: Dictionary = UiConfig.edit_for(_registered[idx]["id"])
        _x_spin.set_value_no_signal(float(edit.get("dx", 0.0)))
        _y_spin.set_value_no_signal(float(edit.get("dy", 0.0)))
        _scale_spin.set_value_no_signal(float(edit.get("scale", node.scale.x)))
        _text_row.visible = bool(_registered[idx]["text_ok"])
        _text_edit.text = String(edit.get("text", ""))
        if node is Button:
                _text_edit.text = (node as Button).text
        elif node is Label:
                _text_edit.text = (node as Label).text
        var del: Button = _prop_box.get_meta("del_btn")
        del.visible = String(_registered[idx]["id"]).begins_with("label_")
        _refresh_labels_list()


func select_label(id: String) -> void:
        var node := label_node(id)
        if node == null:
                return
        var idx := -1
        for i in range(_registered.size()):
                if _registered[i]["id"] == id:
                        idx = i
                        break
        if idx < 0:
                # register it lazily so the normal machinery drives it
                register(id, node, true)
                idx = _registered.size() - 1
        select(idx)


func _refresh_labels_list() -> void:
        for child in _labels_box.get_children():
                child.queue_free()
        for lb in UiConfig.labels:
                var chip := Button.new()
                chip.text = "• %s" % String(lb.get("text", "")).left(18)
                chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
                _style_key(chip, Color("2a2d33"))
                var id := String(lb.get("id", ""))
                chip.pressed.connect(func() -> void: select_label(id))
                _labels_box.add_child(chip)


# ---------------------------------------------------------------- edits

func _on_move(x: float, y: float) -> void:
        if _selected < 0:
                return
        var r: Dictionary = _registered[_selected]
        if not is_instance_valid(r["node"]):
                return
        var node: Control = r["node"]
        if x >= 0.0:
                UiConfig.set_edit(r["id"], "dx", x)
                node.position.x = (r["base_pos"] as Vector2).x + x
        if y >= 0.0:
                UiConfig.set_edit(r["id"], "dy", y)
                node.position.y = (r["base_pos"] as Vector2).y + y


func _on_elem_scale(v: float) -> void:
        if _selected < 0:
                return
        var r: Dictionary = _registered[_selected]
        if not is_instance_valid(r["node"]):
                return
        var node: Control = r["node"]
        node.pivot_offset = node.size * 0.5
        node.scale = Vector2(v, v)
        UiConfig.set_edit(r["id"], "scale", v)


func _on_text(t: String) -> void:
        if _selected < 0:
                return
        var r: Dictionary = _registered[_selected]
        if not is_instance_valid(r["node"]):
                return
        var node: Control = r["node"]
        if node is Button:
                (node as Button).text = t
        elif node is Label:
                (node as Label).text = t
        if String(r["id"]).begins_with("label_"):
                UiConfig.update_label(r["id"], "text", t)
        else:
                UiConfig.set_edit(r["id"], "text", t)
        _refresh_labels_list()


func _on_add_label() -> void:
        var center := _root.get_viewport_rect().size * 0.5
        var id := UiConfig.add_label("MY DETAIL", center, 18, "#ffffff")
        spawn_labels()
        select_label(id)
        _refresh_labels_list()


func _on_delete_label() -> void:
        if _selected < 0:
                return
        var id := String(_registered[_selected]["id"])
        if not id.begins_with("label_"):
                return
        UiConfig.remove_label(id)
        var node := label_node(id)
        if node != null and is_instance_valid(node):
                node.queue_free()
        _registered = _registered.filter(func(r: Dictionary) -> bool: return r["id"] != id)
        select(_first_selectable())



func _on_save() -> void:
        UiConfig.save_config()
        _hint.text = "SAVED — your layout boots with you from now on."


func _on_reset() -> void:
        UiConfig.clear_all()
        for r in _registered:
                if not is_instance_valid(r["node"]):
                        continue
                var node: Control = r["node"]
                node.position = r["base_pos"]
                node.scale = Vector2.ONE
                # custom labels get rebuilt from the (now empty) list
        get_tree().root.content_scale_factor = 1.0
        _scale_ui_spin.set_value_no_signal(1.0)
        spawn_labels()
        select(_first_selectable())
        _hint.text = "RESET — everything is back to factory."


# ---------------------------------------------------------------- picking + dragging

func _gui_input_pick(at: Vector2) -> void:
        if not enabled:
                return
        # topmost registered element whose global rect contains `at`
        var picked := -1
        for i in range(_registered.size() - 1, -1, -1):
                var node: Control = _registered[i]["node"]
                if is_instance_valid(node) and node.is_visible_in_tree() \
                                and node.get_global_rect().has_point(at):
                        picked = i
                        break
        if picked >= 0:
                select(picked)
                var node: Control = _registered[picked]["node"]
                _dragging = true
                _drag_off = at - node.get_global_rect().position
                _drag_dx = float(UiConfig.edit_for(_registered[picked]["id"]).get("dx", 0.0))
                _drag_dy = float(UiConfig.edit_for(_registered[picked]["id"]).get("dy", 0.0))


## The pick layer's input: click = select, drag = move, release = drop.
func _on_pick_input(event: InputEvent) -> void:
        if not enabled:
                return
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_LEFT:
                        if mb.pressed:
                                _gui_input_pick(mb.position)
                        else:
                                _dragging = false
        elif event is InputEventMouseMotion and _dragging and _selected >= 0:
                var mm := event as InputEventMouseMotion
                var r: Dictionary = _registered[_selected]
                if not is_instance_valid(r["node"]):
                        return
                var node: Control = r["node"]
                var target := mm.position - _drag_off
                _drag_dx = target.x - (r["base_pos"] as Vector2).x
                _drag_dy = target.y - (r["base_pos"] as Vector2).y
                node.position = (r["base_pos"] as Vector2) + Vector2(_drag_dx, _drag_dy)
                _x_spin.set_value_no_signal(_drag_dx)
                _y_spin.set_value_no_signal(_drag_dy)


func _unhandled_input(event: InputEvent) -> void:
        if not enabled:
                return
        # safety net only — the pick layer handles everything normal
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
                        _gui_input_pick(mb.position)
                        _dragging = false


func _process(_delta: float) -> void:
        if not enabled or _selected < 0:
                if _sel_outline != null and _sel_outline.visible and not enabled:
                        _sel_outline.visible = false
                return
        var r: Dictionary = _registered[_selected]
        if r.is_empty() or not is_instance_valid(r["node"]):
                return
        var node: Control = r["node"]
        var rect := node.get_global_rect()
        _sel_outline.visible = true
        _sel_outline.position = rect.position - Vector2(4, 4)
        _sel_outline.size = rect.size + Vector2(8, 8)
