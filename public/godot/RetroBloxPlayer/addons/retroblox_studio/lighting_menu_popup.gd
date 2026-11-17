@tool
extends PopupPanel

# RetroBlox Studio - Visual Lighting Preset Menu
# Displays lighting presets with their thumbnail preview images
# in a quick dropdown menu right below the toolbar button.

signal preset_chosen(preset_data: Dictionary)
signal upload_requested
signal manage_requested

const BUILTIN_CATALOG_PATH: String = "res://toolbox/toolbox_catalog.json"
const USER_SAVED_CATALOG: String = "user://retroblox_toolbox_catalog.json"

var plugin: EditorPlugin
var lighting_dialog: AcceptDialog

var _search_edit: LineEdit
var _grid: GridContainer
var _cached_items: Array[Dictionary] = []


func _init() -> void:
	size = Vector2i(380, 440)
	min_size = Vector2i(340, 360)


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# Main panel
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var psb: StyleBoxFlat = StyleBoxFlat.new()
	psb.bg_color = Color(0.13, 0.15, 0.18, 1.0)
	psb.border_width_left = 1
	psb.border_width_top = 1
	psb.border_width_right = 1
	psb.border_width_bottom = 1
	psb.border_color = Color(0.25, 0.30, 0.38, 1.0)
	psb.set_corner_radius_all(6)
	psb.content_margin_left = 8.0
	psb.content_margin_right = 8.0
	psb.content_margin_top = 8.0
	psb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", psb)
	add_child(panel)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	# 1. Header Row
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	vb.add_child(hdr)

	var title_lbl: Label = Label.new()
	title_lbl.text = "Choose Lighting Preset"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 12)
	hdr.add_child(title_lbl)

	var close_btn: Button = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(24, 24)
	close_btn.pressed.connect(hide)
	hdr.add_child(close_btn)

	# 2. Search Row
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search presets..."
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(func(_t: String) -> void: _render_cards())
	vb.add_child(_search_edit)

	# 3. Scrollable Presets Grid
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)

	# 4. Footer Buttons
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	vb.add_child(footer)

	var upload_btn: Button = Button.new()
	upload_btn.text = "+ Upload Lighting"
	upload_btn.tooltip_text = "Upload active scene lighting with thumbnail to community"
	upload_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upload_btn.pressed.connect(func() -> void:
		hide()
		upload_requested.emit()
	)
	footer.add_child(upload_btn)

	var manage_btn: Button = Button.new()
	manage_btn.text = "Manage..."
	manage_btn.tooltip_text = "Open full Lighting & Atmosphere Studio"
	manage_btn.pressed.connect(func() -> void:
		hide()
		manage_requested.emit()
	)
	footer.add_child(manage_btn)


func open_menu(screen_pos: Vector2i) -> void:
	_load_presets()
	_render_cards()
	position = screen_pos
	popup()


func _load_presets() -> void:
	_cached_items.clear()
	var seen: Dictionary = {}

	# 1. Built-in catalog
	if FileAccess.file_exists(BUILTIN_CATALOG_PATH):
		var f: FileAccess = FileAccess.open(BUILTIN_CATALOG_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Array:
				for it in (parsed as Array):
					if it is Dictionary:
						var d := it as Dictionary
						var cat: String = String(d.get("category", ""))
						var t: String = String(d.get("type", ""))
						if cat == "Lighting" or t == "lighting":
							var pid: String = String(d.get("id", ""))
							if pid != "" and not seen.has(pid):
								seen[pid] = true
								_cached_items.append(d)

	# 2. User saved catalog
	if FileAccess.file_exists(USER_SAVED_CATALOG):
		var uf: FileAccess = FileAccess.open(USER_SAVED_CATALOG, FileAccess.READ)
		if uf != null:
			var parsed: Variant = JSON.parse_string(uf.get_as_text())
			if parsed is Array:
				for it in (parsed as Array):
					if it is Dictionary:
						var d := it as Dictionary
						var cat: String = String(d.get("category", ""))
						var t: String = String(d.get("type", ""))
						if cat == "Lighting" or t == "lighting":
							var pid: String = String(d.get("id", ""))
							if pid != "" and not seen.has(pid):
								seen[pid] = true
								_cached_items.append(d)


func _render_cards() -> void:
	if _grid == null:
		return
	for ch in _grid.get_children():
		ch.queue_free()

	var q: String = _search_edit.text.strip_edges().to_lower() if _search_edit != null else ""

	for item in _cached_items:
		var item_name: String = String(item.get("name", "Lighting"))
		var creator: String = String(item.get("creator", "RetroBlox"))
		var desc: String = String(item.get("description", ""))
		var tags: String = String(item.get("tags", "")).to_lower()

		if q != "":
			var full := (item_name + " " + creator + " " + desc + " " + tags).to_lower()
			if full.find(q) < 0:
				continue

		var card: Button = _create_preset_card_button(item)
		_grid.add_child(card)


func _create_preset_card_button(item: Dictionary) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(165, 125)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Card styling
	var nsb: StyleBoxFlat = StyleBoxFlat.new()
	nsb.bg_color = Color(0.18, 0.20, 0.25, 1.0)
	nsb.border_width_left = 1
	nsb.border_width_top = 1
	nsb.border_width_right = 1
	nsb.border_width_bottom = 1
	nsb.border_color = Color(0.28, 0.32, 0.40, 1.0)
	nsb.set_corner_radius_all(5)
	nsb.content_margin_left = 6.0
	nsb.content_margin_right = 6.0
	nsb.content_margin_top = 6.0
	nsb.content_margin_bottom = 6.0
	btn.add_theme_stylebox_override("normal", nsb)

	var hsb: StyleBoxFlat = nsb.duplicate() as StyleBoxFlat
	hsb.bg_color = Color(0.24, 0.28, 0.36, 1.0)
	hsb.border_color = Color(0.40, 0.65, 1.0, 1.0)
	btn.add_theme_stylebox_override("hover", hsb)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	btn.add_child(vb)

	# Thumbnail (72x72)
	var thumb: TextureRect = TextureRect.new()
	thumb.custom_minimum_size = Vector2(72, 72)
	thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.texture = _load_thumbnail(item)
	vb.add_child(thumb)

	# Name label
	var nm_lbl: Label = Label.new()
	nm_lbl.text = String(item.get("name", "Lighting"))
	nm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm_lbl.add_theme_font_size_override("font_size", 10)
	nm_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm_lbl)

	# Creator label
	var cr_lbl: Label = Label.new()
	cr_lbl.text = "by " + String(item.get("creator", "RetroBlox"))
	cr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cr_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cr_lbl.add_theme_font_size_override("font_size", 9)
	cr_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.88))
	cr_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(cr_lbl)

	btn.pressed.connect(func() -> void:
		_on_preset_clicked(item)
	)

	return btn


func _load_thumbnail(item: Dictionary) -> Texture2D:
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

	# Default fallback
	var def_p := "res://assets/icons/lighting/lighting_roblox_hd.png"
	if ResourceLoader.exists(def_p):
		var r: Resource = load(def_p)
		if r is Texture2D:
			return r as Texture2D
	return null


func _on_preset_clicked(item: Dictionary) -> void:
	hide()
	preset_chosen.emit(item)

	var preset_id: String = String(item.get("preset_id", ""))
	if preset_id != "" and plugin != null and plugin.has_method("apply_lighting_preset_by_id"):
		plugin.call("apply_lighting_preset_by_id", preset_id)
		return

	if lighting_dialog != null and is_instance_valid(lighting_dialog):
		lighting_dialog.call("_apply_lighting_preset", item)
