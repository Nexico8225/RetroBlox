@tool
extends AcceptDialog

# RetroBlox Block Code Studio (Scratch / Blockly Style Visual Block Coding)
# Snap-together color-coded blocks that compile into BlockCodeRuntime on any 3D part/node.

const RUNTIME_SCRIPT_PATH := "res://addons/retroblox_studio/block_code_runtime.gd"

var plugin: EditorPlugin

var _blocks: Array[Dictionary] = []
var _stack_vbox: VBoxContainer
var _code_preview: CodeEdit
var _preview_split: HSplitContainer
var _show_code_check: CheckButton
var _status_lbl: Label
var _target_lbl: Label

const CATEGORY_COLORS := {
	"event": Color(0.85, 0.62, 0.10, 1.0),
	"motion": Color(0.20, 0.48, 0.88, 1.0),
	"looks": Color(0.55, 0.28, 0.82, 1.0),
	"gameplay": Color(0.18, 0.64, 0.34, 1.0),
	"control": Color(0.86, 0.44, 0.14, 1.0),
}

const BLOCK_DEFS := [
	# Events
	{"op": "when_touched", "cat": "event", "label": "When Player Touches Part"},
	{"op": "when_start", "cat": "event", "label": "When Game Starts"},
	{"op": "when_clicked", "cat": "event", "label": "When Player Clicks Part"},
	{"op": "every_seconds", "cat": "event", "label": "Every X Seconds", "seconds": 1.0},
	# Motion / Player
	{"op": "teleport_player", "cat": "motion", "label": "Teleport Player", "x": 0.0, "y": 10.0, "z": 0.0},
	{"op": "push_player", "cat": "motion", "label": "Push / Fling Player", "x": 0.0, "y": 55.0, "z": 0.0},
	{"op": "set_walk_speed", "cat": "motion", "label": "Set Walk Speed", "speed": 28.0},
	{"op": "set_jump_power", "cat": "motion", "label": "Set Jump Power", "power": 75.0},
	# Looks / World
	{"op": "set_part_color", "cat": "looks", "label": "Set Part Color", "color": "#ff3b30"},
	{"op": "set_part_visible", "cat": "looks", "label": "Set Part Visible", "visible": true},
	{"op": "rotate_part", "cat": "looks", "label": "Rotate Part (deg)", "x": 0.0, "y": 15.0, "z": 0.0},
	# Gameplay
	{"op": "damage_player", "cat": "gameplay", "label": "Damage Player", "amount": 100.0},
	{"op": "heal_player", "cat": "gameplay", "label": "Heal Player", "amount": 25.0},
	{"op": "give_gear", "cat": "gameplay", "label": "Give Gear", "gear": "ClassicSword"},
	{"op": "add_tix", "cat": "gameplay", "label": "Add Tix / Score", "amount": 10},
	{"op": "camera_shake", "cat": "gameplay", "label": "Camera Shake", "intensity": 0.5},
	{"op": "play_sound", "cat": "gameplay", "label": "Play Sound", "sound": "goal"},
	# Control
	{"op": "wait", "cat": "control", "label": "Wait (Seconds)", "seconds": 1.0},
	{"op": "repeat", "cat": "control", "label": "Repeat N Times", "count": 5},
	{"op": "end_repeat", "cat": "control", "label": "End Repeat"},
	{"op": "print_msg", "cat": "control", "label": "Print Message", "message": "Hello RetroBlox!"},
]


func _init() -> void:
	title = "RetroBlox Block Code — Visual Block Programming"
	size = Vector2i(960, 620)
	min_size = Vector2i(700, 460)
	ok_button_text = "Apply Block Code to Selected Node"


func _ready() -> void:
	_build_ui()
	confirmed.connect(_on_apply_pressed)
	about_to_popup.connect(_load_from_selected_node)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# Top bar
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)

	_target_lbl = Label.new()
	_target_lbl.text = "Target: (Select a 3D Part/Node)"
	_target_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_lbl.add_theme_font_size_override("font_size", 12)
	_target_lbl.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	top.add_child(_target_lbl)

	var tpl_btn := MenuButton.new()
	tpl_btn.text = "Templates"
	var tpop := tpl_btn.get_popup()
	tpop.add_item("Obby Kill Brick (Lava)", 0)
	tpop.add_item("Jump / Launch Pad", 1)
	tpop.add_item("Speed Boost Pad (Temporary)", 2)
	tpop.add_item("Teleporter Pad", 3)
	tpop.add_item("Spinning Coin (+10 Tix)", 4)
	tpop.add_item("Blinking Disappearing Platform", 5)
	tpop.id_pressed.connect(_on_template_selected)
	top.add_child(tpl_btn)

	_show_code_check = CheckButton.new()
	_show_code_check.text = "GDScript Preview"
	_show_code_check.button_pressed = true
	_show_code_check.toggled.connect(func(on: bool):
		if _code_preview != null:
			_code_preview.visible = on
	)
	top.add_child(_show_code_check)

	var clear_btn := Button.new()
	clear_btn.text = "Clear Blocks"
	clear_btn.pressed.connect(func():
		_blocks.clear()
		_rebuild_stack_ui()
	)
	top.add_child(clear_btn)

	# Main split: Palette (Left) | Workspace + Preview (Right)
	var main_split := HSplitContainer.new()
	main_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.split_offset = 240
	root.add_child(main_split)

	# Left Palette
	var pal_scroll := ScrollContainer.new()
	pal_scroll.custom_minimum_size = Vector2(230, 0)
	pal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_child(pal_scroll)

	var pal_vb := VBoxContainer.new()
	pal_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pal_vb.add_theme_constant_override("separation", 4)
	pal_scroll.add_child(pal_vb)

	var cat_titles := {
		"event": "EVENTS (Triggers)",
		"motion": "PLAYER & MOTION",
		"looks": "WORLD & LOOKS",
		"gameplay": "GAMEPLAY & GEAR",
		"control": "CONTROL & LOOPS",
	}
	for cat in ["event", "motion", "looks", "gameplay", "control"]:
		var hdr := Label.new()
		hdr.text = cat_titles[cat]
		hdr.add_theme_font_size_override("font_size", 10)
		hdr.add_theme_color_override("font_color", CATEGORY_COLORS[cat].lightened(0.35))
		pal_vb.add_child(hdr)
		for def in BLOCK_DEFS:
			if def["cat"] == cat:
				var b := Button.new()
				b.text = "+ " + String(def["label"])
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.add_theme_font_size_override("font_size", 11)
				var sb := StyleBoxFlat.new()
				sb.bg_color = CATEGORY_COLORS[cat].darkened(0.25)
				sb.border_width_left = 4
				sb.border_color = CATEGORY_COLORS[cat].lightened(0.2)
				sb.set_corner_radius_all(4)
				sb.content_margin_left = 8
				sb.content_margin_right = 6
				sb.content_margin_top = 4
				sb.content_margin_bottom = 4
				b.add_theme_stylebox_override("normal", sb)
				var def_copy: Dictionary = def.duplicate(true)
				b.pressed.connect(func():
					_blocks.append(def_copy.duplicate(true))
					_rebuild_stack_ui()
				)
				pal_vb.add_child(b)

	# Right: Stack + Live Code Preview
	_preview_split = HSplitContainer.new()
	_preview_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_split.split_offset = 420
	main_split.add_child(_preview_split)

	var stack_scroll := ScrollContainer.new()
	stack_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_split.add_child(stack_scroll)

	_stack_vbox = VBoxContainer.new()
	_stack_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack_vbox.add_theme_constant_override("separation", 5)
	stack_scroll.add_child(_stack_vbox)

	_code_preview = CodeEdit.new()
	_code_preview.editable = false
	_code_preview.custom_minimum_size = Vector2(240, 0)
	_code_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_preview.add_theme_font_size_override("font_size", 11)
	_preview_split.add_child(_code_preview)

	_status_lbl = Label.new()
	_status_lbl.text = "Add blocks from the left palette or pick a Template, then click 'Apply Block Code to Selected Node'."
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.add_theme_color_override("font_color", Color(0.68, 0.82, 0.95))
	root.add_child(_status_lbl)

	_on_template_selected(0)


func _rebuild_stack_ui() -> void:
	if _stack_vbox == null:
		return
	for ch in _stack_vbox.get_children():
		ch.queue_free()

	var indent := 0
	for idx in range(_blocks.size()):
		var blk: Dictionary = _blocks[idx]
		var op := String(blk.get("op", ""))
		var cat := String(blk.get("cat", "control"))
		if op == "end_repeat":
			indent = maxi(0, indent - 1)

		var row_wrap := HBoxContainer.new()
		row_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if indent > 0:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(indent * 22, 0)
			row_wrap.add_child(spacer)

		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var csb := StyleBoxFlat.new()
		var base_col: Color = CATEGORY_COLORS.get(cat, Color.STEEL_BLUE)
		csb.bg_color = base_col.darkened(0.35)
		csb.border_width_left = 5
		csb.border_width_top = 1
		csb.border_width_right = 1
		csb.border_width_bottom = 1
		csb.border_color = base_col.lightened(0.25)
		csb.set_corner_radius_all(5)
		csb.content_margin_left = 8
		csb.content_margin_right = 6
		csb.content_margin_top = 5
		csb.content_margin_bottom = 5
		card.add_theme_stylebox_override("panel", csb)
		row_wrap.add_child(card)

		var hb := HBoxContainer.new()
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_theme_constant_override("separation", 6)
		card.add_child(hb)

		var title_lbl := Label.new()
		title_lbl.text = String(blk.get("label", op))
		title_lbl.add_theme_font_size_override("font_size", 11)
		hb.add_child(title_lbl)

		_add_block_params_ui(hb, blk)

		var spacer_end := Control.new()
		spacer_end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(spacer_end)

		var up_btn := Button.new()
		up_btn.text = "▲"
		up_btn.custom_minimum_size = Vector2(24, 22)
		up_btn.disabled = (idx == 0)
		up_btn.pressed.connect(func():
			var tmp = _blocks[idx]
			_blocks[idx] = _blocks[idx - 1]
			_blocks[idx - 1] = tmp
			_rebuild_stack_ui()
		)
		hb.add_child(up_btn)

		var dn_btn := Button.new()
		dn_btn.text = "▼"
		dn_btn.custom_minimum_size = Vector2(24, 22)
		dn_btn.disabled = (idx == _blocks.size() - 1)
		dn_btn.pressed.connect(func():
			var tmp = _blocks[idx]
			_blocks[idx] = _blocks[idx + 1]
			_blocks[idx + 1] = tmp
			_rebuild_stack_ui()
		)
		hb.add_child(dn_btn)

		var del_btn := Button.new()
		del_btn.text = "✕"
		del_btn.custom_minimum_size = Vector2(24, 22)
		del_btn.pressed.connect(func():
			_blocks.remove_at(idx)
			_rebuild_stack_ui()
		)
		hb.add_child(del_btn)

		_stack_vbox.add_child(row_wrap)
		if op == "repeat":
			indent += 1

	_update_code_preview()


func _add_block_params_ui(hb: HBoxContainer, blk: Dictionary) -> void:
	for k in ["seconds", "amount", "speed", "power", "intensity", "count", "x", "y", "z"]:
		if blk.has(k):
			var kl := Label.new()
			kl.text = "%s:" % k
			kl.add_theme_font_size_override("font_size", 10)
			hb.add_child(kl)
			var sb := SpinBox.new()
			sb.min_value = -9999.0
			sb.max_value = 9999.0
			sb.step = 1.0 if (k == "count" or k == "amount") else 0.1
			sb.value = float(blk[k])
			sb.custom_minimum_size = Vector2(68, 22)
			var key_name: String = k
			sb.value_changed.connect(func(v: float):
				blk[key_name] = int(v) if key_name == "count" else v
				_update_code_preview()
			)
			hb.add_child(sb)

	if blk.has("message"):
		var le := LineEdit.new()
		le.text = String(blk["message"])
		le.custom_minimum_size = Vector2(140, 22)
		le.text_changed.connect(func(t: String):
			blk["message"] = t
			_update_code_preview()
		)
		hb.add_child(le)

	if blk.has("gear"):
		var ob := OptionButton.new()
		var gears := ["ClassicSword", "SpeedCoil", "GravityCoil", "BloxyCola", "PaintballGun"]
		for g in gears:
			ob.add_item(g)
		var idx := gears.find(String(blk["gear"]))
		if idx >= 0:
			ob.selected = idx
		ob.item_selected.connect(func(i: int):
			blk["gear"] = gears[i]
			_update_code_preview()
		)
		hb.add_child(ob)

	if blk.has("sound"):
		var ob := OptionButton.new()
		var sounds := ["goal", "click", "jump", "oof"]
		for s in sounds:
			ob.add_item(s)
		var idx := sounds.find(String(blk["sound"]))
		if idx >= 0:
			ob.selected = idx
		ob.item_selected.connect(func(i: int):
			blk["sound"] = sounds[i]
			_update_code_preview()
		)
		hb.add_child(ob)

	if blk.has("color"):
		var cp := ColorPickerButton.new()
		cp.custom_minimum_size = Vector2(44, 22)
		cp.color = Color.from_string(String(blk["color"]), Color.RED)
		cp.color_changed.connect(func(c: Color):
			blk["color"] = "#" + c.to_html(false)
			_update_code_preview()
		)
		hb.add_child(cp)

	if blk.has("visible"):
		var cb := CheckBox.new()
		cb.text = "Visible"
		cb.button_pressed = bool(blk["visible"])
		cb.toggled.connect(func(on: bool):
			blk["visible"] = on
			_update_code_preview()
		)
		hb.add_child(cb)


func _update_code_preview() -> void:
	if _code_preview == null:
		return
	var lines: PackedStringArray = ["extends Node", "# Auto-generated RetroBlox Block Code", ""]
	var indent := 0
	for blk in _blocks:
		var op := String(blk.get("op", ""))
		var pad := "\t".repeat(indent)
		match op:
			"when_start":
				indent = 1
				lines.append("func _ready() -> void:")
			"when_touched":
				indent = 1
				lines.append("func _on_body_entered(player: Node3D) -> void:")
			"when_clicked":
				indent = 1
				lines.append("func _on_clicked(player: Node3D) -> void:")
			"every_seconds":
				indent = 1
				lines.append("func _on_timer_%.2fs() -> void:" % float(blk.get("seconds", 1.0)))
			"wait":
				lines.append("%sawait get_tree().create_timer(%.2f).timeout" % [pad, float(blk.get("seconds", 1.0))])
			"repeat":
				lines.append("%sfor i in range(%d):" % [pad, int(blk.get("count", 3))])
				indent += 1
			"end_repeat":
				indent = maxi(1, indent - 1)
			"teleport_player":
				lines.append("%splayer.global_position = Vector3(%.1f, %.1f, %.1f)" % [pad, float(blk.get("x", 0)), float(blk.get("y", 10)), float(blk.get("z", 0))])
			"push_player":
				lines.append("%splayer.push(Vector3(%.1f, %.1f, %.1f))" % [pad, float(blk.get("x", 0)), float(blk.get("y", 55)), float(blk.get("z", 0))])
			"set_walk_speed":
				lines.append("%splayer.walk_speed = %.1f" % [pad, float(blk.get("speed", 28))])
			"set_jump_power":
				lines.append("%splayer.jump_power = %.1f" % [pad, float(blk.get("power", 75))])
			"damage_player":
				lines.append("%splayer.take_damage(%.1f)" % [pad, float(blk.get("amount", 100))])
			"heal_player":
				lines.append("%splayer.heal(%.1f)" % [pad, float(blk.get("amount", 25))])
			"give_gear":
				lines.append("%splayer.give_gear(\"%s\")" % [pad, String(blk.get("gear", "ClassicSword"))])
			"add_tix":
				lines.append("%sSession.add_tix(%d)" % [pad, int(blk.get("amount", 10))])
			"set_part_color":
				lines.append("%s_set_part_color(Color(\"%s\"))" % [pad, String(blk.get("color", "#ff3b30"))])
			"set_part_visible":
				lines.append("%sget_parent().visible = %s" % [pad, str(bool(blk.get("visible", true)))])
			"rotate_part":
				lines.append("%sget_parent().rotate_y(deg_to_rad(%.1f))" % [pad, float(blk.get("y", 15))])
			"camera_shake":
				lines.append("%sget_viewport().get_camera_3d().shake(%.2f)" % [pad, float(blk.get("intensity", 0.5))])
			"play_sound":
				lines.append("%sSfx.play_%s()" % [pad, String(blk.get("sound", "goal"))])
			"print_msg":
				lines.append("%sprint(\"%s\")" % [pad, String(blk.get("message", ""))])
	_code_preview.text = "\n".join(lines)


func _on_template_selected(id: int) -> void:
	_blocks.clear()
	match id:
		0: # Obby Kill Brick
			_blocks = [
				{"op": "when_touched", "cat": "event", "label": "When Player Touches Part"},
				{"op": "damage_player", "cat": "gameplay", "label": "Damage Player", "amount": 100.0},
				{"op": "play_sound", "cat": "gameplay", "label": "Play Sound", "sound": "oof"},
			]
		1: # Jump / Launch Pad
			_blocks = [
				{"op": "when_touched", "cat": "event", "label": "When Player Touches Part"},
				{"op": "push_player", "cat": "motion", "label": "Push / Fling Player", "x": 0.0, "y": 65.0, "z": 0.0},
				{"op": "play_sound", "cat": "gameplay", "label": "Play Sound", "sound": "jump"},
			]
		2: # Speed Boost Pad
			_blocks = [
				{"op": "when_touched", "cat": "event", "label": "When Player Touches Part"},
				{"op": "set_walk_speed", "cat": "motion", "label": "Set Walk Speed", "speed": 36.0},
				{"op": "wait", "cat": "control", "label": "Wait (Seconds)", "seconds": 3.0},
				{"op": "set_walk_speed", "cat": "motion", "label": "Set Walk Speed", "speed": 16.0},
			]
		3: # Teleporter Pad
			_blocks = [
				{"op": "when_touched", "cat": "event", "label": "When Player Touches Part"},
				{"op": "camera_shake", "cat": "gameplay", "label": "Camera Shake", "intensity": 0.4},
				{"op": "teleport_player", "cat": "motion", "label": "Teleport Player", "x": 0.0, "y": 20.0, "z": 0.0},
				{"op": "play_sound", "cat": "gameplay", "label": "Play Sound", "sound": "goal"},
			]
		4: # Spinning Coin
			_blocks = [
				{"op": "every_seconds", "cat": "event", "label": "Every X Seconds", "seconds": 0.05},
				{"op": "rotate_part", "cat": "looks", "label": "Rotate Part (deg)", "x": 0.0, "y": 6.0, "z": 0.0},
				{"op": "when_touched", "cat": "event", "label": "When Player Touches Part"},
				{"op": "add_tix", "cat": "gameplay", "label": "Add Tix / Score", "amount": 10},
				{"op": "play_sound", "cat": "gameplay", "label": "Play Sound", "sound": "goal"},
				{"op": "set_part_visible", "cat": "looks", "label": "Set Part Visible", "visible": false},
			]
		5: # Blinking Platform
			_blocks = [
				{"op": "every_seconds", "cat": "event", "label": "Every X Seconds", "seconds": 4.0},
				{"op": "set_part_color", "cat": "looks", "label": "Set Part Color", "color": "#ff9500"},
				{"op": "wait", "cat": "control", "label": "Wait (Seconds)", "seconds": 1.0},
				{"op": "set_part_visible", "cat": "looks", "label": "Set Part Visible", "visible": false},
				{"op": "wait", "cat": "control", "label": "Wait (Seconds)", "seconds": 2.0},
				{"op": "set_part_color", "cat": "looks", "label": "Set Part Color", "color": "#34c759"},
				{"op": "set_part_visible", "cat": "looks", "label": "Set Part Visible", "visible": true},
			]
	_rebuild_stack_ui()


func _load_from_selected_node() -> void:
	if plugin == null:
		return
	var sel := plugin.get_editor_interface().get_selection()
	if sel == null or sel.get_selected_nodes().is_empty():
		_target_lbl.text = "Target: (Select a 3D Part/Node in the Scene)"
		return
	var target := sel.get_selected_nodes()[0]
	_target_lbl.text = "Target: %s (%s)" % [target.name, target.get_class()]
	var existing := target.get_node_or_null("BlockCodeRuntime")
	if existing != null and existing.get("blocks_data") is Array:
		var saved: Array = existing.get("blocks_data")
		if not saved.is_empty():
			_blocks.clear()
			for item in saved:
				if item is Dictionary:
					_blocks.append((item as Dictionary).duplicate(true))
			_rebuild_stack_ui()
			_status_lbl.text = "Loaded existing Block Code from %s." % target.name


func _on_apply_pressed() -> void:
	if plugin == null:
		return
	var sel := plugin.get_editor_interface().get_selection()
	if sel == null or sel.get_selected_nodes().is_empty():
		_status_lbl.text = "Please select a 3D Part or Node in the Scene first!"
		return
	var target := sel.get_selected_nodes()[0]
	var scene_root := plugin.get_tree().edited_scene_root
	var rt := target.get_node_or_null("BlockCodeRuntime")
	if rt == null:
		var scr := load(RUNTIME_SCRIPT_PATH) as Script
		if scr == null:
			_status_lbl.text = "Error: Could not load block_code_runtime.gd"
			return
		rt = scr.new() as Node
		rt.name = "BlockCodeRuntime"
		target.add_child(rt, true)
		if scene_root != null:
			rt.owner = scene_root
	var export_arr: Array = []
	for b in _blocks:
		export_arr.append(b.duplicate(true))
	rt.set("blocks_data", export_arr)
	_status_lbl.text = "Applied %d Block Code blocks to %s!" % [_blocks.size(), target.name]
