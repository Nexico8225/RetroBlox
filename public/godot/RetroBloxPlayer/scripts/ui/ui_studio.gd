class_name UIStudio
extends Control
# In-game UI editor with Photoshop-style 8-dot transform handles, follower inspector popover, numeric X/Y/Scale/Rot/Opacity inputs, and snapping.

signal studio_closed(reopen_esc_menu: bool)

const SAVE_PATH := "user://ui_studio_layout.cfg"
const SNAP_GRID := 16.0
const SNAP_THRESHOLD := 14.0
const HANDLE_HALF := 6.0
const RetroUI := preload("res://scripts/ui/retro_theme.gd")

var hud_root: CanvasLayer
var targets: Dictionary = {}
var selected_key := ""
var snap_enabled := true
var layout_enabled := true

var _top_holder: CenterContainer
var _top_bar: PanelContainer
var _snap_btn: Button
var _popover: PanelContainer
var _pop_title: Label
var _vis_btn: Button
var _spin_x: SpinBox
var _spin_y: SpinBox
var _spin_scale: SpinBox
var _spin_rot: SpinBox
var _spin_alpha: SpinBox
var _updating_spins := false
var _anchor_btns: Dictionary = {}
var _highlight_box: Panel
var _handle_dots: Array[Panel] = []
var _center_dot: Panel
var _snap_line_v: ColorRect
var _snap_line_h: ColorRect
var _file_dialog: FileDialog
var _dragging_target := false
var _dragging_handle := -1
var _drag_start_mouse := Vector2.ZERO
var _drag_start_pos := Vector2.ZERO
var _drag_start_scale := Vector2.ONE
var _drag_start_size := Vector2.ZERO
var _drag_offset := Vector2.ZERO
var _defaults: Dictionary = {}
var _hidden_flags: Dictionary = {}
var _alphas: Dictionary = {}
var _anchors: Dictionary = {}
var _custom_images: Dictionary = {}
var _custom_counter := 0
var _reopen_esc_on_close := true


func setup(p_hud: CanvasLayer, initial_targets: Dictionary) -> void:
	name = "UIStudio"
	hud_root = p_hud
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_build_ui()

	for k in initial_targets.keys():
		register_target(String(k), initial_targets[k])

	load_layout()


func _detach_from_box_container(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	var p := ctrl.get_parent()
	if p is BoxContainer:
		ctrl.top_level = true


func register_target(key: String, ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	targets[key] = ctrl
	if not _defaults.has(key):
		_defaults[key] = {
			"pos": ctrl.position,
			"global_pos": ctrl.global_position,
			"scale": ctrl.scale,
			"rot": ctrl.rotation_degrees,
			"alpha": ctrl.modulate.a if key != "Joystick" else 1.0,
			"visible": ctrl.visible,
			"anchor_l": ctrl.anchor_left,
			"anchor_t": ctrl.anchor_top,
			"anchor_r": ctrl.anchor_right,
			"anchor_b": ctrl.anchor_bottom,
		}
	if not _alphas.has(key):
		_alphas[key] = 1.0
	if not _hidden_flags.has(key):
		_hidden_flags[key] = false
	if not _anchors.has(key):
		_anchors[key] = "Custom"


func set_layout_enabled(enabled: bool) -> void:
	layout_enabled = enabled
	if enabled:
		load_layout()
	else:
		_restore_defaults_temporarily()


func _restore_defaults_temporarily() -> void:
	for k in _defaults.keys():
		if not targets.has(k) or not is_instance_valid(targets[k]):
			continue
		var c: Control = targets[k]
		var d: Dictionary = _defaults[k]
		c.top_level = false
		c.position = d["pos"]
		c.scale = d["scale"]
		c.rotation_degrees = d["rot"]
		if k != "Joystick":
			c.modulate.a = d["alpha"]
		c.visible = d["visible"]
	for k in _custom_images.keys():
		if targets.has(k) and is_instance_valid(targets[k]):
			(targets[k] as Control).visible = false


func _is_mobile_active() -> bool:
	var settings: Node = get_node_or_null("/root/Settings")
	if settings == null:
		return false
	return bool(settings.call("is_mobile_ui_active"))


func _is_target_editable_now(key: String) -> bool:
	if key in ["Joystick", "JumpButton"] and not _is_mobile_active():
		return false
	return true


func open_studio(from_esc_menu := true) -> void:
	_reopen_esc_on_close = from_esc_menu
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var mobile_now := _is_mobile_active()
	if targets.has("Joystick") and is_instance_valid(targets["Joystick"]):
		var joy: Control = targets["Joystick"]
		var joy_parent := joy.get_parent() as Control
		if joy_parent != null:
			joy_parent.visible = mobile_now
		joy.visible = mobile_now and not bool(_hidden_flags.get("Joystick", false))
		joy.modulate.a = maxf(float(_alphas.get("Joystick", 1.0)), 0.78) if mobile_now else 0.0
	if targets.has("JumpButton") and is_instance_valid(targets["JumpButton"]):
		var jb: Control = targets["JumpButton"]
		jb.visible = mobile_now and not bool(_hidden_flags.get("JumpButton", false))

	selected_key = ""
	_set_gizmo_visible(false)
	if _popover != null:
		_popover.visible = false


func close_studio() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dragging_target = false
	_dragging_handle = -1
	if _snap_line_v != null:
		_snap_line_v.visible = false
	if _snap_line_h != null:
		_snap_line_h.visible = false
	if _popover != null:
		_popover.visible = false
	_set_gizmo_visible(false)
	if targets.has("Joystick") and is_instance_valid(targets["Joystick"]):
		var joy: Control = targets["Joystick"]
		joy.modulate.a = 0.0
		var joy_parent := joy.get_parent() as Control
		if joy_parent != null:
			joy_parent.visible = _is_mobile_active()
	save_layout()
	studio_closed.emit(_reopen_esc_on_close)


func is_element_hidden(key: String) -> bool:
	return bool(_hidden_flags.get(key, false))


func get_element_alpha(key: String) -> float:
	return float(_alphas.get(key, 1.0))


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_highlight_and_popover()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_studio()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_handle_pointer_down(mb.global_position)
				accept_event()
			else:
				_handle_pointer_up()
				accept_event()
	elif event is InputEventMouseMotion:
		if _dragging_handle >= 0 or _dragging_target:
			_handle_pointer_move((event as InputEventMouseMotion).global_position)
			accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_handle_pointer_down(st.position)
			accept_event()
		else:
			_handle_pointer_up()
			accept_event()
	elif event is InputEventScreenDrag:
		if _dragging_handle >= 0 or _dragging_target:
			_handle_pointer_move((event as InputEventScreenDrag).position)
			accept_event()


func _handle_pointer_down(screen_pos: Vector2) -> void:
	if _top_bar != null and _top_bar.get_global_rect().has_point(screen_pos):
		return
	if _popover != null and _popover.visible and _popover.get_global_rect().has_point(screen_pos):
		return

	# First check if user clicked one of the 8 Photoshop transform handle dots on the active selection
	var cur := _current_control()
	if cur != null:
		var h_idx := _pick_handle_at(screen_pos)
		if h_idx >= 0:
			_detach_from_box_container(cur)
			_dragging_handle = h_idx
			_dragging_target = false
			_drag_start_mouse = screen_pos
			_drag_start_pos = cur.global_position
			_drag_start_scale = cur.scale
			_drag_start_size = Vector2(maxf(cur.size.x, 24.0), maxf(cur.size.y, 24.0))
			return

	var hit_key := _pick_target_at(screen_pos)
	if hit_key != "":
		selected_key = hit_key
		_sync_inspector()
		cur = _current_control()
		if cur != null:
			_dragging_target = true
			_dragging_handle = -1
			_drag_offset = cur.global_position - screen_pos
	else:
		selected_key = ""
		if _popover != null:
			_popover.visible = false
		_set_gizmo_visible(false)


func _handle_pointer_move(screen_pos: Vector2) -> void:
	var cur := _current_control()
	if cur == null:
		return
	if _dragging_handle >= 0:
		_detach_from_box_container(cur)
		_resize_with_handle(cur, screen_pos)
		_sync_spin_values(cur)
	elif _dragging_target:
		_detach_from_box_container(cur)
		_move_control_with_snap(cur, screen_pos + _drag_offset)
		_sync_spin_values(cur)


func _handle_pointer_up() -> void:
	if _dragging_target or _dragging_handle >= 0:
		_dragging_target = false
		_dragging_handle = -1
		if _snap_line_v != null:
			_snap_line_v.visible = false
		if _snap_line_h != null:
			_snap_line_h.visible = false
		save_layout()


func _pick_handle_at(screen_pos: Vector2) -> int:
	for i in range(_handle_dots.size()):
		var dot := _handle_dots[i]
		if dot != null and dot.visible:
			var r := Rect2(dot.global_position, dot.size).grow(8.0)
			if r.has_point(screen_pos):
				return i
	return -1


func _resize_with_handle(ctrl: Control, mouse_pos: Vector2) -> void:
	var delta := mouse_pos - _drag_start_mouse
	var start_w := _drag_start_size.x * _drag_start_scale.x
	var start_h := _drag_start_size.y * _drag_start_scale.y
	var new_w := start_w
	var new_h := start_h
	var new_pos := _drag_start_pos

	# Handle indices:
	# 0=NW, 1=N, 2=NE, 3=W, 4=E, 5=SW, 6=S, 7=SE
	match _dragging_handle:
		0: # Top-Left
			new_w = start_w - delta.x
			new_h = start_h - delta.y
		1: # Top
			new_h = start_h - delta.y
		2: # Top-Right
			new_w = start_w + delta.x
			new_h = start_h - delta.y
		3: # Left
			new_w = start_w - delta.x
		4: # Right
			new_w = start_w + delta.x
		5: # Bottom-Left
			new_w = start_w - delta.x
			new_h = start_h + delta.y
		6: # Bottom
			new_h = start_h + delta.y
		7: # Bottom-Right
			new_w = start_w + delta.x
			new_h = start_h + delta.y

	var ratio_w := new_w / maxf(_drag_start_size.x, 1.0)
	var ratio_h := new_h / maxf(_drag_start_size.y, 1.0)
	var uniform_s := _drag_start_scale.x
	if _dragging_handle in [1, 6]:
		uniform_s = ratio_h
	elif _dragging_handle in [3, 4]:
		uniform_s = ratio_w
	else:
		uniform_s = (ratio_w + ratio_h) * 0.5

	uniform_s = clampf(uniform_s, 0.30, 3.0)
	if snap_enabled:
		uniform_s = snappedf(uniform_s, 0.05)

	var actual_w := _drag_start_size.x * uniform_s
	var actual_h := _drag_start_size.y * uniform_s
	if _dragging_handle in [0, 3, 5]:
		new_pos.x = _drag_start_pos.x + (start_w - actual_w)
	if _dragging_handle in [0, 1, 2]:
		new_pos.y = _drag_start_pos.y + (start_h - actual_h)

	ctrl.scale = Vector2(uniform_s, uniform_s)
	ctrl.global_position = new_pos


func _move_control_with_snap(ctrl: Control, raw_pos: Vector2) -> void:
	var vp_size := get_viewport_rect().size
	var box_size := ctrl.size * ctrl.scale
	var final_pos := raw_pos
	var show_v := false
	var show_h := false
	var v_x := 0.0
	var h_y := 0.0

	if snap_enabled:
		final_pos.x = snappedf(raw_pos.x, SNAP_GRID)
		final_pos.y = snappedf(raw_pos.y, SNAP_GRID)

		var center_x := (vp_size.x - box_size.x) * 0.5
		var center_y := (vp_size.y - box_size.y) * 0.5
		if absf(raw_pos.x - center_x) <= SNAP_THRESHOLD:
			final_pos.x = center_x
			show_v = true
			v_x = vp_size.x * 0.5
		elif absf(raw_pos.x - 12.0) <= SNAP_THRESHOLD:
			final_pos.x = 12.0
			show_v = true
			v_x = 12.0
		elif absf((raw_pos.x + box_size.x) - (vp_size.x - 12.0)) <= SNAP_THRESHOLD:
			final_pos.x = vp_size.x - 12.0 - box_size.x
			show_v = true
			v_x = vp_size.x - 12.0

		if absf(raw_pos.y - center_y) <= SNAP_THRESHOLD:
			final_pos.y = center_y
			show_h = true
			h_y = vp_size.y * 0.5
		elif absf(raw_pos.y - 12.0) <= SNAP_THRESHOLD:
			final_pos.y = 12.0
			show_h = true
			h_y = 12.0
		elif absf((raw_pos.y + box_size.y) - (vp_size.y - 12.0)) <= SNAP_THRESHOLD:
			final_pos.y = vp_size.y - 12.0 - box_size.y
			show_h = true
			h_y = vp_size.y - 12.0

	final_pos.x = clampf(final_pos.x, 0.0, maxf(vp_size.x - 24.0, 0.0))
	final_pos.y = clampf(final_pos.y, 0.0, maxf(vp_size.y - 24.0, 0.0))
	ctrl.global_position = final_pos

	if _snap_line_v != null:
		_snap_line_v.visible = show_v
		_snap_line_v.position.x = v_x
	if _snap_line_h != null:
		_snap_line_h.visible = show_h
		_snap_line_h.position.y = h_y


func _pick_target_at(screen_pos: Vector2) -> String:
	# Prioritize smaller/specific child buttons (like ChatButton, VoiceMicButton, MenuButton) before parent containers
	var priority_order: Array[String] = []
	for k in targets.keys():
		var ks := String(k)
		if ks in ["MenuButton", "ChatButton", "VoiceMicButton"]:
			priority_order.append(ks)
	for k in targets.keys():
		var ks := String(k)
		if not priority_order.has(ks):
			priority_order.append(ks)

	for ks in priority_order:
		if not _is_target_editable_now(ks):
			continue
		var c: Control = targets[ks]
		if c == null or not is_instance_valid(c):
			continue
		var rect := Rect2(c.global_position, c.size * c.scale)
		if rect.grow(6.0).has_point(screen_pos):
			return ks
	return ""


func _current_control() -> Control:
	if selected_key == "" or not targets.has(selected_key):
		return null
	if not _is_target_editable_now(selected_key):
		return null
	var c: Control = targets[selected_key]
	if c == null or not is_instance_valid(c):
		return null
	return c


func _set_gizmo_visible(vis: bool) -> void:
	if _highlight_box != null:
		_highlight_box.visible = vis
	if _center_dot != null:
		_center_dot.visible = vis
	for d in _handle_dots:
		if d != null:
			d.visible = vis


func _update_highlight_and_popover() -> void:
	var cur := _current_control()
	if cur == null:
		_set_gizmo_visible(false)
		if _popover != null:
			_popover.visible = false
		return

	var box_pos := cur.global_position
	var box_size := Vector2(maxf(cur.size.x, 24.0), maxf(cur.size.y, 24.0)) * cur.scale
	_set_gizmo_visible(true)
	if _highlight_box != null:
		_highlight_box.global_position = box_pos
		_highlight_box.size = box_size
		_highlight_box.rotation_degrees = 0.0

	# Position the 8 Photoshop transform handle dots around the bounding box + 1 center dot
	var pts: Array[Vector2] = [
		box_pos,
		Vector2(box_pos.x + box_size.x * 0.5, box_pos.y),
		Vector2(box_pos.x + box_size.x, box_pos.y),
		Vector2(box_pos.x, box_pos.y + box_size.y * 0.5),
		Vector2(box_pos.x + box_size.x, box_pos.y + box_size.y * 0.5),
		Vector2(box_pos.x, box_pos.y + box_size.y),
		Vector2(box_pos.x + box_size.x * 0.5, box_pos.y + box_size.y),
		box_pos + box_size,
	]
	for i in range(mini(pts.size(), _handle_dots.size())):
		_handle_dots[i].global_position = pts[i] - Vector2(HANDLE_HALF, HANDLE_HALF)
	if _center_dot != null:
		_center_dot.global_position = box_pos + box_size * 0.5 - Vector2(HANDLE_HALF, HANDLE_HALF)

	if _popover != null:
		_popover.visible = true
		var vp_size := get_viewport_rect().size
		var pop_size := _popover.size
		var px := box_pos.x + (box_size.x - pop_size.x) * 0.5
		px = clampf(px, 14.0, maxf(vp_size.x - pop_size.x - 14.0, 14.0))
		# Appear directly above the selected UI element; if near the top edge, appear right below it so it never cuts off
		var py := box_pos.y - pop_size.y - 16.0
		if py < 68.0:
			py = clampf(box_pos.y + box_size.y + 16.0, 68.0, maxf(vp_size.y - pop_size.y - 14.0, 68.0))
		_popover.global_position = Vector2(px, py)


func _build_ui() -> void:
	_snap_line_v = ColorRect.new()
	_snap_line_v.name = "SnapLineV"
	_snap_line_v.color = Color(0.1, 0.55, 1.0, 0.85)
	_snap_line_v.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_snap_line_v.custom_minimum_size = Vector2(2, 0)
	_snap_line_v.size = Vector2(2, 2000)
	_snap_line_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snap_line_v.visible = false
	add_child(_snap_line_v)

	_snap_line_h = ColorRect.new()
	_snap_line_h.name = "SnapLineH"
	_snap_line_h.color = Color(0.1, 0.55, 1.0, 0.85)
	_snap_line_h.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_snap_line_h.custom_minimum_size = Vector2(0, 2)
	_snap_line_h.size = Vector2(3000, 2)
	_snap_line_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snap_line_h.visible = false
	add_child(_snap_line_h)

	# Photoshop-style crisp blue bounding box
	_highlight_box = Panel.new()
	_highlight_box.name = "SelectionBox"
	_highlight_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb_style := StyleBoxFlat.new()
	hb_style.bg_color = Color(0.09, 0.53, 1.0, 0.08)
	hb_style.border_color = Color(0.09, 0.53, 1.0, 0.98)
	hb_style.set_border_width_all(2)
	_highlight_box.add_theme_stylebox_override("panel", hb_style)
	_highlight_box.visible = false
	add_child(_highlight_box)

	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = Color.WHITE
	dot_style.border_color = Color(0.09, 0.53, 1.0, 1.0)
	dot_style.set_border_width_all(2)
	dot_style.set_corner_radius_all(1)

	for i in range(8):
		var dot := Panel.new()
		dot.name = "HandleDot_%d" % i
		dot.size = Vector2(HANDLE_HALF * 2.0, HANDLE_HALF * 2.0)
		dot.custom_minimum_size = dot.size
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", dot_style)
		dot.visible = false
		add_child(dot)
		_handle_dots.append(dot)

	_center_dot = Panel.new()
	_center_dot.name = "CenterDot"
	_center_dot.size = Vector2(HANDLE_HALF * 2.0, HANDLE_HALF * 2.0)
	_center_dot.custom_minimum_size = _center_dot.size
	_center_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_dot.add_theme_stylebox_override("panel", dot_style)
	_center_dot.visible = false
	add_child(_center_dot)

	# Full-width top CenterContainer so the top bar never cuts off on any screen resolution
	_top_holder = CenterContainer.new()
	_top_holder.name = "TopBarHolder"
	_top_holder.anchor_left = 0.0
	_top_holder.anchor_top = 0.0
	_top_holder.anchor_right = 1.0
	_top_holder.anchor_bottom = 0.0
	_top_holder.offset_top = 12.0
	_top_holder.offset_bottom = 58.0
	_top_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_holder)

	_top_bar = PanelContainer.new()
	_top_bar.name = "StudioTopBar"
	var tb_sb := StyleBoxFlat.new()
	tb_sb.bg_color = Color(0.06, 0.08, 0.11, 0.95)
	tb_sb.border_color = Color(1, 1, 1, 0.22)
	tb_sb.set_border_width_all(1)
	tb_sb.set_corner_radius_all(20)
	tb_sb.content_margin_left = 18.0
	tb_sb.content_margin_right = 18.0
	tb_sb.content_margin_top = 7.0
	tb_sb.content_margin_bottom = 7.0
	_top_bar.add_theme_stylebox_override("panel", tb_sb)
	_top_holder.add_child(_top_bar)

	var tb_row := HBoxContainer.new()
	tb_row.add_theme_constant_override("separation", 10)
	_top_bar.add_child(tb_row)

	var hint_lbl := Label.new()
	hint_lbl.text = "Click any UI to transform (drag dots or type numbers)"
	hint_lbl.add_theme_font_size_override("font_size", 13)
	hint_lbl.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0))
	if RetroUI.gotham(600) != null:
		hint_lbl.add_theme_font_override("font", RetroUI.gotham(600))
	tb_row.add_child(hint_lbl)

	_snap_btn = _make_btn("Snap: ON", Vector2(88, 28), Color(0.16, 0.48, 0.68))
	_snap_btn.pressed.connect(func() -> void:
		snap_enabled = not snap_enabled
		_snap_btn.text = "Snap: ON" if snap_enabled else "Snap: OFF")
	tb_row.add_child(_snap_btn)

	var add_img_btn := _make_btn("+ Image", Vector2(80, 28), Color(0.22, 0.45, 0.82))
	add_img_btn.pressed.connect(_on_add_image_pressed)
	tb_row.add_child(add_img_btn)

	var reset_all_btn := _make_btn("Reset All", Vector2(84, 28))
	reset_all_btn.pressed.connect(reset_all)
	tb_row.add_child(reset_all_btn)

	var done_btn := _make_btn("Done", Vector2(74, 28), Color(0.18, 0.68, 0.36))
	done_btn.pressed.connect(close_studio)
	tb_row.add_child(done_btn)

	# Contextual floating popover card that follows the selected UI element
	_popover = PanelContainer.new()
	_popover.name = "ContextualPopover"
	_popover.custom_minimum_size = Vector2(390, 178)
	_popover.visible = false

	var pop_sb := StyleBoxFlat.new()
	pop_sb.bg_color = Color(0.07, 0.09, 0.13, 0.96)
	pop_sb.border_color = Color(0.15, 0.65, 1.0, 0.85)
	pop_sb.set_border_width_all(1)
	pop_sb.set_corner_radius_all(10)
	pop_sb.shadow_color = Color(0, 0, 0, 0.5)
	pop_sb.shadow_size = 14
	pop_sb.content_margin_left = 14.0
	pop_sb.content_margin_right = 14.0
	pop_sb.content_margin_top = 10.0
	pop_sb.content_margin_bottom = 10.0
	_popover.add_theme_stylebox_override("panel", pop_sb)
	add_child(_popover)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_popover.add_child(vbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vbox.add_child(head)

	_pop_title = Label.new()
	_pop_title.text = "Selected UI"
	_pop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pop_title.add_theme_font_size_override("font_size", 14)
	_pop_title.add_theme_color_override("font_color", Color(0.38, 0.88, 1.0))
	if RetroUI.gotham(700) != null:
		_pop_title.add_theme_font_override("font", RetroUI.gotham(700))
	head.add_child(_pop_title)

	_vis_btn = _make_btn("Visible", Vector2(68, 24))
	_vis_btn.pressed.connect(_toggle_selected_visibility)
	head.add_child(_vis_btn)

	var reset_one := _make_btn("Reset", Vector2(58, 24))
	reset_one.pressed.connect(_reset_selected)
	head.add_child(reset_one)

	var del_btn := _make_btn("Del", Vector2(44, 24), Color(0.65, 0.18, 0.18))
	del_btn.pressed.connect(_delete_selected_custom_image)
	head.add_child(del_btn)

	# Anchor Row
	var anchor_row := HBoxContainer.new()
	anchor_row.add_theme_constant_override("separation", 4)
	vbox.add_child(anchor_row)

	var anchor_lbl := Label.new()
	anchor_lbl.text = "Anchor"
	anchor_lbl.custom_minimum_size = Vector2(54, 0)
	anchor_lbl.add_theme_font_size_override("font_size", 12)
	anchor_lbl.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
	anchor_row.add_child(anchor_lbl)

	for a_name in ["Top-L", "Top-R", "Bot-L", "Bot-R", "Center"]:
		var ab := _make_btn(a_name, Vector2(52, 24))
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var captured_name := String(a_name)
		ab.pressed.connect(func() -> void: _apply_anchor_preset(captured_name))
		anchor_row.add_child(ab)
		_anchor_btns[captured_name] = ab

	# Numeric Row 1: X, Y, Scale %
	var num_row1 := HBoxContainer.new()
	num_row1.add_theme_constant_override("separation", 8)
	vbox.add_child(num_row1)

	_spin_x = _make_num_box(num_row1, "X", -1000.0, 4000.0, 1.0, "px")
	_spin_y = _make_num_box(num_row1, "Y", -1000.0, 3000.0, 1.0, "px")
	_spin_scale = _make_num_box(num_row1, "Size", 30.0, 300.0, 5.0, "%")

	_spin_x.value_changed.connect(func(v: float) -> void:
		if _updating_spins:
			return
		var c := _current_control()
		if c != null:
			_detach_from_box_container(c)
			c.global_position.x = v
			save_layout())
	_spin_y.value_changed.connect(func(v: float) -> void:
		if _updating_spins:
			return
		var c := _current_control()
		if c != null:
			_detach_from_box_container(c)
			c.global_position.y = v
			save_layout())
	_spin_scale.value_changed.connect(func(v: float) -> void:
		if _updating_spins:
			return
		var c := _current_control()
		if c != null:
			_detach_from_box_container(c)
			var sc := clampf(v / 100.0, 0.30, 3.0)
			c.scale = Vector2(sc, sc)
			save_layout())

	# Numeric Row 2: Rotation ° and Opacity %
	var num_row2 := HBoxContainer.new()
	num_row2.add_theme_constant_override("separation", 10)
	vbox.add_child(num_row2)

	_spin_rot = _make_num_box(num_row2, "Rotate", -180.0, 180.0, 1.0, "°")
	_spin_alpha = _make_num_box(num_row2, "Opacity", 5.0, 100.0, 5.0, "%")

	_spin_rot.value_changed.connect(func(v: float) -> void:
		if _updating_spins:
			return
		var c := _current_control()
		if c != null:
			_detach_from_box_container(c)
			c.rotation_degrees = v
			save_layout())
	_spin_alpha.value_changed.connect(func(v: float) -> void:
		if _updating_spins:
			return
		var a := clampf(v / 100.0, 0.05, 1.0)
		if selected_key != "":
			_alphas[selected_key] = a
		var c := _current_control()
		if c != null:
			c.modulate.a = a
			save_layout())

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_file_dialog.file_selected.connect(_on_image_file_selected)
	add_child(_file_dialog)


func _make_num_box(parent: HBoxContainer, label_text: String, min_v: float, max_v: float, step_v: float, suffix_text: String) -> SpinBox:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", 4)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94))
	holder.add_child(lbl)

	var sp := SpinBox.new()
	sp.min_value = min_v
	sp.max_value = max_v
	sp.step = step_v
	sp.suffix = suffix_text
	sp.custom_minimum_size = Vector2(78, 26)
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(sp)
	return sp


func _apply_anchor_preset(anchor_name: String) -> void:
	var c := _current_control()
	if c == null:
		return
	_detach_from_box_container(c)
	var vp_size := get_viewport_rect().size
	var box_size := c.size * c.scale
	var margin := 16.0
	match anchor_name:
		"Top-L":
			c.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
			c.global_position = Vector2(margin, margin)
		"Top-R":
			c.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
			c.global_position = Vector2(vp_size.x - box_size.x - margin, margin)
		"Bot-L":
			c.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
			c.global_position = Vector2(margin, vp_size.y - box_size.y - margin)
		"Bot-R":
			c.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
			c.global_position = Vector2(vp_size.x - box_size.x - margin, vp_size.y - box_size.y - margin)
		"Center":
			c.set_anchors_preset(Control.PRESET_CENTER, true)
			c.global_position = (vp_size - box_size) * 0.5
	_anchors[selected_key] = anchor_name
	_sync_inspector()
	save_layout()


func _make_btn(label_text: String, min_sz: Vector2, bg := Color(0.16, 0.19, 0.24)) -> Button:
	var b := Button.new()
	b.text = label_text
	b.custom_minimum_size = min_sz
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(1, 1, 1, 0.24)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	var sb_hi := sb.duplicate() as StyleBoxFlat
	sb_hi.bg_color = bg.lightened(0.14)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hi)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 11)
	return b


func _sync_spin_values(cur: Control) -> void:
	if cur == null:
		return
	_updating_spins = true
	if _spin_x != null:
		_spin_x.value = roundf(cur.global_position.x)
	if _spin_y != null:
		_spin_y.value = roundf(cur.global_position.y)
	if _spin_scale != null:
		_spin_scale.value = roundf(cur.scale.x * 100.0)
	if _spin_rot != null:
		_spin_rot.value = roundf(cur.rotation_degrees)
	var a := float(_alphas.get(selected_key, cur.modulate.a))
	if _spin_alpha != null:
		_spin_alpha.value = roundf(a * 100.0)
	_updating_spins = false


func _sync_inspector() -> void:
	var cur := _current_control()
	if cur == null:
		if _popover != null:
			_popover.visible = false
		_set_gizmo_visible(false)
		return
	if _pop_title != null:
		_pop_title.text = selected_key
	var is_hidden := bool(_hidden_flags.get(selected_key, false))
	if _vis_btn != null:
		_vis_btn.text = "Hidden" if is_hidden else "Visible"
	_sync_spin_values(cur)
	_update_highlight_and_popover()


func _toggle_selected_visibility() -> void:
	var cur := _current_control()
	if cur == null:
		return
	var now_hidden := not bool(_hidden_flags.get(selected_key, false))
	_hidden_flags[selected_key] = now_hidden
	cur.visible = not now_hidden
	_sync_inspector()
	save_layout()


func _on_add_image_pressed() -> void:
	if _file_dialog != null:
		_file_dialog.popup_centered(Vector2i(640, 420))


func _on_image_file_selected(path: String) -> void:
	add_custom_image(path, Vector2(360, 220), Vector2.ONE, 0.0, 1.0)
	save_layout()


func add_custom_image(path: String, pos: Vector2, sc: Vector2, rot: float, alpha: float) -> void:
	if hud_root == null:
		return
	var tex: Texture2D = null
	if path.begins_with("res://"):
		tex = RetroUI.load_png_safe(path)
	else:
		var img := Image.new()
		if img.load(path) == OK and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		tex = RetroUI.load_png_safe("res://assets/icons/logo.png")

	_custom_counter += 1
	var key := "CustomImage_%d" % _custom_counter
	var rect := TextureRect.new()
	rect.name = key
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size = Vector2(96, 96)
	rect.position = pos
	rect.scale = sc
	rect.rotation_degrees = rot
	rect.modulate.a = alpha
	rect.mouse_filter = Control.MOUSE_FILTER_PASS
	hud_root.add_child(rect)
	hud_root.move_child(rect, max(0, hud_root.get_child_count() - 2))

	_custom_images[key] = path
	register_target(key, rect)
	selected_key = key
	_sync_inspector()


func _delete_selected_custom_image() -> void:
	if not _custom_images.has(selected_key):
		return
	var cur := _current_control()
	if cur != null:
		cur.queue_free()
	targets.erase(selected_key)
	_custom_images.erase(selected_key)
	_defaults.erase(selected_key)
	_alphas.erase(selected_key)
	_hidden_flags.erase(selected_key)
	selected_key = ""
	_sync_inspector()
	save_layout()


func _reset_selected() -> void:
	if not _defaults.has(selected_key):
		return
	var cur := _current_control()
	if cur == null:
		return
	var d: Dictionary = _defaults[selected_key]
	cur.top_level = false
	cur.anchor_left = float(d["anchor_l"])
	cur.anchor_top = float(d["anchor_t"])
	cur.anchor_right = float(d["anchor_r"])
	cur.anchor_bottom = float(d["anchor_b"])
	cur.position = d["pos"]
	cur.scale = d["scale"]
	cur.rotation_degrees = d["rot"]
	cur.modulate.a = d["alpha"]
	cur.visible = d["visible"]
	_alphas[selected_key] = d["alpha"]
	_hidden_flags[selected_key] = false
	_anchors[selected_key] = "Custom"
	_sync_inspector()
	save_layout()


func reset_all() -> void:
	for k in _custom_images.keys():
		if targets.has(k) and is_instance_valid(targets[k]):
			targets[k].queue_free()
		targets.erase(k)
	_custom_images.clear()

	for k in _defaults.keys():
		if not targets.has(k) or not is_instance_valid(targets[k]):
			continue
		var c: Control = targets[k]
		var d: Dictionary = _defaults[k]
		c.top_level = false
		c.anchor_left = float(d["anchor_l"])
		c.anchor_top = float(d["anchor_t"])
		c.anchor_right = float(d["anchor_r"])
		c.anchor_bottom = float(d["anchor_b"])
		c.position = d["pos"]
		c.scale = d["scale"]
		c.rotation_degrees = d["rot"]
		if k != "Joystick":
			c.modulate.a = d["alpha"]
		c.visible = d["visible"]
		_alphas[k] = d["alpha"]
		_hidden_flags[k] = false
		_anchors[k] = "Custom"

	selected_key = ""
	_sync_inspector()
	save_layout()


func save_layout() -> void:
	var cf := ConfigFile.new()
	for k in targets.keys():
		var c: Control = targets[k]
		if c == null or not is_instance_valid(c):
			continue
		cf.set_value(k, "pos", c.position)
		cf.set_value(k, "global_pos", c.global_position)
		cf.set_value(k, "top_level", c.top_level)
		cf.set_value(k, "scale", c.scale)
		cf.set_value(k, "rot", c.rotation_degrees)
		cf.set_value(k, "alpha", float(_alphas.get(k, c.modulate.a)))
		cf.set_value(k, "hidden", bool(_hidden_flags.get(k, false)))
		cf.set_value(k, "anchor", String(_anchors.get(k, "Custom")))
		if _custom_images.has(k):
			cf.set_value(k, "image_path", String(_custom_images[k]))
	cf.save(SAVE_PATH)


func load_layout() -> void:
	if not layout_enabled:
		return
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for sec in cf.get_sections():
		if cf.has_section_key(sec, "image_path"):
			var p := String(cf.get_value(sec, "image_path", ""))
			var pos: Vector2 = cf.get_value(sec, "pos", Vector2(360, 220))
			var sc: Vector2 = cf.get_value(sec, "scale", Vector2.ONE)
			var rot := float(cf.get_value(sec, "rot", 0.0))
			var al := float(cf.get_value(sec, "alpha", 1.0))
			add_custom_image(p, pos, sc, rot, al)
		elif targets.has(sec) and is_instance_valid(targets[sec]):
			var c: Control = targets[sec]
			var is_tl := bool(cf.get_value(sec, "top_level", false))
			c.top_level = is_tl
			if is_tl and cf.has_section_key(sec, "global_pos"):
				c.global_position = cf.get_value(sec, "global_pos", c.global_position)
			else:
				c.position = cf.get_value(sec, "pos", c.position)
			c.scale = cf.get_value(sec, "scale", c.scale)
			c.rotation_degrees = float(cf.get_value(sec, "rot", c.rotation_degrees))
			var al := float(cf.get_value(sec, "alpha", 1.0))
			var hid := bool(cf.get_value(sec, "hidden", false))
			_alphas[sec] = al
			_hidden_flags[sec] = hid
			_anchors[sec] = String(cf.get_value(sec, "anchor", "Custom"))
			if sec != "Joystick":
				c.modulate.a = al
			if sec in ["Joystick", "JumpButton"] and not _is_mobile_active():
				c.visible = false
			else:
				c.visible = not hid
