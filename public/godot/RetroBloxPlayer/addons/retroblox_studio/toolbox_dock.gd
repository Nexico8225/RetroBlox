@tool
extends PanelContainer
## RetroBlox Studio — 1:1 Roblox Studio Toolbox & Dev Marketplace
## Features:
## - Custom Icon Picker (change icon when publishing or click 'Icon' on any item card!)
## - Thumbs Up Rating System (click Thumbs Up on any item to rate & sort by Most Thumbs Up!)
## - Model Filter & Sort Bar (Filter by All, Has Script, Verified, Top Rated, My Liked, Custom Icon; Sort by Featured, Most Thumbs Up, Newest, A-Z)
## - Guaranteed Popout Window Close (top-right Close X button + window close_requested signal)
## - Online Dev Cloud Sync + Share Codes (RBXTB:...)

const SERVER_URL: String = "https://retro-blox.vercel.app"
const CLOUD_TOOLBOX_CHANNEL: String = "retroblox_dev_toolbox_v2"
const BUILTIN_CATALOG_PATH: String = "res://toolbox/toolbox_catalog.json"
const PROJECT_PUBLISHED_DIR: String = "res://toolbox/published"
const PROJECT_SAVED_DIR: String = "res://toolbox/saved"
const PROJECT_SAVED_CATALOG: String = "res://toolbox/saved/saved_catalog.json"
const USER_SAVED_DIR: String = "user://retroblox_toolbox_models"
const USER_SAVED_CATALOG: String = "user://retroblox_toolbox_catalog.json"
const RATINGS_SAVE_PATH: String = "user://retroblox_toolbox_ratings.json"
const DELETED_ITEMS_SAVE_PATH: String = "user://retroblox_toolbox_deleted.json"

var plugin: EditorPlugin
var is_window_instance: bool = false
var peer_toolbox: Control = null

var _tab_buttons: Dictionary = {}
var _type_dropdown: OptionButton
var _search_box: LineEdit
var _sort_dropdown: OptionButton
var _filter_dropdown: OptionButton
var _breadcrumb_bar: HBoxContainer
var _breadcrumb_btn: Button
var _breadcrumb_lbl: Label
var _status_label: Label
var _content_vbox: VBoxContainer
var _bg_mode: String = "Dark" # Dark | White | Black
var _bg_buttons: Dictionary = {}

var _publish_window: AcceptDialog
var _pub_node_picker: OptionButton
var _pub_scene_nodes: Array[Node] = []
var _pub_title_input: LineEdit
var _pub_creator_input: LineEdit
var _pub_version_input: LineEdit
var _pub_cat_option: OptionButton
var _pub_subcat_option: OptionButton
var _pub_mode_option: OptionButton
var _pub_desc_input: TextEdit
var _pub_tags_input: LineEdit
var _pub_icon_preview: TextureRect
var _pub_icon_path_lbl: Label
var _pub_pending_icon_path: String = ""
var _pub_marketplace_check: CheckBox
var _pub_cloud_check: CheckBox
var _pub_overwrite_option: OptionButton
var _pub_target_fs_folder: String = ""
var _pub_icon_dialog: FileDialog

var _icon_file_dialog: FileDialog
var _icon_target_item_id: String = ""
var _share_import_dialog: AcceptDialog
var _share_code_input: TextEdit
var _upload_dialog: FileDialog
var _folder_dialog: FileDialog
var _rename_dialog: AcceptDialog
var _rename_input: LineEdit
var _renaming_item_id: String = ""

var _active_tab: String = "Marketplace" # Marketplace | Inventory | Recent | Creations
var _active_type_filter: String = "Models" # Models | Scripts | UI / GUIs | Decals | Meshes | Audio | ROBLOX Sets | All Types
var _active_subcat: String = "" # "" (Home) or VEHICLES | STRUCTURE | LIGHT | WEAPONS | SCRIPTS | UI | ALL_LIST
var _catalog_items: Array[Dictionary] = []
var _recent_ids: Array[String] = []
var _liked_ids: Dictionary = {}     # item_id -> true
var _likes_bonus: Dictionary = {}   # item_id -> int delta
var _custom_icons: Dictionary = {}  # item_id -> icon file path
var _deleted_item_ids: Dictionary = {} # item_id -> true
var _thumb_cache: Dictionary = {}
var _icon_cache: Dictionary = {}
var _shield_tex: Texture2D = null
var _thumb_up_tex: Texture2D = null


func _ready() -> void:
	name = "Toolbox"
	custom_minimum_size = Vector2(210, 240)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ensure_dirs()
	_load_ratings_state()
	_shield_tex = _build_shield_texture()
	_thumb_up_tex = _get_tab_icon("thumb_up")
	_build_ui()
	reload_catalog()
	call_deferred("_sync_from_cloud_marketplace", true)


func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROJECT_PUBLISHED_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROJECT_SAVED_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_SAVED_DIR))


func _load_ratings_state() -> void:
	if not FileAccess.file_exists(RATINGS_SAVE_PATH):
		return
	var f: FileAccess = FileAccess.open(RATINGS_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var d: Dictionary = parsed as Dictionary
		if d.get("liked") is Dictionary:
			_liked_ids = (d["liked"] as Dictionary).duplicate()
		if d.get("bonus") is Dictionary:
			_likes_bonus = (d["bonus"] as Dictionary).duplicate()
		if d.get("icons") is Dictionary:
			_custom_icons = (d["icons"] as Dictionary).duplicate()


func _save_ratings_state() -> void:
	var f: FileAccess = FileAccess.open(RATINGS_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"liked": _liked_ids,
		"bonus": _likes_bonus,
		"icons": _custom_icons,
	}, "\t"))


func _build_ui() -> void:
	var root_sb: StyleBoxFlat = StyleBoxFlat.new()
	root_sb.bg_color = Color(0.14, 0.14, 0.14, 1.0)
	root_sb.border_color = Color(0.08, 0.08, 0.08, 1.0)
	root_sb.set_border_width_all(1)
	root_sb.content_margin_left = 0.0
	root_sb.content_margin_right = 0.0
	root_sb.content_margin_top = 0.0
	root_sb.content_margin_bottom = 0.0
	add_theme_stylebox_override("panel", root_sb)

	var root_col: VBoxContainer = VBoxContainer.new()
	root_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_col.add_theme_constant_override("separation", 0)
	add_child(root_col)

	# ------------------------------------------------------------------------
	# 1. Top Title Bar ("Toolbox" + Publish + Popout / Close Window)
	# ------------------------------------------------------------------------
	var title_bar: PanelContainer = PanelContainer.new()
	var tsb: StyleBoxFlat = StyleBoxFlat.new()
	tsb.bg_color = Color(0.18, 0.18, 0.18, 1.0)
	tsb.content_margin_left = 8.0
	tsb.content_margin_right = 8.0
	tsb.content_margin_top = 4.0
	tsb.content_margin_bottom = 4.0
	title_bar.add_theme_stylebox_override("panel", tsb)
	root_col.add_child(title_bar)

	var title_hbox: HBoxContainer = HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 6)
	title_bar.add_child(title_hbox)

	var title_lbl: Label = Label.new()
	title_lbl.text = "Toolbox"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_hbox.add_child(title_lbl)

	var pub_top_btn: Button = _make_flat_btn("+ Publish", Color(0.0, 0.55, 0.88), Color.WHITE)
	pub_top_btn.tooltip_text = "Publish a Model, Script, UI/GUI, Folder, Decal, or Audio with custom icon!"
	pub_top_btn.pressed.connect(open_publish_dialog_for_selection)
	title_hbox.add_child(pub_top_btn)

	if not is_window_instance:
		var pop_btn: Button = _make_flat_btn("Popout", Color(0.24, 0.24, 0.24), Color(0.88, 0.88, 0.88))
		pop_btn.tooltip_text = "Open Toolbox in a large resizable window"
		pop_btn.pressed.connect(func() -> void:
			if plugin != null and plugin.has_method("_on_open_toolbox_window"):
				plugin.call("_on_open_toolbox_window")
		)
		title_hbox.add_child(pop_btn)
	else:
		var close_win_btn: Button = _make_flat_btn("Close (X)", Color(0.68, 0.18, 0.20), Color.WHITE)
		close_win_btn.tooltip_text = "Close this Popout Toolbox Window"
		close_win_btn.pressed.connect(_close_parent_window)
		title_hbox.add_child(close_win_btn)

	# ------------------------------------------------------------------------
	# 2. Roblox Studio 4 Icon Tabs (Marketplace | Inventory | Recent | Creations)
	# ------------------------------------------------------------------------
	var tabs_row: HBoxContainer = HBoxContainer.new()
	tabs_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_row.add_theme_constant_override("separation", 0)
	root_col.add_child(tabs_row)

	var tab_defs: Array[Dictionary] = [
		{"id": "Marketplace", "tip": "Marketplace — Dev & Roblox published models, scripts, UI, audio, decals", "icon": "bag"},
		{"id": "Inventory", "tip": "Inventory — Your saved, liked & acquired Toolbox items", "icon": "grid"},
		{"id": "Recent", "tip": "Recent — Recently inserted items", "icon": "clock"},
		{"id": "Creations", "tip": "Creations — Items you published for devs to use", "icon": "bulb"},
	]
	for tdef in tab_defs:
		var tab_id: String = String(tdef["id"])
		var icon_kind: String = String(tdef["icon"])
		var btn: Button = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(44, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = String(tdef["tip"])
		btn.icon = _get_tab_icon(icon_kind)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.pressed.connect(func() -> void:
			_active_tab = tab_id
			_update_tab_styles()
			_rebuild_content()
		)
		tabs_row.add_child(btn)
		_tab_buttons[tab_id] = btn
	_update_tab_styles()

	# ------------------------------------------------------------------------
	# 3. Search, Category Dropdown, Model Filter & Sort Bar
	# ------------------------------------------------------------------------
	var controls_pad: PanelContainer = PanelContainer.new()
	var cpsb: StyleBoxFlat = StyleBoxFlat.new()
	cpsb.bg_color = Color(0.16, 0.16, 0.16, 1.0)
	cpsb.border_width_bottom = 1
	cpsb.border_color = Color(0.10, 0.10, 0.10, 1.0)
	cpsb.content_margin_left = 8.0
	cpsb.content_margin_right = 8.0
	cpsb.content_margin_top = 6.0
	cpsb.content_margin_bottom = 6.0
	controls_pad.add_theme_stylebox_override("panel", cpsb)
	root_col.add_child(controls_pad)

	var controls_col: VBoxContainer = VBoxContainer.new()
	controls_col.add_theme_constant_override("separation", 5)
	controls_pad.add_child(controls_col)

	var search_row: HBoxContainer = HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 5)
	controls_col.add_child(search_row)

	var ddsb: StyleBoxFlat = StyleBoxFlat.new()
	ddsb.bg_color = Color(0.13, 0.13, 0.13, 1.0)
	ddsb.border_color = Color(0.28, 0.28, 0.28, 1.0)
	ddsb.set_border_width_all(1)
	ddsb.set_corner_radius_all(3)
	ddsb.content_margin_left = 6.0
	ddsb.content_margin_right = 6.0

	_type_dropdown = OptionButton.new()
	for t_name in ["Models", "Scripts", "UI / GUIs", "Folders", "ROBLOX Sets", "Decals", "Meshes", "Audio", "All Types"]:
		_type_dropdown.add_item(t_name)
	_type_dropdown.custom_minimum_size = Vector2(92, 28)
	_type_dropdown.add_theme_font_size_override("font_size", 12)
	_type_dropdown.add_theme_stylebox_override("normal", ddsb)
	_type_dropdown.item_selected.connect(func(idx: int) -> void:
		_active_type_filter = _type_dropdown.get_item_text(idx)
		_active_subcat = ""
		_rebuild_content()
	)
	search_row.add_child(_type_dropdown)

	_search_box = LineEdit.new()
	_search_box.placeholder_text = "Search"
	_search_box.clear_button_enabled = true
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.custom_minimum_size = Vector2(80, 28)
	_search_box.add_theme_font_size_override("font_size", 12)
	var ssb: StyleBoxFlat = StyleBoxFlat.new()
	ssb.bg_color = Color(0.11, 0.11, 0.11, 1.0)
	ssb.border_color = Color(0.28, 0.28, 0.28, 1.0)
	ssb.set_border_width_all(1)
	ssb.set_corner_radius_all(3)
	ssb.content_margin_left = 8.0
	ssb.content_margin_right = 8.0
	var sfocus: StyleBoxFlat = ssb.duplicate() as StyleBoxFlat
	sfocus.border_color = Color(0.0, 0.64, 1.0, 1.0)
	_search_box.add_theme_stylebox_override("normal", ssb)
	_search_box.add_theme_stylebox_override("focus", sfocus)
	_search_box.text_changed.connect(func(_t: String) -> void: _rebuild_content())
	search_row.add_child(_search_box)

	# Filter & Sort Row (Filter Models by Script/Verified/Top Rated/My Liked + Sort by Thumbs Up!)
	var filter_row: HFlowContainer = HFlowContainer.new()
	filter_row.add_theme_constant_override("h_separation", 5)
	filter_row.add_theme_constant_override("v_separation", 4)
	controls_col.add_child(filter_row)

	_filter_dropdown = OptionButton.new()
	for f_opt in ["Filter: All Items", "Filter: Has Script", "Filter: Verified Only", "Filter: Top Rated (50+)", "Filter: My Thumbs Up", "Filter: Custom Icon"]:
		_filter_dropdown.add_item(f_opt)
	_filter_dropdown.custom_minimum_size = Vector2(124, 24)
	_filter_dropdown.add_theme_font_size_override("font_size", 11)
	_filter_dropdown.add_theme_stylebox_override("normal", ddsb)
	_filter_dropdown.item_selected.connect(func(_idx: int) -> void:
		if _filter_dropdown.selected > 0 and _active_subcat == "":
			_active_subcat = "ALL_LIST"
		_rebuild_content()
	)
	filter_row.add_child(_filter_dropdown)

	_sort_dropdown = OptionButton.new()
	for s_opt in ["Sort: Featured", "Sort: Most Thumbs Up", "Sort: Newest", "Sort: A - Z"]:
		_sort_dropdown.add_item(s_opt)
	_sort_dropdown.custom_minimum_size = Vector2(124, 24)
	_sort_dropdown.add_theme_font_size_override("font_size", 11)
	_sort_dropdown.add_theme_stylebox_override("normal", ddsb)
	_sort_dropdown.item_selected.connect(func(_idx: int) -> void:
		if _sort_dropdown.selected > 0 and _active_subcat == "":
			_active_subcat = "ALL_LIST"
		_rebuild_content()
	)
	filter_row.add_child(_sort_dropdown)

	# Popular quick-search links
	var pop_flow: HFlowContainer = HFlowContainer.new()
	pop_flow.add_theme_constant_override("h_separation", 6)
	pop_flow.add_theme_constant_override("v_separation", 2)
	controls_col.add_child(pop_flow)

	var pop_lbl: Label = Label.new()
	pop_lbl.text = "Popular:"
	pop_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.62))
	pop_lbl.add_theme_font_size_override("font_size", 11)
	pop_flow.add_child(pop_lbl)

	for kw in ["GamePass", "Pine Tree", "Car", "Weapon", "Structure", "Light", "UI", "Script"]:
		var lbtn: LinkButton = LinkButton.new()
		lbtn.text = kw
		lbtn.underline = LinkButton.UNDERLINE_MODE_ALWAYS
		lbtn.add_theme_color_override("font_color", Color(0.42, 0.68, 1.0))
		lbtn.add_theme_font_size_override("font_size", 11)
		var captured_kw: String = kw
		lbtn.pressed.connect(func() -> void:
			_type_dropdown.selected = 7 # All Types
			_active_type_filter = "All Types"
			_search_box.text = captured_kw.to_lower()
			_rebuild_content()
		)
		pop_flow.add_child(lbtn)

	# ------------------------------------------------------------------------
	# 4. Breadcrumb Bar ("< All Models / Search Results for car")
	# ------------------------------------------------------------------------
	_breadcrumb_bar = HBoxContainer.new()
	_breadcrumb_bar.visible = false
	_breadcrumb_bar.add_theme_constant_override("separation", 4)
	controls_col.add_child(_breadcrumb_bar)

	_breadcrumb_btn = Button.new()
	_breadcrumb_btn.text = "< All Models"
	_breadcrumb_btn.flat = true
	_breadcrumb_btn.focus_mode = Control.FOCUS_NONE
	_breadcrumb_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_breadcrumb_btn.add_theme_color_override("font_hover_color", Color(0.32, 0.72, 1.0))
	_breadcrumb_btn.add_theme_font_size_override("font_size", 12)
	_breadcrumb_btn.pressed.connect(func() -> void:
		_active_subcat = ""
		_search_box.text = ""
		_filter_dropdown.selected = 0
		_sort_dropdown.selected = 0
		_rebuild_content()
	)
	_breadcrumb_bar.add_child(_breadcrumb_btn)

	_breadcrumb_lbl = Label.new()
	_breadcrumb_lbl.text = ""
	_breadcrumb_lbl.add_theme_color_override("font_color", Color.WHITE)
	_breadcrumb_lbl.add_theme_font_size_override("font_size", 12)
	_breadcrumb_bar.add_child(_breadcrumb_lbl)

	# ------------------------------------------------------------------------
	# 5. Main Scrollable Viewport
	# ------------------------------------------------------------------------
	var main_scroll: ScrollContainer = ScrollContainer.new()
	main_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root_col.add_child(main_scroll)

	var pad_margin: MarginContainer = MarginContainer.new()
	pad_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad_margin.add_theme_constant_override("margin_left", 8)
	pad_margin.add_theme_constant_override("margin_right", 8)
	pad_margin.add_theme_constant_override("margin_top", 8)
	pad_margin.add_theme_constant_override("margin_bottom", 8)
	main_scroll.add_child(pad_margin)

	_content_vbox = VBoxContainer.new()
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_vbox.add_theme_constant_override("separation", 10)
	pad_margin.add_child(_content_vbox)

	# ------------------------------------------------------------------------
	# 6. Status & Bottom Background Bar ("Background: [Dark] [White] [Black]" + Cloud Sync)
	# ------------------------------------------------------------------------
	var footer_panel: PanelContainer = PanelContainer.new()
	var fsb: StyleBoxFlat = StyleBoxFlat.new()
	fsb.bg_color = Color(0.17, 0.17, 0.17, 1.0)
	fsb.border_width_top = 1
	fsb.border_color = Color(0.10, 0.10, 0.10, 1.0)
	fsb.content_margin_left = 8.0
	fsb.content_margin_right = 8.0
	fsb.content_margin_top = 5.0
	fsb.content_margin_bottom = 5.0
	footer_panel.add_theme_stylebox_override("panel", fsb)
	root_col.add_child(footer_panel)

	var footer_col: VBoxContainer = VBoxContainer.new()
	footer_col.add_theme_constant_override("separation", 4)
	footer_panel.add_child(footer_col)

	_status_label = Label.new()
	_status_label.text = "Click any item to insert, rate with Thumbs Up, or click 'Icon' to customize its icon!"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.95))
	_status_label.add_theme_font_size_override("font_size", 11)
	footer_col.add_child(_status_label)

	var bg_flow: HFlowContainer = HFlowContainer.new()
	bg_flow.add_theme_constant_override("h_separation", 4)
	bg_flow.add_theme_constant_override("v_separation", 4)
	footer_col.add_child(bg_flow)

	var bg_lbl: Label = Label.new()
	bg_lbl.text = "Background:"
	bg_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	bg_lbl.add_theme_font_size_override("font_size", 11)
	bg_flow.add_child(bg_lbl)

	for mode_name in ["Dark", "White", "Black"]:
		var bbtn: Button = Button.new()
		bbtn.text = mode_name
		bbtn.custom_minimum_size = Vector2(46, 22)
		bbtn.focus_mode = Control.FOCUS_NONE
		bbtn.add_theme_font_size_override("font_size", 10)
		var captured_mode: String = mode_name
		bbtn.pressed.connect(func() -> void:
			_bg_mode = captured_mode
			_update_bg_button_styles()
			_rebuild_content()
		)
		bg_flow.add_child(bbtn)
		_bg_buttons[mode_name] = bbtn
	_update_bg_button_styles()

	var sync_btn: Button = _make_flat_btn("Sync Online", Color(0.18, 0.36, 0.24), Color(0.75, 1.0, 0.82))
	sync_btn.tooltip_text = "Fetch newly published dev creations from the RetroBlox Online Marketplace."
	sync_btn.pressed.connect(func() -> void: _sync_from_cloud_marketplace(false))
	bg_flow.add_child(sync_btn)

	var code_btn: Button = _make_flat_btn("Import Code", Color(0.24, 0.24, 0.34), Color(0.85, 0.88, 1.0))
	code_btn.tooltip_text = "Paste a Dev Share Code (RBXTB:...) from another developer to import their asset."
	code_btn.pressed.connect(func() -> void: _share_import_dialog.popup_centered(Vector2i(420, 240)))
	bg_flow.add_child(code_btn)

	_build_publish_dialog()
	_build_upload_and_rename_dialogs()


func _close_parent_window() -> void:
	var p: Node = get_parent()
	while p != null:
		if p is Window:
			(p as Window).hide()
			return
		p = p.get_parent()
	if plugin != null and plugin.has_method("_on_close_toolbox_window"):
		plugin.call("_on_close_toolbox_window")


# ============================================================================
# PROCEDURAL ROBLOX STUDIO ICONS, CUSTOM ICON LOADER & THUMBNAIL RENDERER
# ============================================================================

func _get_tab_icon(kind: String) -> Texture2D:
	if _icon_cache.has(kind):
		return _icon_cache[kind] as Texture2D
	var img: Image = Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c: Color = Color(0.92, 0.92, 0.92, 1.0)
	if kind == "bag":
		img.fill_rect(Rect2i(4, 7, 12, 10), c)
		img.fill_rect(Rect2i(7, 4, 6, 2), c)
		img.fill_rect(Rect2i(6, 5, 2, 2), c)
		img.fill_rect(Rect2i(12, 5, 2, 2), c)
	elif kind == "grid":
		img.fill_rect(Rect2i(4, 4, 5, 5), c)
		img.fill_rect(Rect2i(11, 4, 5, 5), c)
		img.fill_rect(Rect2i(4, 11, 5, 5), c)
		img.fill_rect(Rect2i(11, 11, 5, 5), c)
	elif kind == "clock":
		for y in range(20):
			for x in range(20):
				var d: float = Vector2(x - 9.5, y - 9.5).length()
				if d <= 7.5 and d >= 5.2:
					img.set_pixel(x, y, c)
		img.fill_rect(Rect2i(9, 5, 2, 5), c)
		img.fill_rect(Rect2i(9, 9, 4, 2), c)
	elif kind == "bulb":
		for y in range(20):
			for x in range(20):
				var d: float = Vector2(x - 9.5, y - 7.5).length()
				if d <= 5.2:
					img.set_pixel(x, y, c)
		img.fill_rect(Rect2i(7, 12, 6, 3), c)
		img.fill_rect(Rect2i(8, 16, 4, 2), c)
	elif kind == "thumb_up":
		img = Image.create(14, 14, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var g: Color = Color(0.32, 0.88, 0.45, 1.0)
		img.fill_rect(Rect2i(2, 6, 3, 6), g)
		img.fill_rect(Rect2i(6, 6, 6, 6), g)
		img.fill_rect(Rect2i(7, 2, 2, 4), g)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_icon_cache[kind] = tex
	return tex


func _build_shield_texture() -> Texture2D:
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var gold: Color = Color(1.0, 0.72, 0.12, 1.0)
	var white: Color = Color(1.0, 0.98, 0.90, 1.0)
	for y in range(2, 14):
		var half_w: int = 6 if y < 8 else maxi(1, 6 - (y - 7))
		for x in range(8 - half_w, 8 + half_w):
			img.set_pixel(x, y, gold)
	img.fill_rect(Rect2i(6, 5, 4, 4), white)
	return ImageTexture.create_from_image(img)


func _load_texture_from_any_path(icon_p: String) -> Texture2D:
	if icon_p == "":
		return null
	if _thumb_cache.has("file:" + icon_p):
		return _thumb_cache["file:" + icon_p] as Texture2D
	var glob_p: String = ProjectSettings.globalize_path(icon_p)
	var load_p: String = glob_p if FileAccess.file_exists(glob_p) else icon_p
	if FileAccess.file_exists(load_p):
		var img: Image = Image.load_from_file(load_p)
		if img != null and not img.is_empty():
			if img.get_width() != 128 or img.get_height() != 128:
				img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
			var tex: ImageTexture = ImageTexture.create_from_image(img)
			_thumb_cache["file:" + icon_p] = tex
			return tex
	if icon_p.begins_with("res://") and ResourceLoader.exists(icon_p):
		var r: Resource = load(icon_p)
		if r is Texture2D:
			var r_img: Image = (r as Texture2D).get_image()
			if r_img != null and not r_img.is_empty():
				if r_img.get_width() != 128 or r_img.get_height() != 128:
					r_img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
				var tex: ImageTexture = ImageTexture.create_from_image(r_img)
				_thumb_cache["file:" + icon_p] = tex
				return tex
			_thumb_cache["file:" + icon_p] = r
			return r as Texture2D
	return null


func _get_item_thumbnail(item: Dictionary) -> Texture2D:
	var item_id: String = String(item.get("id", ""))
	# 1. Check user-customized icon override first!
	if item_id != "" and _custom_icons.has(item_id):
		var custom_p: String = String(_custom_icons[item_id])
		var ctex: Texture2D = _load_texture_from_any_path(custom_p)
		if ctex != null:
			return ctex

	# 2. Check item's own icon_path field
	var icon_p: String = String(item.get("icon_path", ""))
	if icon_p != "":
		var itex: Texture2D = _load_texture_from_any_path(icon_p)
		if itex != null:
			return itex

	var kind: String = String(item.get("thumb_kind", ""))
	if kind == "":
		var cat: String = String(item.get("category", "Models"))
		var nm: String = String(item.get("name", "")).to_lower()
		if nm.find("tree") >= 0 or nm.find("pine") >= 0:
			kind = "pine_tree"
		elif nm.find("car") >= 0 or nm.find("vehicle") >= 0 or nm.find("truck") >= 0:
			kind = "car"
		elif nm.find("tower") >= 0 or nm.find("house") >= 0 or nm.find("building") >= 0:
			kind = "watchtower"
		elif nm.find("light") >= 0 or nm.find("lamp") >= 0:
			kind = "street_lamp"
		elif cat == "UI / GUIs" or String(item.get("type", "")) == "ui":
			kind = "ui_shop"
		elif cat == "Scripts" or String(item.get("type", "")) == "script":
			kind = "script"
		elif cat == "Folders" or String(item.get("type", "")) == "folder" or nm.find("folder") >= 0 or nm.find("kit") >= 0 or nm.find("set") >= 0:
			kind = "folder"
		else:
			kind = "custom_model_" + (item_id if item_id != "" else "default")

	if _thumb_cache.has(kind):
		return _thumb_cache[kind] as Texture2D

	var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	if kind == "pine_tree" or kind == "tall_pine":
		img.fill_rect(Rect2i(28, 46, 8, 14), Color(0.45, 0.28, 0.14))
		_draw_triangle(img, Vector2i(32, 22), Vector2i(12, 48), Vector2i(52, 48), Color(0.18, 0.48, 0.22))
		_draw_triangle(img, Vector2i(32, 13), Vector2i(16, 36), Vector2i(48, 36), Color(0.22, 0.56, 0.26))
		_draw_triangle(img, Vector2i(32, 6), Vector2i(20, 24), Vector2i(44, 24), Color(0.26, 0.64, 0.30))
	elif kind == "snowy_pine":
		img.fill_rect(Rect2i(29, 46, 6, 13), Color(0.38, 0.24, 0.14))
		_draw_triangle(img, Vector2i(32, 22), Vector2i(14, 48), Vector2i(50, 48), Color(0.22, 0.46, 0.32))
		_draw_triangle(img, Vector2i(32, 20), Vector2i(18, 38), Vector2i(46, 38), Color(0.90, 0.95, 1.0))
		_draw_triangle(img, Vector2i(32, 8), Vector2i(20, 26), Vector2i(44, 26), Color(0.94, 0.98, 1.0))
	elif kind == "watchtower":
		img.fill_rect(Rect2i(12, 52, 40, 5), Color(0.55, 0.57, 0.60))
		img.fill_rect(Rect2i(18, 22, 4, 30), Color(0.52, 0.34, 0.18))
		img.fill_rect(Rect2i(42, 22, 4, 30), Color(0.52, 0.34, 0.18))
		img.fill_rect(Rect2i(16, 20, 32, 5), Color(0.66, 0.46, 0.26))
		img.fill_rect(Rect2i(18, 34, 28, 3), Color(0.48, 0.30, 0.16))
		_draw_triangle(img, Vector2i(32, 8), Vector2i(13, 20), Vector2i(51, 20), Color(0.24, 0.26, 0.28))
	elif kind == "street_lamp":
		img.fill_rect(Rect2i(30, 14, 4, 44), Color(0.45, 0.48, 0.52))
		img.fill_rect(Rect2i(16, 12, 32, 4), Color(0.55, 0.58, 0.62))
		img.fill_rect(Rect2i(14, 15, 6, 4), Color(1.0, 0.92, 0.45))
		img.fill_rect(Rect2i(44, 15, 6, 4), Color(1.0, 0.92, 0.45))
	elif kind == "car":
		img.fill_rect(Rect2i(10, 30, 44, 14), Color(0.12, 0.36, 0.92))
		img.fill_rect(Rect2i(18, 20, 24, 11), Color(0.45, 0.78, 0.98))
		img.fill_rect(Rect2i(46, 31, 8, 12), Color(0.98, 0.84, 0.12))
		img.fill_rect(Rect2i(14, 40, 10, 10), Color(0.15, 0.15, 0.17))
		img.fill_rect(Rect2i(40, 40, 10, 10), Color(0.15, 0.15, 0.17))
	elif kind == "crashed_car":
		img.fill_rect(Rect2i(12, 34, 40, 13), Color(0.28, 0.26, 0.24))
		_draw_triangle(img, Vector2i(32, 12), Vector2i(20, 35), Vector2i(46, 35), Color(1.0, 0.42, 0.08))
		_draw_triangle(img, Vector2i(32, 18), Vector2i(25, 34), Vector2i(39, 34), Color(1.0, 0.82, 0.18))
	elif kind == "fence":
		img.fill_rect(Rect2i(10, 22, 5, 26), Color(0.58, 0.38, 0.20))
		img.fill_rect(Rect2i(30, 22, 5, 26), Color(0.58, 0.38, 0.20))
		img.fill_rect(Rect2i(49, 22, 5, 26), Color(0.58, 0.38, 0.20))
		img.fill_rect(Rect2i(8, 27, 48, 4), Color(0.66, 0.44, 0.24))
		img.fill_rect(Rect2i(8, 37, 48, 4), Color(0.66, 0.44, 0.24))
	elif kind == "teleport":
		img.fill_rect(Rect2i(8, 26, 20, 16), Color(0.22, 0.76, 0.36))
		img.fill_rect(Rect2i(36, 26, 20, 16), Color(0.96, 0.34, 0.34))
	elif kind == "spawn":
		img.fill_rect(Rect2i(10, 24, 44, 20), Color(0.75, 0.77, 0.80))
		img.fill_rect(Rect2i(10, 40, 44, 6), Color(0.52, 0.54, 0.58))
		img.fill_rect(Rect2i(24, 28, 16, 10), Color(0.22, 0.24, 0.28))
	elif kind == "invisible_spawn":
		img.fill_rect(Rect2i(12, 26, 40, 18), Color(0.35, 0.55, 0.75, 0.35))
	elif kind == "sign":
		img.fill_rect(Rect2i(30, 32, 4, 22), Color(0.55, 0.36, 0.18))
		img.fill_rect(Rect2i(14, 16, 36, 18), Color(0.72, 0.52, 0.30))
		img.fill_rect(Rect2i(18, 22, 28, 3), Color(0.20, 0.16, 0.12))
		img.fill_rect(Rect2i(22, 27, 20, 3), Color(0.20, 0.16, 0.12))
	elif kind == "lava_bar":
		img.fill_rect(Rect2i(8, 28, 48, 8), Color(1.0, 0.32, 0.08))
		img.fill_rect(Rect2i(26, 22, 12, 20), Color(0.30, 0.32, 0.36))
	elif kind == "sliding_door":
		img.fill_rect(Rect2i(12, 10, 40, 46), Color(0.28, 0.32, 0.38))
		img.fill_rect(Rect2i(16, 14, 15, 40), Color(0.32, 0.78, 0.96))
		img.fill_rect(Rect2i(33, 14, 15, 40), Color(0.32, 0.78, 0.96))
	elif kind == "gold_coin":
		for y in range(12, 52):
			for x in range(12, 52):
				if Vector2(x - 32, y - 32).length() <= 18.0:
					img.set_pixel(x, y, Color(1.0, 0.84, 0.16))
		img.fill_rect(Rect2i(29, 22, 6, 20), Color(0.82, 0.60, 0.06))
	elif kind == "conveyor":
		img.fill_rect(Rect2i(10, 22, 44, 22), Color(0.22, 0.24, 0.28))
		img.fill_rect(Rect2i(18, 29, 28, 8), Color(0.95, 0.78, 0.18))
	elif kind == "sword_stand":
		img.fill_rect(Rect2i(18, 42, 28, 12), Color(0.55, 0.58, 0.64))
		img.fill_rect(Rect2i(30, 10, 4, 28), Color(0.82, 0.88, 0.96))
		img.fill_rect(Rect2i(24, 32, 16, 4), Color(0.96, 0.78, 0.16))
	elif kind == "obby":
		img.fill_rect(Rect2i(8, 38, 14, 8), Color(0.20, 0.68, 0.96))
		img.fill_rect(Rect2i(25, 28, 14, 8), Color(0.96, 0.76, 0.18))
		img.fill_rect(Rect2i(42, 18, 14, 8), Color(0.24, 0.84, 0.42))
	elif kind.begins_with("ui_"):
		img.fill_rect(Rect2i(10, 14, 44, 36), Color(0.16, 0.22, 0.34))
		img.fill_rect(Rect2i(10, 14, 44, 8), Color(0.58, 0.34, 0.88))
		img.fill_rect(Rect2i(16, 28, 32, 6), Color(0.28, 0.78, 0.46))
		img.fill_rect(Rect2i(16, 38, 22, 6), Color(0.96, 0.78, 0.22))
	elif kind == "script":
		img.fill_rect(Rect2i(16, 10, 32, 44), Color(0.18, 0.32, 0.48))
		img.fill_rect(Rect2i(20, 18, 20, 3), Color(0.48, 0.86, 1.0))
		img.fill_rect(Rect2i(20, 25, 24, 3), Color(0.75, 0.92, 1.0))
		img.fill_rect(Rect2i(20, 32, 16, 3), Color(1.0, 0.84, 0.32))
		img.fill_rect(Rect2i(20, 39, 22, 3), Color(0.55, 0.94, 0.64))
	elif kind == "folder":
		img.fill_rect(Rect2i(10, 14, 20, 8), Color(0.92, 0.72, 0.20))
		img.fill_rect(Rect2i(10, 20, 44, 30), Color(0.98, 0.82, 0.30))
		img.fill_rect(Rect2i(10, 26, 44, 24), Color(1.0, 0.88, 0.42))
		img.fill_rect(Rect2i(14, 32, 26, 2), Color(0.85, 0.65, 0.18))
		img.fill_rect(Rect2i(14, 37, 20, 2), Color(0.85, 0.65, 0.18))
	else:
		var h: int = kind.hash()
		var col: Color = Color.from_hsv(float(abs(h) % 360) / 360.0, 0.68, 0.92)
		img.fill_rect(Rect2i(16, 18, 32, 30), col)
		img.fill_rect(Rect2i(20, 12, 24, 8), col.lightened(0.22))
		img.fill_rect(Rect2i(26, 26, 12, 12), Color(1, 1, 1, 0.35))

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_thumb_cache[kind] = tex
	return tex


func _draw_triangle(img: Image, p0: Vector2i, p1: Vector2i, p2: Vector2i, col: Color) -> void:
	var min_y: int = clampi(mini(p0.y, mini(p1.y, p2.y)), 0, img.get_height() - 1)
	var max_y: int = clampi(maxi(p0.y, maxi(p1.y, p2.y)), 0, img.get_height() - 1)
	var min_x: int = clampi(mini(p0.x, mini(p1.x, p2.x)), 0, img.get_width() - 1)
	var max_x: int = clampi(maxi(p0.x, maxi(p1.x, p2.x)), 0, img.get_width() - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var v0: Vector2 = Vector2(p2 - p0)
			var v1: Vector2 = Vector2(p1 - p0)
			var v2: Vector2 = Vector2(x - p0.x, y - p0.y)
			var dot00: float = v0.dot(v0)
			var dot01: float = v0.dot(v1)
			var dot02: float = v0.dot(v2)
			var dot11: float = v1.dot(v1)
			var dot12: float = v1.dot(v2)
			var denom: float = dot00 * dot11 - dot01 * dot01
			if absf(denom) > 0.0001:
				var u: float = (dot11 * dot02 - dot01 * dot12) / denom
				var v: float = (dot00 * dot12 - dot01 * dot02) / denom
				if u >= 0.0 and v >= 0.0 and (u + v) <= 1.0:
					img.set_pixel(x, y, col)


# ============================================================================
# HOME VIEW ("Categories", "Trending", "Essential") & SEARCH/CATEGORY GRID VIEW
# ============================================================================

func _rebuild_content() -> void:
	if _content_vbox == null:
		return
	for ch in _content_vbox.get_children():
		ch.queue_free()

	var q: String = _search_box.text.strip_edges() if _search_box != null else ""
	var has_custom_filter: bool = (_filter_dropdown != null and _filter_dropdown.selected > 0) or (_sort_dropdown != null and _sort_dropdown.selected > 0)
	var is_marketplace_home: bool = (_active_tab == "Marketplace" and q == "" and _active_subcat == "" and _active_type_filter == "Models" and not has_custom_filter)

	if is_marketplace_home:
		_breadcrumb_bar.visible = false
		_build_marketplace_home_view()
		return

	_breadcrumb_bar.visible = true
	_breadcrumb_btn.text = "< All " + _active_type_filter
	if q != "":
		_breadcrumb_lbl.text = "/ Search Results for " + q
	elif _active_subcat != "" and _active_subcat != "ALL_LIST":
		_breadcrumb_lbl.text = "/ " + _active_subcat.capitalize()
	elif _active_tab != "Marketplace":
		_breadcrumb_lbl.text = "/ " + _active_tab
	else:
		_breadcrumb_lbl.text = ""

	if _active_tab == "Creations":
		var create_bar: HFlowContainer = HFlowContainer.new()
		create_bar.add_theme_constant_override("h_separation", 6)
		create_bar.add_theme_constant_override("v_separation", 4)
		_content_vbox.add_child(create_bar)

		var pub_new_btn: Button = _make_flat_btn("+ Publish Selected Node / Scene", Color(0.0, 0.56, 0.88), Color.WHITE)
		pub_new_btn.pressed.connect(open_publish_dialog_for_selection)
		create_bar.add_child(pub_new_btn)

		var up_dir_btn: Button = _make_flat_btn("📁 Publish Folder...", Color(0.24, 0.45, 0.65), Color.WHITE)
		up_dir_btn.tooltip_text = "Select a folder on disk to package and publish with all files inside"
		up_dir_btn.pressed.connect(_on_upload_folder_pressed)
		create_bar.add_child(up_dir_btn)

		var up_new_btn: Button = _make_flat_btn("Upload File...", Color(0.18, 0.42, 0.28), Color.WHITE)
		up_new_btn.pressed.connect(_on_upload_pressed)
		create_bar.add_child(up_new_btn)

	var filtered: Array[Dictionary] = _get_filtered_items()
	var grid: HFlowContainer = HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	_content_vbox.add_child(grid)

	for item in filtered:
		grid.add_child(_build_thumbnail_tile(item))

	if filtered.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.custom_minimum_size = Vector2(200, 60)
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if _active_tab == "Creations":
			empty_lbl.text = "You haven't published any creations yet.\nClick '+ Publish Selected Node / Scene' above to publish a Model, Script, UI/GUI, or Folder for devs to use!"
		elif _active_tab == "Recent":
			empty_lbl.text = "No recently inserted items yet. Click any item in Marketplace to insert it!"
		else:
			empty_lbl.text = "No items matched your current search or filter."
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		empty_lbl.add_theme_font_size_override("font_size", 12)
		_content_vbox.add_child(empty_lbl)


func _build_marketplace_home_view() -> void:
	_content_vbox.add_child(_make_section_header("Categories", func() -> void:
		_active_subcat = "ALL_LIST"
		_rebuild_content()
	))

	var cat_grid: HFlowContainer = HFlowContainer.new()
	cat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_grid.add_theme_constant_override("h_separation", 8)
	cat_grid.add_theme_constant_override("v_separation", 8)
	_content_vbox.add_child(cat_grid)

	var cat_cards: Array[Dictionary] = [
		{"title": "VEHICLES", "subcat": "VEHICLES", "type": "Models", "bg": Color(0.66, 0.22, 0.22), "thumb": "car"},
		{"title": "STRUCTURE", "subcat": "STRUCTURE", "type": "Models", "bg": Color(0.32, 0.72, 0.78), "thumb": "watchtower"},
		{"title": "LIGHT", "subcat": "LIGHT", "type": "Models", "bg": Color(0.72, 0.75, 0.78), "thumb": "street_lamp"},
		{"title": "WEAPONS", "subcat": "WEAPONS", "type": "Models", "bg": Color(0.76, 0.42, 0.16), "thumb": "sword_stand"},
		{"title": "SCRIPTS", "subcat": "SCRIPTS", "type": "Scripts", "bg": Color(0.20, 0.40, 0.72), "thumb": "script"},
		{"title": "UI & GUIS", "subcat": "UI", "type": "UI / GUIs", "bg": Color(0.46, 0.26, 0.68), "thumb": "ui_shop"},
	]
	for cc in cat_cards:
		cat_grid.add_child(_build_category_banner_tile(cc))

	var dev_items: Array[Dictionary] = []
	for item in _catalog_items:
		if not bool(item.get("builtin", false)) and bool(item.get("published", true)):
			dev_items.append(item)
	if not dev_items.is_empty():
		_content_vbox.add_child(_make_section_header("Community Dev Published", func() -> void:
			_active_tab = "Creations"
			_update_tab_styles()
			_rebuild_content()
		))
		var dev_grid: HFlowContainer = HFlowContainer.new()
		dev_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dev_grid.add_theme_constant_override("h_separation", 10)
		dev_grid.add_theme_constant_override("v_separation", 10)
		_content_vbox.add_child(dev_grid)
		for ditem in dev_items:
			dev_grid.add_child(_build_thumbnail_tile(ditem))

	_content_vbox.add_child(_make_section_header("Trending", func() -> void:
		_active_subcat = "ALL_LIST"
		_rebuild_content()
	))
	var trend_grid: HFlowContainer = HFlowContainer.new()
	trend_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trend_grid.add_theme_constant_override("h_separation", 10)
	trend_grid.add_theme_constant_override("v_separation", 10)
	_content_vbox.add_child(trend_grid)
	for item in _catalog_items:
		if String(item.get("section", "")) == "Trending":
			trend_grid.add_child(_build_thumbnail_tile(item))

	_content_vbox.add_child(_make_section_header("Essential", func() -> void:
		_active_subcat = "ALL_LIST"
		_rebuild_content()
	))
	var ess_grid: HFlowContainer = HFlowContainer.new()
	ess_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ess_grid.add_theme_constant_override("h_separation", 10)
	ess_grid.add_theme_constant_override("v_separation", 10)
	_content_vbox.add_child(ess_grid)
	for item in _catalog_items:
		if String(item.get("section", "")) == "Essential":
			ess_grid.add_child(_build_thumbnail_tile(item))


func _make_section_header(title_txt: String, on_see_all: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl: Label = Label.new()
	lbl.text = title_txt
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl)

	var see_btn: Button = Button.new()
	see_btn.text = "See All >"
	see_btn.flat = true
	see_btn.focus_mode = Control.FOCUS_NONE
	see_btn.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68))
	see_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	see_btn.add_theme_font_size_override("font_size", 11)
	see_btn.pressed.connect(on_see_all)
	row.add_child(see_btn)
	return row


func _build_category_banner_tile(cc: Dictionary) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(92, 102)
	btn.focus_mode = Control.FOCUS_NONE
	var bg_col: Color = cc["bg"] as Color
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.border_color = bg_col.lightened(0.22)
	var hov: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	hov.bg_color = bg_col.lightened(0.12)
	hov.border_color = Color.WHITE
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", sb)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(vbox)

	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.texture = _get_item_thumbnail({"thumb_kind": String(cc["thumb"])})
	icon_rect.custom_minimum_size = Vector2(56, 56)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_rect)

	var lbl: Label = Label.new()
	lbl.text = String(cc["title"])
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl)

	var subcat_str: String = String(cc["subcat"])
	var type_str: String = String(cc["type"])
	btn.pressed.connect(func() -> void:
		_active_subcat = subcat_str
		_active_type_filter = type_str
		for i in range(_type_dropdown.item_count):
			if _type_dropdown.get_item_text(i) == type_str:
				_type_dropdown.selected = i
				break
		_rebuild_content()
	)
	return btn


func _get_item_likes(item: Dictionary) -> int:
	var item_id: String = String(item.get("id", ""))
	var base_likes: int = int(item.get("thumbs_up", 12))
	var bonus: int = int(_likes_bonus.get(item_id, 0))
	return maxi(0, base_likes + bonus)


func _toggle_thumbs_up(item: Dictionary) -> void:
	var item_id: String = String(item.get("id", ""))
	if item_id == "":
		return
	var currently_liked: bool = bool(_liked_ids.get(item_id, false))
	var cur_bonus: int = int(_likes_bonus.get(item_id, 0))
	if currently_liked:
		_liked_ids.erase(item_id)
		_likes_bonus[item_id] = cur_bonus - 1
		_set_status("Removed Thumbs Up from '%s'." % String(item.get("name", "")), Color(0.75, 0.78, 0.84))
	else:
		_liked_ids[item_id] = true
		_likes_bonus[item_id] = cur_bonus + 1
		_set_status("Gave a Thumbs Up to '%s'!" % String(item.get("name", "")), Color(0.45, 0.96, 0.58))
	_save_ratings_state()
	_rebuild_content()


func _build_thumbnail_tile(item: Dictionary) -> VBoxContainer:
	var tile: VBoxContainer = VBoxContainer.new()
	tile.custom_minimum_size = Vector2(96, 162)
	tile.clip_contents = true
	tile.add_theme_constant_override("separation", 3)
	var captured: Dictionary = item.duplicate()
	var item_id: String = String(captured.get("id", ""))
	var is_builtin: bool = bool(captured.get("builtin", false))
	var likes_count: int = _get_item_likes(captured)
	var is_liked: bool = bool(_liked_ids.get(item_id, false))

	var thumb_container: PanelContainer = PanelContainer.new()
	thumb_container.custom_minimum_size = Vector2(92, 92)
	thumb_container.clip_contents = true
	var tsb: StyleBoxFlat = StyleBoxFlat.new()
	if _bg_mode == "White":
		tsb.bg_color = Color(0.95, 0.96, 0.98, 1.0)
	elif _bg_mode == "Black":
		tsb.bg_color = Color(0.05, 0.05, 0.06, 1.0)
	else:
		tsb.bg_color = Color(0.11, 0.11, 0.11, 1.0)
	tsb.set_corner_radius_all(4)
	tsb.set_border_width_all(1)
	tsb.border_color = Color(0.24, 0.24, 0.24, 1.0)
	thumb_container.add_theme_stylebox_override("panel", tsb)
	tile.add_child(thumb_container)

	var tex_rect: TextureRect = TextureRect.new()
	tex_rect.texture = _get_item_thumbnail(captured)
	tex_rect.custom_minimum_size = Vector2(80, 80)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_rect.offset_left = 6.0
	tex_rect.offset_top = 6.0
	tex_rect.offset_right = -6.0
	tex_rect.offset_bottom = -6.0
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_container.add_child(tex_rect)

	var thumb_btn: Button = Button.new()
	thumb_btn.custom_minimum_size = Vector2(92, 92)
	thumb_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	thumb_btn.focus_mode = Control.FOCUS_NONE
	thumb_btn.flat = true
	thumb_btn.tooltip_text = "%s\nby %s (v%s) — %d Thumbs Up\n%s\n\nClick to Insert into Scene!" % [
		String(captured.get("name", "Asset")),
		String(captured.get("creator", "RetroBlox")),
		String(captured.get("version", "1.0")),
		likes_count,
		String(captured.get("description", ""))
	]
	var thov: StyleBoxFlat = StyleBoxFlat.new()
	thov.bg_color = Color(0, 0, 0, 0)
	thov.border_color = Color(0.0, 0.64, 1.0, 1.0)
	thov.set_border_width_all(2)
	thov.set_corner_radius_all(4)
	thumb_btn.add_theme_stylebox_override("hover", thov)
	thumb_btn.add_theme_stylebox_override("pressed", thov)
	thumb_btn.pressed.connect(func() -> void: _insert_toolbox_item(captured))
	thumb_container.add_child(thumb_btn)

	if bool(captured.get("verified", true)):
		var shield_rect: TextureRect = TextureRect.new()
		shield_rect.texture = _shield_tex
		shield_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shield_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shield_rect.custom_minimum_size = Vector2(16, 16)
		shield_rect.size = Vector2(16, 16)
		shield_rect.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		shield_rect.offset_left = -20.0
		shield_rect.offset_top = -20.0
		shield_rect.offset_right = -4.0
		shield_rect.offset_bottom = -4.0
		shield_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb_container.add_child(shield_rect)

	var name_btn: Button = Button.new()
	var raw_title: String = String(captured.get("name", "Asset"))
	name_btn.text = raw_title if raw_title.length() <= 14 else (raw_title.substr(0, 12) + "...")
	name_btn.flat = true
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.focus_mode = Control.FOCUS_NONE
	name_btn.tooltip_text = raw_title + " — Click to Insert"
	name_btn.add_theme_color_override("font_color", Color(0.28, 0.64, 1.0))
	name_btn.add_theme_color_override("font_hover_color", Color(0.55, 0.82, 1.0))
	name_btn.add_theme_font_size_override("font_size", 11)
	name_btn.pressed.connect(func() -> void: _insert_toolbox_item(captured))
	tile.add_child(name_btn)

	var by_lbl: Label = Label.new()
	by_lbl.text = "by " + String(captured.get("creator", "RetroBlox"))
	by_lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62))
	by_lbl.add_theme_font_size_override("font_size", 10)
	tile.add_child(by_lbl)

	# Thumbs Up Rating Button + Icon Changer Button Row
	var rate_row: HFlowContainer = HFlowContainer.new()
	rate_row.add_theme_constant_override("h_separation", 3)
	rate_row.add_theme_constant_override("v_separation", 2)
	tile.add_child(rate_row)

	var like_btn: Button = Button.new()
	like_btn.icon = _thumb_up_tex
	like_btn.text = str(likes_count)
	like_btn.focus_mode = Control.FOCUS_NONE
	like_btn.custom_minimum_size = Vector2(46, 20)
	like_btn.tooltip_text = "Click to rate '%s' with a Thumbs Up!" % raw_title
	var lsb: StyleBoxFlat = StyleBoxFlat.new()
	lsb.bg_color = Color(0.14, 0.42, 0.22, 1.0) if is_liked else Color(0.18, 0.19, 0.22, 1.0)
	lsb.border_color = Color(0.32, 0.85, 0.45, 1.0) if is_liked else Color(0.28, 0.30, 0.34, 1.0)
	lsb.set_border_width_all(1)
	lsb.set_corner_radius_all(3)
	lsb.content_margin_left = 4.0
	lsb.content_margin_right = 5.0
	like_btn.add_theme_stylebox_override("normal", lsb)
	like_btn.add_theme_stylebox_override("hover", lsb)
	like_btn.add_theme_stylebox_override("pressed", lsb)
	like_btn.add_theme_color_override("font_color", Color(0.65, 1.0, 0.72) if is_liked else Color(0.82, 0.85, 0.90))
	like_btn.add_theme_font_size_override("font_size", 10)
	like_btn.pressed.connect(func() -> void: _toggle_thumbs_up(captured))
	rate_row.add_child(like_btn)

	var icon_btn: Button = _make_mini_btn("Icon", Color(0.26, 0.24, 0.38))
	icon_btn.tooltip_text = "Change the thumbnail icon image for '%s'" % raw_title
	icon_btn.pressed.connect(func() -> void:
		_icon_target_item_id = item_id
		_icon_file_dialog.popup_centered_ratio(0.60)
	)
	rate_row.add_child(icon_btn)

	var mini_row: HFlowContainer = HFlowContainer.new()
	mini_row.add_theme_constant_override("h_separation", 3)
	mini_row.add_theme_constant_override("v_separation", 2)
	tile.add_child(mini_row)

	var scr_path: String = String(captured.get("script_path", ""))
	if scr_path != "" and FileAccess.file_exists(scr_path):
		var sbtn: Button = _make_mini_btn("Script", Color(0.18, 0.28, 0.42))
		sbtn.tooltip_text = "Open " + scr_path.get_file() + " in Script Editor"
		sbtn.pressed.connect(func() -> void: _open_script_in_editor(scr_path))
		mini_row.add_child(sbtn)

	var share_btn: Button = _make_mini_btn("Share", Color(0.18, 0.42, 0.28))
	share_btn.tooltip_text = "Copy Dev Share Code to clipboard so other devs can import this creation!"
	share_btn.pressed.connect(func() -> void: _copy_share_code_for_item(captured))
	mini_row.add_child(share_btn)

	var del_btn: Button = _make_mini_btn("X", Color(0.52, 0.15, 0.18))
	del_btn.tooltip_text = "Delete '%s' from Toolbox (Owner Action)" % raw_title
	del_btn.pressed.connect(func() -> void: _delete_saved_item(item_id))
	mini_row.add_child(del_btn)

	return tile

	return tile


func _get_filtered_items() -> Array[Dictionary]:
	var q: String = _search_box.text.strip_edges().to_lower() if _search_box != null else ""
	var filter_mode: int = _filter_dropdown.selected if _filter_dropdown != null else 0
	var sort_mode: int = _sort_dropdown.selected if _sort_dropdown != null else 0
	var out: Array[Dictionary] = []

	for item in _catalog_items:
		var is_builtin: bool = bool(item.get("builtin", false))
		var is_published: bool = bool(item.get("published", true))
		var item_id: String = String(item.get("id", ""))
		var cat: String = _normalize_category(String(item.get("category", "Models")), String(item.get("type", "")))
		var subcat: String = String(item.get("subcat", ""))

		if _active_tab == "Marketplace":
			if not is_builtin and not is_published:
				continue
		elif _active_tab == "Inventory":
			if is_builtin and not _recent_ids.has(item_id) and not _liked_ids.has(item_id):
				continue
		elif _active_tab == "Recent":
			if not _recent_ids.has(item_id):
				continue
		elif _active_tab == "Creations":
			if is_builtin:
				continue

		if _active_subcat != "" and _active_subcat != "ALL_LIST":
			if subcat != _active_subcat and cat.to_upper().find(_active_subcat) < 0:
				continue

		if q == "" and _active_type_filter != "All Types":
			if _active_type_filter == "Folders" or _active_type_filter == "ROBLOX Sets":
				if cat != "Folders" and String(item.get("type", "")) != "folder":
					continue
			elif _active_type_filter == "Meshes":
				if cat != "Models":
					continue
			elif _active_type_filter == "Decals" or _active_type_filter == "Audio":
				if cat != "Audio & Decals":
					continue
			elif cat != _active_type_filter:
				continue

		# Model / Item Filter Dropdown
		if filter_mode == 1: # Has Script
			if String(item.get("script_path", "")) == "" and String(item.get("type", "")) != "script":
				continue
		elif filter_mode == 2: # Verified Only
			if not bool(item.get("verified", true)):
				continue
		elif filter_mode == 3: # Top Rated (50+ Thumbs Up)
			if _get_item_likes(item) < 50:
				continue
		elif filter_mode == 4: # My Thumbs Up
			if not bool(_liked_ids.get(item_id, false)):
				continue
		elif filter_mode == 5: # Custom Icon
			if not _custom_icons.has(item_id) and String(item.get("icon_path", "")) == "":
				continue

		if q != "":
			var hay: String = (
				String(item.get("name", "")) + " " +
				String(item.get("creator", "")) + " " +
				String(item.get("description", "")) + " " +
				String(item.get("tags", "")) + " " +
				cat + " " + subcat
			).to_lower()
			var matched: bool = true
			for token in q.split(" ", false):
				if hay.find(token) < 0:
					matched = false
					break
			if not matched:
				continue

		out.append(item)

	# Sort Dropdown
	if sort_mode == 1: # Most Thumbs Up
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _get_item_likes(a) > _get_item_likes(b)
		)
	elif sort_mode == 2: # Newest (user creations first)
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return not bool(a.get("builtin", false)) and bool(b.get("builtin", false))
		)
	elif sort_mode == 3: # A - Z
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("name", "")).to_lower() < String(b.get("name", "")).to_lower()
		)

	return out


# ============================================================================
# ONLINE DEV MARKETPLACE CLOUD SYNC + SHAREABLE DEV CODES
# ============================================================================

func _sync_from_cloud_marketplace(silent: bool = false) -> void:
	if not silent:
		_set_status("Syncing dev creations from RetroBlox Online Marketplace...", Color(0.55, 0.85, 1.0))
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	var url: String = "%s/api/placechat/%s" % [SERVER_URL, CLOUD_TOOLBOX_CHANNEL]
	var err: int = http.request(url, PackedStringArray(["User-Agent: RetroBloxStudio/2.0"]), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return
	var res: Array = await http.request_completed
	http.queue_free()
	if res.is_empty() or int(res[1]) < 200 or int(res[1]) >= 300:
		if not silent:
			_set_status("Local & Built-in Marketplace ready (%d items)." % _catalog_items.size(), Color(0.68, 0.82, 0.96))
		return

	var body_bytes: PackedByteArray = res[3]
	var parsed: Variant = JSON.parse_string(body_bytes.get_string_from_utf8())
	var added_count: int = 0
	if parsed is Dictionary and (parsed as Dictionary).has("messages"):
		var msgs: Variant = (parsed as Dictionary)["messages"]
		if msgs is Array:
			for m in (msgs as Array):
				if m is Dictionary:
					var txt: String = String((m as Dictionary).get("text", ""))
					if txt.begins_with("RBXTB:"):
						if _import_share_code_string(txt, true):
							added_count += 1
	if added_count > 0:
		_save_user_catalog()
		_rebuild_content()
		_set_status("Synced %d new dev creation(s) from Online Marketplace!" % added_count, Color(0.52, 0.96, 0.64))
	elif not silent:
		_set_status("Online Marketplace is up to date (%d items available)." % _catalog_items.size(), Color(0.52, 0.96, 0.64))


func _publish_item_to_cloud(item: Dictionary) -> void:
	var share_code: String = _encode_item_to_share_code(item)
	if share_code == "" or share_code.length() > 48000:
		return
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	var url: String = "%s/api/placechat/%s" % [SERVER_URL, CLOUD_TOOLBOX_CHANNEL]
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"User-Agent: RetroBloxStudio/2.0"
	])
	var payload: String = JSON.stringify({"text": share_code})
	var err: int = http.request(url, headers, HTTPClient.METHOD_POST, payload)
	if err == OK:
		await http.request_completed
	http.queue_free()


func _encode_item_to_share_code(item: Dictionary) -> String:
	var res_path: String = String(item.get("path", ""))
	if not FileAccess.file_exists(res_path):
		return ""
	var raw_bytes: PackedByteArray = FileAccess.get_file_as_bytes(res_path)
	if raw_bytes.is_empty():
		return ""
	var comp: PackedByteArray = raw_bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	var icon_b64: String = ""
	var icon_p: String = String(item.get("icon_path", ""))
	var item_id: String = String(item.get("id", ""))
	if item_id != "" and _custom_icons.has(item_id):
		icon_p = String(_custom_icons[item_id])
	if icon_p != "" and FileAccess.file_exists(icon_p):
		var ibytes: PackedByteArray = FileAccess.get_file_as_bytes(icon_p)
		if ibytes.size() <= 16384:
			icon_b64 = Marshalls.raw_to_base64(ibytes)

	var pack_dict: Dictionary = {
		"id": item_id,
		"name": String(item.get("name", "DevAsset")),
		"creator": String(item.get("creator", "Builder")),
		"version": String(item.get("version", "1.0")),
		"category": String(item.get("category", "Models")),
		"subcat": String(item.get("subcat", "STRUCTURE")),
		"type": String(item.get("type", "model_script")),
		"ext": res_path.get_extension().to_lower(),
		"description": String(item.get("description", "")),
		"tags": String(item.get("tags", "")),
		"thumbs_up": _get_item_likes(item),
		"icon_b64": icon_b64,
		"orig_len": raw_bytes.size(),
		"data_b64": Marshalls.raw_to_base64(comp),
	}
	var json_bytes: PackedByteArray = JSON.stringify(pack_dict).to_utf8_buffer()
	return "RBXTB:" + Marshalls.raw_to_base64(json_bytes)


func _copy_share_code_for_item(item: Dictionary) -> void:
	var code: String = _encode_item_to_share_code(item)
	if code == "":
		_set_status("Could not generate Share Code for this item.", Color(1.0, 0.55, 0.55))
		return
	DisplayServer.clipboard_set(code)
	_set_status("Copied Dev Share Code for '%s' to clipboard!" % String(item.get("name", "")), Color(0.55, 0.96, 0.65))


func _import_share_code_string(code_str: String, silent: bool = false) -> bool:
	var clean: String = code_str.strip_edges()
	if not clean.begins_with("RBXTB:"):
		if not silent:
			_set_status("Invalid Share Code (must start with RBXTB:).", Color(1.0, 0.55, 0.55))
		return false
	var b64_part: String = clean.substr(6)
	var json_str: String = Marshalls.base64_to_raw(b64_part).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed as Dictionary
	var item_id: String = String(d.get("id", ""))
	if item_id == "":
		return false
	for existing in _catalog_items:
		if String(existing.get("id", "")) == item_id:
			return false

	var comp_bytes: PackedByteArray = Marshalls.base64_to_raw(String(d.get("data_b64", "")))
	var orig_len: int = int(d.get("orig_len", 0))
	if comp_bytes.is_empty() or orig_len <= 0:
		return false
	var raw_bytes: PackedByteArray = comp_bytes.decompress(orig_len, FileAccess.COMPRESSION_DEFLATE)
	if raw_bytes.is_empty():
		return false

	_ensure_dirs()
	var slug: String = _slugify(String(d.get("name", item_id)))
	var ext: String = String(d.get("ext", "tscn"))
	var proj_p: String = "%s/%s.%s" % [PROJECT_PUBLISHED_DIR, slug, ext]
	var user_p: String = "%s/%s.%s" % [USER_SAVED_DIR, slug, ext]

	var wf1: FileAccess = FileAccess.open(proj_p, FileAccess.WRITE)
	if wf1 != null:
		wf1.store_buffer(raw_bytes)
	var wf2: FileAccess = FileAccess.open(user_p, FileAccess.WRITE)
	if wf2 != null:
		wf2.store_buffer(raw_bytes)

	var icon_p: String = ""
	var icon_b64: String = String(d.get("icon_b64", ""))
	if icon_b64 != "":
		var ibytes: PackedByteArray = Marshalls.base64_to_raw(icon_b64)
		if not ibytes.is_empty():
			icon_p = "%s/%s_icon.png" % [PROJECT_PUBLISHED_DIR, slug]
			var if1: FileAccess = FileAccess.open(icon_p, FileAccess.WRITE)
			if if1 != null:
				if1.store_buffer(ibytes)

	_catalog_items.insert(0, {
		"id": item_id,
		"name": String(d.get("name", "Community Asset")),
		"creator": String(d.get("creator", "Dev")),
		"version": String(d.get("version", "1.0")),
		"category": String(d.get("category", "Models")),
		"subcat": String(d.get("subcat", "STRUCTURE")),
		"type": String(d.get("type", "model_script")),
		"path": proj_p,
		"user_path": user_p,
		"icon_path": icon_p,
		"script_path": proj_p if ext == "gd" else "",
		"description": String(d.get("description", "Shared dev creation.")),
		"tags": String(d.get("tags", "community shared")),
		"thumbs_up": int(d.get("thumbs_up", 1)),
		"builtin": false,
		"published": true,
		"verified": true,
	})
	if not silent:
		_save_user_catalog()
		_rebuild_content()
		_set_status("Imported '%s' by %s into your Toolbox!" % [String(d.get("name", "")), String(d.get("creator", "Dev"))], Color(0.55, 0.96, 0.65))
	return true


# ============================================================================
# PUBLISH TO TOOLBOX DIALOG (WITH CUSTOM ICON PICKER!)
# ============================================================================

func _build_publish_dialog() -> void:
	_publish_window = AcceptDialog.new()
	_publish_window.title = "Publish to Toolbox — Share Models, Scripts, UI & Folders for Devs"
	_publish_window.ok_button_text = "Publish to Toolbox"
	_publish_window.min_size = Vector2i(440, 460)
	_publish_window.size = Vector2i(560, 560)
	_publish_window.unresizable = false
	_publish_window.close_requested.connect(_publish_window.hide)
	_publish_window.canceled.connect(_publish_window.hide)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(400, 380)
	_publish_window.add_child(scroll)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)

	var help_lbl: Label = Label.new()
	help_lbl.text = "Publish any Model, Script (.gd), UI/GUI, Folder, Decal, or Audio from your Scene with a custom Icon so developers can find, rate, and insert it!"
	help_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_lbl.add_theme_color_override("font_color", Color(0.72, 0.84, 0.98))
	help_lbl.add_theme_font_size_override("font_size", 12)
	col.add_child(help_lbl)

	var node_row: HBoxContainer = HBoxContainer.new()
	node_row.add_theme_constant_override("separation", 8)
	col.add_child(node_row)
	var node_lbl: Label = Label.new()
	node_lbl.text = "Scene Node:"
	node_lbl.custom_minimum_size = Vector2(120, 0)
	node_row.add_child(node_lbl)
	_pub_node_picker = OptionButton.new()
	_pub_node_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pub_node_picker.item_selected.connect(_on_publish_node_picked)
	node_row.add_child(_pub_node_picker)

	var browse_disk_btn: Button = Button.new()
	browse_disk_btn.text = "Or Upload File..."
	browse_disk_btn.pressed.connect(func() -> void:
		_publish_window.hide()
		_on_upload_pressed()
	)
	node_row.add_child(browse_disk_btn)

	var browse_folder_btn: Button = Button.new()
	browse_folder_btn.text = "📁 Upload Folder..."
	browse_folder_btn.tooltip_text = "Select a folder on disk to publish with all files inside"
	browse_folder_btn.pressed.connect(func() -> void:
		_publish_window.hide()
		_on_upload_folder_pressed()
	)
	node_row.add_child(browse_folder_btn)

	# Custom Icon Picker Row
	var icon_row: HBoxContainer = HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 8)
	col.add_child(icon_row)
	var icon_lbl: Label = Label.new()
	icon_lbl.text = "Custom Icon:"
	icon_lbl.custom_minimum_size = Vector2(120, 0)
	icon_row.add_child(icon_lbl)

	_pub_icon_preview = TextureRect.new()
	_pub_icon_preview.custom_minimum_size = Vector2(44, 44)
	_pub_icon_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pub_icon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pub_icon_preview.texture = _get_item_thumbnail({"thumb_kind": "pine_tree"})
	icon_row.add_child(_pub_icon_preview)

	_pub_icon_path_lbl = Label.new()
	_pub_icon_path_lbl.text = "(Auto Preview Icon)"
	_pub_icon_path_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pub_icon_path_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	_pub_icon_path_lbl.add_theme_font_size_override("font_size", 11)
	icon_row.add_child(_pub_icon_path_lbl)

	var snap_icon_btn: Button = Button.new()
	snap_icon_btn.text = "📸 Snapshot View"
	snap_icon_btn.tooltip_text = "Capture 3D viewport into 128x128 icon image"
	snap_icon_btn.pressed.connect(_on_snapshot_viewport_as_publish_icon)
	icon_row.add_child(snap_icon_btn)

	var pick_icon_btn: Button = Button.new()
	pick_icon_btn.text = "Choose Icon..."
	pick_icon_btn.pressed.connect(func() -> void:
		_pub_icon_dialog.popup_centered_ratio(0.65)
	)
	icon_row.add_child(pick_icon_btn)

	var clear_icon_btn: Button = Button.new()
	clear_icon_btn.text = "Reset"
	clear_icon_btn.pressed.connect(func() -> void:
		_pub_pending_icon_path = ""
		_pub_icon_path_lbl.text = "(Auto Preview Icon)"
		_pub_icon_preview.texture = _get_item_thumbnail({"thumb_kind": "pine_tree"})
	)
	icon_row.add_child(clear_icon_btn)

	var mode_row: HBoxContainer = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	col.add_child(mode_row)
	var mode_lbl: Label = Label.new()
	mode_lbl.text = "Publish Mode:"
	mode_lbl.custom_minimum_size = Vector2(120, 0)
	mode_row.add_child(mode_lbl)
	_pub_mode_option = OptionButton.new()
	_pub_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pub_mode_option.add_item("Full Node / Model / UI / Folder (.tscn)")
	_pub_mode_option.add_item("Attached GDScript Only (.gd)")
	mode_row.add_child(_pub_mode_option)

	var over_row: HBoxContainer = HBoxContainer.new()
	over_row.add_theme_constant_override("separation", 8)
	col.add_child(over_row)
	var over_lbl: Label = Label.new()
	over_lbl.text = "Action:"
	over_lbl.custom_minimum_size = Vector2(120, 0)
	over_row.add_child(over_lbl)
	_pub_overwrite_option = OptionButton.new()
	_pub_overwrite_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pub_overwrite_option.add_item("Publish as New Asset")
	_pub_overwrite_option.item_selected.connect(_on_overwrite_item_selected)
	over_row.add_child(_pub_overwrite_option)

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	col.add_child(title_row)
	var title_lbl: Label = Label.new()
	title_lbl.text = "Title:"
	title_lbl.custom_minimum_size = Vector2(120, 0)
	title_row.add_child(title_lbl)
	_pub_title_input = LineEdit.new()
	_pub_title_input.placeholder_text = "e.g. Pine Tree, Police Car, Shop GUI, Kill Script"
	_pub_title_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_pub_title_input)

	var cat_row: HBoxContainer = HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 8)
	col.add_child(cat_row)
	var cat_lbl: Label = Label.new()
	cat_lbl.text = "Asset Type:"
	cat_lbl.custom_minimum_size = Vector2(120, 0)
	cat_row.add_child(cat_lbl)
	_pub_cat_option = OptionButton.new()
	_pub_cat_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c_opt in ["Models", "Scripts", "UI / GUIs", "Folders", "Audio & Decals"]:
		_pub_cat_option.add_item(c_opt)
	_pub_cat_option.item_selected.connect(func(c_idx: int) -> void:
		var c_txt: String = _pub_cat_option.get_item_text(c_idx)
		if c_txt == "Folders":
			_pub_mode_option.selected = 0
			if _pub_tags_input.text.find("folder") == -1:
				_pub_tags_input.text = "folder kit set " + _pub_tags_input.text
			if _pub_pending_icon_path == "":
				_pub_icon_preview.texture = _get_item_thumbnail({"thumb_kind": "folder", "type": "folder", "category": "Folders"})
	)
	cat_row.add_child(_pub_cat_option)

	var subcat_row: HBoxContainer = HBoxContainer.new()
	subcat_row.add_theme_constant_override("separation", 8)
	col.add_child(subcat_row)
	var subcat_lbl: Label = Label.new()
	subcat_lbl.text = "Marketplace Tile:"
	subcat_lbl.custom_minimum_size = Vector2(120, 0)
	subcat_row.add_child(subcat_lbl)
	_pub_subcat_option = OptionButton.new()
	_pub_subcat_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for sc_opt in ["STRUCTURE", "VEHICLES", "LIGHT", "WEAPONS", "SCRIPTS", "UI"]:
		_pub_subcat_option.add_item(sc_opt)
	subcat_row.add_child(_pub_subcat_option)

	var creator_row: HBoxContainer = HBoxContainer.new()
	creator_row.add_theme_constant_override("separation", 8)
	col.add_child(creator_row)
	var creator_lbl: Label = Label.new()
	creator_lbl.text = "Creator Name:"
	creator_lbl.custom_minimum_size = Vector2(120, 0)
	creator_row.add_child(creator_lbl)
	_pub_creator_input = LineEdit.new()
	_pub_creator_input.text = _get_default_creator_name()
	_pub_creator_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creator_row.add_child(_pub_creator_input)

	var ver_row: HBoxContainer = HBoxContainer.new()
	ver_row.add_theme_constant_override("separation", 8)
	col.add_child(ver_row)
	var ver_lbl: Label = Label.new()
	ver_lbl.text = "Version:"
	ver_lbl.custom_minimum_size = Vector2(120, 0)
	ver_row.add_child(ver_lbl)
	_pub_version_input = LineEdit.new()
	_pub_version_input.text = "1.0"
	_pub_version_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ver_row.add_child(_pub_version_input)

	var desc_lbl: Label = Label.new()
	desc_lbl.text = "Description:"
	col.add_child(desc_lbl)
	_pub_desc_input = TextEdit.new()
	_pub_desc_input.placeholder_text = "Describe what this creation does for other developers..."
	_pub_desc_input.custom_minimum_size = Vector2(0, 64)
	_pub_desc_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_pub_desc_input)

	var tags_row: HBoxContainer = HBoxContainer.new()
	tags_row.add_theme_constant_override("separation", 8)
	col.add_child(tags_row)
	var tags_lbl: Label = Label.new()
	tags_lbl.text = "Search Tags:"
	tags_lbl.custom_minimum_size = Vector2(120, 0)
	tags_row.add_child(tags_lbl)
	_pub_tags_input = LineEdit.new()
	_pub_tags_input.placeholder_text = "e.g. car tree weapon ui shop script"
	_pub_tags_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tags_row.add_child(_pub_tags_input)

	_pub_marketplace_check = CheckBox.new()
	_pub_marketplace_check.text = "Distribute on Toolbox Marketplace (visible in Marketplace, Inventory & Creations)"
	_pub_marketplace_check.button_pressed = true
	col.add_child(_pub_marketplace_check)

	_pub_cloud_check = CheckBox.new()
	_pub_cloud_check.text = "Sync to RetroBlox Online Dev Cloud + Copy Dev Share Code to Clipboard"
	_pub_cloud_check.button_pressed = true
	col.add_child(_pub_cloud_check)

	_publish_window.confirmed.connect(_confirm_publish_selected)
	add_child(_publish_window)

	_pub_icon_dialog = FileDialog.new()
	_pub_icon_dialog.title = "Select Custom Icon Image for Toolbox Asset"
	_pub_icon_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_pub_icon_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_pub_icon_dialog.filters = PackedStringArray([
		"*.png ; PNG Images (*.png)",
		"*.jpg, *.jpeg ; JPEG Images (*.jpg, *.jpeg)",
		"*.webp ; WebP Images (*.webp)",
		"* ; All Files (*)"
	])
	_pub_icon_dialog.file_selected.connect(_on_publish_icon_selected)
	_pub_icon_dialog.close_requested.connect(_pub_icon_dialog.hide)
	_pub_icon_dialog.canceled.connect(_pub_icon_dialog.hide)
	_pub_icon_dialog.transient = true
	_pub_icon_dialog.exclusive = false
	add_child(_pub_icon_dialog)


func _build_upload_and_rename_dialogs() -> void:
	_upload_dialog = FileDialog.new()
	_upload_dialog.title = "Upload & Publish Model, UI Scene, Folder, Script, or Audio to Toolbox"
	_upload_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_upload_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_upload_dialog.filters = PackedStringArray([
		"*.tscn, *.scn ; Godot Scenes (Models, UI / GUIs, Folders)",
		"*.gd ; GDScript Files",
		"*.glb, *.gltf, *.obj ; 3D Meshes & Models",
		"*.mp3, *.wav, *.ogg, *.png, *.jpg ; Audio & Decals",
	])
	_upload_dialog.files_selected.connect(_on_files_uploaded)
	_upload_dialog.close_requested.connect(_upload_dialog.hide)
	_upload_dialog.canceled.connect(_upload_dialog.hide)
	add_child(_upload_dialog)

	_folder_dialog = FileDialog.new()
	_folder_dialog.title = "Select Folder to Publish to Toolbox (with all contents inside)"
	_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_folder_dialog.dir_selected.connect(_on_folder_selected_to_publish)
	_folder_dialog.close_requested.connect(_folder_dialog.hide)
	_folder_dialog.canceled.connect(_folder_dialog.hide)
	add_child(_folder_dialog)

	_icon_file_dialog = FileDialog.new()
	_icon_file_dialog.title = "Select Custom Icon Image for Toolbox Asset"
	_icon_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_icon_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_icon_file_dialog.filters = PackedStringArray([
		"*.png ; PNG Images (*.png)",
		"*.jpg, *.jpeg ; JPEG Images (*.jpg, *.jpeg)",
		"*.webp ; WebP Images (*.webp)",
		"* ; All Files (*)"
	])
	_icon_file_dialog.file_selected.connect(_on_custom_icon_file_selected)
	_icon_file_dialog.close_requested.connect(_icon_file_dialog.hide)
	_icon_file_dialog.canceled.connect(_icon_file_dialog.hide)
	add_child(_icon_file_dialog)

	_rename_dialog = AcceptDialog.new()
	_rename_dialog.title = "Rename Toolbox Asset"
	_rename_input = LineEdit.new()
	_rename_input.custom_minimum_size = Vector2(260, 28)
	_rename_dialog.add_child(_rename_input)
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	_rename_dialog.close_requested.connect(_rename_dialog.hide)
	_rename_dialog.canceled.connect(_rename_dialog.hide)
	add_child(_rename_dialog)

	_share_import_dialog = AcceptDialog.new()
	_share_import_dialog.title = "Import Dev Share Code (RBXTB:...)"
	_share_import_dialog.ok_button_text = "Import to Toolbox"
	_share_code_input = TextEdit.new()
	_share_code_input.placeholder_text = "Paste a Dev Share Code starting with RBXTB: here..."
	_share_code_input.custom_minimum_size = Vector2(380, 140)
	_share_import_dialog.add_child(_share_code_input)
	_share_import_dialog.confirmed.connect(func() -> void:
		if _import_share_code_string(_share_code_input.text, false):
			_share_code_input.text = ""
	)
	_share_import_dialog.close_requested.connect(_share_import_dialog.hide)
	_share_import_dialog.canceled.connect(_share_import_dialog.hide)
	add_child(_share_import_dialog)


func _on_snapshot_viewport_as_publish_icon() -> void:
	var vp: SubViewport = null
	if plugin != null and plugin.get_editor_interface() != null:
		vp = plugin.get_editor_interface().get_editor_viewport_3d(0)
	if vp == null:
		vp = get_viewport() as SubViewport
	if vp != null:
		var tex: ViewportTexture = vp.get_texture()
		if tex != null:
			var img: Image = tex.get_image()
			if img != null and not img.is_empty():
				var min_dim: int = mini(img.get_width(), img.get_height())
				var start_x: int = (img.get_width() - min_dim) / 2
				var start_y: int = (img.get_height() - min_dim) / 2
				var cropped: Image = img.get_region(Rect2i(start_x, start_y, min_dim, min_dim))
				cropped.resize(128, 128, Image.INTERPOLATE_LANCZOS)
				_ensure_dirs()
				var snap_path: String = "%s/snapshot_preview_%d.png" % [PROJECT_PUBLISHED_DIR, Time.get_unix_time_from_system()]
				var global_snap: String = ProjectSettings.globalize_path(snap_path)
				var err: Error = cropped.save_png(global_snap)
				if err == OK:
					_pub_pending_icon_path = snap_path
					_pub_icon_path_lbl.text = "Viewport Snapshot"
					var ptex := ImageTexture.create_from_image(cropped)
					_pub_icon_preview.texture = ptex
					_set_status("Snapped 3D Viewport for icon!", Color(0.52, 0.96, 0.64))
					return
	_set_status("Could not snapshot viewport. Please click 'Choose Icon...' to pick an image.", Color(1.0, 0.72, 0.40))


func _on_publish_icon_selected(src_path: String) -> void:
	if src_path == "":
		return
	_pub_pending_icon_path = src_path
	_pub_icon_path_lbl.text = src_path.get_file()
	var ptex: Texture2D = _load_texture_from_any_path(src_path)
	if ptex != null:
		_pub_icon_preview.texture = ptex


func _on_custom_icon_file_selected(src_path: String) -> void:
	if src_path == "":
		return
	var global_src: String = ProjectSettings.globalize_path(src_path)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src_path)
	if bytes.is_empty():
		bytes = FileAccess.get_file_as_bytes(global_src)
	if bytes.is_empty():
		_set_status("Could not read image file: " + src_path, Color(1.0, 0.55, 0.55))
		return

	if _icon_target_item_id == "__PUBLISH_DIALOG__":
		_pub_pending_icon_path = src_path
		_pub_icon_path_lbl.text = src_path.get_file()
		var ptex: Texture2D = _load_texture_from_any_path(src_path)
		if ptex != null:
			_pub_icon_preview.texture = ptex
		return

	# Copy icon into project published dir & user dir for the target item_id
	_ensure_dirs()
	var ext: String = src_path.get_extension().to_lower()
	var slug: String = _slugify(_icon_target_item_id)
	var dst_proj: String = "%s/%s_icon.png" % [PROJECT_PUBLISHED_DIR, slug]
	var dst_user: String = "%s/%s_icon.png" % [USER_SAVED_DIR, slug]

	var src_load_p: String = global_src if FileAccess.file_exists(global_src) else src_path
	var img: Image = Image.load_from_file(src_load_p)
	if img != null and not img.is_empty():
		img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(dst_proj))
		img.save_png(ProjectSettings.globalize_path(dst_user))
	else:
		var wf1: FileAccess = FileAccess.open(dst_proj, FileAccess.WRITE)
		if wf1 != null: wf1.store_buffer(bytes)
		var wf2: FileAccess = FileAccess.open(dst_user, FileAccess.WRITE)
		if wf2 != null: wf2.store_buffer(bytes)

	_thumb_cache.erase("file:" + dst_proj)
	_thumb_cache.erase("file:" + dst_user)
	_thumb_cache.erase("file:" + src_path)
	_custom_icons[_icon_target_item_id] = dst_proj
	for item in _catalog_items:
		if String(item.get("id", "")) == _icon_target_item_id:
			item["icon_path"] = dst_proj
			item["thumb_kind"] = ""
			break
	_save_ratings_state()
	_save_user_catalog()
	_rebuild_content()
	_set_status("Updated icon for asset!", Color(0.52, 0.96, 0.64))


func _get_default_creator_name() -> String:
	var cf: ConfigFile = ConfigFile.new()
	if cf.load("user://retroblox_session.cfg") == OK:
		var u: String = String(cf.get_value("auth", "username", ""))
		if u != "":
			return u
	return "Builder"


func _populate_scene_node_picker() -> void:
	_pub_scene_nodes.clear()
	_pub_node_picker.clear()
	if plugin == null or plugin.get_editor_interface() == null:
		_pub_node_picker.add_item("(No active scene open)")
	else:
		var root: Node = plugin.get_editor_interface().get_edited_scene_root()
		if root == null:
			_pub_node_picker.add_item("(No active scene open — pick a FileSystem folder below)")
		else:
			_collect_scene_nodes_recursive(root, "")

	# Append project FileSystem folders so user can also pick any folder in res://
	var fs_folders: Array[String] = []
	_scan_fs_folders_recursive("res://", fs_folders, 0, 3)
	if not fs_folders.is_empty():
		_pub_node_picker.add_separator("── FileSystem Folders ──")
		for fpath in fs_folders:
			var f_file_count: int = _count_fs_dir_files_recursive(fpath)
			var item_text: String = "📁 %s (%d files)" % [fpath, f_file_count]
			_pub_node_picker.add_item(item_text)
			var item_idx: int = _pub_node_picker.item_count - 1
			_pub_node_picker.set_item_metadata(item_idx, fpath)

	var currently_selected: Node = _get_selected_node()
	var select_idx: int = 0
	for i in range(_pub_scene_nodes.size()):
		if _pub_scene_nodes[i] == currently_selected:
			select_idx = i
			break
	if not _pub_scene_nodes.is_empty():
		_pub_node_picker.selected = select_idx
		_on_publish_node_picked(select_idx)


func _scan_fs_folders_recursive(path: String, out_folders: Array[String], depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	var da: DirAccess = DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if da.current_is_dir() and not fname.begins_with(".") and fname != ".godot" and fname != ".import" and fname != "addons":
			var sub_path: String = path.path_join(fname)
			out_folders.append(sub_path)
			_scan_fs_folders_recursive(sub_path, out_folders, depth + 1, max_depth)
		fname = da.get_next()
	da.list_dir_end()


func _count_fs_dir_files_recursive(dir_path: String) -> int:
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return 0
	var count: int = 0
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not fname.begins_with(".") and fname != ".godot" and fname != ".import":
			var sub_path: String = dir_path.path_join(fname)
			if da.current_is_dir():
				count += _count_fs_dir_files_recursive(sub_path)
			else:
				var ext: String = fname.get_extension().to_lower()
				if ext != "import" and ext != "uid":
					count += 1
		fname = da.get_next()
	da.list_dir_end()
	return count


func _find_fs_folder_icon(dir_path: String) -> String:
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return ""
	var first_img: String = ""
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not fname.begins_with(".") and fname != ".godot" and fname != ".import":
			var sub_path: String = dir_path.path_join(fname)
			if da.current_is_dir():
				var found_sub: String = _find_fs_folder_icon(sub_path)
				if found_sub != "":
					da.list_dir_end()
					return found_sub
			else:
				var ext: String = fname.get_extension().to_lower()
				if ext in ["png", "jpg", "jpeg", "webp"]:
					var lower_name: String = fname.to_lower()
					if lower_name.find("icon") >= 0 or lower_name.find("thumb") >= 0:
						da.list_dir_end()
						return sub_path
					elif first_img == "":
						first_img = sub_path
		fname = da.get_next()
	da.list_dir_end()
	return first_img


func _collect_scene_nodes_recursive(node: Node, indent: String) -> void:
	if node == null:
		return
	_pub_scene_nodes.append(node)
	var has_scr: String = " [Script]" if (node.get_script() is Script) else ""
	var child_cnt: int = node.get_child_count()
	var is_f: bool = (
		bool(node.get_meta("retroblox_folder", false))
		or node.name.to_lower().find("folder") >= 0
		or node.name.to_lower().find("kit") >= 0
		or node.name.to_lower().find("set") >= 0
		or node.name.to_lower().find("pack") >= 0
		or (node.get_class() == "Node" and child_cnt > 0)
	)
	var prefix: String = "📁 " if is_f else ""
	var cnt_tag: String = " (%d items)" % child_cnt if (child_cnt > 0) else ""
	_pub_node_picker.add_item("%s%s%s (%s)%s%s" % [indent, prefix, node.name, node.get_class(), cnt_tag, has_scr])
	for ch in node.get_children():
		_collect_scene_nodes_recursive(ch, indent + "  ")


func _on_publish_node_picked(idx: int) -> void:
	if idx < 0 or idx >= _pub_node_picker.item_count:
		return
	var meta_val: Variant = _pub_node_picker.get_item_metadata(idx)
	if meta_val != null and (meta_val is String) and String(meta_val) != "":
		var folder_p: String = String(meta_val)
		_pub_target_fs_folder = folder_p
		_apply_fs_folder_to_publish_form(folder_p)
		return

	_pub_target_fs_folder = ""
	if idx < 0 or idx >= _pub_scene_nodes.size():
		return
	var sel: Node = _pub_scene_nodes[idx]
	if sel == null or not is_instance_valid(sel):
		return

	var has_script: bool = sel.get_script() is Script
	var sub_script: String = _find_first_script_in_subtree(sel)
	var child_count: int = _count_subtree_nodes(sel)

	_pub_title_input.text = String(sel.name)
	_pub_version_input.text = "1.0"
	_pub_mode_option.selected = 0

	var is_ui: bool = (sel is Control) or (sel is CanvasLayer)
	var is_audio: bool = (sel is AudioStreamPlayer) or (sel is AudioStreamPlayer3D) or (sel is Decal)
	var is_folder: bool = (
		bool(sel.get_meta("retroblox_folder", false))
		or String(sel.name).to_lower().find("folder") >= 0
		or String(sel.name).to_lower().find("kit") >= 0
		or String(sel.name).to_lower().find("set") >= 0
		or String(sel.name).to_lower().find("pack") >= 0
		or String(sel.name).to_lower().find("group") >= 0
		or String(sel.name).to_lower().find("collection") >= 0
		or (sel.get_class() == "Node" and not is_ui)
		or (sel.get_child_count() > 0 and not (sel is VisualInstance3D or sel is CollisionShape3D or sel is CollisionObject3D or sel is Light3D or sel is Camera3D or is_ui or is_audio))
	)

	if is_ui:
		_pub_cat_option.selected = 2
		_pub_subcat_option.selected = 5
		_pub_tags_input.text = "ui gui hud custom " + String(sel.name).to_lower()
	elif is_folder:
		_pub_cat_option.selected = 3
		_pub_subcat_option.selected = 0
		_pub_mode_option.selected = 0
		_pub_tags_input.text = "folder kit set collection " + String(sel.name).to_lower()
		if _pub_pending_icon_path == "":
			_pub_icon_preview.texture = _get_item_thumbnail({"thumb_kind": "folder", "type": "folder", "category": "Folders"})
	elif is_audio:
		_pub_cat_option.selected = 4
		_pub_subcat_option.selected = 0
		_pub_tags_input.text = "audio sound decal " + String(sel.name).to_lower()
	elif sel.get_class() == "Node" and has_script and sel.get_child_count() == 0:
		_pub_cat_option.selected = 1
		_pub_subcat_option.selected = 4
		_pub_mode_option.selected = 1
		_pub_tags_input.text = "script custom " + String(sel.name).to_lower()
	else:
		_pub_cat_option.selected = 0
		_pub_subcat_option.selected = 0
		_pub_tags_input.text = "model custom " + ("script " if sub_script != "" else "") + String(sel.name).to_lower()

	if is_folder:
		var items_inside: int = child_count - 1
		_pub_desc_input.text = "Folder '%s' with %d item%s inside (including all sub-models, parts, scripts, and components)." % [
			sel.name,
			items_inside,
			"s" if items_inside != 1 else ""
		]
	else:
		_pub_desc_input.text = "Published %s (%d node%s%s)." % [
			_pub_cat_option.get_item_text(_pub_cat_option.selected),
			child_count,
			"s" if child_count != 1 else "",
			", includes script" if sub_script != "" else ""
		]


func open_publish_dialog_for_fs_folder(folder_path: String) -> void:
	_pub_target_fs_folder = folder_path
	_populate_overwrite_dropdown()
	_pub_overwrite_option.selected = 0
	_pub_pending_icon_path = ""
	if _pub_icon_path_lbl != null:
		_pub_icon_path_lbl.text = "(Auto Preview Icon)"
	_populate_scene_node_picker()

	var found_idx: int = -1
	for i in range(_pub_node_picker.item_count):
		var meta: Variant = _pub_node_picker.get_item_metadata(i)
		if meta != null and String(meta) == folder_path:
			found_idx = i
			break
	if found_idx >= 0:
		_pub_node_picker.selected = found_idx
	else:
		var f_cnt: int = _count_fs_dir_files_recursive(folder_path)
		_pub_node_picker.add_item("📁 %s (%d files)" % [folder_path, f_cnt])
		var new_idx: int = _pub_node_picker.item_count - 1
		_pub_node_picker.set_item_metadata(new_idx, folder_path)
		_pub_node_picker.selected = new_idx

	_apply_fs_folder_to_publish_form(folder_path)
	_publish_window.popup_centered(Vector2i(560, 560))


func _apply_fs_folder_to_publish_form(folder_path: String) -> void:
	var clean_path: String = folder_path
	if clean_path.ends_with("/"):
		clean_path = clean_path.left(-1)
	var folder_name: String = clean_path.get_file()
	if folder_name == "":
		folder_name = "Folder"
	var readable_name: String = folder_name.replace("_", " ").capitalize()

	_pub_title_input.text = readable_name
	_pub_version_input.text = "1.0"
	_pub_cat_option.selected = 3 # Folders
	_pub_subcat_option.selected = 0 # STRUCTURE
	_pub_mode_option.selected = 0 # Full Scene

	var file_count: int = _count_fs_dir_files_recursive(clean_path)
	_pub_desc_input.text = "Folder '%s' (%s) containing %d file%s inside (including all sub-folders, scenes, models, scripts, and assets)." % [
		readable_name,
		clean_path,
		file_count,
		"s" if file_count != 1 else ""
	]
	_pub_tags_input.text = "%s folder kit set collection filesystem published" % folder_name.to_lower()

	var auto_icon: String = _find_fs_folder_icon(clean_path)
	if auto_icon != "":
		_pub_pending_icon_path = auto_icon
		var tex: Texture2D = _load_texture_from_any_path(auto_icon)
		if tex != null:
			_pub_icon_preview.texture = tex
			_pub_icon_path_lbl.text = auto_icon.get_file()
		else:
			_pub_icon_preview.texture = _get_item_thumbnail({"thumb_kind": "folder", "type": "folder", "category": "Folders"})
			_pub_icon_path_lbl.text = "(Folder Icon)"
	else:
		_pub_icon_preview.texture = _get_item_thumbnail({"thumb_kind": "folder", "type": "folder", "category": "Folders"})
		_pub_icon_path_lbl.text = "(Folder Icon)"


func open_publish_dialog_for_selection() -> void:
	if plugin != null and plugin.get_editor_interface() != null:
		var paths: PackedStringArray = plugin.get_editor_interface().get_selected_paths()
		for p in paths:
			var gp: String = ProjectSettings.globalize_path(p)
			if DirAccess.dir_exists_absolute(gp) and not FileAccess.file_exists(gp):
				open_publish_dialog_for_fs_folder(p)
				return

	_pub_target_fs_folder = ""
	_populate_overwrite_dropdown()
	_pub_overwrite_option.selected = 0
	_pub_pending_icon_path = ""
	if _pub_icon_path_lbl != null:
		_pub_icon_path_lbl.text = "(Auto Preview Icon)"
	_populate_scene_node_picker()
	_publish_window.popup_centered(Vector2i(560, 560))


func _populate_overwrite_dropdown() -> void:
	if _pub_overwrite_option == null:
		return
	_pub_overwrite_option.clear()
	_pub_overwrite_option.add_item("Publish as New Asset")
	_pub_overwrite_option.set_item_metadata(0, "")
	var idx: int = 1
	for item in _catalog_items:
		if not bool(item.get("builtin", false)):
			_pub_overwrite_option.add_item("Update Existing: " + String(item.get("name", "")))
			_pub_overwrite_option.set_item_metadata(idx, String(item.get("id", "")))
			idx += 1


func _on_overwrite_item_selected(index: int) -> void:
	if index <= 0:
		return
	var target_id: String = String(_pub_overwrite_option.get_item_metadata(index))
	for item in _catalog_items:
		if String(item.get("id", "")) == target_id:
			_pub_title_input.text = String(item.get("name", ""))
			_pub_creator_input.text = String(item.get("creator", "Builder"))
			var old_ver: float = String(item.get("version", "1.0")).to_float()
			_pub_version_input.text = "%.1f" % (old_ver + 0.1)
			_pub_desc_input.text = String(item.get("description", ""))
			_pub_tags_input.text = String(item.get("tags", ""))
			break


func _confirm_publish_selected() -> void:
	if _pub_target_fs_folder != "":
		_confirm_publish_fs_folder(_pub_target_fs_folder)
		return

	var sel: Node = null
	var pick_idx: int = _pub_node_picker.selected
	if pick_idx >= 0 and pick_idx < _pub_scene_nodes.size():
		sel = _pub_scene_nodes[pick_idx]
	if sel == null or not is_instance_valid(sel):
		sel = _get_selected_node()
	if sel == null:
		_set_status("Open a scene and pick a node to publish, or click 'Or Upload File...'.", Color(1.0, 0.55, 0.55))
		return

	var raw_name: String = _pub_title_input.text.strip_edges()
	if raw_name == "":
		raw_name = String(sel.name)
	var slug: String = _slugify(raw_name)
	var chosen_cat: String = _pub_cat_option.get_item_text(_pub_cat_option.selected)
	var chosen_subcat: String = _pub_subcat_option.get_item_text(_pub_subcat_option.selected)
	var publish_script_only: bool = (_pub_mode_option.selected == 1)

	_ensure_dirs()
	var proj_path: String = ""
	var user_path: String = ""
	var script_p: String = ""
	var item_type: String = "model_script"

	if publish_script_only:
		var scr: Script = sel.get_script() as Script
		if scr == null:
			var sub_scr_path: String = _find_first_script_in_subtree(sel)
			if sub_scr_path != "":
				scr = load(sub_scr_path) as Script
		if scr == null:
			_set_status("Selected node does not have an attached GDScript to publish.", Color(1.0, 0.55, 0.55))
			return
		proj_path = "%s/%s.gd" % [PROJECT_PUBLISHED_DIR, slug]
		user_path = "%s/%s.gd" % [USER_SAVED_DIR, slug]
		var src_code: String = scr.source_code
		if src_code == "" and scr.resource_path != "" and FileAccess.file_exists(scr.resource_path):
			src_code = FileAccess.get_file_as_string(scr.resource_path)
		var wf1: FileAccess = FileAccess.open(proj_path, FileAccess.WRITE)
		if wf1 != null:
			wf1.store_string(src_code)
		var wf2: FileAccess = FileAccess.open(user_path, FileAccess.WRITE)
		if wf2 != null:
			wf2.store_string(src_code)
		script_p = proj_path
		chosen_cat = "Scripts"
		chosen_subcat = "SCRIPTS"
		item_type = "script"
	else:
		var clone: Node = sel.duplicate(15)
		if clone == null:
			_set_status("Could not duplicate the selected node.", Color(1.0, 0.55, 0.55))
			return
		clone.name = raw_name.validate_node_name()
		if clone is Node3D and sel.get_parent() != null:
			(clone as Node3D).position = Vector3.ZERO

		if chosen_cat == "Folders" or bool(sel.get_meta("retroblox_folder", false)):
			clone.set_meta("retroblox_folder", true)

		_embed_all_descendants_recursive(clone, clone)

		var packed: PackedScene = PackedScene.new()
		var err: int = packed.pack(clone)
		clone.free()
		if err != OK:
			_set_status("Failed to pack node into scene (error %d)." % err, Color(1.0, 0.55, 0.55))
			return

		proj_path = "%s/%s.tscn" % [PROJECT_PUBLISHED_DIR, slug]
		user_path = "%s/%s.tscn" % [USER_SAVED_DIR, slug]
		ResourceSaver.save(packed, proj_path)
		ResourceSaver.save(packed, user_path)
		ResourceSaver.save(packed, "%s/%s.tscn" % [PROJECT_SAVED_DIR, slug])

		if sel.get_script() is Script:
			script_p = (sel.get_script() as Script).resource_path
		else:
			script_p = _find_first_script_in_subtree(sel)

		if chosen_cat == "UI / GUIs" or (sel is Control) or (sel is CanvasLayer):
			item_type = "ui"
		elif chosen_cat == "Folders" or bool(sel.get_meta("retroblox_folder", false)):
			item_type = "folder"
		elif chosen_cat == "Scripts":
			item_type = "script"
		elif chosen_cat == "Audio & Decals":
			item_type = "audio"
		else:
			item_type = "model_script"

	var item_id: String = "published_" + slug
	if _pub_overwrite_option.selected > 0:
		var existing_id: String = String(_pub_overwrite_option.get_item_metadata(_pub_overwrite_option.selected))
		if existing_id != "":
			item_id = existing_id

	var saved_icon_path: String = ""
	if _pub_pending_icon_path != "":
		var global_src: String = ProjectSettings.globalize_path(_pub_pending_icon_path)
		var ibytes: PackedByteArray = FileAccess.get_file_as_bytes(_pub_pending_icon_path)
		if ibytes.is_empty():
			ibytes = FileAccess.get_file_as_bytes(global_src)
		if not ibytes.is_empty():
			var iext: String = _pub_pending_icon_path.get_extension().to_lower()
			saved_icon_path = "%s/%s_icon.%s" % [PROJECT_PUBLISHED_DIR, slug, iext]
			var user_icon_path: String = "%s/%s_icon.%s" % [USER_SAVED_DIR, slug, iext]
			var iwf1: FileAccess = FileAccess.open(saved_icon_path, FileAccess.WRITE)
			if iwf1 != null:
				iwf1.store_buffer(ibytes)
			var iwf2: FileAccess = FileAccess.open(user_icon_path, FileAccess.WRITE)
			if iwf2 != null:
				iwf2.store_buffer(ibytes)
			_thumb_cache.erase("file:" + saved_icon_path)
			_thumb_cache.erase("file:" + user_icon_path)
			_thumb_cache.erase("file:" + _pub_pending_icon_path)
			_custom_icons[item_id] = saved_icon_path
			_save_ratings_state()

	for i in range(_catalog_items.size() - 1, -1, -1):
		if String(_catalog_items[i].get("id", "")) == item_id:
			_catalog_items.remove_at(i)

	var creator_name: String = _pub_creator_input.text.strip_edges()
	if creator_name == "":
		creator_name = "Builder"
	var version_str: String = _pub_version_input.text.strip_edges()
	if version_str == "":
		version_str = "1.0"
	var desc_str: String = _pub_desc_input.text.strip_edges()
	if desc_str == "":
		desc_str = "Published %s by %s." % [chosen_cat, creator_name]

	var new_entry: Dictionary = {
		"id": item_id,
		"name": raw_name,
		"creator": creator_name,
		"version": version_str,
		"category": chosen_cat,
		"subcat": chosen_subcat,
		"section": "Trending",
		"type": item_type,
		"path": proj_path,
		"user_path": user_path,
		"icon_path": saved_icon_path,
		"thumb_kind": "folder" if (item_type == "folder" and saved_icon_path == "") else "",
		"script_path": script_p,
		"description": desc_str,
		"tags": _pub_tags_input.text.strip_edges() + " " + raw_name.to_lower() + " published custom",
		"thumbs_up": 1,
		"builtin": false,
		"published": _pub_marketplace_check.button_pressed,
		"verified": true,
	}

	_catalog_items.insert(0, new_entry)
	_save_user_catalog()

	if _pub_cloud_check.button_pressed:
		_copy_share_code_for_item(new_entry)
		_publish_item_to_cloud(new_entry)

	_active_tab = "Marketplace" if _pub_marketplace_check.button_pressed else "Creations"
	_active_subcat = ""
	_update_tab_styles()
	_rebuild_content()
	if plugin != null and plugin.get_editor_interface() != null:
		plugin.get_editor_interface().get_resource_filesystem().scan()
	if chosen_cat == "Folders" or item_type == "folder":
		_set_status("Published Folder '%s' with all items inside by %s to Toolbox Marketplace!" % [raw_name, creator_name], Color(0.52, 0.96, 0.64))
	else:
		_set_status("Published '%s' (by %s) to Toolbox Marketplace!" % [raw_name, creator_name], Color(0.52, 0.96, 0.64))


# ============================================================================
# CATALOG STORAGE, INSERTION & HELPERS
# ============================================================================

func _normalize_category(raw_cat: String, item_type: String) -> String:
	if raw_cat in ["Models", "UI / GUIs", "Scripts", "Folders", "Audio & Decals"]:
		return raw_cat
	if raw_cat == "Models + Scripts":
		return "Models"
	if item_type == "ui":
		return "UI / GUIs"
	if item_type == "script":
		return "Scripts"
	if item_type == "folder":
		return "Folders"
	if item_type == "audio" or item_type == "decal":
		return "Audio & Decals"
	return "Models"


func reload_catalog() -> void:
	_ensure_dirs()
	_load_ratings_state()
	_load_deleted_items()
	_catalog_items.clear()
	var seen_ids: Dictionary = {}

	for cat_path in [PROJECT_SAVED_CATALOG, USER_SAVED_CATALOG]:
		if FileAccess.file_exists(cat_path):
			var f: FileAccess = FileAccess.open(cat_path, FileAccess.READ)
			if f != null:
				var parsed: Variant = JSON.parse_string(f.get_as_text())
				if parsed is Array:
					for entry in (parsed as Array):
						if entry is Dictionary:
							var d: Dictionary = (entry as Dictionary).duplicate()
							var item_id: String = String(d.get("id", ""))
							var p: String = String(d.get("path", ""))
							var up: String = String(d.get("user_path", ""))
							var valid_path: String = p if (p != "" and FileAccess.file_exists(p)) else (up if (up != "" and FileAccess.file_exists(up)) else "")
							if item_id != "" and valid_path != "" and not seen_ids.has(item_id) and not _deleted_item_ids.has(item_id):
								d["path"] = valid_path
								d["builtin"] = false
								d["category"] = _normalize_category(String(d.get("category", "")), String(d.get("type", "")))
								if not d.has("published"):
									d["published"] = true
								seen_ids[item_id] = true
								_catalog_items.append(d)

	for scan_dir in [PROJECT_PUBLISHED_DIR, PROJECT_SAVED_DIR]:
		var dir: DirAccess = DirAccess.open(scan_dir)
		if dir != null:
			dir.list_dir_begin()
			var fname: String = dir.get_next()
			while fname != "":
				if not dir.current_is_dir() and not fname.ends_with(".json") and not fname.ends_with(".import") and not fname.ends_with(".uid") and not fname.contains("_icon."):
					var full_p: String = scan_dir + "/" + fname
					var auto_id: String = "saved_" + fname.get_basename()
					var already: bool = false
					for existing in _catalog_items:
						if String(existing.get("path", "")) == full_p or String(existing.get("id", "")) == auto_id:
							already = true
							break
					if not already and not _deleted_item_ids.has(auto_id):
						var ext: String = fname.get_extension().to_lower()
						var is_script: bool = (ext == "gd")
						var is_ui: bool = fname.to_lower().begins_with("ui_") or fname.to_lower().find("gui") >= 0 or fname.to_lower().find("hud") >= 0
						var is_folder: bool = fname.to_lower().find("folder") >= 0
						var is_media: bool = ext in ["mp3", "wav", "ogg", "png", "jpg", "jpeg"]
						var cat: String = "Scripts" if is_script else ("UI / GUIs" if is_ui else ("Folders" if is_folder else ("Audio & Decals" if is_media else "Models")))
						var tp: String = "script" if is_script else ("ui" if is_ui else ("folder" if is_folder else ("audio" if is_media else "model_script")))
						_catalog_items.append({
							"id": auto_id,
							"name": fname.get_basename().replace("_", " ").capitalize(),
							"creator": _get_default_creator_name(),
							"version": "1.0",
							"category": cat,
							"subcat": "STRUCTURE",
							"type": tp,
							"path": full_p,
							"script_path": full_p if is_script else "",
							"description": "Published in " + full_p,
							"tags": fname.get_basename().replace("_", " ") + " published custom",
							"thumbs_up": 1,
							"builtin": false,
							"published": true,
							"verified": true,
						})
				fname = dir.get_next()
			dir.list_dir_end()

	if FileAccess.file_exists(BUILTIN_CATALOG_PATH):
		var bf: FileAccess = FileAccess.open(BUILTIN_CATALOG_PATH, FileAccess.READ)
		if bf != null:
			var bparsed: Variant = JSON.parse_string(bf.get_as_text())
			if bparsed is Array:
				for entry in (bparsed as Array):
					if entry is Dictionary:
						var d: Dictionary = (entry as Dictionary).duplicate()
						var item_id: String = String(d.get("id", ""))
						if item_id != "" and not seen_ids.has(item_id) and not _deleted_item_ids.has(item_id):
							d["builtin"] = true
							d["category"] = _normalize_category(String(d.get("category", "")), String(d.get("type", "")))
							seen_ids[item_id] = true
							_catalog_items.append(d)

	_rebuild_content()


func _save_user_catalog() -> void:
	var saved_only: Array[Dictionary] = []
	for item in _catalog_items:
		if not bool(item.get("builtin", false)):
			saved_only.append(item)
	var json_str: String = JSON.stringify(saved_only, "\t")
	var pf: FileAccess = FileAccess.open(PROJECT_SAVED_CATALOG, FileAccess.WRITE)
	if pf != null:
		pf.store_string(json_str)
	var uf: FileAccess = FileAccess.open(USER_SAVED_CATALOG, FileAccess.WRITE)
	if uf != null:
		uf.store_string(json_str)
	if peer_toolbox != null and is_instance_valid(peer_toolbox) and peer_toolbox.has_method("reload_catalog"):
		peer_toolbox.call("reload_catalog")


func _on_upload_folder_pressed() -> void:
	if _folder_dialog != null:
		_folder_dialog.popup_centered_ratio(0.65)


func _on_folder_selected_to_publish(dir_path: String) -> void:
	if dir_path == "":
		return
	open_publish_dialog_for_fs_folder(dir_path)


func _confirm_publish_fs_folder(folder_path: String) -> void:
	if folder_path == "":
		_set_status("No folder specified to publish.", Color(1.0, 0.55, 0.55))
		return
	_ensure_dirs()
	var clean_path: String = folder_path
	if clean_path.ends_with("/"):
		clean_path = clean_path.left(-1)
	var raw_name: String = _pub_title_input.text.strip_edges()
	if raw_name == "":
		raw_name = clean_path.get_file()
	if raw_name == "":
		raw_name = "Folder"
	var slug: String = _slugify(raw_name)
	var readable_name: String = raw_name

	var container: Node3D = Node3D.new()
	container.name = slug.validate_node_name()
	container.set_meta("retroblox_folder", true)
	container.set_meta("retroblox_folder_source", clean_path)

	var files_packed: int = _package_fs_dir_into_node_recursive(clean_path, container)
	_embed_all_descendants_recursive(container, container)

	var packed: PackedScene = PackedScene.new()
	var pack_err: int = packed.pack(container)
	container.free()

	if pack_err != OK:
		_set_status("Failed to package folder hierarchy (error %d)." % pack_err, Color(1.0, 0.55, 0.55))
		return

	var proj_path: String = "%s/%s.tscn" % [PROJECT_PUBLISHED_DIR, slug]
	var user_path: String = "%s/%s.tscn" % [USER_SAVED_DIR, slug]
	ResourceSaver.save(packed, proj_path)
	ResourceSaver.save(packed, user_path)
	ResourceSaver.save(packed, "%s/%s.tscn" % [PROJECT_SAVED_DIR, slug])

	# Also copy the full folder on disk into toolbox published and user dirs so all loose assets are intact
	var proj_pub_folder: String = ProjectSettings.globalize_path("%s/%s" % [PROJECT_PUBLISHED_DIR, slug])
	var user_saved_folder: String = ProjectSettings.globalize_path("%s/%s" % [USER_SAVED_DIR, slug])
	_copy_dir_recursive(ProjectSettings.globalize_path(clean_path), proj_pub_folder)
	_copy_dir_recursive(ProjectSettings.globalize_path(clean_path), user_saved_folder)

	var saved_icon_path: String = ""
	if _pub_pending_icon_path != "":
		var global_src: String = ProjectSettings.globalize_path(_pub_pending_icon_path)
		var ibytes: PackedByteArray = FileAccess.get_file_as_bytes(_pub_pending_icon_path)
		if ibytes.is_empty():
			ibytes = FileAccess.get_file_as_bytes(global_src)
		if not ibytes.is_empty():
			var iext: String = _pub_pending_icon_path.get_extension().to_lower()
			saved_icon_path = "%s/%s_icon.%s" % [PROJECT_PUBLISHED_DIR, slug, iext]
			var user_icon_path: String = "%s/%s_icon.%s" % [USER_SAVED_DIR, slug, iext]
			var iwf1: FileAccess = FileAccess.open(saved_icon_path, FileAccess.WRITE)
			if iwf1 != null:
				iwf1.store_buffer(ibytes)
			var iwf2: FileAccess = FileAccess.open(user_icon_path, FileAccess.WRITE)
			if iwf2 != null:
				iwf2.store_buffer(ibytes)
			_thumb_cache.erase("file:" + saved_icon_path)
			_thumb_cache.erase("file:" + user_icon_path)
			_thumb_cache.erase("file:" + _pub_pending_icon_path)
			_custom_icons["published_" + slug] = saved_icon_path
			_save_ratings_state()

	var overwrite_id: String = ""
	if _pub_overwrite_option != null and _pub_overwrite_option.selected > 0:
		overwrite_id = String(_pub_overwrite_option.get_item_metadata(_pub_overwrite_option.selected))
	var item_id: String = overwrite_id if overwrite_id != "" else ("published_" + slug)

	for i in range(_catalog_items.size() - 1, -1, -1):
		if String(_catalog_items[i].get("id", "")) == item_id:
			_catalog_items.remove_at(i)

	var desc_text: String = _pub_desc_input.text.strip_edges()
	if desc_text == "":
		desc_text = "Folder '%s' (%s) containing %d item(s) inside." % [readable_name, clean_path, files_packed]
	var tags_text: String = _pub_tags_input.text.strip_edges()
	if tags_text == "":
		tags_text = "%s folder kit set collection filesystem published" % readable_name.to_lower()

	var entry: Dictionary = {
		"id": item_id,
		"name": readable_name,
		"creator": _pub_creator_input.text.strip_edges() if _pub_creator_input.text.strip_edges() != "" else _get_default_creator_name(),
		"version": _pub_version_input.text.strip_edges() if _pub_version_input.text.strip_edges() != "" else "1.0",
		"category": "Folders",
		"subcat": "STRUCTURE",
		"type": "folder",
		"path": proj_path,
		"user_path": user_path,
		"icon_path": saved_icon_path,
		"thumb_kind": "folder" if saved_icon_path == "" else "",
		"script_path": "",
		"description": desc_text,
		"tags": tags_text,
		"thumbs_up": 1,
		"builtin": false,
		"published": true,
		"verified": true,
	}

	_catalog_items.insert(0, entry)
	_save_user_catalog()
	if _pub_cloud_check != null and _pub_cloud_check.button_pressed:
		_publish_item_to_cloud(entry)

	_pub_target_fs_folder = ""
	_active_tab = "Creations"
	_update_tab_styles()
	_rebuild_content()
	if plugin != null and plugin.get_editor_interface() != null:
		plugin.get_editor_interface().get_resource_filesystem().scan()
	_set_status("Published FileSystem Folder '%s' with %d item(s) to Toolbox!" % [readable_name, files_packed], Color(0.55, 0.95, 0.65))


func _package_fs_dir_into_node_recursive(dir_path: String, parent_node: Node) -> int:
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return 0
	var count: int = 0
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not fname.begins_with(".") and fname != ".godot" and fname != ".import":
			var sub_path: String = dir_path.path_join(fname)
			if da.current_is_dir():
				var sub_node: Node3D = Node3D.new()
				sub_node.name = fname.validate_node_name()
				sub_node.set_meta("retroblox_folder", true)
				parent_node.add_child(sub_node)
				count += _package_fs_dir_into_node_recursive(sub_path, sub_node)
			else:
				var ext: String = fname.get_extension().to_lower()
				if ext in ["import", "uid"]:
					pass
				elif ext in ["tscn", "scn"]:
					var s_res: Resource = load(sub_path)
					if s_res is PackedScene:
						var s_inst: Node = (s_res as PackedScene).instantiate()
						if s_inst != null:
							s_inst.name = fname.get_basename().validate_node_name()
							parent_node.add_child(s_inst)
							count += 1
				elif ext in ["glb", "gltf"]:
					var g_res: Resource = load(sub_path)
					if g_res is PackedScene:
						var g_inst: Node = (g_res as PackedScene).instantiate()
						if g_inst != null:
							g_inst.name = fname.get_basename().validate_node_name()
							parent_node.add_child(g_inst)
							count += 1
					elif g_res is Mesh:
						var mi: MeshInstance3D = MeshInstance3D.new()
						mi.name = fname.get_basename().validate_node_name()
						mi.mesh = g_res as Mesh
						parent_node.add_child(mi)
						count += 1
				elif ext == "obj":
					var o_res: Resource = load(sub_path)
					if o_res is Mesh:
						var mi: MeshInstance3D = MeshInstance3D.new()
						mi.name = fname.get_basename().validate_node_name()
						mi.mesh = o_res as Mesh
						parent_node.add_child(mi)
						count += 1
				elif ext == "gd":
					var scr: Script = load(sub_path) as Script
					if scr != null:
						var sn: Node3D = Node3D.new()
						sn.name = fname.get_basename().validate_node_name()
						sn.set_script(scr)
						parent_node.add_child(sn)
						count += 1
				elif ext in ["mp3", "wav", "ogg"]:
					var st: AudioStream = load(sub_path) as AudioStream
					if st != null:
						var asp: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
						asp.name = fname.get_basename().validate_node_name()
						asp.stream = st
						parent_node.add_child(asp)
						count += 1
				elif ext in ["png", "jpg", "jpeg", "webp"]:
					if fname.to_lower().find("icon") < 0 and fname.to_lower().find("thumb") < 0:
						var tex: Texture2D = load(sub_path) as Texture2D
						if tex != null:
							var sprite: Sprite3D = Sprite3D.new()
							sprite.name = fname.get_basename().validate_node_name()
							sprite.texture = tex
							parent_node.add_child(sprite)
							count += 1
				else:
					count += 1
		fname = da.get_next()
	da.list_dir_end()
	return count


func _copy_dir_recursive(src: String, dst: String) -> void:
	var da_src: DirAccess = DirAccess.open(src)
	if da_src == null:
		return
	if not DirAccess.dir_exists_absolute(dst):
		DirAccess.make_dir_recursive_absolute(dst)
	da_src.list_dir_begin()
	var fname: String = da_src.get_next()
	while fname != "":
		if not fname.begins_with(".") and fname != ".godot" and fname != ".import":
			var src_item: String = src.path_join(fname)
			var dst_item: String = dst.path_join(fname)
			if da_src.current_is_dir():
				_copy_dir_recursive(src_item, dst_item)
			else:
				var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src_item)
				if not bytes.is_empty():
					var wf: FileAccess = FileAccess.open(dst_item, FileAccess.WRITE)
					if wf != null:
						wf.store_buffer(bytes)
		fname = da_src.get_next()
	da_src.list_dir_end()


func _on_upload_pressed() -> void:
	if _upload_dialog != null:
		_upload_dialog.popup_centered_ratio(0.65)


func _on_files_uploaded(paths: PackedStringArray) -> void:
	if paths.size() == 1:
		var single_p: String = paths[0]
		var fname: String = single_p.get_file()
		open_publish_dialog_for_selection()
		_pub_title_input.text = fname.get_basename().replace("_", " ").capitalize()
		var ext: String = fname.get_extension().to_lower()
		if ext == "gd":
			_pub_cat_option.selected = 1 # Scripts
			_pub_mode_option.selected = 1 # Script only
		elif ext in ["mp3", "wav", "ogg", "png", "jpg", "jpeg"]:
			_pub_cat_option.selected = 3 # Audio & Decals
		_set_status("Selected '%s' for publishing. Snapshot or choose an icon, then click OK!" % fname, Color(0.45, 0.88, 1.0))
		return
	_ensure_dirs()
	var imported_count: int = 0
	for src_path in paths:
		var fname: String = src_path.get_file()
		var ext: String = fname.get_extension().to_lower()
		var slug: String = _slugify(fname.get_basename())
		var dst_proj: String = "%s/%s.%s" % [PROJECT_PUBLISHED_DIR, slug, ext]
		var dst_user: String = "%s/%s.%s" % [USER_SAVED_DIR, slug, ext]

		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src_path)
		if bytes.is_empty():
			continue
		var wf1: FileAccess = FileAccess.open(dst_proj, FileAccess.WRITE)
		if wf1 != null:
			wf1.store_buffer(bytes)
		var wf2: FileAccess = FileAccess.open(dst_user, FileAccess.WRITE)
		if wf2 != null:
			wf2.store_buffer(bytes)

		var is_script: bool = (ext == "gd")
		var is_ui: bool = fname.to_lower().begins_with("ui_") or fname.to_lower().find("gui") >= 0 or fname.to_lower().find("hud") >= 0
		var is_folder: bool = fname.to_lower().find("folder") >= 0
		var is_media: bool = ext in ["mp3", "wav", "ogg", "png", "jpg", "jpeg"]
		var cat: String = "Scripts" if is_script else ("UI / GUIs" if is_ui else ("Folders" if is_folder else ("Audio & Decals" if is_media else "Models")))
		var item_type: String = "script" if is_script else ("ui" if is_ui else ("folder" if is_folder else ("audio" if is_media else "model_script")))
		var item_id: String = "published_" + slug
		for i in range(_catalog_items.size() - 1, -1, -1):
			if String(_catalog_items[i].get("id", "")) == item_id:
				_catalog_items.remove_at(i)

		var readable_name: String = fname.get_basename().replace("_", " ").replace("-", " ").capitalize()
		var entry: Dictionary = {
			"id": item_id,
			"name": readable_name,
			"creator": _get_default_creator_name(),
			"version": "1.0",
			"category": cat,
			"subcat": "STRUCTURE",
			"type": item_type,
			"path": dst_proj,
			"user_path": dst_user,
			"script_path": dst_proj if is_script else "",
			"description": "Uploaded & published " + fname + " into Toolbox.",
			"tags": readable_name.to_lower() + " uploaded published " + ext,
			"thumbs_up": 1,
			"builtin": false,
			"published": true,
			"verified": true,
		}
		_catalog_items.insert(0, entry)
		_publish_item_to_cloud(entry)
		imported_count += 1

	if imported_count > 0:
		_save_user_catalog()
		_active_tab = "Creations"
		_update_tab_styles()
		_rebuild_content()
		if plugin != null and plugin.get_editor_interface() != null:
			plugin.get_editor_interface().get_resource_filesystem().scan()
		_set_status("Uploaded & published %d file(s) to Toolbox Marketplace!" % imported_count, Color(0.55, 0.95, 0.65))


func _insert_toolbox_item(item: Dictionary) -> void:
	if plugin == null or plugin.get_editor_interface() == null:
		return
	var ei: EditorInterface = plugin.get_editor_interface()
	var root: Node = ei.get_edited_scene_root()
	if root == null:
		_set_status("Open a 3D scene first before inserting from the Toolbox.", Color(1.0, 0.65, 0.35))
		return

	var res_path: String = String(item.get("path", ""))
	if not FileAccess.file_exists(res_path):
		var up: String = String(item.get("user_path", ""))
		if up != "" and FileAccess.file_exists(up):
			res_path = up
		else:
			_set_status("Asset file not found: " + res_path, Color(1.0, 0.55, 0.55))
			return

	var item_id: String = String(item.get("id", ""))
	if item_id != "":
		_recent_ids.erase(item_id)
		_recent_ids.insert(0, item_id)

	var item_type: String = String(item.get("type", "model_script"))
	var cat: String = _normalize_category(String(item.get("category", "Models")), item_type)

	if item_type == "script" or res_path.ends_with(".gd"):
		var scr: Script = load(res_path) as Script
		if scr == null:
			_set_status("Could not load script: " + res_path, Color(1.0, 0.55, 0.55))
			return
		var sel: Node = _get_selected_node()
		if sel != null and sel != root:
			sel.set_script(scr)
			_set_status("Attached script '%s' to '%s'!" % [res_path.get_file(), sel.name], Color(0.55, 0.95, 0.65))
		else:
			var parent: Node = _get_target_parent_3d(root)
			var script_node: Node3D = Node3D.new()
			script_node.name = String(item.get("name", "ScriptNode")).validate_node_name()
			script_node.set_script(scr)
			parent.add_child(script_node, true)
			script_node.owner = root
			ei.get_selection().clear()
			ei.get_selection().add_node(script_node)
			_set_status("Inserted '%s' with script '%s'!" % [script_node.name, res_path.get_file()], Color(0.55, 0.95, 0.65))
		return

	var ext: String = res_path.get_extension().to_lower()
	if ext in ["mp3", "wav", "ogg"]:
		var stream: AudioStream = load(res_path) as AudioStream
		var asp: AudioStreamPlayer = AudioStreamPlayer.new()
		asp.name = String(item.get("name", "ToolboxSound")).validate_node_name()
		asp.stream = stream
		root.add_child(asp, true)
		asp.owner = root
		ei.get_selection().clear()
		ei.get_selection().add_node(asp)
		_set_status("Inserted Audio '%s'!" % asp.name, Color(0.55, 0.95, 0.65))
		return
	elif ext in ["png", "jpg", "jpeg"]:
		var tex: Texture2D = load(res_path) as Texture2D
		var decal: Decal = Decal.new()
		decal.name = String(item.get("name", "ToolboxDecal")).validate_node_name()
		decal.texture_albedo = tex
		var parent3d: Node = _get_target_parent_3d(root)
		parent3d.add_child(decal, true)
		decal.global_position = _get_spawn_position()
		decal.owner = root
		ei.get_selection().clear()
		ei.get_selection().add_node(decal)
		_set_status("Inserted Decal '%s'!" % decal.name, Color(0.55, 0.95, 0.65))
		return

	var packed_res: Resource = load(res_path)
	var inst: Node = null
	if packed_res is PackedScene:
		inst = (packed_res as PackedScene).instantiate()
	elif packed_res is Mesh:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = packed_res as Mesh
		mi.name = String(item.get("name", "MeshModel")).validate_node_name()
		inst = mi
	if inst == null:
		_set_status("Could not instantiate asset: " + res_path, Color(1.0, 0.55, 0.55))
		return

	if (inst is Control) or (inst is CanvasLayer) or cat == "UI / GUIs" or item_type == "ui":
		var ui_parent: Node = root if (inst is CanvasLayer) else _get_or_create_ui_parent(root)
		ui_parent.add_child(inst, true)
		_assign_owner_recursive(inst, root)
		ei.get_selection().clear()
		ei.get_selection().add_node(inst)
		_set_status("Inserted UI '%s' into '%s'!" % [String(item.get("name", inst.name)), ui_parent.name], Color(0.88, 0.62, 1.0))
		return

	var parent_node: Node = _get_target_parent_3d(root)
	var spawn_pos: Vector3 = _get_spawn_position()
	parent_node.add_child(inst, true)
	if inst is Node3D:
		(inst as Node3D).global_position = spawn_pos

	var is_item_folder: bool = (item_type == "folder" or cat == "Folders" or bool(inst.get_meta("retroblox_folder", false)) or inst.name.to_lower().find("folder") >= 0)
	if is_item_folder:
		inst.scene_file_path = ""
		_assign_owner_recursive(inst, root)
		var c_cnt: int = _count_subtree_nodes(inst) - 1
		ei.get_selection().clear()
		ei.get_selection().add_node(inst)
		_set_status("Inserted Folder '%s' with %d item(s) into scene!" % [String(item.get("name", inst.name)), c_cnt], Color(0.55, 0.95, 0.65))
		return

	_assign_owner_recursive(inst, root)

	ei.get_selection().clear()
	ei.get_selection().add_node(inst)
	_set_status("Inserted '%s' by %s at (%.0f, %.0f, %.0f)!" % [
		String(item.get("name", inst.name)),
		String(item.get("creator", "RetroBlox")),
		spawn_pos.x, spawn_pos.y, spawn_pos.z
	], Color(0.55, 0.95, 0.65))


func _open_script_in_editor(scr_path: String) -> void:
	if plugin == null or plugin.get_editor_interface() == null:
		return
	var scr: Script = load(scr_path) as Script
	if scr != null:
		plugin.get_editor_interface().edit_script(scr)
		plugin.get_editor_interface().set_main_screen_editor("Script")
		_set_status("Opened '%s' in the Script Editor." % scr_path.get_file(), Color(0.65, 0.88, 1.0))


func _on_rename_confirmed() -> void:
	var new_name: String = _rename_input.text.strip_edges()
	if new_name == "" or _renaming_item_id == "":
		return
	for item in _catalog_items:
		if String(item.get("id", "")) == _renaming_item_id:
			item["name"] = new_name
			break
	_renaming_item_id = ""
	_save_user_catalog()
	_rebuild_content()


func _delete_saved_item(item_id: String) -> void:
	if item_id == "":
		return
	_deleted_item_ids[item_id] = true
	_save_deleted_items()

	var deleted_name: String = item_id
	for i in range(_catalog_items.size() - 1, -1, -1):
		if String(_catalog_items[i].get("id", "")) == item_id:
			var item: Dictionary = _catalog_items[i]
			deleted_name = String(item.get("name", item_id))
			var p: String = String(item.get("path", ""))
			var up: String = String(item.get("user_path", ""))
			var ip: String = String(item.get("icon_path", ""))

			if p != "" and FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			if up != "" and FileAccess.file_exists(up):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(up))
			if ip != "" and FileAccess.file_exists(ip):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(ip))

			if _custom_icons.has(item_id):
				var cip: String = String(_custom_icons[item_id])
				if cip != "" and FileAccess.file_exists(cip):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(cip))
				_custom_icons.erase(item_id)

			var slug: String = _slugify(item_id)
			var proj_folder: String = ProjectSettings.globalize_path("%s/%s" % [PROJECT_PUBLISHED_DIR, slug])
			if DirAccess.dir_exists_absolute(proj_folder):
				_remove_dir_recursive(proj_folder)
			var user_folder: String = ProjectSettings.globalize_path("%s/%s" % [USER_SAVED_DIR, slug])
			if DirAccess.dir_exists_absolute(user_folder):
				_remove_dir_recursive(user_folder)

			_catalog_items.remove_at(i)
			break

	_thumb_cache.clear()
	_save_ratings_state()
	_save_user_catalog()
	_rebuild_content()
	if plugin != null and plugin.get_editor_interface() != null:
		plugin.get_editor_interface().get_resource_filesystem().scan()
	_set_status("Deleted '%s' from Toolbox (Owner Action)!" % deleted_name, Color(0.85, 0.85, 0.92))


func _load_deleted_items() -> void:
	_deleted_item_ids.clear()
	if FileAccess.file_exists(DELETED_ITEMS_SAVE_PATH):
		var f: FileAccess = FileAccess.open(DELETED_ITEMS_SAVE_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_deleted_item_ids = parsed as Dictionary


func _save_deleted_items() -> void:
	var f: FileAccess = FileAccess.open(DELETED_ITEMS_SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_deleted_item_ids, "\t"))


func _remove_dir_recursive(dir_path: String) -> void:
	var da: DirAccess = DirAccess.open(dir_path)
	if da == null:
		return
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			var sub_path: String = dir_path.path_join(fname)
			if da.current_is_dir():
				_remove_dir_recursive(sub_path)
			else:
				DirAccess.remove_absolute(sub_path)
		fname = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(dir_path)


func _make_flat_btn(txt: String, bg: Color, fg: Color) -> Button:
	var b: Button = Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 24)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = bg.lightened(0.24)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	var hov: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	hov.bg_color = bg.lightened(0.14)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_font_size_override("font_size", 11)
	return b


func _make_mini_btn(txt: String, bg: Color) -> Button:
	var b: Button = Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 18)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 9)
	return b


func _update_tab_styles() -> void:
	for tab_id in _tab_buttons.keys():
		var b: Button = _tab_buttons[tab_id] as Button
		var active: bool = (tab_id == _active_tab)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.18, 0.18, 0.18, 1.0) if active else Color(0.13, 0.13, 0.13, 1.0)
		sb.border_width_top = 3 if active else 0
		sb.border_width_bottom = 0 if active else 1
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_color = Color(0.0, 0.64, 1.0, 1.0) if active else Color(0.09, 0.09, 0.09, 1.0)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.modulate = Color(1, 1, 1, 1) if active else Color(0.68, 0.68, 0.68, 1)


func _update_bg_button_styles() -> void:
	for mode_name in _bg_buttons.keys():
		var b: Button = _bg_buttons[mode_name] as Button
		var active: bool = (mode_name == _bg_mode)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.0, 0.58, 0.96, 1.0) if active else Color(0.22, 0.22, 0.22, 1.0)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 6.0
		sb.content_margin_right = 6.0
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_color_override("font_color", Color.WHITE)


func _get_selected_node() -> Node:
	if plugin == null or plugin.get_editor_interface() == null:
		return null
	var nodes: Array[Node] = plugin.get_editor_interface().get_selection().get_selected_nodes()
	if nodes.is_empty():
		return null
	return nodes[0]


func _get_target_parent_3d(root: Node) -> Node:
	var sel: Node = _get_selected_node()
	if sel != null and sel is Node3D and (bool(sel.get_meta("retroblox_folder", false)) or sel.name == "World" or sel.name.to_lower().find("folder") >= 0):
		return sel
	var world: Node = root.get_node_or_null("World")
	if world != null:
		return world
	return root


func _get_or_create_ui_parent(root: Node) -> Node:
	var sel: Node = _get_selected_node()
	if sel != null and ((sel is Control) or (sel is CanvasLayer)):
		return sel
	for candidate_name in ["UI", "HUD", "CanvasLayer", "ScreenGui"]:
		var existing: Node = root.get_node_or_null(candidate_name)
		if existing != null and ((existing is CanvasLayer) or (existing is Control)):
			return existing
	if root is Control or root is CanvasLayer:
		return root
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "UI"
	root.add_child(canvas, true)
	canvas.owner = root
	return canvas


func _get_spawn_position() -> Vector3:
	if plugin != null and plugin.has_method("_get_spawn_pos"):
		var pos_v: Variant = plugin.call("_get_spawn_pos")
		if pos_v is Vector3:
			return pos_v as Vector3
	if plugin != null and plugin.get_editor_interface() != null:
		var vp: SubViewport = plugin.get_editor_interface().get_editor_viewport_3d(0)
		if vp != null and vp.get_camera_3d() != null:
			var cam: Camera3D = vp.get_camera_3d()
			var p: Vector3 = cam.global_position - cam.global_transform.basis.z * 14.0
			p.y = maxf(1.0, snappedf(p.y, 1.0))
			p.x = snappedf(p.x, 1.0)
			p.z = snappedf(p.z, 1.0)
			return p
	return Vector3(0, 2, 0)


func _assign_owner_recursive(node: Node, new_owner: Node) -> void:
	if node != new_owner:
		node.owner = new_owner
	for ch in node.get_children():
		_assign_owner_recursive(ch, new_owner)


func _embed_all_descendants_recursive(node: Node, root_owner: Node) -> void:
	if node != root_owner:
		node.owner = root_owner
		node.scene_file_path = ""
	for ch in node.get_children():
		_embed_all_descendants_recursive(ch, root_owner)


func _find_first_script_in_subtree(node: Node) -> String:
	if node.get_script() is Script:
		return (node.get_script() as Script).resource_path
	for ch in node.get_children():
		var found: String = _find_first_script_in_subtree(ch)
		if found != "":
			return found
	return ""


func _count_subtree_nodes(node: Node) -> int:
	var total: int = 1
	for ch in node.get_children():
		total += _count_subtree_nodes(ch)
	return total


func _slugify(raw: String) -> String:
	var s: String = raw.strip_edges().to_lower()
	var out: String = ""
	for i in range(s.length()):
		var c: int = s.unicode_at(i)
		if (c >= 97 and c <= 122) or (c >= 48 and c <= 57):
			out += char(c)
		elif not out.ends_with("_"):
			out += "_"
	out = out.trim_prefix("_").trim_suffix("_")
	if out == "":
		out = "custom_asset_" + str(Time.get_ticks_msec() % 100000)
	return out


func _set_status(msg: String, col: Color) -> void:
	if _status_label != null:
		_status_label.text = msg
		_status_label.add_theme_color_override("font_color", col)
