@tool
extends EditorPlugin

# RetroBlox Studio Editor Plugin
# Safe, lightweight builder tools:
# - Compact toolbar (+Part, +Gear, Studs, Unlink, Snap:ON, Mv, Sc, Hide, Hider, Settings)
# - Auto-unlinks selected parts via EditorSelection.selection_changed (never hooks node_added during reimport!)
# - Any-number Move & Scale Snap with scale-baking on release
# - Hierarchy-only Node Hider/Unhider (triggered on demand, never in _process)

const PlayerSettingsDialogScript = preload("res://addons/retroblox_studio/player_settings_dialog.gd")
const HiderUnhiderDialogScript = preload("res://addons/retroblox_studio/hider_unhider_dialog.gd")
const ITEM_SPAWNER_PATH = "res://scripts/world/item_spawner.gd"
const STUD_SHADER_PATH = "res://assets/studs/part_studs.gdshader"
const STUD_TEX_PATH = "res://assets/studs/stud_tile.png"
const STUD_NORMAL_PATH = "res://assets/Materials/Studs 4x4 Normal Plastic.png"

var _toolbar: HBoxContainer
var _settings_dialog: AcceptDialog
var _hider_dialog: AcceptDialog

var _snap_enabled: bool = true
var _move_snap_studs: float = 1.0
var _scale_snap_studs: float = 0.5

var _snap_toggle_btn: Button
var _move_snap_spin: SpinBox
var _scale_snap_spin: SpinBox
var _scene_tree_control: Tree = null
var _last_positions: Dictionary = {}


func _enter_tree() -> void:
	_register_custom_project_settings()
	_create_toolbar()

	_settings_dialog = PlayerSettingsDialogScript.new()
	get_editor_interface().get_base_control().add_child(_settings_dialog)

	_hider_dialog = HiderUnhiderDialogScript.new()
	_hider_dialog.set("plugin_ref", self)
	get_editor_interface().get_base_control().add_child(_hider_dialog)

	add_tool_menu_item("RetroBlox Player Settings...", _on_open_player_settings)
	add_tool_menu_item("RetroBlox Hider/Unhider Node...", _on_open_hider_dialog)

	var sel: EditorSelection = get_editor_interface().get_selection()
	if sel != null and not sel.selection_changed.is_connected(_on_selection_changed):
		sel.selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	var sel: EditorSelection = get_editor_interface().get_selection()
	if sel != null and sel.selection_changed.is_connected(_on_selection_changed):
		sel.selection_changed.disconnect(_on_selection_changed)
	remove_tool_menu_item("RetroBlox Player Settings...")
	remove_tool_menu_item("RetroBlox Hider/Unhider Node...")
	set_all_workspace_nodes_hidden(false)
	if _toolbar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()
		_toolbar = null
	if _settings_dialog != null:
		_settings_dialog.queue_free()
		_settings_dialog = null
	if _hider_dialog != null:
		_hider_dialog.queue_free()
		_hider_dialog = null


func _process(_delta: float) -> void:
	if not _snap_enabled:
		return
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs != null and fs.is_scanning():
		return
	var sel: EditorSelection = get_editor_interface().get_selection()
	if sel == null:
		return
	var selected_nodes: Array[Node] = sel.get_selected_nodes()
	if selected_nodes.is_empty():
		return
	var mouse_down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var scene_root: Node = get_tree().edited_scene_root
	for node in selected_nodes:
		if node is Node3D and node != scene_root and is_instance_valid(node):
			_apply_move_and_scale_snap(node as Node3D, mouse_down)


func _on_selection_changed() -> void:
	var fs: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	if fs != null and fs.is_scanning():
		return
	var sel: EditorSelection = get_editor_interface().get_selection()
	if sel == null:
		return
	var scene_root: Node = get_tree().edited_scene_root
	for node in sel.get_selected_nodes():
		if node != null and is_instance_valid(node) and node != scene_root:
			_unlink_single_part(node)


func _apply_move_and_scale_snap(n3: Node3D, mouse_down: bool) -> void:
	if _move_snap_studs > 0.0:
		var id_key: int = n3.get_instance_id()
		var cur_p: Vector3 = n3.position
		var prev_p: Vector3 = _last_positions.get(id_key, cur_p)
		if not cur_p.is_equal_approx(prev_p):
			var px: float = snappedf(cur_p.x, _move_snap_studs) if absf(cur_p.x - prev_p.x) > 0.0001 else cur_p.x
			var py: float = snappedf(cur_p.y, _move_snap_studs) if absf(cur_p.y - prev_p.y) > 0.0001 else cur_p.y
			var pz: float = snappedf(cur_p.z, _move_snap_studs) if absf(cur_p.z - prev_p.z) > 0.0001 else cur_p.z
			n3.position = Vector3(px, py, pz)
			_last_positions[id_key] = n3.position

	if _scale_snap_studs > 0.0 and not n3.scale.is_equal_approx(Vector3.ONE):
		var mi: MeshInstance3D = n3.get_node_or_null("MeshInstance3D") as MeshInstance3D
		var cs: CollisionShape3D = n3.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if mi != null and mi.mesh is BoxMesh:
			var bm: BoxMesh = mi.mesh as BoxMesh
			var base_sz: Vector3 = bm.size
			var target_x: float = maxf(snappedf(base_sz.x * absf(n3.scale.x), _scale_snap_studs), _scale_snap_studs)
			var target_y: float = maxf(snappedf(base_sz.y * absf(n3.scale.y), _scale_snap_studs), _scale_snap_studs)
			var target_z: float = maxf(snappedf(base_sz.z * absf(n3.scale.z), _scale_snap_studs), _scale_snap_studs)
			if not mouse_down:
				bm.size = Vector3(target_x, target_y, target_z)
				if cs != null and cs.shape is BoxShape3D:
					(cs.shape as BoxShape3D).size = Vector3(target_x, target_y, target_z)
				n3.scale = Vector3.ONE
			else:
				n3.scale = Vector3(
					target_x / maxf(base_sz.x, 0.001),
					target_y / maxf(base_sz.y, 0.001),
					target_z / maxf(base_sz.z, 0.001)
				)
		elif mi != null and mi.mesh is PrismMesh:
			var pm: PrismMesh = mi.mesh as PrismMesh
			var base_sz2: Vector3 = pm.size
			var tx: float = maxf(snappedf(base_sz2.x * absf(n3.scale.x), _scale_snap_studs), _scale_snap_studs)
			var ty: float = maxf(snappedf(base_sz2.y * absf(n3.scale.y), _scale_snap_studs), _scale_snap_studs)
			var tz: float = maxf(snappedf(base_sz2.z * absf(n3.scale.z), _scale_snap_studs), _scale_snap_studs)
			if not mouse_down:
				pm.size = Vector3(tx, ty, tz)
				if cs != null and cs.shape is BoxShape3D:
					(cs.shape as BoxShape3D).size = Vector3(tx, ty, tz)
				n3.scale = Vector3.ONE
			else:
				n3.scale = Vector3(tx / maxf(base_sz2.x, 0.001), ty / maxf(base_sz2.y, 0.001), tz / maxf(base_sz2.z, 0.001))
		else:
			var sx: float = maxf(snappedf(absf(n3.scale.x), _scale_snap_studs), _scale_snap_studs)
			var sy: float = maxf(snappedf(absf(n3.scale.y), _scale_snap_studs), _scale_snap_studs)
			var sz: float = maxf(snappedf(absf(n3.scale.z), _scale_snap_studs), _scale_snap_studs)
			if not n3.scale.is_equal_approx(Vector3(sx, sy, sz)):
				n3.scale = Vector3(sx, sy, sz)


func _register_custom_project_settings() -> void:
	_set_setting_default("player/movement/walk_speed", 16.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "1,200,1")
	_set_setting_default("player/movement/jump_power", 50.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,300,1")
	_set_setting_default("player/movement/gravity", 196.2, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,1000,1")
	_set_setting_default("player/movement/bunny_hop", true, TYPE_BOOL)
	_set_setting_default("player/health/max_health", 100.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "1,10000,1")
	_set_setting_default("player/health/health_regen_rate", 1.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,50,0.5")
	_set_setting_default("player/health/fall_damage_enabled", true, TYPE_BOOL)
	_set_setting_default("player/features/voice_chat", true, TYPE_BOOL)
	_set_setting_default("player/features/shift_lock", true, TYPE_BOOL)
	_set_setting_default("player/features/lose_item_when_dead", true, TYPE_BOOL)
	_set_setting_default("player/appearance/default_shirt", "", TYPE_STRING)
	_set_setting_default("player/appearance/default_pants", "", TYPE_STRING)
	_set_setting_default("world/baseplate/size", 512.0, TYPE_FLOAT, PROPERTY_HINT_RANGE, "64,4096,64")


func _set_setting_default(name: String, default_value: Variant, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, default_value)
	ProjectSettings.set_initial_value(name, default_value)
	if ProjectSettings.has_method("set_as_basic"):
		ProjectSettings.set_as_basic(name, true)
	var info: Dictionary = {
		"name": name,
		"type": type,
		"hint": hint,
		"hint_string": hint_string
	}
	ProjectSettings.add_property_info(info)


func _create_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "RetroBloxToolbar"
	_toolbar.add_theme_constant_override("separation", 2)

	_toolbar.add_child(VSeparator.new())

	# 1. + Part Dropdown
	var part_menu: MenuButton = MenuButton.new()
	part_menu.text = "+Part"
	part_menu.tooltip_text = "Insert a Part inside the selected node at the 3D camera look point"
	var popup: PopupMenu = part_menu.get_popup()
	popup.add_item("Block (4 x 1.2 x 2)", 0)
	popup.add_item("Brick (4 x 2 x 2)", 1)
	popup.add_item("Plate (4 x 0.4 x 4)", 2)
	popup.add_item("Cylinder (4 x 2 x 4)", 3)
	popup.add_item("Sphere (4 x 4 x 4)", 4)
	popup.add_item("Wedge (4 x 2 x 4)", 5)
	popup.add_item("Truss / Ladder (3 x 20 x 0.8)", 6)
	popup.id_pressed.connect(_on_part_selected)
	_toolbar.add_child(part_menu)

	# 2. + Gear Spawner Dropdown
	var item_menu: MenuButton = MenuButton.new()
	item_menu.text = "+Gear"
	item_menu.tooltip_text = "Insert an editable Item Spawner pad at the 3D camera look point"
	var ipop: PopupMenu = item_menu.get_popup()
	ipop.add_item("🎲 Random Gear Spawner (Cycles res://gears/)", 0)
	ipop.add_separator()
	ipop.add_item("Speed Coil Spawner", 1)
	ipop.add_item("Gravity Coil Spawner", 2)
	ipop.add_item("Fusion Coil (Speed + Gravity) Spawner", 3)
	ipop.add_item("Heal Coil Spawner", 4)
	ipop.add_item("Linked Sword (With Lunge) Spawner", 5)
	ipop.add_item("Flame Sword (Burns Enemies) Spawner", 6)
	ipop.add_item("Slow Sword (Slows Enemies) Spawner", 7)
	ipop.add_item("Super Sword (Huge Fast Lunge) Spawner", 8)
	ipop.add_item("Swelling Ball (Hold to Grow) Spawner", 9)
	ipop.add_item("Healing Potion Spawner", 10)
	ipop.add_item("Big Head Potion Spawner", 11)
	ipop.add_item("Flying Carpet Spawner", 12)
	ipop.add_item("Hyperlaser Gun (Slow Insta-Kill Orb) Spawner", 13)
	ipop.add_item("Rocket Launcher Spawner", 14)
	ipop.add_item("Subspace Tripmine Spawner", 15)
	ipop.add_separator()
	ipop.add_item("Spawn All 15 Gears in World", 99)
	ipop.id_pressed.connect(_on_item_spawner_selected)
	_toolbar.add_child(item_menu)

	# 3. Surface Studs Dropdown
	var studs_menu: MenuButton = MenuButton.new()
	studs_menu.text = "Studs"
	studs_menu.tooltip_text = "Toggle studs on Top, Bottom, Left, Right, or Full (All Sides) for selected parts"
	var sp_pop: PopupMenu = studs_menu.get_popup()
	sp_pop.add_item("Full Studs (All Sides: ON/OFF)", 0)
	sp_pop.add_item("Top Studs (Toggle)", 1)
	sp_pop.add_item("Bottom Studs (Toggle)", 2)
	sp_pop.add_item("Left Studs (Toggle)", 3)
	sp_pop.add_item("Right Studs (Toggle)", 4)
	sp_pop.add_item("Front / Back Studs (Toggle)", 5)
	sp_pop.add_item("No Studs (Smooth Plastic)", 6)
	sp_pop.add_item("Default (Top Studs Only)", 7)
	sp_pop.id_pressed.connect(_on_surface_studs_selected)
	_toolbar.add_child(studs_menu)

	# 4. Unlink Data Button
	var unlink_btn: Button = Button.new()
	unlink_btn.text = "Unlink"
	unlink_btn.tooltip_text = "Make Mesh, Material & Shape unique on selected nodes so changing color/size never affects duplicates"
	unlink_btn.pressed.connect(_on_unlink_selected_pressed)
	_toolbar.add_child(unlink_btn)

	# 5. Snap Toggle + Editable Any-Number Move Snap & Scale Snap SpinBoxes
	_snap_toggle_btn = Button.new()
	_snap_toggle_btn.text = "Snap:ON"
	_snap_toggle_btn.tooltip_text = "Toggle Builder Move & Scale Snapping"
	_snap_toggle_btn.pressed.connect(_on_toggle_snap_pressed)
	_toolbar.add_child(_snap_toggle_btn)

	var mv_lbl: Label = Label.new()
	mv_lbl.text = "Mv:"
	mv_lbl.tooltip_text = "Move Snap in Studs (type any number: 0.001 to 100000, e.g. 0.1, 1, 200)"
	_toolbar.add_child(mv_lbl)

	_move_snap_spin = SpinBox.new()
	_move_snap_spin.min_value = 0.001
	_move_snap_spin.max_value = 100000.0
	_move_snap_spin.step = 0.001
	_move_snap_spin.custom_arrow_step = 0.25
	_move_snap_spin.allow_greater = true
	_move_snap_spin.value = _move_snap_studs
	_move_snap_spin.tooltip_text = "Move Snap in Studs (type any number like 0.05, 1, 200)"
	_move_snap_spin.custom_minimum_size = Vector2(68, 0)
	_move_snap_spin.value_changed.connect(func(v: float) -> void: _move_snap_studs = maxf(0.001, v))
	_toolbar.add_child(_move_snap_spin)

	var sc_lbl: Label = Label.new()
	sc_lbl.text = "Sc:"
	sc_lbl.tooltip_text = "Scale Snap in Studs (type any number: 0.001 to 100000, e.g. 0.1, 0.5, 200)"
	_toolbar.add_child(sc_lbl)

	_scale_snap_spin = SpinBox.new()
	_scale_snap_spin.min_value = 0.001
	_scale_snap_spin.max_value = 100000.0
	_scale_snap_spin.step = 0.001
	_scale_snap_spin.custom_arrow_step = 0.25
	_scale_snap_spin.allow_greater = true
	_scale_snap_spin.value = _scale_snap_studs
	_scale_snap_spin.tooltip_text = "Scale Snap in Studs (type any number like 0.1, 0.5, 200 — bakes on release so it never jumps!)"
	_scale_snap_spin.custom_minimum_size = Vector2(68, 0)
	_scale_snap_spin.value_changed.connect(func(v: float) -> void: _scale_snap_studs = maxf(0.001, v))
	_toolbar.add_child(_scale_snap_spin)

	# 6. Hide Selected in Hierarchy + Hider/Unhider Node Panel Button
	var hide_sel_btn: Button = Button.new()
	hide_sel_btn.text = "Hide"
	hide_sel_btn.tooltip_text = "Hide selected node(s) in the Hierarchy panel (stays visible in the 3D game!)"
	hide_sel_btn.pressed.connect(hide_selected_workspace_nodes)
	_toolbar.add_child(hide_sel_btn)

	var hider_btn: Button = Button.new()
	hider_btn.text = "Hider"
	hider_btn.tooltip_text = "Open Hider/Unhider Node panel to Hide All, Unhide All, or Hide/Unhide specific nodes in the Hierarchy"
	hider_btn.pressed.connect(_on_open_hider_dialog)
	_toolbar.add_child(hider_btn)

	# 7. Player Settings Button
	var settings_btn: Button = Button.new()
	settings_btn.text = "Settings"
	settings_btn.tooltip_text = "Edit player walk speed, jump power, gravity, and health"
	settings_btn.pressed.connect(_on_open_player_settings)
	_toolbar.add_child(settings_btn)

	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)


func _on_open_player_settings() -> void:
	if _settings_dialog != null:
		if _settings_dialog.has_method("_load_values"):
			_settings_dialog.call("_load_values")
		_settings_dialog.popup_centered()


func _on_open_hider_dialog() -> void:
	if _hider_dialog != null:
		if _hider_dialog.has_method("refresh_node_list"):
			_hider_dialog.call("refresh_node_list")
		_hider_dialog.popup_centered()


func _on_toggle_snap_pressed() -> void:
	_snap_enabled = not _snap_enabled
	if _snap_toggle_btn != null:
		_snap_toggle_btn.text = "Snap:ON" if _snap_enabled else "Snap:OFF"


# ============================================================================
# UNLINK DATA (BUTTON + AUTO-UNLINK ON SELECTION)
# ============================================================================

func _on_unlink_selected_pressed() -> void:
	var sel: EditorSelection = get_editor_interface().get_selection()
	if sel == null:
		return
	for node in sel.get_selected_nodes():
		_unlink_node_resources_recursive(node)


func _unlink_single_part(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	for ch in node.get_children():
		if ch is MeshInstance3D:
			var mi: MeshInstance3D = ch as MeshInstance3D
			if mi.mesh != null and not bool(mi.get_meta("_rbx_unlinked", false)):
				mi.mesh = mi.mesh.duplicate(true)
				mi.mesh.resource_local_to_scene = true
				if mi.material_override != null:
					mi.material_override = mi.material_override.duplicate(true)
					mi.material_override.resource_local_to_scene = true
				mi.set_meta("_rbx_unlinked", true)
		elif ch is CollisionShape3D:
			var cs: CollisionShape3D = ch as CollisionShape3D
			if cs.shape != null and not bool(cs.get_meta("_rbx_unlinked", false)):
				cs.shape = cs.shape.duplicate(true)
				cs.shape.resource_local_to_scene = true
				cs.set_meta("_rbx_unlinked", true)


func _unlink_node_resources_recursive(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			mi.mesh = mi.mesh.duplicate(true)
			mi.mesh.resource_local_to_scene = true
		if mi.material_override != null:
			mi.material_override = mi.material_override.duplicate(true)
			mi.material_override.resource_local_to_scene = true
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var smat: Material = mi.get_surface_override_material(s)
				if smat != null:
					var dup_mat: Material = smat.duplicate(true) as Material
					dup_mat.resource_local_to_scene = true
					mi.set_surface_override_material(s, dup_mat)
		mi.set_meta("_rbx_unlinked", true)
	elif node is CollisionShape3D:
		var cs: CollisionShape3D = node as CollisionShape3D
		if cs.shape != null:
			cs.shape = cs.shape.duplicate(true)
			cs.shape.resource_local_to_scene = true
		cs.set_meta("_rbx_unlinked", true)
	for ch in node.get_children():
		_unlink_node_resources_recursive(ch)


# ============================================================================
# SPAWN INSIDE SELECTED NODE & AT 3D CAMERA LOOK POSITION
# + KEEP COLLAPSED SCENE TREE NODES COLLAPSED
# ============================================================================

func _get_selected_or_world_parent(root: Node) -> Node:
	var sel: EditorSelection = get_editor_interface().get_selection()
	if sel != null:
		var nodes: Array[Node] = sel.get_selected_nodes()
		if not nodes.is_empty():
			var chosen: Node = nodes[0]
			if chosen != null and is_instance_valid(chosen) and (chosen == root or root.is_ancestor_of(chosen)):
				return chosen
	var world: Node = root.get_node_or_null("World")
	if world != null:
		return world
	return root


func _get_camera_look_spawn_world_pos(part_half_height: float) -> Vector3:
	var vp: SubViewport = get_editor_interface().get_editor_viewport_3d(0)
	if vp != null:
		var cam: Camera3D = vp.get_camera_3d()
		if cam != null:
			var from: Vector3 = cam.global_position
			var forward: Vector3 = -cam.global_transform.basis.z.normalized()
			var to: Vector3 = from + forward * 65.0
			var world_3d: World3D = vp.find_world_3d()
			if world_3d != null and world_3d.direct_space_state != null:
				var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
				var hit: Dictionary = world_3d.direct_space_state.intersect_ray(q)
				if not hit.is_empty():
					var hp: Vector3 = hit["position"]
					var hn: Vector3 = hit.get("normal", Vector3.UP)
					var pos: Vector3 = hp + hn * part_half_height
					return _snap_vec3(pos)
			var air_pos: Vector3 = from + forward * 14.0
			return _snap_vec3(air_pos)
	return Vector3(0.0, part_half_height + 2.0, 0.0)


func _snap_vec3(v: Vector3) -> Vector3:
	if not _snap_enabled or _move_snap_studs <= 0.0:
		return v
	return Vector3(
		snappedf(v.x, _move_snap_studs),
		snappedf(v.y, _move_snap_studs),
		snappedf(v.z, _move_snap_studs)
	)


func _find_scene_tree_control(node: Node) -> Tree:
	if node is Tree:
		var p: Node = node.get_parent()
		if p != null and ("Scene" in p.name or "SceneTree" in p.get_class()):
			return node as Tree
	for ch in node.get_children():
		var found: Tree = _find_scene_tree_control(ch)
		if found != null:
			return found
	return null


func _snapshot_collapsed_items() -> Dictionary:
	var map: Dictionary = {}
	if _scene_tree_control == null or not is_instance_valid(_scene_tree_control):
		_scene_tree_control = _find_scene_tree_control(get_editor_interface().get_base_control())
	if _scene_tree_control == null:
		return map
	var root_item: TreeItem = _scene_tree_control.get_root()
	if root_item != null:
		_collect_collapsed_recursive(root_item, "", map)
	return map


func _collect_collapsed_recursive(item: TreeItem, path_prefix: String, map: Dictionary) -> void:
	var cur_path: String = path_prefix + "/" + item.get_text(0)
	if item.collapsed:
		map[cur_path] = true
	var child: TreeItem = item.get_first_child()
	while child != null:
		_collect_collapsed_recursive(child, cur_path, map)
		child = child.get_next()


func _restore_collapsed_items(map: Dictionary) -> void:
	if map.is_empty() or _scene_tree_control == null or not is_instance_valid(_scene_tree_control):
		return
	var root_item: TreeItem = _scene_tree_control.get_root()
	if root_item != null:
		_apply_collapsed_recursive(root_item, "", map)


func _apply_collapsed_recursive(item: TreeItem, path_prefix: String, map: Dictionary) -> void:
	var cur_path: String = path_prefix + "/" + item.get_text(0)
	if map.has(cur_path):
		item.collapsed = true
	var child: TreeItem = item.get_first_child()
	while child != null:
		_apply_collapsed_recursive(child, cur_path, map)
		child = child.get_next()


func _attach_spawner_editor_preview(spawner: StaticBody3D, root: Node, item_id: int, spawner_script: Script) -> void:
	var meta: Dictionary = spawner_script.call("get_type_meta", item_id)
	var col_color: Color = meta.get("color", Color.WHITE)
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	mesh_node.name = "MeshInstance3D"
	var bmesh: BoxMesh = BoxMesh.new()
	bmesh.size = Vector3(3.6, 0.5, 3.6)
	mesh_node.mesh = bmesh
	var smat: ShaderMaterial = _make_default_stud_material()
	smat.set_shader_parameter("albedo", col_color.darkened(0.15))
	mesh_node.material_override = smat
	spawner.add_child(mesh_node)
	mesh_node.owner = root


func _on_item_spawner_selected(item_id: int) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return
	var spawner_script: Script = load(ITEM_SPAWNER_PATH) as Script
	if spawner_script == null:
		return
	if item_id == 99:
		_spawn_all_starter_gears_in_editor(root, spawner_script)
		return
	var collapsed_state: Dictionary = _snapshot_collapsed_items()
	var target_parent: Node = _get_selected_or_world_parent(root)
	var spawner: StaticBody3D = spawner_script.new() as StaticBody3D
	var meta: Dictionary = spawner_script.call("get_type_meta", item_id)
	spawner.name = String(meta.get("name", "Item")).replace(" ", "") + "Spawner"
	spawner.set("item_type", item_id)
	target_parent.add_child(spawner)
	spawner.owner = root
	_attach_spawner_editor_preview(spawner, root, item_id, spawner_script)
	spawner.global_position = _get_camera_look_spawn_world_pos(0.3)
	_unlink_node_resources_recursive(spawner)
	call_deferred("_restore_collapsed_items", collapsed_state)


func _spawn_all_starter_gears_in_editor(root: Node, spawner_script: Script) -> void:
	var world: Node = root.get_node_or_null("World")
	var parent_node: Node = world if world != null else root
	var holder: Node3D = parent_node.get_node_or_null("ItemSpawners") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "ItemSpawners"
		parent_node.add_child(holder)
		holder.owner = root
	for i in range(1, 16):
		var meta: Dictionary = spawner_script.call("get_type_meta", i)
		var s_name: String = String(meta.get("name", "Item")).replace(" ", "") + "Spawner"
		if holder.get_node_or_null(s_name) != null:
			continue
		var sp: StaticBody3D = spawner_script.new() as StaticBody3D
		sp.name = s_name
		sp.set("item_type", i)
		sp.position = Vector3(-28.0 + float(i - 1) * 4.0, 0.25, -11.0)
		holder.add_child(sp)
		sp.owner = root
		_attach_spawner_editor_preview(sp, root, i, spawner_script)


func _make_default_stud_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.resource_local_to_scene = true
	var sh: Shader = load(STUD_SHADER_PATH) as Shader
	var st: Texture2D = load(STUD_TEX_PATH) as Texture2D
	var sn: Texture2D = load(STUD_NORMAL_PATH) as Texture2D
	mat.shader = sh
	mat.set_shader_parameter("albedo", Color("7f8c8d"))
	if st != null:
		mat.set_shader_parameter("stud_tex", st)
	if sn != null:
		mat.set_shader_parameter("stud_normal_tex", sn)
	mat.set_shader_parameter("stud_density", 1.0)
	mat.set_shader_parameter("normal_depth", 1.2)
	mat.set_shader_parameter("roughness_val", 0.4)
	mat.set_shader_parameter("specular_val", 0.5)
	mat.set_shader_parameter("stud_full", false)
	mat.set_shader_parameter("stud_top", true)
	mat.set_shader_parameter("stud_bottom", false)
	mat.set_shader_parameter("stud_left", false)
	mat.set_shader_parameter("stud_right", false)
	mat.set_shader_parameter("stud_front", false)
	mat.set_shader_parameter("stud_back", false)
	return mat


func _on_part_selected(id: int) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		printerr("RetroBlox Studio: Open a 3D scene before inserting parts.")
		return

	var collapsed_state: Dictionary = _snapshot_collapsed_items()
	var target_parent: Node = _get_selected_or_world_parent(root)

	var part: StaticBody3D = StaticBody3D.new()
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"

	var part_size: Vector3 = Vector3(4.0, 1.2, 2.0)
	var shape_box: BoxShape3D = BoxShape3D.new()
	shape_box.resource_local_to_scene = true
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.resource_local_to_scene = true

	if id == 0:
		part.name = "Part"
		part_size = Vector3(4.0, 1.2, 2.0)
		box_mesh.size = part_size
		shape_box.size = part_size
		mesh_inst.mesh = box_mesh
		col_shape.shape = shape_box
	elif id == 1:
		part.name = "Brick"
		part_size = Vector3(4.0, 2.0, 2.0)
		box_mesh.size = part_size
		shape_box.size = part_size
		mesh_inst.mesh = box_mesh
		col_shape.shape = shape_box
	elif id == 2:
		part.name = "Plate"
		part_size = Vector3(4.0, 0.4, 4.0)
		box_mesh.size = part_size
		shape_box.size = part_size
		mesh_inst.mesh = box_mesh
		col_shape.shape = shape_box
	elif id == 3:
		part.name = "Cylinder"
		part_size = Vector3(4.0, 2.0, 4.0)
		var cyl_mesh: CylinderMesh = CylinderMesh.new()
		cyl_mesh.resource_local_to_scene = true
		cyl_mesh.top_radius = 2.0
		cyl_mesh.bottom_radius = 2.0
		cyl_mesh.height = 2.0
		var cyl_shape: CylinderShape3D = CylinderShape3D.new()
		cyl_shape.resource_local_to_scene = true
		cyl_shape.radius = 2.0
		cyl_shape.height = 2.0
		mesh_inst.mesh = cyl_mesh
		col_shape.shape = cyl_shape
	elif id == 4:
		part.name = "Sphere"
		part_size = Vector3(4.0, 4.0, 4.0)
		var sph_mesh: SphereMesh = SphereMesh.new()
		sph_mesh.resource_local_to_scene = true
		sph_mesh.radius = 2.0
		sph_mesh.height = 4.0
		var sph_shape: SphereShape3D = SphereShape3D.new()
		sph_shape.resource_local_to_scene = true
		sph_shape.radius = 2.0
		mesh_inst.mesh = sph_mesh
		col_shape.shape = sph_shape
	elif id == 5:
		part.name = "Wedge"
		part_size = Vector3(4.0, 2.0, 4.0)
		var pwedge: PrismMesh = PrismMesh.new()
		pwedge.resource_local_to_scene = true
		pwedge.size = part_size
		pwedge.left_to_right = 0.0
		shape_box.size = part_size
		mesh_inst.mesh = pwedge
		col_shape.shape = shape_box
	elif id == 6:
		part.name = "ClimbLadder"
		part_size = Vector3(3.0, 20.0, 0.8)
		box_mesh.size = part_size
		shape_box.size = part_size
		mesh_inst.mesh = box_mesh
		col_shape.shape = shape_box
		part.add_to_group("ladder")
		part.add_to_group("climb")
		part.collision_layer = 17

	mesh_inst.material_override = _make_default_stud_material()

	part.add_child(mesh_inst)
	part.add_child(col_shape)
	target_parent.add_child(part)

	part.owner = root
	mesh_inst.owner = root
	col_shape.owner = root

	part.global_position = _get_camera_look_spawn_world_pos(part_size.y * 0.5)
	_unlink_node_resources_recursive(part)

	call_deferred("_restore_collapsed_items", collapsed_state)


# ============================================================================
# HIERARCHY-ONLY NODE HIDER / UNHIDER API
# Hides nodes ONLY in the Scene Tree Hierarchy panel — NEVER in the 3D game!
# ============================================================================

func get_manageable_workspace_nodes() -> Array[Node]:
	var list: Array[Node] = []
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return list
	var world: Node = root.get_node_or_null("World")
	var scan_root: Node = world if world != null else root
	for ch in scan_root.get_children():
		if ch.name in ["HUD", "LocalPlayer", "CameraRig", "WorldEnvironment", "Sun"]:
			continue
		list.append(ch)
	return list


func set_node_hidden_in_workspace(node: Node, hide_flag: bool) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null or node == null or not is_instance_valid(node) or node == root:
		return
	node.set_meta("_rbx_hidden_in_workspace", hide_flag)
	if node is Node3D:
		(node as Node3D).visible = true
	_sync_hierarchy_tree_visibility()


func _sync_hierarchy_tree_visibility() -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return
	if _scene_tree_control == null or not is_instance_valid(_scene_tree_control):
		_scene_tree_control = _find_scene_tree_control(get_editor_interface().get_base_control())
	if _scene_tree_control == null:
		return
	var root_item: TreeItem = _scene_tree_control.get_root()
	if root_item != null:
		_sync_tree_item_recursive(root, root_item)


func _sync_tree_item_recursive(scene_root: Node, item: TreeItem) -> void:
	var meta_val: Variant = item.get_metadata(0)
	var matched_node: Node = null
	if meta_val is NodePath:
		matched_node = scene_root.get_node_or_null(meta_val as NodePath)
	if matched_node != null and is_instance_valid(matched_node) and matched_node != scene_root:
		var should_hide: bool = bool(matched_node.get_meta("_rbx_hidden_in_workspace", false))
		if item.visible == should_hide:
			item.visible = not should_hide
	var child: TreeItem = item.get_first_child()
	while child != null:
		_sync_tree_item_recursive(scene_root, child)
		child = child.get_next()


func hide_selected_workspace_nodes() -> void:
	var sel: EditorSelection = get_editor_interface().get_selection()
	if sel == null:
		return
	var chosen: Array[Node] = sel.get_selected_nodes().duplicate()
	sel.clear()
	for n in chosen:
		set_node_hidden_in_workspace(n, true)


func set_all_workspace_nodes_hidden(hide_flag: bool) -> void:
	var sel: EditorSelection = get_editor_interface().get_selection()
	if sel != null and hide_flag:
		sel.clear()
	for n in get_manageable_workspace_nodes():
		set_node_hidden_in_workspace(n, hide_flag)


# ============================================================================
# SURFACE STUDS CONFIGURATION (TOP, BOTTOM, LEFT, RIGHT, FULL)
# ============================================================================

func _on_surface_studs_selected(id: int) -> void:
	var sel: EditorSelection = get_editor_interface().get_selection()
	if sel == null:
		return
	var nodes: Array[Node] = sel.get_selected_nodes()
	if nodes.is_empty():
		printerr("RetroBlox Studio: Select one or more parts to change surface studs.")
		return
	for node in nodes:
		_apply_surface_studs_recursive(node, id)


func _apply_surface_studs_recursive(node: Node, id: int) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		var mat: Material = mi.material_override
		if mat == null or not (mat is ShaderMaterial):
			var old_col: Color = Color("7f8c8d")
			if mat is StandardMaterial3D:
				old_col = (mat as StandardMaterial3D).albedo_color
			var new_smat: ShaderMaterial = _make_default_stud_material()
			new_smat.set_shader_parameter("albedo", old_col)
			mi.material_override = new_smat
			mat = new_smat
		var smat: ShaderMaterial = mat as ShaderMaterial
		if smat != null:
			smat.resource_local_to_scene = true
			if id == 0:
				var cur_full: bool = bool(smat.get_shader_parameter("stud_full"))
				smat.set_shader_parameter("stud_full", not cur_full)
			elif id == 1:
				var raw_top: Variant = smat.get_shader_parameter("stud_top")
				var cur_top: bool = bool(raw_top) if raw_top != null else true
				smat.set_shader_parameter("stud_top", not cur_top)
			elif id == 2:
				var cur_bot: bool = bool(smat.get_shader_parameter("stud_bottom"))
				smat.set_shader_parameter("stud_bottom", not cur_bot)
			elif id == 3:
				var cur_left: bool = bool(smat.get_shader_parameter("stud_left"))
				smat.set_shader_parameter("stud_left", not cur_left)
			elif id == 4:
				var cur_right: bool = bool(smat.get_shader_parameter("stud_right"))
				smat.set_shader_parameter("stud_right", not cur_right)
			elif id == 5:
				var cur_front: bool = bool(smat.get_shader_parameter("stud_front"))
				smat.set_shader_parameter("stud_front", not cur_front)
				smat.set_shader_parameter("stud_back", not cur_front)
			elif id == 6:
				smat.set_shader_parameter("stud_full", false)
				smat.set_shader_parameter("stud_top", false)
				smat.set_shader_parameter("stud_bottom", false)
				smat.set_shader_parameter("stud_left", false)
				smat.set_shader_parameter("stud_right", false)
				smat.set_shader_parameter("stud_front", false)
				smat.set_shader_parameter("stud_back", false)
			elif id == 7:
				smat.set_shader_parameter("stud_full", false)
				smat.set_shader_parameter("stud_top", true)
				smat.set_shader_parameter("stud_bottom", false)
				smat.set_shader_parameter("stud_left", false)
				smat.set_shader_parameter("stud_right", false)
				smat.set_shader_parameter("stud_front", false)
				smat.set_shader_parameter("stud_back", false)
	for ch in node.get_children():
		_apply_surface_studs_recursive(ch, id)
