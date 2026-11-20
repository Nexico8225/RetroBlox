@tool
extends PanelContainer

# RetroBlox Studio: Combined Cyclops Level Builder & RetroBlox Building System
# Floating, Draggable, Resizable, and Dockable Building Tool with Show/Hide toggle.

signal closed

var plugin: EditorPlugin

var _is_floating: bool = true
var _dragging_window: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _resizing_window: bool = false
var _resize_start_pos: Vector2 = Vector2.ZERO
var _resize_start_size: Vector2 = Vector2.ZERO

var _header_bar: PanelContainer
var _content_box: VBoxContainer
var _tab_container: TabContainer

# Snap settings
var _blockout_snap_studs: float = 1.0
var _active_material: String = "Plastic"
var _active_color: Color = Color("a0a0a0")

func _init() -> void:
	custom_minimum_size = Vector2(340, 480)
	size = Vector2(360, 520)

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# Main Panel Styling
	var psb = StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.15, 0.19, 0.98)
	psb.border_width_left = 1
	psb.border_width_top = 1
	psb.border_width_right = 1
	psb.border_width_bottom = 1
	psb.border_color = Color(0.26, 0.32, 0.42, 1.0)
	psb.set_corner_radius_all(6)
	psb.shadow_size = 12
	psb.shadow_color = Color(0, 0, 0, 0.45)
	add_theme_stylebox_override("panel", psb)

	var root_vb = VBoxContainer.new()
	root_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vb.add_theme_constant_override("separation", 4)
	add_child(root_vb)

	# 1. Draggable Window Header
	_header_bar = PanelContainer.new()
	var hsb = StyleBoxFlat.new()
	hsb.bg_color = Color(0.18, 0.22, 0.28, 1.0)
	hsb.content_margin_left = 8.0
	hsb.content_margin_right = 6.0
	hsb.content_margin_top = 5.0
	hsb.content_margin_bottom = 5.0
	hsb.set_corner_radius_all(4)
	_header_bar.add_theme_stylebox_override("panel", hsb)
	root_vb.add_child(_header_bar)

	var hh = HBoxContainer.new()
	hh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_bar.add_child(hh)

	var title_lbl = Label.new()
	title_lbl.text = "BuildersUI"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 11)
	hh.add_child(title_lbl)

	var min_btn = Button.new()
	min_btn.text = "_"
	min_btn.custom_minimum_size = Vector2(22, 20)
	min_btn.tooltip_text = "Minimize / Expand Builder Panel"
	min_btn.pressed.connect(_on_toggle_minimize)
	hh.add_child(min_btn)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(22, 20)
	close_btn.tooltip_text = "Close / Hide Builder Panel (Hotkey: B)"
	close_btn.pressed.connect(func():
		hide()
		closed.emit()
	)
	hh.add_child(close_btn)

	# Drag listener on header
	_header_bar.gui_input.connect(_on_header_gui_input)

	# 2. Content Box
	_content_box = VBoxContainer.new()
	_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_box.add_theme_constant_override("separation", 6)
	root_vb.add_child(_content_box)

	# Tab Container
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_box.add_child(_tab_container)

	_build_blockout_tab()
	_build_parts_tab()
	_build_materials_colors_tab()
	_build_pads_spawners_tab()

	# Quick Logic & Scripting Bar (Block Code + Orchestrator)
	var logic_bar = HBoxContainer.new()
	logic_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logic_bar.add_theme_constant_override("separation", 6)
	_content_box.add_child(logic_bar)

	var bc_btn = Button.new()
	bc_btn.text = "Block Code"
	bc_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bc_btn.tooltip_text = "Open Scratch-style Visual Block Code for Selected Node"
	bc_btn.pressed.connect(func():
		if plugin != null and plugin.has_method("_on_open_block_code"):
			plugin.call("_on_open_block_code")
	)
	logic_bar.add_child(bc_btn)

	var orch_btn = Button.new()
	orch_btn.text = "Orchestrator"
	orch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orch_btn.tooltip_text = "Open Orchestrator Visual Blueprint Graph for Selected Node"
	orch_btn.pressed.connect(func():
		if plugin != null and plugin.has_method("_on_open_orchestrator"):
			plugin.call("_on_open_orchestrator")
	)
	logic_bar.add_child(orch_btn)

	# 3. Bottom Resize Handle Grip
	var bottom_row = HBoxContainer.new()
	bottom_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vb.add_child(bottom_row)

	var tip_lbl = Label.new()
	tip_lbl.text = "Drag header to move | Drag corner to resize"
	tip_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_lbl.add_theme_font_size_override("font_size", 9)
	tip_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78))
	bottom_row.add_child(tip_lbl)

	var resize_grip = Control.new()
	resize_grip.custom_minimum_size = Vector2(16, 16)
	resize_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	resize_grip.gui_input.connect(_on_resize_grip_gui_input)
	bottom_row.add_child(resize_grip)

# ============================================================================
# DRAGGING & RESIZING
# ============================================================================

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging_window = true
				_drag_offset = get_global_mouse_position() - global_position
			else:
				_dragging_window = false
	elif event is InputEventMouseMotion and _dragging_window:
		global_position = get_global_mouse_position() - _drag_offset

func _on_resize_grip_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_resizing_window = true
				_resize_start_pos = get_global_mouse_position()
				_resize_start_size = size
			else:
				_resizing_window = false
	elif event is InputEventMouseMotion and _resizing_window:
		var delta_pos = get_global_mouse_position() - _resize_start_pos
		var new_w = maxf(280.0, _resize_start_size.x + delta_pos.x)
		var new_h = maxf(240.0, _resize_start_size.y + delta_pos.y)
		size = Vector2(new_w, new_h)
		custom_minimum_size = Vector2(new_w, new_h)

func _on_toggle_minimize() -> void:
	if _content_box != null:
		_content_box.visible = not _content_box.visible
		if not _content_box.visible:
			custom_minimum_size = Vector2(size.x, 34)
			size = Vector2(size.x, 34)
		else:
			custom_minimum_size = Vector2(size.x, 460)
			size = Vector2(size.x, 460)

# ============================================================================
# TAB 1: CYCLOPS LEVEL BLOCKOUT & GEOMETRY TOOLS
# ============================================================================

func _build_blockout_tab() -> void:
	var scroll = ScrollContainer.new()
	scroll.name = "Cyclops Blockout"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(scroll)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)

	var sub_h = Label.new()
	sub_h.text = "Cyclops Live Viewport Tools:"
	sub_h.add_theme_font_size_override("font_size", 11)
	sub_h.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vb.add_child(sub_h)

	var cyc_top = HBoxContainer.new()
	cyc_top.add_theme_constant_override("separation", 4)
	vb.add_child(cyc_top)
	_add_action_button(cyc_top, "+ CyclopsBlocks Layer", func(): _ensure_cyclops_blocks_node())
	_add_action_button(cyc_top, "Toggle 3D Bar", func(): _toggle_cyclops_3d_bar())

	var cyc_grid = GridContainer.new()
	cyc_grid.columns = 3
	cyc_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(cyc_grid)

	_add_action_button(cyc_grid, "Draw Block", func(): _activate_cyclops_tool("block"))
	_add_action_button(cyc_grid, "Draw Cylinder", func(): _activate_cyclops_tool("cylinder"))
	_add_action_button(cyc_grid, "Draw Prism", func(): _activate_cyclops_tool("prism"))
	_add_action_button(cyc_grid, "Draw Sphere", func(): _activate_cyclops_tool("sphere"))
	_add_action_button(cyc_grid, "Draw Stairs", func(): _activate_cyclops_tool("stairs"))
	_add_action_button(cyc_grid, "Face Edit", func(): _activate_cyclops_tool("edit_face"))
	_add_action_button(cyc_grid, "Edge Edit", func(): _activate_cyclops_tool("edit_edge"))
	_add_action_button(cyc_grid, "Vertex Edit", func(): _activate_cyclops_tool("edit_vertex"))
	_add_action_button(cyc_grid, "Clip / Slice", func(): _activate_cyclops_tool("clip"))
	_add_action_button(cyc_grid, "Move Tool", func(): _activate_cyclops_tool("move"))
	_add_action_button(cyc_grid, "Rotate Tool", func(): _activate_cyclops_tool("rotate"))
	_add_action_button(cyc_grid, "Mat Brush", func(): _activate_cyclops_tool("material_brush"))

	vb.add_child(HSeparator.new())

	# Grid Snap Row
	var snap_row = HBoxContainer.new()
	vb.add_child(snap_row)
	var slbl = Label.new()
	slbl.text = "Snap:"
	slbl.add_theme_font_size_override("font_size", 10)
	snap_row.add_child(slbl)
	for s_val in [0.25, 0.5, 1.0, 2.0, 4.0]:
		var s_btn = Button.new()
		s_btn.text = str(s_val)
		s_btn.custom_minimum_size = Vector2(36, 22)
		s_btn.add_theme_font_size_override("font_size", 9)
		s_btn.pressed.connect(func(): _blockout_snap_studs = s_val)
		snap_row.add_child(s_btn)

	# Brush Creation Grid
	var b_lbl = Label.new()
	b_lbl.text = "Insert Brush Shapes:"
	b_lbl.add_theme_font_size_override("font_size", 10)
	vb.add_child(b_lbl)

	var brush_grid = GridContainer.new()
	brush_grid.columns = 2
	brush_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(brush_grid)

	_add_action_button(brush_grid, "+ Block (Cube)", func(): _spawn_cyclops_shape("block"))
	_add_action_button(brush_grid, "+ Wedge / Ramp", func(): _spawn_cyclops_shape("wedge"))
	_add_action_button(brush_grid, "+ Cylinder Pillar", func(): _spawn_cyclops_shape("cylinder"))
	_add_action_button(brush_grid, "+ Prism (Pyramid)", func(): _spawn_cyclops_shape("prism"))
	_add_action_button(brush_grid, "+ Stairs (10 Steps)", func(): _spawn_cyclops_shape("stairs"))
	_add_action_button(brush_grid, "+ Arch / Doorway", func(): _spawn_cyclops_shape("arch"))
	_add_action_button(brush_grid, "+ Hollow Room", func(): _spawn_cyclops_shape("hollow_room"))
	_add_action_button(brush_grid, "+ Thin Wall (1 Stud)", func(): _spawn_cyclops_shape("wall"))

	# Geometry Modification on Selected
	vb.add_child(HSeparator.new())
	var mod_lbl = Label.new()
	mod_lbl.text = "Modify Selected Part:"
	mod_lbl.add_theme_font_size_override("font_size", 10)
	vb.add_child(mod_lbl)

	var mod_grid = GridContainer.new()
	mod_grid.columns = 2
	mod_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(mod_grid)

	_add_action_button(mod_grid, "Extrude Width (+X)", func(): _extrude_selected(Vector3(1, 0, 0)))
	_add_action_button(mod_grid, "Extrude Height (+Y)", func(): _extrude_selected(Vector3(0, 1, 0)))
	_add_action_button(mod_grid, "Extrude Depth (+Z)", func(): _extrude_selected(Vector3(0, 0, 1)))
	_add_action_button(mod_grid, "Shrink (-1 Stud)", func(): _extrude_selected(Vector3(-1, -1, -1)))
	_add_action_button(mod_grid, "Slice in Half", func(): _slice_selected())
	_add_action_button(mod_grid, "Hollow Out Part", func(): _hollow_selected())

# ============================================================================
# TAB 2: RETROBLOX CLASSIC PARTS
# ============================================================================

func _build_parts_tab() -> void:
	var scroll = ScrollContainer.new()
	scroll.name = "Parts & Studs"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(scroll)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)

	var p_lbl = Label.new()
	p_lbl.text = "Classic RetroBlox Parts:"
	p_lbl.add_theme_font_size_override("font_size", 11)
	p_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vb.add_child(p_lbl)

	var p_grid = GridContainer.new()
	p_grid.columns = 2
	p_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(p_grid)

	_add_action_button(p_grid, "Part (4x1.2x2)", func(): _spawn_part(0))
	_add_action_button(p_grid, "Brick (4x2x2)", func(): _spawn_part(1))
	_add_action_button(p_grid, "Small Brick (2x1x1)", func(): _spawn_part(7))
	_add_action_button(p_grid, "Plate (4x0.4x4)", func(): _spawn_part(2))
	_add_action_button(p_grid, "Sphere Brick (4x4x4)", func(): _spawn_part(4))
	_add_action_button(p_grid, "Small Sphere (2x2x2)", func(): _spawn_part(8))
	_add_action_button(p_grid, "Triangle (4x2x2)", func(): _spawn_part(9))
	_add_action_button(p_grid, "Wedge (4x2x4)", func(): _spawn_part(5))
	_add_action_button(p_grid, "Cylinder (4x2x4)", func(): _spawn_part(3))
	_add_action_button(p_grid, "Truss (Climbable)", func(): _spawn_part(6))

	vb.add_child(HSeparator.new())
	var h_lbl = Label.new()
	h_lbl.text = "Hollow Shapes and CSG Operations:"
	h_lbl.add_theme_font_size_override("font_size", 10)
	vb.add_child(h_lbl)

	var h_grid = GridContainer.new()
	h_grid.columns = 2
	h_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(h_grid)

	_add_action_button(h_grid, "Hollow Circle / Pipe", func(): _spawn_part(10))
	_add_action_button(h_grid, "Hollow Cube / Room", func(): _spawn_part(11))
	_add_action_button(h_grid, "Hollow Triangle", func(): _spawn_part(12))
	_add_action_button(h_grid, "CSG Union (Merge)", func(): _spawn_part(20))
	_add_action_button(h_grid, "CSG Subtract (Cut)", func(): _spawn_part(21))

	vb.add_child(HSeparator.new())
	var s_lbl = Label.new()
	s_lbl.text = "Surface Studs on Selected:"
	s_lbl.add_theme_font_size_override("font_size", 10)
	vb.add_child(s_lbl)

	var s_grid = GridContainer.new()
	s_grid.columns = 2
	s_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(s_grid)

	_add_action_button(s_grid, "Top Studs (Toggle)", func(): _apply_studs(1))
	_add_action_button(s_grid, "Full Studs (All Sides)", func(): _apply_studs(0))
	_add_action_button(s_grid, "Bottom Studs", func(): _apply_studs(2))
	_add_action_button(s_grid, "Smooth Plastic (No Studs)", func(): _apply_studs(6))

	vb.add_child(HSeparator.new())
	var unlink_btn = Button.new()
	unlink_btn.text = "Unlink Data (Make Unique)"
	unlink_btn.tooltip_text = "Make Mesh, Material & Shape unique so changing color/size never affects duplicates"
	unlink_btn.pressed.connect(func():
		if plugin != null and plugin.has_method("_on_unlink_selected_pressed"):
			plugin.call("_on_unlink_selected_pressed")
	)
	vb.add_child(unlink_btn)

# ============================================================================
# TAB 3: MATERIALS & BRICKCOLORS
# ============================================================================

func _build_materials_colors_tab() -> void:
	var scroll = ScrollContainer.new()
	scroll.name = "Color & Material"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(scroll)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)

	var c_lbl = Label.new()
	c_lbl.text = "Classic BrickColors Palette:"
	c_lbl.add_theme_font_size_override("font_size", 11)
	c_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vb.add_child(c_lbl)

	var color_grid = GridContainer.new()
	color_grid.columns = 8
	color_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(color_grid)

	var classic_colors: Array[Color] = [
		Color("c4281c"), Color("0d69ac"), Color("f5cd30"), Color("27462d"),
		Color("ffffff"), Color("1b2a35"), Color("635f62"), Color("a0a5a9"),
		Color("e8ab2d"), Color("da8541"), Color("aa55ff"), Color("00ffff"),
		Color("6b3200"), Color("b4846c"), Color("78909c"), Color("455a64")
	]

	for col in classic_colors:
		var cb = Button.new()
		cb.custom_minimum_size = Vector2(28, 26)
		var csb = StyleBoxFlat.new()
		csb.bg_color = col
		csb.set_corner_radius_all(3)
		cb.add_theme_stylebox_override("normal", csb)
		cb.pressed.connect(func():
			_active_color = col
			_apply_color_to_selected(col)
		)
		color_grid.add_child(cb)

	vb.add_child(HSeparator.new())
	var m_lbl = Label.new()
	m_lbl.text = "Surface Material:"
	m_lbl.add_theme_font_size_override("font_size", 10)
	vb.add_child(m_lbl)

	var mat_grid = GridContainer.new()
	mat_grid.columns = 2
	mat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(mat_grid)

	for mat_name in ["Plastic", "Smooth Plastic", "Wood", "Metal", "Neon", "Glass", "Cobblestone", "Brick"]:
		var mb = Button.new()
		mb.text = mat_name
		mb.pressed.connect(func(): _apply_material_to_selected(mat_name))
		mat_grid.add_child(mb)

# ============================================================================
# TAB 4: INTERACTIVE PADS & GEAR SPAWNERS
# ============================================================================

func _build_pads_spawners_tab() -> void:
	var scroll = ScrollContainer.new()
	scroll.name = "Pads & Spawners"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.add_child(scroll)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)

	var pad_lbl = Label.new()
	pad_lbl.text = "Interactive Gameplay Pads:"
	pad_lbl.add_theme_font_size_override("font_size", 11)
	pad_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vb.add_child(pad_lbl)

	var pad_grid = GridContainer.new()
	pad_grid.columns = 2
	pad_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(pad_grid)

	_add_action_button(pad_grid, "Jump Pad (Yellow)", func(): _spawn_pad(0))
	_add_action_button(pad_grid, "Speed Pad (Blue)", func(): _spawn_pad(1))
	_add_action_button(pad_grid, "Lava Kill Pad (Red)", func(): _spawn_pad(2))
	_add_action_button(pad_grid, "Ice Slide Pad (Cyan)", func(): _spawn_pad(3))
	_add_action_button(pad_grid, "Checkpoint (Green)", func(): _spawn_pad(4))
	_add_action_button(pad_grid, "Heal Pad (Emerald)", func(): _spawn_pad(5))

	vb.add_child(HSeparator.new())
	var sp_lbl = Label.new()
	sp_lbl.text = "Gear Spawner Pads:"
	sp_lbl.add_theme_font_size_override("font_size", 10)
	vb.add_child(sp_lbl)

	var sp_grid = GridContainer.new()
	sp_grid.columns = 2
	sp_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(sp_grid)

	_add_action_button(sp_grid, "Random Gear Spawner", func(): _spawn_gear_spawner(0))
	_add_action_button(sp_grid, "Linked Sword Spawner", func(): _spawn_gear_spawner(5))
	_add_action_button(sp_grid, "Speed Coil Spawner", func(): _spawn_gear_spawner(1))
	_add_action_button(sp_grid, "Gravity Coil Spawner", func(): _spawn_gear_spawner(2))
	_add_action_button(sp_grid, "Rocket Launcher Spawner", func(): _spawn_gear_spawner(14))
	_add_action_button(sp_grid, "Bloxy Cola Spawner", func(): _spawn_gear_spawner(19))

# ============================================================================
# LOGIC & SPAWNING HELPERS
# ============================================================================

func _add_action_button(parent: Control, label_text: String, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = label_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 10)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _get_spawn_world_pos() -> Vector3:
	if plugin != null and plugin.has_method("_get_camera_look_spawn_world_pos"):
		return plugin.call("_get_camera_look_spawn_world_pos", 1.0)
	return Vector3(0, 1.0, 0)

func _spawn_part(part_id: int) -> void:
	if plugin != null and plugin.has_method("_on_part_selected"):
		plugin.call("_on_part_selected", part_id)

func _apply_studs(stud_id: int) -> void:
	if plugin != null and plugin.has_method("_on_surface_studs_selected"):
		plugin.call("_on_surface_studs_selected", stud_id)

func _spawn_pad(pad_id: int) -> void:
	if plugin != null and plugin.has_method("_on_interactive_pad_selected"):
		plugin.call("_on_interactive_pad_selected", pad_id)

func _spawn_gear_spawner(gear_id: int) -> void:
	if plugin != null and plugin.has_method("_on_item_spawner_selected"):
		plugin.call("_on_item_spawner_selected", gear_id)

func _get_scene_root() -> Node:
	if plugin != null:
		var ei = plugin.get_editor_interface()
		if ei != null:
			var er = ei.get_edited_scene_root()
			if er != null:
				return er
		if plugin.get_tree() != null:
			var tr = plugin.get_tree().edited_scene_root
			if tr != null:
				return tr
	return null

func _spawn_cyclops_shape(shape_type: String) -> void:
	if plugin == null:
		return
	var scene_root = _get_scene_root()
	if scene_root == null:
		printerr("[BuildersUI] Please create or open a 3D scene first.")
		return

	var spawn_pos = _get_spawn_world_pos()
	var body = StaticBody3D.new()
	var mi = MeshInstance3D.new()
	mi.name = "MeshInstance3D"
	var cs = CollisionShape3D.new()
	cs.name = "CollisionShape3D"

	match shape_type:
		"block":
			body.name = "BlockBrush"
			var bm = BoxMesh.new()
			bm.size = Vector3(4.0, 4.0, 4.0)
			var bs = BoxShape3D.new()
			bs.size = bm.size
			mi.mesh = bm
			cs.shape = bs
		"wedge":
			body.name = "WedgeRamp"
			var pm = PrismMesh.new()
			pm.size = Vector3(4.0, 4.0, 6.0)
			pm.left_to_right = 0.0
			var bs = BoxShape3D.new()
			bs.size = pm.size
			mi.mesh = pm
			cs.shape = bs
		"cylinder":
			body.name = "CylinderPillar"
			var cm = CylinderMesh.new()
			cm.top_radius = 2.0
			cm.bottom_radius = 2.0
			cm.height = 8.0
			var cshape = CylinderShape3D.new()
			cshape.radius = 2.0
			cshape.height = 8.0
			mi.mesh = cm
			cs.shape = cshape
		"prism":
			body.name = "PrismPyramid"
			var pm = PrismMesh.new()
			pm.size = Vector3(4.0, 4.0, 4.0)
			var bs = BoxShape3D.new()
			bs.size = pm.size
			mi.mesh = pm
			cs.shape = bs
		"stairs":
			body.name = "Stairs"
			return _build_stairs_shape(scene_root, spawn_pos)
		"arch":
			body.name = "ArchDoorway"
			return _build_arch_shape(scene_root, spawn_pos)
		"hollow_room":
			body.name = "HollowRoom"
			return _build_room_shape(scene_root, spawn_pos)
		"wall":
			body.name = "Wall"
			var bm = BoxMesh.new()
			bm.size = Vector3(12.0, 8.0, 1.0)
			var bs = BoxShape3D.new()
			bs.size = bm.size
			mi.mesh = bm
			cs.shape = bs

	body.add_child(mi)
	body.add_child(cs)
	scene_root.add_child(body, true)
	body.global_position = spawn_pos
	body.owner = scene_root
	mi.owner = scene_root
	cs.owner = scene_root

	var sel = plugin.get_editor_interface().get_selection()
	if sel != null:
		sel.clear()
		sel.add_node(body)

func _build_stairs_shape(scene_root: Node, base_pos: Vector3) -> void:
	var stairs_root = Node3D.new()
	stairs_root.name = "Stairs"
	scene_root.add_child(stairs_root, true)
	stairs_root.global_position = base_pos
	stairs_root.owner = scene_root

	var steps_count = 8
	var step_height = 0.5
	var step_depth = 1.0
	var step_width = 4.0

	for i in range(steps_count):
		var sb = StaticBody3D.new()
		sb.name = "Step_" + str(i + 1)
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = Vector3(step_width, step_height, step_depth)
		mi.mesh = bm
		var cs = CollisionShape3D.new()
		var bs = BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs

		sb.add_child(mi)
		sb.add_child(cs)
		stairs_root.add_child(sb, true)
		sb.position = Vector3(0, i * step_height, -i * step_depth)
		sb.owner = scene_root
		mi.owner = scene_root
		cs.owner = scene_root

	var sel = plugin.get_editor_interface().get_selection()
	if sel != null:
		sel.clear()
		sel.add_node(stairs_root)

func _build_arch_shape(scene_root: Node, base_pos: Vector3) -> void:
	var arch_root = Node3D.new()
	arch_root.name = "Archway"
	scene_root.add_child(arch_root, true)
	arch_root.global_position = base_pos
	arch_root.owner = scene_root

	# Left pillar, Right pillar, Top lintel
	var p1 = _create_box_part("LeftPillar", Vector3(2, 8, 2), Vector3(-3, 4, 0), scene_root, arch_root)
	var p2 = _create_box_part("RightPillar", Vector3(2, 8, 2), Vector3(3, 4, 0), scene_root, arch_root)
	var top = _create_box_part("Lintel", Vector3(8, 2, 2), Vector3(0, 9, 0), scene_root, arch_root)

	var sel = plugin.get_editor_interface().get_selection()
	if sel != null:
		sel.clear()
		sel.add_node(arch_root)

func _build_room_shape(scene_root: Node, base_pos: Vector3) -> void:
	var room_root = Node3D.new()
	room_root.name = "HollowRoom"
	scene_root.add_child(room_root, true)
	room_root.global_position = base_pos
	room_root.owner = scene_root

	var floor = _create_box_part("Floor", Vector3(16, 1, 16), Vector3(0, 0.5, 0), scene_root, room_root)
	var ceiling = _create_box_part("Ceiling", Vector3(16, 1, 16), Vector3(0, 8.5, 0), scene_root, room_root)
	var w1 = _create_box_part("NorthWall", Vector3(16, 8, 1), Vector3(0, 4.5, -8), scene_root, room_root)
	var w2 = _create_box_part("SouthWall", Vector3(16, 8, 1), Vector3(0, 4.5, 8), scene_root, room_root)
	var w3 = _create_box_part("WestWall", Vector3(1, 8, 16), Vector3(-8, 4.5, 0), scene_root, room_root)
	var w4 = _create_box_part("EastWall", Vector3(1, 8, 16), Vector3(8, 4.5, 0), scene_root, room_root)

	var sel = plugin.get_editor_interface().get_selection()
	if sel != null:
		sel.clear()
		sel.add_node(room_root)

func _create_box_part(p_name: String, p_size: Vector3, p_pos: Vector3, s_root: Node, parent: Node) -> StaticBody3D:
	var sb = StaticBody3D.new()
	sb.name = p_name
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = p_size
	mi.mesh = bm
	var cs = CollisionShape3D.new()
	var bs = BoxShape3D.new()
	bs.size = p_size
	cs.shape = bs
	sb.add_child(mi)
	sb.add_child(cs)
	parent.add_child(sb, true)
	sb.position = p_pos
	sb.owner = s_root
	mi.owner = s_root
	cs.owner = s_root
	return sb

func _extrude_selected(direction: Vector3) -> void:
	if plugin == null:
		return
	var sel = plugin.get_editor_interface().get_selection()
	if sel == null:
		return
	var delta = direction * _blockout_snap_studs
	for node in sel.get_selected_nodes():
		if node is Node3D:
			for ch in node.get_children():
				if ch is MeshInstance3D:
					var mi := ch as MeshInstance3D
					if mi.mesh is BoxMesh:
						var bm := mi.mesh as BoxMesh
						bm.size = Vector3(
							maxf(0.2, bm.size.x + delta.x),
							maxf(0.2, bm.size.y + delta.y),
							maxf(0.2, bm.size.z + delta.z)
						)
				if ch is CollisionShape3D:
					var cs := ch as CollisionShape3D
					if cs.shape is BoxShape3D:
						var bs := cs.shape as BoxShape3D
						bs.size = Vector3(
							maxf(0.2, bs.size.x + delta.x),
							maxf(0.2, bs.size.y + delta.y),
							maxf(0.2, bs.size.z + delta.z)
						)

func _slice_selected() -> void:
	if plugin == null:
		return
	var sel = plugin.get_editor_interface().get_selection()
	if sel == null:
		return
	var scene_root = plugin.get_tree().edited_scene_root
	if scene_root == null:
		return

	for node in sel.get_selected_nodes():
		if node is StaticBody3D:
			var mi: MeshInstance3D = null
			for ch in node.get_children():
				if ch is MeshInstance3D and ch.mesh is BoxMesh:
					mi = ch
					break
			if mi != null:
				var bm := mi.mesh as BoxMesh
				var half_w = bm.size.x * 0.5
				bm.size.x = half_w
				node.position.x -= half_w * 0.5
				# Clone for second half
				var clone = node.duplicate(true)
				clone.position.x += half_w
				node.get_parent().add_child(clone, true)
				clone.owner = scene_root

func _hollow_selected() -> void:
	if plugin == null:
		return
	var sel = plugin.get_editor_interface().get_selection()
	if sel == null:
		return
	var scene_root = plugin.get_tree().edited_scene_root
	if scene_root == null:
		return

	for node in sel.get_selected_nodes():
		if node is StaticBody3D:
			var mi: MeshInstance3D = null
			for ch in node.get_children():
				if ch is MeshInstance3D and ch.mesh is BoxMesh:
					mi = ch
					break
			if mi != null:
				var bm := mi.mesh as BoxMesh
				var original_pos = node.global_position
				var original_size = bm.size
				node.queue_free()
				# Replace with 4 walls + floor
				var hollow_group = Node3D.new()
				hollow_group.name = "HollowBox"
				scene_root.add_child(hollow_group, true)
				hollow_group.global_position = original_pos
				hollow_group.owner = scene_root

				var t = 1.0 # wall thickness
				_create_box_part("Floor", Vector3(original_size.x, t, original_size.z), Vector3(0, t * 0.5, 0), scene_root, hollow_group)
				_create_box_part("WallN", Vector3(original_size.x, original_size.y, t), Vector3(0, original_size.y * 0.5, -original_size.z * 0.5 + t * 0.5), scene_root, hollow_group)
				_create_box_part("WallS", Vector3(original_size.x, original_size.y, t), Vector3(0, original_size.y * 0.5, original_size.z * 0.5 - t * 0.5), scene_root, hollow_group)
				_create_box_part("WallW", Vector3(t, original_size.y, original_size.z), Vector3(-original_size.x * 0.5 + t * 0.5, original_size.y * 0.5, 0), scene_root, hollow_group)
				_create_box_part("WallE", Vector3(t, original_size.y, original_size.z), Vector3(original_size.x * 0.5 - t * 0.5, original_size.y * 0.5, 0), scene_root, hollow_group)
				return

func _apply_color_to_selected(color: Color) -> void:
	if plugin == null:
		return
	var sel = plugin.get_editor_interface().get_selection()
	if sel == null:
		return
	for node in sel.get_selected_nodes():
		_apply_color_recursive(node, color)

func _apply_color_recursive(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is ShaderMaterial:
			(mi.material_override as ShaderMaterial).set_shader_parameter("albedo", color)
		elif mi.material_override is StandardMaterial3D:
			(mi.material_override as StandardMaterial3D).albedo_color = color
		else:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = color
			mi.material_override = mat
	for ch in node.get_children():
		_apply_color_recursive(ch, color)

func _apply_material_to_selected(mat_type: String) -> void:
	if plugin == null:
		return
	var sel = plugin.get_editor_interface().get_selection()
	if sel == null:
		return
	for node in sel.get_selected_nodes():
		_apply_mat_recursive(node, mat_type)

func _apply_mat_recursive(node: Node, mat_type: String) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat = StandardMaterial3D.new()
		mat.albedo_color = _active_color
		match mat_type:
			"Neon":
				mat.emission_enabled = true
				mat.emission = _active_color
				mat.emission_energy_multiplier = 2.0
			"Glass":
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.4
				mat.roughness = 0.1
			"Metal":
				mat.metallic = 0.85
				mat.roughness = 0.25
			"Smooth Plastic":
				mat.roughness = 0.2
			"Wood":
				mat.roughness = 0.8
		mi.material_override = mat
	for ch in node.get_children():
		_apply_mat_recursive(ch, mat_type)


# ============================================================================
# CYCLOPS LEVEL BUILDER INTEGRATION
# ============================================================================

func _get_cyclops_builder() -> Node:
	if plugin != null and plugin.get_tree() != null:
		var autoload := plugin.get_tree().root.get_node_or_null("CyclopsAutoload")
		if autoload != null and autoload.get("builder") != null:
			return autoload.get("builder") as Node
	return null


func _ensure_cyclops_blocks_node() -> Node:
	var scene_root := _get_scene_root()
	if scene_root == null:
		printerr("[BuildersUI] Open a 3D scene first to add a CyclopsBlocks layer.")
		return null
	var existing := scene_root.find_child("CyclopsBlocks", true, false)
	if existing != null:
		var sel := plugin.get_editor_interface().get_selection()
		if sel != null:
			sel.clear()
			sel.add_node(existing)
		return existing
	if ClassDB.class_exists("CyclopsBlocks"):
		var cb: Node = ClassDB.instantiate("CyclopsBlocks")
		cb.name = "CyclopsBlocks"
		scene_root.add_child(cb, true)
		cb.owner = scene_root
		var sel := plugin.get_editor_interface().get_selection()
		if sel != null:
			sel.clear()
			sel.add_node(cb)
		return cb
	printerr("[BuildersUI] CyclopsBlocks class not registered. Enable Cyclops Level Builder plugin in Project Settings.")
	return null


func _toggle_cyclops_3d_bar() -> void:
	var cyc := _get_cyclops_builder()
	if cyc == null:
		printerr("[BuildersUI] Cyclops Level Builder plugin is not active.")
		return
	var cur := bool(cyc.get("show_3d_toolbar"))
	cyc.set("show_3d_toolbar", not cur)


func _activate_cyclops_tool(tool_id: String) -> void:
	var cyc := _get_cyclops_builder()
	if cyc == null:
		printerr("[BuildersUI] Cyclops Level Builder is not active. Enable it in Project -> Project Settings -> Plugins.")
		return
	# Ensure a CyclopsBlocks or CyclopsBlock is selected when drawing new geometry
	if tool_id in ["block", "cylinder", "prism", "sphere", "stairs"]:
		var sel := plugin.get_editor_interface().get_selection()
		var has_cyclops_sel := false
		if sel != null:
			for n in sel.get_selected_nodes():
				var gname: String = String(n.get_script().get_global_name()) if n.get_script() != null else ""
				if n.get_class() == "CyclopsBlocks" or n.get_class() == "CyclopsBlock" or gname in ["CyclopsBlocks", "CyclopsBlock"]:
					has_cyclops_sel = true
					break
		if not has_cyclops_sel:
			_ensure_cyclops_blocks_node()
	if cyc.has_method("get_tool_by_id") and cyc.has_method("switch_to_tool"):
		var t = cyc.call("get_tool_by_id", tool_id)
		if t != null:
			cyc.call("switch_to_tool", t)
