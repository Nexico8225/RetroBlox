@tool
extends AcceptDialog

# RetroBlox Studio: Custom Nodes Library (MrEliptik Hidden Gems)
# Browse and insert powerful pre-configured gameplay, camera, physics and hazard nodes.

signal node_spawn_requested(node_id: String)

var plugin: EditorPlugin
var _filter_edit: LineEdit
var _item_list: ItemList
var _desc_lbl: Label
var _selected_id: String = ""

const NODES_DATA: Array[Dictionary] = [
	{
		"id": "kill_zone",
		"name": "KillZone3D",
		"category": "Hazard & Combat",
		"desc": "Damages or instantly eliminates any player who steps into its area (Lava, Acid, Death Pit).",
		"script": "res://addons/retroblox_studio/custom_nodes/kill_zone_3d.gd"
	},
	{
		"id": "jump_pad",
		"name": "JumpPad3D",
		"category": "Movement & Obby",
		"desc": "Launches the player upward or along any launch vector on contact with bounce velocity.",
		"script": "res://addons/retroblox_studio/custom_nodes/jump_pad_3d.gd"
	},
	{
		"id": "speed_boost",
		"name": "SpeedBoostPad3D",
		"category": "Movement & Obby",
		"desc": "Temporarily multiplies player walk speed for a configurable duration.",
		"script": "res://addons/retroblox_studio/custom_nodes/speed_boost_pad_3d.gd"
	},
	{
		"id": "teleport_pad",
		"name": "TeleportPad3D",
		"category": "Movement & Obby",
		"desc": "Instantly teleports touching players to target coordinates or target scene node.",
		"script": "res://addons/retroblox_studio/custom_nodes/teleport_pad_3d.gd"
	},
	{
		"id": "conveyor_belt",
		"name": "ConveyorBelt3D",
		"category": "Mechanisms & Physics",
		"desc": "AnimatableBody3D surface with continuous linear velocity that pushes players and parts forward.",
		"script": "res://addons/retroblox_studio/custom_nodes/conveyor_belt_3d.gd"
	},
	{
		"id": "rotating_part",
		"name": "RotatingPart3D",
		"category": "Mechanisms & Physics",
		"desc": "Constantly spins around X, Y, or Z axis at customizable RPM. Perfect for spinning traps and obstacles.",
		"script": "res://addons/retroblox_studio/custom_nodes/rotating_part_3d.gd"
	},
	{
		"id": "disappearing_platform",
		"name": "DisappearingPlatform3D",
		"category": "Movement & Obby",
		"desc": "Classic obby tile: player steps on it -> flashes/shakes -> drops/disappears -> regenerates.",
		"script": "res://addons/retroblox_studio/custom_nodes/disappearing_platform_3d.gd"
	},
	{
		"id": "coin_pickup",
		"name": "CoinPickup3D",
		"category": "Gameplay & Economy",
		"desc": "Spinning collectible coin that awards Tix/Points to the player on touch, with respawn timer.",
		"script": "res://addons/retroblox_studio/custom_nodes/coin_pickup_3d.gd"
	},
	{
		"id": "checkpoint",
		"name": "Checkpoint3D",
		"category": "Movement & Obby",
		"desc": "Updates the player respawn spawn point when touched. Lights up green when activated.",
		"script": "res://addons/retroblox_studio/custom_nodes/checkpoint_3d.gd"
	},
	{
		"id": "shaker",
		"name": "Shaker3D",
		"category": "Visual Effects & Camera",
		"desc": "Screen and camera shake generator with Perlin trauma falloff for explosions, jumps, and impacts.",
		"script": "res://addons/retroblox_studio/custom_nodes/shaker_3d.gd"
	},
	{
		"id": "phantom_camera",
		"name": "PhantomCamera3D",
		"category": "Visual Effects & Camera",
		"desc": "Cinematic third-person and cutscene camera controller with smooth damping and target tracking.",
		"script": "res://addons/retroblox_studio/custom_nodes/phantom_camera_3d.gd"
	}
]

func _init() -> void:
	title = "RetroBlox Custom Nodes Library"
	size = Vector2i(620, 480)
	min_size = Vector2i(500, 380)
	ok_button_text = "Insert into Scene"

func _ready() -> void:
	_build_ui()
	confirmed.connect(_on_confirmed)

func _build_ui() -> void:
	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)

	var hdr = Label.new()
	hdr.text = "Select a Custom Node to insert into your 3D Scene:"
	hdr.add_theme_font_size_override("font_size", 12)
	vb.add_child(hdr)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Search custom nodes (e.g. lava, jump, camera, coin, spin)..."
	_filter_edit.clear_button_enabled = true
	_filter_edit.text_changed.connect(func(_t: String): _refresh_list())
	vb.add_child(_filter_edit)

	var split = HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(split)

	_item_list = ItemList.new()
	_item_list.custom_minimum_size = Vector2(260, 200)
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.item_selected.connect(_on_item_selected)
	_item_list.item_activated.connect(func(_idx: int): _on_confirmed())
	split.add_child(_item_list)

	var right_panel = PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rsb = StyleBoxFlat.new()
	rsb.bg_color = Color(0.12, 0.14, 0.18)
	rsb.content_margin_left = 10.0
	rsb.content_margin_right = 10.0
	rsb.content_margin_top = 10.0
	rsb.content_margin_bottom = 10.0
	rsb.set_corner_radius_all(4)
	right_panel.add_theme_stylebox_override("panel", rsb)
	split.add_child(right_panel)

	var rvb = VBoxContainer.new()
	rvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rvb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(rvb)

	var desc_title = Label.new()
	desc_title.text = "Node Information:"
	desc_title.add_theme_font_size_override("font_size", 11)
	desc_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	rvb.add_child(desc_title)

	_desc_lbl = Label.new()
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_lbl.text = "Select a node on the left to view details."
	_desc_lbl.add_theme_font_size_override("font_size", 11)
	rvb.add_child(_desc_lbl)

	_refresh_list()

func _refresh_list() -> void:
	if _item_list == null:
		return
	_item_list.clear()
	var q = _filter_edit.text.strip_edges().to_lower() if _filter_edit != null else ""
	for i in range(NODES_DATA.size()):
		var data = NODES_DATA[i]
		var id_str: String = String(data.get("id", ""))
		var name_str: String = String(data.get("name", ""))
		var cat_str: String = String(data.get("category", ""))
		var desc_str: String = String(data.get("desc", ""))
		if q != "" and name_str.to_lower().find(q) < 0 and cat_str.to_lower().find(q) < 0 and desc_str.to_lower().find(q) < 0:
			continue
		var idx = _item_list.add_item(name_str + " [" + cat_str + "]")
		_item_list.set_item_metadata(idx, id_str)

	if _item_list.item_count > 0:
		_item_list.select(0)
		_on_item_selected(0)

func _on_item_selected(index: int) -> void:
	var id_str: String = String(_item_list.get_item_metadata(index))
	_selected_id = id_str
	for data in NODES_DATA:
		if String(data.get("id", "")) == id_str:
			_desc_lbl.text = "Name: " + String(data.get("name", "")) + "\n" + \
				"Category: " + String(data.get("category", "")) + "\n\n" + \
				String(data.get("desc", "")) + "\n\n" + \
				"Script: " + String(data.get("script", ""))
			return

func _on_confirmed() -> void:
	if _selected_id != "":
		node_spawn_requested.emit(_selected_id)
		if plugin != null and plugin.has_method("spawn_custom_node_by_id"):
			plugin.call("spawn_custom_node_by_id", _selected_id)
