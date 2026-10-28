@tool
extends AcceptDialog
# Hider / Unhider Node Panel for RetroBlox Studio.
# Hides nodes in the Hierarchy (Scene Tree panel) without hiding them in the 3D game.

var plugin_ref: EditorPlugin
var _search_box: LineEdit
var _list_box: VBoxContainer
var _status_lbl: Label


func _init() -> void:
	title = "Hider / Unhider Node (Hierarchy)"
	size = Vector2i(440, 310)
	max_size = Vector2i(500, 380)
	ok_button_text = "Close"


func _ready() -> void:
	close_requested.connect(hide)
	confirmed.connect(hide)
	_build_ui()


func _build_ui() -> void:
	var root_vb: VBoxContainer = VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 6)
	add_child(root_vb)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	root_vb.add_child(top_row)

	var hide_all_btn: Button = Button.new()
	hide_all_btn.text = "Hide All"
	hide_all_btn.custom_minimum_size = Vector2(76, 26)
	hide_all_btn.pressed.connect(_on_hide_all_pressed)
	top_row.add_child(hide_all_btn)

	var unhide_all_btn: Button = Button.new()
	unhide_all_btn.text = "Unhide All"
	unhide_all_btn.custom_minimum_size = Vector2(84, 26)
	unhide_all_btn.pressed.connect(_on_unhide_all_pressed)
	top_row.add_child(unhide_all_btn)

	var hide_sel_btn: Button = Button.new()
	hide_sel_btn.text = "Hide Selected"
	hide_sel_btn.custom_minimum_size = Vector2(96, 26)
	hide_sel_btn.pressed.connect(_on_hide_selected_pressed)
	top_row.add_child(hide_sel_btn)

	var refresh_btn: Button = Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.custom_minimum_size = Vector2(64, 26)
	refresh_btn.pressed.connect(refresh_node_list)
	top_row.add_child(refresh_btn)

	var close_btn: Button = Button.new()
	close_btn.text = "X Close"
	close_btn.custom_minimum_size = Vector2(68, 26)
	close_btn.pressed.connect(hide)
	top_row.add_child(close_btn)

	_search_box = LineEdit.new()
	_search_box.placeholder_text = "Filter specific node by name..."
	_search_box.text_changed.connect(func(_t: String) -> void: refresh_node_list())
	root_vb.add_child(_search_box)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.add_theme_font_size_override("font_size", 11)
	root_vb.add_child(_status_lbl)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(410, 165)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vb.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 3)
	scroll.add_child(_list_box)


func _on_hide_all_pressed() -> void:
	if plugin_ref != null:
		plugin_ref.call("set_all_workspace_nodes_hidden", true)
	refresh_node_list()


func _on_unhide_all_pressed() -> void:
	if plugin_ref != null:
		plugin_ref.call("set_all_workspace_nodes_hidden", false)
	refresh_node_list()


func _on_hide_selected_pressed() -> void:
	if plugin_ref != null:
		plugin_ref.call("hide_selected_workspace_nodes")
	refresh_node_list()


func refresh_node_list() -> void:
	if _list_box == null or plugin_ref == null:
		return
	for ch in _list_box.get_children():
		ch.queue_free()

	var nodes: Array = plugin_ref.call("get_manageable_workspace_nodes")
	var q: String = _search_box.text.strip_edges().to_lower() if _search_box != null else ""
	var hidden_count: int = 0

	for n in nodes:
		if n == null or not is_instance_valid(n):
			continue
		var node: Node = n as Node
		var is_hid: bool = bool(node.get_meta("_rbx_hidden_in_workspace", false))
		if is_hid:
			hidden_count += 1
		var n_name: String = String(node.name)
		if q != "" and not (q in n_name.to_lower()):
			continue

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_list_box.add_child(row)

		var name_lbl: Label = Label.new()
		var parent_name: String = String(node.get_parent().name) if node.get_parent() != null else ""
		name_lbl.text = "%s (%s · %s)" % [n_name, node.get_class(), parent_name]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_color_override("font_color", Color(0.65, 0.70, 0.78) if is_hid else Color.WHITE)
		row.add_child(name_lbl)

		var state_lbl: Label = Label.new()
		state_lbl.text = "HIDDEN" if is_hid else "VISIBLE"
		state_lbl.add_theme_color_override("font_color", Color("ff8787") if is_hid else Color("69db7c"))
		state_lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(state_lbl)

		var toggle_btn: Button = Button.new()
		toggle_btn.text = "Unhide" if is_hid else "Hide"
		toggle_btn.custom_minimum_size = Vector2(68, 24)
		toggle_btn.pressed.connect(_on_toggle_single_node.bind(node, not is_hid))
		row.add_child(toggle_btn)

	if _status_lbl != null:
		_status_lbl.text = "Nodes: %d  ·  Hidden in Hierarchy: %d (All stay visible in 3D game)" % [nodes.size(), hidden_count]


func _on_toggle_single_node(node: Node, hide_now: bool) -> void:
	if plugin_ref != null and node != null and is_instance_valid(node):
		plugin_ref.call("set_node_hidden_in_workspace", node, hide_now)
	refresh_node_list()
