@tool
extends AcceptDialog

# RetroBlox Studio - Lighting & Atmosphere Studio
# Allows creators to apply vibrant HD Roblox lighting presets,
# customize atmosphere, and upload/publish custom lighting setups
# with thumbnails to the Toolbox and Cloud for other creators to use.

signal lighting_applied(preset_name: String)
signal lighting_published(preset_data: Dictionary)

const BUILTIN_CATALOG_PATH: String = "res://toolbox/toolbox_catalog.json"
const USER_SAVED_CATALOG: String = "user://retroblox_toolbox_catalog.json"
const PROJECT_LIGHTING_DIR: String = "res://toolbox/published/lighting"
const USER_LIGHTING_DIR: String = "user://retroblox_toolbox_models/lighting"
const SERVER_URL: String = "https://retro-blox.vercel.app"
const CLOUD_TOOLBOX_CHANNEL: String = "retroblox_dev_toolbox_v2"

var plugin: EditorPlugin

var _tab_container: TabContainer
var _presets_grid: GridContainer
var _search_input: LineEdit
var _filter_option: OptionButton
var _status_lbl: Label

# Upload Controls
var _detected_env_lbl: Label
var _detected_lights_lbl: Label
var _upload_name_edit: LineEdit
var _upload_creator_edit: LineEdit
var _upload_tags_edit: LineEdit
var _upload_desc_edit: TextEdit
var _thumb_preview: TextureRect
var _thumb_source_lbl: Label
var _sync_cloud_check: CheckBox
var _copy_code_check: CheckBox
var _pending_thumb_image: Image
var _pending_thumb_path: String = ""
var _file_dialog: FileDialog

var _cached_presets: Array[Dictionary] = []


func _init() -> void:
	title = "RetroBlox - Lighting & Atmosphere Studio"
	size = Vector2i(860, 640)
	min_size = Vector2i(680, 500)
	unresizable = false
	ok_button_text = "Close"


func _ready() -> void:
	confirmed.connect(hide)
	close_requested.connect(hide)
	_build_ui()
	_refresh_presets()


func _build_ui() -> void:
	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# 1. Top Header Bar
	var top_bar: PanelContainer = PanelContainer.new()
	var top_sb: StyleBoxFlat = StyleBoxFlat.new()
	top_sb.bg_color = Color(0.14, 0.16, 0.20, 1.0)
	top_sb.content_margin_left = 12.0
	top_sb.content_margin_right = 12.0
	top_sb.content_margin_top = 8.0
	top_sb.content_margin_bottom = 8.0
	top_bar.add_theme_stylebox_override("panel", top_sb)
	main_vbox.add_child(top_bar)

	var top_h: HBoxContainer = HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 10)
	top_bar.add_child(top_h)

	var title_vb: VBoxContainer = VBoxContainer.new()
	title_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(title_vb)

	var h_title: Label = Label.new()
	h_title.text = "RetroBlox Lighting & Atmosphere Presets"
	h_title.add_theme_font_size_override("font_size", 14)
	title_vb.add_child(h_title)

	var h_sub: Label = Label.new()
	h_sub.text = "Apply vibrant Roblox HD lighting or upload custom sky/light setups with thumbnails for everyone to use."
	h_sub.add_theme_font_size_override("font_size", 11)
	h_sub.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	title_vb.add_child(h_sub)

	# Quick 1-Click Roblox HD Button
	var hd_btn: Button = Button.new()
	hd_btn.text = "Apply Roblox HD Lighting"
	hd_btn.tooltip_text = "Instant 1-click vibrant Roblox HD daytime lighting with Sun, SkyFillLight, SSAO & material fix"
	hd_btn.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	var hd_sb := StyleBoxFlat.new()
	hd_sb.bg_color = Color(0.12, 0.44, 0.82)
	hd_sb.set_corner_radius_all(4)
	hd_sb.content_margin_left = 10.0
	hd_sb.content_margin_right = 10.0
	hd_sb.content_margin_top = 6.0
	hd_sb.content_margin_bottom = 6.0
	hd_btn.add_theme_stylebox_override("normal", hd_sb)
	hd_btn.pressed.connect(func() -> void:
		apply_preset_by_id("roblox_hd")
	)
	top_h.add_child(hd_btn)

	var upload_tab_btn: Button = Button.new()
	upload_tab_btn.text = "+ Upload Lighting"
	upload_tab_btn.tooltip_text = "Upload current scene lighting to the Toolbox and Cloud"
	upload_tab_btn.pressed.connect(func() -> void:
		if _tab_container != null:
			_tab_container.current_tab = 1
			_refresh_upload_scan()
	)
	top_h.add_child(upload_tab_btn)

	# 2. Tabs
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_tab_container)

	_build_presets_tab()
	_build_upload_tab()

	# 3. Status Bar at Bottom
	_status_lbl = Label.new()
	_status_lbl.text = "Ready. Select a lighting preset or capture your scene lighting to upload."
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.add_theme_color_override("font_color", Color(0.68, 0.82, 0.95))
	main_vbox.add_child(_status_lbl)

	# FileDialog for thumbnail browsing
	_file_dialog = FileDialog.new()
	_file_dialog.title = "Select Thumbnail Image for Lighting Preset"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Image Files"])
	_file_dialog.file_selected.connect(_on_thumbnail_file_selected)
	add_child(_file_dialog)


func open_upload_tab() -> void:
	if _tab_container != null:
		_tab_container.current_tab = 1
		_refresh_upload_scan()


# ============================================================================
# TAB 1: PRESET BROWSER
# ============================================================================

func _build_presets_tab() -> void:
	var tab_vb: VBoxContainer = VBoxContainer.new()
	tab_vb.name = "Lighting Presets"
	tab_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_vb.add_theme_constant_override("separation", 8)
	_tab_container.add_child(tab_vb)

	# Filter / Search Bar
	var search_bar: HBoxContainer = HBoxContainer.new()
	search_bar.add_theme_constant_override("separation", 6)
	tab_vb.add_child(search_bar)

	var s_lbl: Label = Label.new()
	s_lbl.text = "Search:"
	search_bar.add_child(s_lbl)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search presets by name or mood (e.g. sunset, hd, night, overcast)..."
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.text_changed.connect(func(_t: String) -> void: _render_preset_cards())
	search_bar.add_child(_search_input)

	_filter_option = OptionButton.new()
	_filter_option.add_item("All Presets")
	_filter_option.add_item("Built-in HD")
	_filter_option.add_item("Community & Uploaded")
	_filter_option.item_selected.connect(func(_idx: int) -> void: _render_preset_cards())
	search_bar.add_child(_filter_option)

	var refresh_btn: Button = Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.tooltip_text = "Reload all local and cloud lighting presets"
	refresh_btn.pressed.connect(_refresh_presets)
	search_bar.add_child(refresh_btn)

	# Scrollable Cards Grid
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_vb.add_child(scroll)

	_presets_grid = GridContainer.new()
	_presets_grid.columns = 2
	_presets_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_presets_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_presets_grid.add_theme_constant_override("h_separation", 10)
	_presets_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_presets_grid)


func _refresh_presets() -> void:
	_cached_presets.clear()
	var seen_ids: Dictionary = {}

	# 1. Load from BUILTIN_CATALOG_PATH
	if FileAccess.file_exists(BUILTIN_CATALOG_PATH):
		var bf: FileAccess = FileAccess.open(BUILTIN_CATALOG_PATH, FileAccess.READ)
		if bf != null:
			var txt: String = bf.get_as_text()
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Array:
				for it in parsed:
					if it is Dictionary:
						var d := it as Dictionary
						var cat: String = String(d.get("category", ""))
						var t: String = String(d.get("type", ""))
						if cat == "Lighting" or t == "lighting":
							var pid: String = String(d.get("id", ""))
							if pid != "" and not seen_ids.has(pid):
								seen_ids[pid] = true
								_cached_presets.append(d)

	# 2. Load from USER_SAVED_CATALOG
	if FileAccess.file_exists(USER_SAVED_CATALOG):
		var uf: FileAccess = FileAccess.open(USER_SAVED_CATALOG, FileAccess.READ)
		if uf != null:
			var txt: String = uf.get_as_text()
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Array:
				for it in parsed:
					if it is Dictionary:
						var d := it as Dictionary
						var cat: String = String(d.get("category", ""))
						var t: String = String(d.get("type", ""))
						if cat == "Lighting" or t == "lighting":
							var pid: String = String(d.get("id", ""))
							if pid != "" and not seen_ids.has(pid):
								seen_ids[pid] = true
								_cached_presets.append(d)

	_render_preset_cards()


func _render_preset_cards() -> void:
	if _presets_grid == null:
		return
	for ch in _presets_grid.get_children():
		ch.queue_free()

	var query: String = _search_input.text.strip_edges().to_lower() if _search_input != null else ""
	var filter_mode: int = _filter_option.selected if _filter_option != null else 0

	for item in _cached_presets:
		var item_name: String = String(item.get("name", "Lighting Preset"))
		var creator: String = String(item.get("creator", "RetroBlox"))
		var desc: String = String(item.get("description", ""))
		var tags: String = String(item.get("tags", "")).to_lower()
		var is_builtin: bool = bool(item.get("builtin", false))

		if filter_mode == 1 and not is_builtin:
			continue
		elif filter_mode == 2 and is_builtin:
			continue

		if query != "":
			var full_haystack := (item_name + " " + creator + " " + desc + " " + tags).to_lower()
			if full_haystack.find(query) < 0:
				continue

		var card: PanelContainer = _build_preset_card(item)
		_presets_grid.add_child(card)


func _build_preset_card(item: Dictionary) -> PanelContainer:
	var pc: PanelContainer = PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.20, 0.24, 1.0)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.28, 0.32, 0.38, 1.0)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	pc.add_theme_stylebox_override("panel", sb)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	pc.add_child(hbox)

	# Thumbnail (110x110)
	var thumb_rect: TextureRect = TextureRect.new()
	thumb_rect.custom_minimum_size = Vector2(110, 110)
	thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb_rect.texture = _load_preset_texture(item)
	hbox.add_child(thumb_rect)

	# Info column
	var info_vb: VBoxContainer = VBoxContainer.new()
	info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vb.add_theme_constant_override("separation", 4)
	hbox.add_child(info_vb)

	var title_lbl: Label = Label.new()
	title_lbl.text = String(item.get("name", "Lighting"))
	title_lbl.add_theme_font_size_override("font_size", 13)
	info_vb.add_child(title_lbl)

	var creator_lbl: Label = Label.new()
	creator_lbl.text = "by " + String(item.get("creator", "RetroBlox"))
	creator_lbl.add_theme_font_size_override("font_size", 10)
	creator_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.88))
	info_vb.add_child(creator_lbl)

	var desc_lbl: Label = Label.new()
	desc_lbl.text = String(item.get("description", "Vibrant environment lighting"))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.80, 0.84, 0.88))
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_vb.add_child(desc_lbl)

	# Buttons Row
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	info_vb.add_child(btn_row)

	var apply_btn: Button = Button.new()
	apply_btn.text = "Use in Scene"
	apply_btn.tooltip_text = "Apply this lighting setup directly to active 3D scene"
	apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_btn.pressed.connect(func() -> void:
		_apply_lighting_preset(item)
	)
	btn_row.add_child(apply_btn)

	var code_btn: Button = Button.new()
	code_btn.text = "Share Code"
	code_btn.tooltip_text = "Copy share code to clipboard"
	code_btn.pressed.connect(func() -> void:
		_copy_share_code(item)
	)
	btn_row.add_child(code_btn)

	return pc


func _load_preset_texture(item: Dictionary) -> Texture2D:
	var icon_p: String = String(item.get("icon_path", ""))
	if icon_p != "":
		var glob_p: String = ProjectSettings.globalize_path(icon_p)
		var load_p: String = glob_p if FileAccess.file_exists(glob_p) else icon_p
		if FileAccess.file_exists(load_p):
			var img: Image = Image.load_from_file(load_p)
			if img != null and not img.is_empty():
				return ImageTexture.create_from_image(img)
		if icon_p.begins_with("res://") and ResourceLoader.exists(icon_p):
			var r: Resource = load(icon_p)
			if r is Texture2D:
				return r as Texture2D

	# Fallback to default HD icon
	var fb_path := "res://assets/icons/lighting/lighting_roblox_hd.png"
	if ResourceLoader.exists(fb_path):
		var r: Resource = load(fb_path)
		if r is Texture2D:
			return r as Texture2D
	return null


# ============================================================================
# TAB 2: UPLOAD & PUBLISH CUSTOM LIGHTING
# ============================================================================

func _build_upload_tab() -> void:
	var tab_vb: VBoxContainer = VBoxContainer.new()
	tab_vb.name = "Upload Lighting"
	tab_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_vb.add_theme_constant_override("separation", 10)
	_tab_container.add_child(tab_vb)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_vb.add_child(scroll)

	var form_vb: VBoxContainer = VBoxContainer.new()
	form_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_vb.add_theme_constant_override("separation", 10)
	scroll.add_child(form_vb)

	# 1. Detection card
	var det_panel: PanelContainer = PanelContainer.new()
	var dsb: StyleBoxFlat = StyleBoxFlat.new()
	dsb.bg_color = Color(0.12, 0.14, 0.18, 1.0)
	dsb.border_width_left = 2
	dsb.border_color = Color(0.24, 0.58, 0.94, 1.0)
	dsb.set_corner_radius_all(4)
	dsb.content_margin_left = 10.0
	dsb.content_margin_right = 10.0
	dsb.content_margin_top = 8.0
	dsb.content_margin_bottom = 8.0
	det_panel.add_theme_stylebox_override("panel", dsb)
	form_vb.add_child(det_panel)

	var det_vb: VBoxContainer = VBoxContainer.new()
	det_vb.add_theme_constant_override("separation", 4)
	det_panel.add_child(det_vb)

	var det_title: Label = Label.new()
	det_title.text = "Scene Lighting Scanner"
	det_title.add_theme_font_size_override("font_size", 12)
	det_vb.add_child(det_title)

	_detected_env_lbl = Label.new()
	_detected_env_lbl.text = "Scanning scene for WorldEnvironment..."
	_detected_env_lbl.add_theme_font_size_override("font_size", 11)
	det_vb.add_child(_detected_env_lbl)

	_detected_lights_lbl = Label.new()
	_detected_lights_lbl.text = "Scanning scene for DirectionalLight3D..."
	_detected_lights_lbl.add_theme_font_size_override("font_size", 11)
	det_vb.add_child(_detected_lights_lbl)

	var scan_btn: Button = Button.new()
	scan_btn.text = "Rescan Active Scene"
	scan_btn.pressed.connect(_refresh_upload_scan)
	det_vb.add_child(scan_btn)

	# 2. Name & Creator
	var grid_inputs: GridContainer = GridContainer.new()
	grid_inputs.columns = 2
	grid_inputs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_inputs.add_theme_constant_override("h_separation", 10)
	grid_inputs.add_theme_constant_override("v_separation", 8)
	form_vb.add_child(grid_inputs)

	var name_lbl: Label = Label.new()
	name_lbl.text = "Preset Name:"
	grid_inputs.add_child(name_lbl)

	_upload_name_edit = LineEdit.new()
	_upload_name_edit.placeholder_text = "e.g. Sunset Golden Hour, Neon Midnight, Spooky Mist"
	_upload_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_inputs.add_child(_upload_name_edit)

	var creator_lbl: Label = Label.new()
	creator_lbl.text = "Creator Name:"
	grid_inputs.add_child(creator_lbl)

	_upload_creator_edit = LineEdit.new()
	_upload_creator_edit.placeholder_text = "e.g. Nexico8225"
	_upload_creator_edit.text = "Nexico8225"
	_upload_creator_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_inputs.add_child(_upload_creator_edit)

	var tags_lbl: Label = Label.new()
	tags_lbl.text = "Atmosphere Tags:"
	grid_inputs.add_child(tags_lbl)

	_upload_tags_edit = LineEdit.new()
	_upload_tags_edit.placeholder_text = "e.g. sunset, warm, haze, orange, realistic, obby"
	_upload_tags_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_inputs.add_child(_upload_tags_edit)

	# 3. Description
	var desc_lbl: Label = Label.new()
	desc_lbl.text = "Description:"
	form_vb.add_child(desc_lbl)

	_upload_desc_edit = TextEdit.new()
	_upload_desc_edit.custom_minimum_size = Vector2(0, 60)
	_upload_desc_edit.placeholder_text = "Describe the lighting setup, mood, and atmosphere..."
	form_vb.add_child(_upload_desc_edit)

	# 4. Thumbnail Section
	var thumb_sec: HBoxContainer = HBoxContainer.new()
	thumb_sec.add_theme_constant_override("separation", 12)
	form_vb.add_child(thumb_sec)

	_thumb_preview = TextureRect.new()
	_thumb_preview.custom_minimum_size = Vector2(100, 100)
	_thumb_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_set_default_thumb_preview()
	thumb_sec.add_child(_thumb_preview)

	var thumb_controls_vb: VBoxContainer = VBoxContainer.new()
	thumb_controls_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb_controls_vb.add_theme_constant_override("separation", 6)
	thumb_sec.add_child(thumb_controls_vb)

	var thumb_hdr: Label = Label.new()
	thumb_hdr.text = "Preset Thumbnail Image"
	thumb_hdr.add_theme_font_size_override("font_size", 12)
	thumb_controls_vb.add_child(thumb_hdr)

	_thumb_source_lbl = Label.new()
	_thumb_source_lbl.text = "No custom thumbnail selected (using default icon)."
	_thumb_source_lbl.add_theme_font_size_override("font_size", 10)
	_thumb_source_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.85))
	thumb_controls_vb.add_child(_thumb_source_lbl)

	var t_btn_row: HBoxContainer = HBoxContainer.new()
	t_btn_row.add_theme_constant_override("separation", 8)
	thumb_controls_vb.add_child(t_btn_row)

	var snap_btn: Button = Button.new()
	snap_btn.text = "Capture 3D Viewport"
	snap_btn.tooltip_text = "Take a snapshot directly from Godot's active 3D camera viewport"
	snap_btn.pressed.connect(_capture_3d_viewport_as_thumb)
	t_btn_row.add_child(snap_btn)

	var browse_btn: Button = Button.new()
	browse_btn.text = "Browse Image File..."
	browse_btn.tooltip_text = "Select a custom PNG or JPG image from your computer"
	browse_btn.pressed.connect(func() -> void:
		_file_dialog.popup_centered_ratio(0.65)
	)
	t_btn_row.add_child(browse_btn)

	var reset_thumb_btn: Button = Button.new()
	reset_thumb_btn.text = "Reset"
	reset_thumb_btn.pressed.connect(_reset_thumbnail)
	t_btn_row.add_child(reset_thumb_btn)

	# 5. Sharing Checkboxes
	_sync_cloud_check = CheckBox.new()
	_sync_cloud_check.text = "Sync to RetroBlox Online Dev Cloud (so everyone online can see and use it!)"
	_sync_cloud_check.button_pressed = true
	form_vb.add_child(_sync_cloud_check)

	_copy_code_check = CheckBox.new()
	_copy_code_check.text = "Copy Dev Share Code to Clipboard"
	_copy_code_check.button_pressed = true
	form_vb.add_child(_copy_code_check)

	# 6. Publish Button
	var pub_btn: Button = Button.new()
	pub_btn.text = "Publish Lighting to Community / Toolbox"
	pub_btn.custom_minimum_size = Vector2(0, 36)
	var pub_sb: StyleBoxFlat = StyleBoxFlat.new()
	pub_sb.bg_color = Color(0.18, 0.54, 0.28, 1.0)
	pub_sb.set_corner_radius_all(5)
	pub_btn.add_theme_stylebox_override("normal", pub_sb)
	pub_btn.pressed.connect(_on_publish_button_pressed)
	form_vb.add_child(pub_btn)


func _set_default_thumb_preview() -> void:
	var def_p := "res://assets/icons/lighting/lighting_roblox_hd.png"
	if ResourceLoader.exists(def_p):
		var r: Resource = load(def_p)
		if r is Texture2D:
			_thumb_preview.texture = r as Texture2D


func _reset_thumbnail() -> void:
	_pending_thumb_image = null
	_pending_thumb_path = ""
	_thumb_source_lbl.text = "No custom thumbnail selected (using default icon)."
	_set_default_thumb_preview()


func _capture_3d_viewport_as_thumb() -> void:
	var vp: SubViewport = null
	if plugin != null and plugin.get_editor_interface() != null:
		vp = plugin.get_editor_interface().get_editor_viewport_3d(0)
	if vp == null:
		vp = get_viewport() as SubViewport
	if vp == null:
		_set_status("Could not locate 3D editor viewport.", Color(1.0, 0.5, 0.5))
		return

	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		_set_status("Viewport texture is null.", Color(1.0, 0.5, 0.5))
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		_set_status("Could not capture viewport image.", Color(1.0, 0.5, 0.5))
		return

	var min_dim: int = mini(img.get_width(), img.get_height())
	var sx: int = (img.get_width() - min_dim) / 2
	var sy: int = (img.get_height() - min_dim) / 2
	var cropped: Image = img.get_region(Rect2i(sx, sy, min_dim, min_dim))
	cropped.resize(128, 128, Image.INTERPOLATE_LANCZOS)

	_pending_thumb_image = cropped
	_pending_thumb_path = "captured_viewport"
	_thumb_preview.texture = ImageTexture.create_from_image(cropped)
	_thumb_source_lbl.text = "Active 3D Viewport snapshot captured (128x128)."
	_set_status("Captured 3D viewport snapshot for thumbnail!", Color(0.55, 0.95, 0.65))


func _on_thumbnail_file_selected(file_path: String) -> void:
	var img: Image = Image.load_from_file(file_path)
	if img == null or img.is_empty():
		_set_status("Could not load image: " + file_path, Color(1.0, 0.5, 0.5))
		return
	if img.get_width() != 128 or img.get_height() != 128:
		img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	_pending_thumb_image = img
	_pending_thumb_path = file_path
	_thumb_preview.texture = ImageTexture.create_from_image(img)
	_thumb_source_lbl.text = "Image loaded: " + file_path.get_file()
	_set_status("Loaded thumbnail: " + file_path.get_file(), Color(0.55, 0.95, 0.65))


func _refresh_upload_scan() -> void:
	var scene_root: Node = get_tree().edited_scene_root
	if scene_root == null:
		_detected_env_lbl.text = "No scene open. Please open a 3D scene in Godot."
		_detected_lights_lbl.text = ""
		return

	var env: WorldEnvironment = scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env != null:
		_detected_env_lbl.text = "WorldEnvironment: FOUND (Sky background & Tonemap ready)"
		_detected_env_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
	else:
		_detected_env_lbl.text = "WorldEnvironment: NOT FOUND (Tip: Click 'Apply Roblox HD Lighting' to create one)"
		_detected_env_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))

	var light_names: Array[String] = []
	for ch in scene_root.get_children():
		if ch is DirectionalLight3D:
			light_names.append(ch.name)
	if light_names.size() > 0:
		_detected_lights_lbl.text = "Directional Lights: " + ", ".join(light_names)
		_detected_lights_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
	else:
		_detected_lights_lbl.text = "Directional Lights: None found in scene root."
		_detected_lights_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))


func _on_publish_button_pressed() -> void:
	var scene_root: Node = get_tree().edited_scene_root
	if scene_root == null:
		_set_status("Open a 3D scene first before publishing lighting.", Color(1.0, 0.5, 0.5))
		return

	var p_name: String = _upload_name_edit.text.strip_edges()
	if p_name == "":
		_set_status("Please enter a Preset Name before publishing.", Color(1.0, 0.5, 0.5))
		return

	var creator: String = _upload_creator_edit.text.strip_edges()
	if creator == "":
		creator = "Creator"

	var desc: String = _upload_desc_edit.text.strip_edges()
	var tags: String = _upload_tags_edit.text.strip_edges()

	# Create a LightingSetup container node with duplicates of WorldEnvironment and DirectionalLights
	var lighting_root: Node3D = Node3D.new()
	lighting_root.name = p_name.validate_node_name()

	var w_env: WorldEnvironment = scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if w_env != null:
		var cloned_env: WorldEnvironment = w_env.duplicate() as WorldEnvironment
		cloned_env.name = "WorldEnvironment"
		lighting_root.add_child(cloned_env)
		cloned_env.owner = lighting_root
	else:
		# If none present, generate vibrant default environment
		var default_env := _create_procedural_env(Color(0.10, 0.52, 0.92), Color(0.72, 0.90, 1.0))
		var new_w_env := WorldEnvironment.new()
		new_w_env.name = "WorldEnvironment"
		new_w_env.environment = default_env
		lighting_root.add_child(new_w_env)
		new_w_env.owner = lighting_root

	var found_any_light: bool = false
	for ch in scene_root.get_children():
		if ch is DirectionalLight3D:
			var d_clone: DirectionalLight3D = (ch as DirectionalLight3D).duplicate() as DirectionalLight3D
			d_clone.name = ch.name
			lighting_root.add_child(d_clone)
			d_clone.owner = lighting_root
			found_any_light = true

	if not found_any_light:
		var def_sun := DirectionalLight3D.new()
		def_sun.name = "Sun"
		def_sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
		def_sun.light_color = Color(1.0, 0.95, 0.86)
		def_sun.light_energy = 0.90
		def_sun.shadow_enabled = true
		lighting_root.add_child(def_sun)
		def_sun.owner = lighting_root

	# Pack to scene
	var ps: PackedScene = PackedScene.new()
	var pack_err: Error = ps.pack(lighting_root)
	if pack_err != OK:
		lighting_root.queue_free()
		_set_status("Failed to pack lighting nodes into scene: %d" % pack_err, Color(1.0, 0.5, 0.5))
		return

	# Ensure target directories exist
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROJECT_LIGHTING_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_LIGHTING_DIR))

	var slug: String = _slugify(p_name)
	var timestamp: int = int(Time.get_unix_time_from_system())
	var file_base: String = "lighting_%s_%d" % [slug, timestamp]

	var proj_tscn: String = "%s/%s.tscn" % [PROJECT_LIGHTING_DIR, file_base]
	var user_tscn: String = "%s/%s.tscn" % [USER_LIGHTING_DIR, file_base]
	var global_proj_tscn: String = ProjectSettings.globalize_path(proj_tscn)
	var global_user_tscn: String = ProjectSettings.globalize_path(user_tscn)

	ResourceSaver.save(ps, proj_tscn)
	ResourceSaver.save(ps, global_user_tscn)
	lighting_root.queue_free()

	# Save thumbnail image
	var proj_thumb: String = "%s/%s_thumb.png" % [PROJECT_LIGHTING_DIR, file_base]
	var user_thumb: String = "%s/%s_thumb.png" % [USER_LIGHTING_DIR, file_base]
	var thumb_img_to_save: Image = _pending_thumb_image
	if thumb_img_to_save == null or thumb_img_to_save.is_empty():
		# Auto capture viewport if creator didn't specify one
		thumb_img_to_save = _auto_capture_viewport_or_icon()

	if thumb_img_to_save != null and not thumb_img_to_save.is_empty():
		thumb_img_to_save.save_png(ProjectSettings.globalize_path(proj_thumb))
		thumb_img_to_save.save_png(ProjectSettings.globalize_path(user_thumb))

	var item_dict: Dictionary = {
		"id": file_base,
		"name": p_name,
		"creator": creator,
		"version": "1.0",
		"category": "Lighting",
		"subcat": "LIGHT",
		"section": "Creations",
		"thumb_kind": "lighting",
		"icon_path": proj_thumb,
		"type": "lighting",
		"path": proj_tscn,
		"user_path": user_tscn,
		"description": desc,
		"tags": tags + " lighting atmosphere custom",
		"published": true,
		"verified": true,
		"thumbs_up": 1
	}

	_save_item_to_catalog(item_dict)

	# Share code
	if _copy_code_check.button_pressed:
		_copy_share_code(item_dict)

	# Cloud Sync
	if _sync_cloud_check.button_pressed:
		_publish_to_cloud_marketplace(item_dict)

	_set_status("Published lighting preset '%s' with thumbnail!" % p_name, Color(0.55, 0.95, 0.65))
	_refresh_presets()
	if _tab_container != null:
		_tab_container.current_tab = 0
	lighting_published.emit(item_dict)


func _auto_capture_viewport_or_icon() -> Image:
	var vp: SubViewport = null
	if plugin != null and plugin.get_editor_interface() != null:
		vp = plugin.get_editor_interface().get_editor_viewport_3d(0)
	if vp != null:
		var tex: ViewportTexture = vp.get_texture()
		if tex != null:
			var img: Image = tex.get_image()
			if img != null and not img.is_empty():
				var min_dim: int = mini(img.get_width(), img.get_height())
				var sx: int = (img.get_width() - min_dim) / 2
				var sy: int = (img.get_height() - min_dim) / 2
				var cropped: Image = img.get_region(Rect2i(sx, sy, min_dim, min_dim))
				cropped.resize(128, 128, Image.INTERPOLATE_LANCZOS)
				return cropped

	# Fallback to copy default icon
	var def_p := "res://assets/icons/lighting/lighting_roblox_hd.png"
	if ResourceLoader.exists(def_p):
		var r: Resource = load(def_p)
		if r is Texture2D:
			return (r as Texture2D).get_image()
	return Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)


func _save_item_to_catalog(item: Dictionary) -> void:
	for cat_path in [BUILTIN_CATALOG_PATH, USER_SAVED_CATALOG]:
		var catalog: Array = []
		if FileAccess.file_exists(cat_path):
			var rf: FileAccess = FileAccess.open(cat_path, FileAccess.READ)
			if rf != null:
				var p: Variant = JSON.parse_string(rf.get_as_text())
				if p is Array:
					catalog = p as Array

		# Prepend new item
		catalog.insert(0, item)
		var wf: FileAccess = FileAccess.open(cat_path, FileAccess.WRITE)
		if wf != null:
			wf.store_string(JSON.stringify(catalog, "  "))


# ============================================================================
# APPLY LIGHTING PRESET LOGIC
# ============================================================================

func apply_preset_by_id(preset_id: String) -> void:
	var scene_root: Node = get_tree().edited_scene_root
	if scene_root == null:
		_set_status("Open a 3D scene first before applying lighting.", Color(1.0, 0.5, 0.5))
		return

	match preset_id:
		"roblox_hd":
			_apply_roblox_hd_lighting(scene_root)
			_set_status("Applied Roblox HD Lighting (Vibrant Daytime + glTF Fix)!", Color(0.55, 0.95, 0.65))
		"sunset":
			_apply_sunset_lighting(scene_root)
			_set_status("Applied Sunset Golden Hour Lighting!", Color(0.55, 0.95, 0.65))
		"midnight":
			_apply_midnight_lighting(scene_root)
			_set_status("Applied Midnight Starry Night Lighting!", Color(0.55, 0.95, 0.65))
		"overcast":
			_apply_overcast_lighting(scene_root)
			_set_status("Applied Overcast Soft Studio Lighting!", Color(0.55, 0.95, 0.65))
		"cyberpunk":
			_apply_cyberpunk_lighting(scene_root)
			_set_status("Applied Cyberpunk Neon Dusk Lighting!", Color(0.55, 0.95, 0.65))
		_:
			_apply_roblox_hd_lighting(scene_root)
			_set_status("Applied Lighting setup!", Color(0.55, 0.95, 0.65))

	fix_dull_materials(scene_root)
	lighting_applied.emit(preset_id)


func _apply_lighting_preset(item: Dictionary) -> void:
	var scene_root: Node = get_tree().edited_scene_root
	if scene_root == null:
		_set_status("Open a 3D scene first before applying lighting.", Color(1.0, 0.5, 0.5))
		return

	var preset_id: String = String(item.get("preset_id", ""))
	if preset_id != "":
		apply_preset_by_id(preset_id)
		return

	var res_path: String = String(item.get("path", ""))
	if not FileAccess.file_exists(res_path):
		var up: String = String(item.get("user_path", ""))
		if up != "" and FileAccess.file_exists(up):
			res_path = up

	if FileAccess.file_exists(res_path):
		var p_res: Resource = load(res_path)
		if p_res is PackedScene:
			var inst: Node = (p_res as PackedScene).instantiate()
			if inst != null:
				_merge_nodes_into_scene(inst, scene_root)
				inst.queue_free()
				fix_dull_materials(scene_root)
				_set_status("Applied Lighting preset '%s'!" % String(item.get("name", "")), Color(0.55, 0.95, 0.65))
				lighting_applied.emit(String(item.get("name", "")))
				return

	# Fallback to default
	_apply_roblox_hd_lighting(scene_root)
	fix_dull_materials(scene_root)
	_set_status("Applied default lighting setup.", Color(0.55, 0.95, 0.65))


func _merge_nodes_into_scene(source_container: Node, target_root: Node) -> void:
	# 1. WorldEnvironment
	var src_env: WorldEnvironment = source_container.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if src_env == null:
		for ch in source_container.get_children():
			if ch is WorldEnvironment:
				src_env = ch as WorldEnvironment
				break

	if src_env != null and src_env.environment != null:
		var target_w_env: WorldEnvironment = target_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if target_w_env == null:
			target_w_env = WorldEnvironment.new()
			target_w_env.name = "WorldEnvironment"
			target_root.add_child(target_w_env)
			target_root.move_child(target_w_env, 0)
			target_w_env.owner = target_root
		target_w_env.environment = src_env.environment.duplicate()

	# 2. Directional Lights
	for ch in source_container.get_children():
		if ch is DirectionalLight3D:
			var src_l := ch as DirectionalLight3D
			var target_l: DirectionalLight3D = target_root.get_node_or_null(NodePath(src_l.name)) as DirectionalLight3D
			if target_l == null:
				target_l = DirectionalLight3D.new()
				target_l.name = src_l.name
				target_root.add_child(target_l)
				target_l.owner = target_root
			target_l.visible = true
			target_l.position = src_l.position
			target_l.rotation = src_l.rotation
			target_l.light_color = src_l.light_color
			target_l.light_energy = src_l.light_energy
			target_l.light_specular = src_l.light_specular
			target_l.shadow_enabled = src_l.shadow_enabled
			target_l.shadow_bias = src_l.shadow_bias
			target_l.shadow_normal_bias = src_l.shadow_normal_bias
			target_l.shadow_opacity = src_l.shadow_opacity
			target_l.shadow_blur = src_l.shadow_blur
			target_l.directional_shadow_mode = src_l.directional_shadow_mode
			target_l.directional_shadow_blend_splits = src_l.directional_shadow_blend_splits
			target_l.directional_shadow_max_distance = src_l.directional_shadow_max_distance

	# 3. BounceFillLight cleanup
	var bounce_fill: DirectionalLight3D = target_root.get_node_or_null("BounceFillLight") as DirectionalLight3D
	if bounce_fill != null:
		bounce_fill.visible = false


# 1. Roblox HD (Direct from ColorWorld)
func _apply_roblox_hd_lighting(scene_root: Node) -> void:
	var w_env: WorldEnvironment = _get_or_create_world_env(scene_root)
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.10, 0.52, 0.92, 1.0)
	psky.sky_horizon_color = Color(0.72, 0.90, 1.0, 1.0)
	psky.ground_horizon_color = Color(0.58, 0.80, 0.94, 1.0)
	psky.ground_bottom_color = Color(0.28, 0.50, 0.72, 1.0)
	psky.sun_angle_max = 24.0
	psky.sun_curve = 0.06

	var sky_res := Sky.new()
	sky_res.sky_material = psky

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.78, 0.86, 0.96, 1.0)
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.90
	env.tonemap_white = 1.65
	env.ssao_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.03
	env.adjustment_brightness = 1.0
	env.glow_enabled = false
	env.fog_enabled = false
	w_env.environment = env

	var sun: DirectionalLight3D = _get_or_create_directional_light(scene_root, "Sun", 1)
	sun.visible = true
	sun.position = Vector3(0.0, 60.0, 0.0)
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88, 1.0)
	sun.light_energy = 0.78
	sun.light_specular = 0.35
	sun.shadow_enabled = true
	sun.shadow_bias = 0.015
	sun.shadow_normal_bias = 1.1
	sun.shadow_opacity = 0.62
	sun.shadow_blur = 0.30
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_blend_splits = false
	sun.directional_shadow_max_distance = 120.0

	var sky_fill: DirectionalLight3D = _get_or_create_directional_light(scene_root, "SkyFillLight", 2)
	sky_fill.visible = true
	sky_fill.position = Vector3(0.0, 45.0, 0.0)
	sky_fill.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	sky_fill.light_color = Color(0.72, 0.85, 1.0, 1.0)
	sky_fill.light_energy = 0.16
	sky_fill.light_specular = 0.0
	sky_fill.shadow_enabled = false

	var bounce_fill: DirectionalLight3D = scene_root.get_node_or_null("BounceFillLight") as DirectionalLight3D
	if bounce_fill != null:
		bounce_fill.visible = false


# 2. Sunset Golden Hour
func _apply_sunset_lighting(scene_root: Node) -> void:
	var w_env: WorldEnvironment = _get_or_create_world_env(scene_root)
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.25, 0.18, 0.45, 1.0)
	psky.sky_horizon_color = Color(0.98, 0.52, 0.22, 1.0)
	psky.ground_horizon_color = Color(0.55, 0.30, 0.18, 1.0)
	psky.ground_bottom_color = Color(0.20, 0.12, 0.10, 1.0)
	psky.sun_angle_max = 30.0
	psky.sun_curve = 0.08

	var sky_res := Sky.new()
	sky_res.sky_material = psky

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.95, 0.75, 0.60, 1.0)
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 1.35
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.62, 0.38, 1.0)
	env.fog_sun_scatter = 0.25
	env.fog_density = 0.00018
	env.fog_sky_affect = 0.08
	w_env.environment = env

	var sun: DirectionalLight3D = _get_or_create_directional_light(scene_root, "Sun", 1)
	sun.visible = true
	sun.position = Vector3(0.0, 35.0, 0.0)
	sun.rotation_degrees = Vector3(-18.0, -60.0, 0.0)
	sun.light_color = Color(1.0, 0.70, 0.32, 1.0)
	sun.light_energy = 1.15
	sun.light_specular = 0.45
	sun.shadow_enabled = true
	sun.shadow_bias = 0.015
	sun.shadow_normal_bias = 1.1
	sun.shadow_opacity = 0.70
	sun.shadow_blur = 0.40
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 260.0

	var sky_fill: DirectionalLight3D = _get_or_create_directional_light(scene_root, "SkyFillLight", 2)
	sky_fill.visible = true
	sky_fill.position = Vector3(0.0, 30.0, 0.0)
	sky_fill.rotation_degrees = Vector3(-25.0, 120.0, 0.0)
	sky_fill.light_color = Color(0.42, 0.38, 0.62, 1.0)
	sky_fill.light_energy = 0.28
	sky_fill.light_specular = 0.06
	sky_fill.shadow_enabled = false


# 3. Midnight Starry Night
func _apply_midnight_lighting(scene_root: Node) -> void:
	var w_env: WorldEnvironment = _get_or_create_world_env(scene_root)
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.02, 0.03, 0.09, 1.0)
	psky.sky_horizon_color = Color(0.08, 0.11, 0.24, 1.0)
	psky.ground_horizon_color = Color(0.05, 0.07, 0.14, 1.0)
	psky.ground_bottom_color = Color(0.01, 0.02, 0.05, 1.0)
	psky.sun_angle_max = 18.0
	psky.sun_curve = 0.04

	var sky_res := Sky.new()
	sky_res.sky_material = psky

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.20, 0.25, 0.42, 1.0)
	env.ambient_light_sky_contribution = 0.20
	env.ambient_light_energy = 0.20
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 1.30
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.11, 0.22, 1.0)
	env.fog_sun_scatter = 0.10
	env.fog_density = 0.00025
	env.fog_sky_affect = 0.12
	w_env.environment = env

	var sun: DirectionalLight3D = _get_or_create_directional_light(scene_root, "Sun", 1)
	sun.visible = true
	sun.position = Vector3(0.0, 60.0, 0.0)
	sun.rotation_degrees = Vector3(-55.0, -20.0, 0.0)
	sun.light_color = Color(0.62, 0.74, 0.96, 1.0)
	sun.light_energy = 0.35
	sun.light_specular = 0.25
	sun.shadow_enabled = true
	sun.shadow_bias = 0.020
	sun.shadow_normal_bias = 1.1
	sun.shadow_opacity = 0.50
	sun.shadow_blur = 0.40
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 260.0

	var sky_fill: DirectionalLight3D = _get_or_create_directional_light(scene_root, "SkyFillLight", 2)
	sky_fill.visible = true
	sky_fill.position = Vector3(0.0, 40.0, 0.0)
	sky_fill.rotation_degrees = Vector3(-35.0, 160.0, 0.0)
	sky_fill.light_color = Color(0.12, 0.16, 0.28, 1.0)
	sky_fill.light_energy = 0.12
	sky_fill.light_specular = 0.02
	sky_fill.shadow_enabled = false


# 4. Overcast Soft Studio
func _apply_overcast_lighting(scene_root: Node) -> void:
	var w_env: WorldEnvironment = _get_or_create_world_env(scene_root)
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.55, 0.58, 0.64, 1.0)
	psky.sky_horizon_color = Color(0.74, 0.77, 0.82, 1.0)
	psky.ground_horizon_color = Color(0.50, 0.52, 0.56, 1.0)
	psky.ground_bottom_color = Color(0.30, 0.32, 0.35, 1.0)
	psky.sun_angle_max = 40.0
	psky.sun_curve = 0.15

	var sky_res := Sky.new()
	sky_res.sky_material = psky

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.85, 0.88, 0.92, 1.0)
	env.ambient_light_sky_contribution = 0.50
	env.ambient_light_energy = 0.40
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.30
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 0.90
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.77, 0.82, 1.0)
	env.fog_sun_scatter = 0.12
	env.fog_density = 0.00015
	env.fog_sky_affect = 0.05
	w_env.environment = env

	var sun: DirectionalLight3D = _get_or_create_directional_light(scene_root, "Sun", 1)
	sun.visible = true
	sun.position = Vector3(0.0, 60.0, 0.0)
	sun.rotation_degrees = Vector3(-65.0, -30.0, 0.0)
	sun.light_color = Color(0.96, 0.96, 0.98, 1.0)
	sun.light_energy = 0.75
	sun.light_specular = 0.20
	sun.shadow_enabled = true
	sun.shadow_bias = 0.020
	sun.shadow_normal_bias = 1.2
	sun.shadow_opacity = 0.45
	sun.shadow_blur = 0.80
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 260.0

	var sky_fill: DirectionalLight3D = _get_or_create_directional_light(scene_root, "SkyFillLight", 2)
	sky_fill.visible = true
	sky_fill.position = Vector3(0.0, 45.0, 0.0)
	sky_fill.rotation_degrees = Vector3(-45.0, 150.0, 0.0)
	sky_fill.light_color = Color(0.70, 0.72, 0.76, 1.0)
	sky_fill.light_energy = 0.30
	sky_fill.light_specular = 0.04
	sky_fill.shadow_enabled = false


# 5. Cyberpunk Neon Dusk
func _apply_cyberpunk_lighting(scene_root: Node) -> void:
	var w_env: WorldEnvironment = _get_or_create_world_env(scene_root)
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.32, 0.04, 0.45, 1.0)
	psky.sky_horizon_color = Color(0.88, 0.18, 0.52, 1.0)
	psky.ground_horizon_color = Color(0.30, 0.08, 0.35, 1.0)
	psky.ground_bottom_color = Color(0.08, 0.02, 0.12, 1.0)
	psky.sun_angle_max = 28.0
	psky.sun_curve = 0.06

	var sky_res := Sky.new()
	sky_res.sky_material = psky

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.50, 0.25, 0.60, 1.0)
	env.ambient_light_sky_contribution = 0.40
	env.ambient_light_energy = 0.40
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 1.35
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.80
	env.glow_bloom = 0.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.65, 0.18, 0.45, 1.0)
	env.fog_sun_scatter = 0.28
	env.fog_density = 0.00020
	env.fog_sky_affect = 0.10
	w_env.environment = env

	var sun: DirectionalLight3D = _get_or_create_directional_light(scene_root, "Sun", 1)
	sun.visible = true
	sun.position = Vector3(0.0, 45.0, 0.0)
	sun.rotation_degrees = Vector3(-30.0, -40.0, 0.0)
	sun.light_color = Color(1.0, 0.35, 0.30, 1.0)
	sun.light_energy = 1.05
	sun.light_specular = 0.50
	sun.shadow_enabled = true
	sun.shadow_bias = 0.015
	sun.shadow_normal_bias = 1.1
	sun.shadow_opacity = 0.70
	sun.shadow_blur = 0.35
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 260.0

	var sky_fill: DirectionalLight3D = _get_or_create_directional_light(scene_root, "SkyFillLight", 2)
	sky_fill.visible = true
	sky_fill.position = Vector3(0.0, 35.0, 0.0)
	sky_fill.rotation_degrees = Vector3(-35.0, 140.0, 0.0)
	sky_fill.light_color = Color(0.15, 0.85, 1.0, 1.0)
	sky_fill.light_energy = 0.45
	sky_fill.light_specular = 0.08
	sky_fill.shadow_enabled = false


# Helpers
func _get_or_create_world_env(scene_root: Node) -> WorldEnvironment:
	var w_env: WorldEnvironment = scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if w_env == null:
		w_env = WorldEnvironment.new()
		w_env.name = "WorldEnvironment"
		scene_root.add_child(w_env)
		scene_root.move_child(w_env, 0)
		w_env.owner = scene_root
	return w_env


func _get_or_create_directional_light(scene_root: Node, node_name: String, target_idx: int) -> DirectionalLight3D:
	var l: DirectionalLight3D = scene_root.get_node_or_null(NodePath(node_name)) as DirectionalLight3D
	if l == null:
		l = DirectionalLight3D.new()
		l.name = node_name
		scene_root.add_child(l)
		scene_root.move_child(l, mini(target_idx, scene_root.get_child_count() - 1))
		l.owner = scene_root
	return l


func _create_procedural_env(top_col: Color, horizon_col: Color) -> Environment:
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = top_col
	psky.sky_horizon_color = horizon_col
	psky.ground_horizon_color = Color(0.58, 0.80, 0.94)
	psky.ground_bottom_color = Color(0.28, 0.50, 0.72)
	var sky_res := Sky.new()
	sky_res.sky_material = psky

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky_res
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.84, 0.88, 0.95)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.35
	env.ssao_enabled = true
	return env


# Fix dull glTF materials across the scene (ColorWorld material unclamp pass)
static func fix_dull_materials(scene_root: Node) -> int:
	var fixed_mats: int = 0
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for ch in cur.get_children():
			stack.append(ch)
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			var mat: Material = mi.material_override
			if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
				mat = mi.get_surface_override_material(0)
				if mat == null:
					mat = mi.mesh.surface_get_material(0)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				if bm.metallic > 0.05 or bm.roughness > 0.65:
					var new_bm := bm.duplicate() as BaseMaterial3D
					new_bm.metallic = 0.0
					new_bm.roughness = 0.36
					new_bm.metallic_specular = 0.48
					if cur.has_meta("extras"):
						var ex: Variant = cur.get_meta("extras")
						if typeof(ex) == TYPE_DICTIONARY and (ex as Dictionary).has("Color"):
							var c_str := str((ex as Dictionary)["Color"]).replace("(", "").replace(")", "")
							var parts := c_str.split(",")
							if parts.size() >= 3:
								new_bm.albedo_color = Color(
									float(parts[0].strip_edges()) / 255.0,
									float(parts[1].strip_edges()) / 255.0,
									float(parts[2].strip_edges()) / 255.0,
									1.0
								)
					mi.material_override = new_bm
					fixed_mats += 1
	return fixed_mats


# ============================================================================
# CLOUD & SHARE CODE LOGIC
# ============================================================================

func _copy_share_code(item: Dictionary) -> void:
	var code: String = _encode_item_to_share_code(item)
	if code == "":
		_set_status("Could not generate share code for this item.", Color(1.0, 0.5, 0.5))
		return
	DisplayServer.clipboard_set(code)
	_set_status("Copied Dev Share Code for '%s' to clipboard!" % String(item.get("name", "")), Color(0.55, 0.95, 0.65))


func _encode_item_to_share_code(item: Dictionary) -> String:
	var res_path: String = String(item.get("path", ""))
	if not FileAccess.file_exists(res_path):
		var up: String = String(item.get("user_path", ""))
		if up != "" and FileAccess.file_exists(up):
			res_path = up
	if not FileAccess.file_exists(res_path):
		return ""

	var raw_bytes: PackedByteArray = FileAccess.get_file_as_bytes(res_path)
	if raw_bytes.is_empty():
		return ""
	var comp: PackedByteArray = raw_bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	var icon_b64: String = ""
	var icon_p: String = String(item.get("icon_path", ""))
	if icon_p != "" and FileAccess.file_exists(icon_p):
		var ibytes: PackedByteArray = FileAccess.get_file_as_bytes(icon_p)
		if ibytes.size() <= 16384:
			icon_b64 = Marshalls.raw_to_base64(ibytes)

	var pack_dict: Dictionary = {
		"id": String(item.get("id", "")),
		"name": String(item.get("name", "Lighting")),
		"creator": String(item.get("creator", "Creator")),
		"version": "1.0",
		"category": "Lighting",
		"subcat": "LIGHT",
		"type": "lighting",
		"ext": res_path.get_extension().to_lower(),
		"description": String(item.get("description", "")),
		"tags": String(item.get("tags", "")),
		"thumbs_up": int(item.get("thumbs_up", 1)),
		"icon_b64": icon_b64,
		"orig_len": raw_bytes.size(),
		"data_b64": Marshalls.raw_to_base64(comp)
	}
	var json_bytes: PackedByteArray = JSON.stringify(pack_dict).to_utf8_buffer()
	return "RBXTB:" + Marshalls.raw_to_base64(json_bytes)


func _publish_to_cloud_marketplace(item: Dictionary) -> void:
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


func _slugify(text: String) -> String:
	var s: String = text.to_lower()
	var res: String = ""
	for i in range(s.length()):
		var c: String = s[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			res += c
		elif c == " " or c == "_" or c == "-":
			if not res.ends_with("_") and res.length() > 0:
				res += "_"
	if res.length() > 28:
		res = res.substr(0, 28)
	return res if res != "" else "lighting"


func _set_status(msg: String, color: Color) -> void:
	if _status_lbl != null:
		_status_lbl.text = msg
		_status_lbl.add_theme_color_override("font_color", color)
