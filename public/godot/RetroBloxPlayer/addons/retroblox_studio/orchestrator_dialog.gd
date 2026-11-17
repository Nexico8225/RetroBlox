@tool
extends AcceptDialog

# RetroBlox Orchestrator Studio (Visual Scripting & Blueprints)
# Visual node-based logic graph editor for RetroBlox SDK.

var plugin: EditorPlugin
var _graph_edit: GraphEdit
var _status_lbl: Label
var _node_counter: int = 1

func _init() -> void:
	title = "RetroBlox Orchestrator — Visual Logic & Blueprint Studio"
	size = Vector2i(880, 600)
	min_size = Vector2i(640, 440)
	ok_button_text = "Apply Logic to Selected Node"

func _ready() -> void:
	_build_ui()
	confirmed.connect(_on_apply_logic_pressed)

func _build_ui() -> void:
	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	# 1. Toolbar Bar
	var tb = HBoxContainer.new()
	tb.add_theme_constant_override("separation", 6)
	vb.add_child(tb)

	var add_event_btn = MenuButton.new()
	add_event_btn.text = "+ Event Node"
	var epop = add_event_btn.get_popup()
	epop.add_item("On Touched (Player Touches Part)", 0)
	epop.add_item("On Clicked (Player Clicks)", 1)
	epop.add_item("On Timer Tick (Repeated)", 2)
	epop.add_item("On Game Start", 3)
	epop.id_pressed.connect(_on_add_event_selected)
	tb.add_child(add_event_btn)

	var add_action_btn = MenuButton.new()
	add_action_btn.text = "+ Action Node"
	var apop = add_action_btn.get_popup()
	apop.add_item("Teleport Player (Destination X/Y/Z)", 0)
	apop.add_item("Damage Player (Lava / Trap)", 1)
	apop.add_item("Heal Player (Health Regen)", 2)
	apop.add_item("Give Gear (Sword / Coil / Cola)", 3)
	apop.add_item("Add Tix / Points (Score / Leaderboard)", 4)
	apop.add_item("Camera Shake (Shaker FX)", 5)
	apop.add_item("Change Part Color", 6)
	apop.add_item("Toggle Visibility", 7)
	apop.add_item("Print Debug Message", 8)
	apop.id_pressed.connect(_on_add_action_selected)
	tb.add_child(add_action_btn)

	var add_flow_btn = MenuButton.new()
	add_flow_btn.text = "+ Flow Control"
	var fpop = add_flow_btn.get_popup()
	fpop.add_item("Delay / Wait (Seconds)", 0)
	fpop.add_item("Branch (If / Else)", 1)
	fpop.add_item("Sequence (Step 1 -> Step 2)", 2)
	fpop.id_pressed.connect(_on_add_flow_selected)
	tb.add_child(add_flow_btn)

	tb.add_child(VSeparator.new())

	var template_menu = MenuButton.new()
	template_menu.text = "Templates"
	var tpop = template_menu.get_popup()
	tpop.add_item("Template: Lava Kill on Touch", 0)
	tpop.add_item("Template: Teleporter with Shake", 1)
	tpop.add_item("Template: Speed Coil Giver on Touch", 2)
	tpop.add_item("Template: Repeating Timer Healer", 3)
	tpop.id_pressed.connect(_on_template_selected)
	tb.add_child(template_menu)

	var clear_btn = Button.new()
	clear_btn.text = "Clear Graph"
	clear_btn.pressed.connect(_clear_graph)
	tb.add_child(clear_btn)

	# 2. GraphEdit
	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.right_disconnects = true
	_graph_edit.connection_request.connect(_on_connection_request)
	_graph_edit.disconnection_request.connect(_on_disconnection_request)
	vb.add_child(_graph_edit)

	# 3. Status Bar
	_status_lbl = Label.new()
	_status_lbl.text = "Connect Event nodes to Action nodes. Click 'Apply Logic to Selected Node' to bind logic to your selection."
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.add_theme_color_override("font_color", Color(0.68, 0.82, 0.95))
	vb.add_child(_status_lbl)

	# Spawn default starting graph
	_load_template_lava()

func _clear_graph() -> void:
	if _graph_edit == null:
		return
	_graph_edit.clear_connections()
	for ch in _graph_edit.get_children():
		if ch is GraphNode:
			ch.queue_free()
	_node_counter = 1

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	_graph_edit.connect_node(from_node, from_port, to_node, to_port)

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	_graph_edit.disconnect_node(from_node, from_port, to_node, to_port)

func _create_base_node(node_title: String, pos: Vector2) -> GraphNode:
	var gn = GraphNode.new()
	gn.title = node_title
	gn.name = "Node_" + str(_node_counter)
	_node_counter += 1
	gn.position_offset = pos
	gn.resizable = true
	gn.custom_minimum_size = Vector2(200, 110)
	_graph_edit.add_child(gn)
	return gn

func _on_add_event_selected(id: int) -> void:
	var pos = Vector2(80 + randf() * 40, 100 + randf() * 60)
	match id:
		0:
			var gn = _create_base_node("Event: On Touched", pos)
			gn.set_slot(0, false, 0, Color.WHITE, true, 0, Color.GREEN)
			var lbl = Label.new()
			lbl.text = "Triggered when any player touches this part."
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.add_theme_font_size_override("font_size", 10)
			gn.add_child(lbl)
			gn.set_meta("orchestrator_type", "event")
			gn.set_meta("event_name", "on_touched")
		1:
			var gn = _create_base_node("Event: On Clicked", pos)
			gn.set_slot(0, false, 0, Color.WHITE, true, 0, Color.GREEN)
			var lbl = Label.new()
			lbl.text = "Triggered when clicked by player cursor."
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.add_theme_font_size_override("font_size", 10)
			gn.add_child(lbl)
			gn.set_meta("orchestrator_type", "event")
			gn.set_meta("event_name", "on_clicked")
		2:
			var gn = _create_base_node("Event: On Timer Tick", pos)
			gn.set_slot(0, false, 0, Color.WHITE, true, 0, Color.GREEN)
			var spin = SpinBox.new()
			spin.prefix = "Every (s): "
			spin.min_value = 0.1
			spin.max_value = 600.0
			spin.value = 1.0
			gn.add_child(spin)
			gn.set_meta("orchestrator_type", "event")
			gn.set_meta("event_name", "on_timer")
		3:
			var gn = _create_base_node("Event: On Game Start", pos)
			gn.set_slot(0, false, 0, Color.WHITE, true, 0, Color.GREEN)
			var lbl = Label.new()
			lbl.text = "Runs once as soon as game loads."
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.add_theme_font_size_override("font_size", 10)
			gn.add_child(lbl)
			gn.set_meta("orchestrator_type", "event")
			gn.set_meta("event_name", "on_game_start")

func _on_add_action_selected(id: int) -> void:
	var pos = Vector2(360 + randf() * 40, 100 + randf() * 60)
	match id:
		0: # Teleport
			var gn = _create_base_node("Action: Teleport Player", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			var le = LineEdit.new()
			le.placeholder_text = "Target X, Y, Z (e.g. 0, 10, 0)"
			le.text = "0, 10, 0"
			gn.add_child(le)
			gn.set_meta("orchestrator_type", "action")
			gn.set_meta("action_type", "teleport")
		1: # Damage
			var gn = _create_base_node("Action: Damage Player", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			var spin = SpinBox.new()
			spin.prefix = "Damage: "
			spin.min_value = 1.0
			spin.max_value = 1000.0
			spin.value = 100.0
			gn.add_child(spin)
			gn.set_meta("orchestrator_type", "action")
			gn.set_meta("action_type", "damage")
		2: # Heal
			var gn = _create_base_node("Action: Heal Player", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			var spin = SpinBox.new()
			spin.prefix = "Health: +"
			spin.min_value = 1.0
			spin.max_value = 1000.0
			spin.value = 25.0
			gn.add_child(spin)
			gn.set_meta("orchestrator_type", "action")
			gn.set_meta("action_type", "heal")
		3: # Give Gear
			var gn = _create_base_node("Action: Give Gear", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			var opt = OptionButton.new()
			opt.add_item("Linked Sword")
			opt.add_item("Speed Coil")
			opt.add_item("Gravity Coil")
			opt.add_item("Rocket Launcher")
			opt.add_item("Bloxy Cola")
			gn.add_child(opt)
			gn.set_meta("orchestrator_type", "action")
			gn.set_meta("action_type", "give_gear")
		4: # Add Points / Tix
			var gn = _create_base_node("Action: Add Points / Tix", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			var spin = SpinBox.new()
			spin.prefix = "Tix: +"
			spin.min_value = 1
			spin.max_value = 100000
			spin.value = 10
			gn.add_child(spin)
			gn.set_meta("orchestrator_type", "action")
			gn.set_meta("action_type", "add_points")
		5: # Screen Shake
			var gn = _create_base_node("Action: Camera Shake (Shaker)", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			var spin = SpinBox.new()
			spin.prefix = "Trauma: "
			spin.min_value = 0.1
			spin.max_value = 1.0
			spin.step = 0.05
			spin.value = 0.6
			gn.add_child(spin)
			gn.set_meta("orchestrator_type", "action")
			gn.set_meta("action_type", "screen_shake")
		6: # Change Color
			var gn = _create_base_node("Action: Change Part Color", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			var cp = ColorPickerButton.new()
			cp.color = Color(1.0, 0.2, 0.2)
			gn.add_child(cp)
			gn.set_meta("orchestrator_type", "action")
			gn.set_meta("action_type", "change_color")
		7: # Toggle Visibility
			var gn = _create_base_node("Action: Toggle Visibility", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			var lbl = Label.new()
			lbl.text = "Inverts part visible/hidden state."
			lbl.add_theme_font_size_override("font_size", 10)
			gn.add_child(lbl)
			gn.set_meta("orchestrator_type", "action")
			gn.set_meta("action_type", "toggle_visibility")
		8: # Print
			var gn = _create_base_node("Action: Print Message", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			var le = LineEdit.new()
			le.placeholder_text = "Message text..."
			le.text = "Part activated!"
			gn.add_child(le)
			gn.set_meta("orchestrator_type", "action")
			gn.set_meta("action_type", "print_message")

func _on_add_flow_selected(id: int) -> void:
	var pos = Vector2(250 + randf() * 30, 120 + randf() * 40)
	match id:
		0: # Delay
			var gn = _create_base_node("Flow: Delay / Wait", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			var spin = SpinBox.new()
			spin.prefix = "Wait (s): "
			spin.min_value = 0.05
			spin.max_value = 60.0
			spin.step = 0.1
			spin.value = 1.0
			gn.add_child(spin)
			gn.set_meta("orchestrator_type", "flow")
			gn.set_meta("flow_type", "delay")
		1: # Branch
			var gn = _create_base_node("Flow: Branch (If/Else)", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			gn.set_slot(1, false, 0, Color.WHITE, true, 0, Color.ORANGE)
			var l1 = Label.new()
			l1.text = "True (Then)"
			l1.add_theme_font_size_override("font_size", 10)
			gn.add_child(l1)
			var l2 = Label.new()
			l2.text = "False (Else)"
			l2.add_theme_font_size_override("font_size", 10)
			gn.add_child(l2)
			gn.set_meta("orchestrator_type", "flow")
			gn.set_meta("flow_type", "branch")
		2: # Sequence
			var gn = _create_base_node("Flow: Sequence", pos)
			gn.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
			gn.set_slot(1, false, 0, Color.WHITE, true, 0, Color.CYAN)
			var l1 = Label.new()
			l1.text = "Step 1"
			l1.add_theme_font_size_override("font_size", 10)
			gn.add_child(l1)
			var l2 = Label.new()
			l2.text = "Step 2"
			l2.add_theme_font_size_override("font_size", 10)
			gn.add_child(l2)
			gn.set_meta("orchestrator_type", "flow")
			gn.set_meta("flow_type", "sequence")

func _on_template_selected(id: int) -> void:
	match id:
		0: _load_template_lava()
		1: _load_template_teleporter()
		2: _load_template_gear()
		3: _load_template_timer_healer()

func _load_template_lava() -> void:
	_clear_graph()
	var ev = _create_base_node("Event: On Touched", Vector2(80, 140))
	ev.set_slot(0, false, 0, Color.WHITE, true, 0, Color.GREEN)
	var lbl = Label.new()
	lbl.text = "Triggered when any player touches this part."
	lbl.add_theme_font_size_override("font_size", 10)
	ev.add_child(lbl)
	ev.set_meta("orchestrator_type", "event")
	ev.set_meta("event_name", "on_touched")

	var act = _create_base_node("Action: Damage Player", Vector2(360, 140))
	act.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
	var spin = SpinBox.new()
	spin.prefix = "Damage: "
	spin.min_value = 1.0
	spin.max_value = 1000.0
	spin.value = 100.0
	act.add_child(spin)
	act.set_meta("orchestrator_type", "action")
	act.set_meta("action_type", "damage")

	_graph_edit.connect_node(ev.name, 0, act.name, 0)
	_status_lbl.text = "Loaded template: Lava Kill on Touch."

func _load_template_teleporter() -> void:
	_clear_graph()
	var ev = _create_base_node("Event: On Touched", Vector2(80, 140))
	ev.set_slot(0, false, 0, Color.WHITE, true, 0, Color.GREEN)
	var lbl = Label.new()
	lbl.text = "Player touches teleporter pad."
	lbl.add_theme_font_size_override("font_size", 10)
	ev.add_child(lbl)
	ev.set_meta("orchestrator_type", "event")
	ev.set_meta("event_name", "on_touched")

	var tp = _create_base_node("Action: Teleport Player", Vector2(340, 100))
	tp.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
	var le = LineEdit.new()
	le.text = "0, 12, 0"
	tp.add_child(le)
	tp.set_meta("orchestrator_type", "action")
	tp.set_meta("action_type", "teleport")

	var shk = _create_base_node("Action: Camera Shake (Shaker)", Vector2(340, 240))
	shk.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
	var spin = SpinBox.new()
	spin.value = 0.5
	shk.add_child(spin)
	shk.set_meta("orchestrator_type", "action")
	shk.set_meta("action_type", "screen_shake")

	_graph_edit.connect_node(ev.name, 0, tp.name, 0)
	_graph_edit.connect_node(ev.name, 0, shk.name, 0)
	_status_lbl.text = "Loaded template: Teleporter with Camera Shake."

func _load_template_gear() -> void:
	_clear_graph()
	var ev = _create_base_node("Event: On Touched", Vector2(80, 140))
	ev.set_slot(0, false, 0, Color.WHITE, true, 0, Color.GREEN)
	var lbl = Label.new()
	lbl.text = "Player steps on item giver."
	lbl.add_theme_font_size_override("font_size", 10)
	ev.add_child(lbl)
	ev.set_meta("orchestrator_type", "event")
	ev.set_meta("event_name", "on_touched")

	var act = _create_base_node("Action: Give Gear", Vector2(360, 140))
	act.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
	var opt = OptionButton.new()
	opt.add_item("Speed Coil")
	act.add_child(opt)
	act.set_meta("orchestrator_type", "action")
	act.set_meta("action_type", "give_gear")

	_graph_edit.connect_node(ev.name, 0, act.name, 0)
	_status_lbl.text = "Loaded template: Speed Coil Giver on Touch."

func _load_template_timer_healer() -> void:
	_clear_graph()
	var ev = _create_base_node("Event: On Timer Tick", Vector2(80, 140))
	ev.set_slot(0, false, 0, Color.WHITE, true, 0, Color.GREEN)
	var spin1 = SpinBox.new()
	spin1.prefix = "Interval (s): "
	spin1.value = 2.0
	ev.add_child(spin1)
	ev.set_meta("orchestrator_type", "event")
	ev.set_meta("event_name", "on_timer")

	var act = _create_base_node("Action: Heal Player", Vector2(360, 140))
	act.set_slot(0, true, 0, Color.GREEN, true, 0, Color.GREEN)
	var spin2 = SpinBox.new()
	spin2.prefix = "Health: +"
	spin2.value = 10.0
	act.add_child(spin2)
	act.set_meta("orchestrator_type", "action")
	act.set_meta("action_type", "heal")

	_graph_edit.connect_node(ev.name, 0, act.name, 0)
	_status_lbl.text = "Loaded template: Repeating Timer Healer."

func export_graph_to_dict() -> Dictionary:
	var res: Dictionary = {
		"nodes": [],
		"actions": []
	}
	var connections: Array[Dictionary] = _graph_edit.get_connection_list()
	for ch in _graph_edit.get_children():
		if ch is GraphNode:
			var gn := ch as GraphNode
			var o_type = String(gn.get_meta("orchestrator_type", ""))
			if o_type == "event":
				var ev_name = String(gn.get_meta("event_name", "on_touched"))
				res["nodes"].append({"type": ev_name, "id": gn.name})
				# Collect connected actions
				for con in connections:
					if con["from_node"] == gn.name:
						var target_gn = _graph_edit.get_node_or_null(NodePath(con["to_node"])) as GraphNode
						if target_gn != null and String(target_gn.get_meta("orchestrator_type", "")) == "action":
							var act_dict = _extract_action_dict(target_gn)
							act_dict["event"] = ev_name
							res["actions"].append(act_dict)
	return res

func _extract_action_dict(gn: GraphNode) -> Dictionary:
	var act_type = String(gn.get_meta("action_type", ""))
	var d: Dictionary = {"type": act_type}
	match act_type:
		"damage":
			for ch in gn.get_children():
				if ch is SpinBox:
					d["amount"] = (ch as SpinBox).value
		"heal":
			for ch in gn.get_children():
				if ch is SpinBox:
					d["amount"] = (ch as SpinBox).value
		"teleport":
			for ch in gn.get_children():
				if ch is LineEdit:
					var parts = (ch as LineEdit).text.split(",")
					if parts.size() >= 3:
						d["x"] = float(parts[0])
						d["y"] = float(parts[1])
						d["z"] = float(parts[2])
		"give_gear":
			for ch in gn.get_children():
				if ch is OptionButton:
					d["gear"] = (ch as OptionButton).get_item_text((ch as OptionButton).selected).to_lower().replace(" ", "_")
		"add_points":
			for ch in gn.get_children():
				if ch is SpinBox:
					d["points"] = int((ch as SpinBox).value)
		"screen_shake":
			for ch in gn.get_children():
				if ch is SpinBox:
					d["trauma"] = (ch as SpinBox).value
		"change_color":
			for ch in gn.get_children():
				if ch is ColorPickerButton:
					d["color"] = (ch as ColorPickerButton).color.to_html()
		"print_message":
			for ch in gn.get_children():
				if ch is LineEdit:
					d["message"] = (ch as LineEdit).text
	return d

func _on_apply_logic_pressed() -> void:
	if plugin == null:
		return
	var ed_sel = plugin.get_editor_interface().get_selection()
	if ed_sel == null:
		return
	var nodes = ed_sel.get_selected_nodes()
	if nodes.is_empty():
		_status_lbl.text = "Select a node in the scene tree to attach this Orchestrator logic."
		return

	var graph_data = export_graph_to_dict()
	var target = nodes[0]
	var runtime_path = "res://addons/retroblox_studio/orchestrator_runtime.gd"
	var r_scr = load(runtime_path) as Script

	var existing = target.get_node_or_null("OrchestratorLogic")
	if existing != null:
		existing.set("graph_data", graph_data)
	else:
		var logic_node = Node.new()
		logic_node.name = "OrchestratorLogic"
		logic_node.set_script(r_scr)
		logic_node.set("graph_data", graph_data)
		target.add_child(logic_node, true)
		logic_node.owner = plugin.get_tree().edited_scene_root

	_status_lbl.text = "Applied Orchestrator Logic to " + target.name + " (" + str(graph_data["actions"].size()) + " actions)."
