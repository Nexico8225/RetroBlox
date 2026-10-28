class_name InventoryUI
extends Control
# Roblox-style Expanding Hotbar + Infinite Scrollable Backpack Inventory.
# Appears when you pick up / equip an item and expands wider as you equip/collect more items (1 -> 10 slots).

signal active_item_changed(item_data: Dictionary)

const RetroUI = preload("res://scripts/ui/retro_theme.gd")
const HOTBAR_SLOTS: int = 10

var hotbar: Array = []
var backpack: Array[Dictionary] = []
var active_slot: int = -1
var is_open: bool = false

var _hotbar_panel: PanelContainer
var _hotbar_row: HBoxContainer
var _hotbar_btns: Array[Button] = []

var _tooltip_pill: PanelContainer
var _tooltip_label: Label
var _hovered_hotbar_slot: int = -1
var _gear_hover_pill: PanelContainer
var _gear_hover_label: Label

var _backpack_panel: PanelContainer
var _search_edit: LineEdit
var _backpack_grid: GridContainer
var _count_label: Label
var _icon_cache: Dictionary = {}


class SlotButton extends Button:
	var owner_ui: Control
	var is_hotbar: bool = true
	var slot_index: int = 0
	var num_label: Label
	var icon_rect: TextureRect
	var name_label: Label
	var cd_rect: ColorRect

	func _init() -> void:
		custom_minimum_size = Vector2(60, 60)
		focus_mode = Control.FOCUS_NONE
		clip_text = true

		icon_rect = TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.position = Vector2(8, 8)
		icon_rect.size = Vector2(44, 44)
		add_child(icon_rect)

		num_label = Label.new()
		num_label.name = "SlotNum"
		num_label.position = Vector2(5, 2)
		num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		num_label.add_theme_font_size_override("font_size", 11)
		num_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 0.90))
		num_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		num_label.add_theme_constant_override("shadow_offset_x", 1)
		num_label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(num_label)

		name_label = Label.new()
		name_label.name = "ItemName"
		name_label.position = Vector2(2, 43)
		name_label.size = Vector2(56, 15)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", 9)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
		name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		name_label.add_theme_constant_override("shadow_offset_x", 1)
		name_label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(name_label)

		cd_rect = ColorRect.new()
		cd_rect.name = "CooldownOverlay"
		cd_rect.color = Color(0.0, 0.75, 1.0, 0.36)
		cd_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_rect.position = Vector2(2, 2)
		cd_rect.size = Vector2(0, 4)
		cd_rect.visible = false
		add_child(cd_rect)

	func set_cooldown_ratio(ratio: float) -> void:
		if cd_rect == null:
			return
		if ratio <= 0.01:
			cd_rect.visible = false
		else:
			cd_rect.visible = true
			var w: float = (custom_minimum_size.x - 6.0) * clampf(ratio, 0.0, 1.0)
			cd_rect.position = Vector2(3.0, custom_minimum_size.y - 6.0)
			cd_rect.size = Vector2(w, 4.0)

	func set_slot_size(dim: float) -> void:
		custom_minimum_size = Vector2(dim, dim)
		size = Vector2(dim, dim)
		var pad: float = roundf(dim * 0.13)
		if icon_rect != null:
			icon_rect.position = Vector2(pad, pad)
			icon_rect.size = Vector2(dim - pad * 2.0, dim - pad * 2.0)
		if name_label != null:
			name_label.position = Vector2(2.0, dim - 17.0)
			name_label.size = Vector2(dim - 4.0, 15.0)

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if owner_ui == null:
			return null
		var item: Dictionary = owner_ui.call("_get_slot_item", is_hotbar, slot_index)
		if item.is_empty():
			return null
		var preview: PanelContainer = PanelContainer.new()
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.14, 0.22, 0.92)
		sb.border_color = Color("339af0")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 8.0
		sb.content_margin_right = 8.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		preview.add_theme_stylebox_override("panel", sb)
		var lbl: Label = Label.new()
		lbl.text = String(item.get("name", "Item"))
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_font_size_override("font_size", 12)
		preview.add_child(lbl)
		set_drag_preview(preview)
		return {
			"from_hotbar": is_hotbar,
			"index": slot_index,
		}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("from_hotbar")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if owner_ui != null and data is Dictionary:
			owner_ui.call("_handle_slot_drop", data as Dictionary, is_hotbar, slot_index)


class BackpackDropZone extends PanelContainer:
	var owner_ui: Control

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("from_hotbar")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if owner_ui != null and data is Dictionary:
			owner_ui.call("_handle_slot_drop", data as Dictionary, false, -1)


func _ready() -> void:
	name = "InventoryUI"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar.resize(HOTBAR_SLOTS)
	for i in range(HOTBAR_SLOTS):
		hotbar[i] = {}
	_build_ui()
	_refresh_ui()
	_update_layout_positions()


func _process(_delta: float) -> void:
	_update_layout_positions()


func _update_layout_positions() -> void:
	var vp_rect: Rect2 = get_viewport_rect()
	var vp_sz: Vector2 = vp_rect.size
	if vp_sz.x < 10.0 or vp_sz.y < 10.0:
		vp_sz = Vector2(1280.0, 720.0)
	position = Vector2.ZERO
	size = vp_sz

	if _hotbar_panel != null and is_instance_valid(_hotbar_panel) and _hotbar_panel.visible:
		var vis_count: int = 0
		var total_w: float = 0.0
		var max_h: float = 60.0
		for i in range(_hotbar_btns.size()):
			var b: SlotButton = _hotbar_btns[i] as SlotButton
			if b != null and b.visible:
				vis_count += 1
				total_w += b.custom_minimum_size.x
				max_h = maxf(max_h, b.custom_minimum_size.y)
		if vis_count > 1:
			total_w += float(vis_count - 1) * 6.0
		var hb_sz: Vector2 = Vector2(maxf(total_w, 60.0), max_h)
		_hotbar_row.size = hb_sz
		_hotbar_panel.size = hb_sz
		_hotbar_panel.position = Vector2((vp_sz.x - hb_sz.x) * 0.5, vp_sz.y - hb_sz.y - 8.0)

	if _tooltip_pill != null and is_instance_valid(_tooltip_pill) and _tooltip_pill.visible:
		var tp_sz: Vector2 = _tooltip_pill.get_combined_minimum_size()
		_tooltip_pill.size = tp_sz
		var center_x: float = vp_sz.x * 0.5
		if _hovered_hotbar_slot >= 0 and _hovered_hotbar_slot < _hotbar_btns.size():
			var hb_btn: Control = _hotbar_btns[_hovered_hotbar_slot]
			if hb_btn != null and hb_btn.visible:
				center_x = hb_btn.global_position.x + hb_btn.size.x * 0.5
		_tooltip_pill.position = Vector2(clampf(center_x - tp_sz.x * 0.5, 8.0, maxf(8.0, vp_sz.x - tp_sz.x - 8.0)), vp_sz.y - 84.0 - tp_sz.y)

	if _backpack_panel != null and is_instance_valid(_backpack_panel) and _backpack_panel.visible:
		var bp_sz: Vector2 = Vector2(minf(664.0, vp_sz.x - 24.0), minf(330.0, vp_sz.y - 110.0))
		_backpack_panel.size = bp_sz
		_backpack_panel.position = Vector2((vp_sz.x - bp_sz.x) * 0.5, vp_sz.y - 84.0 - bp_sz.y)


func toggle_backpack() -> void:
	set_backpack_open(not is_open)


func set_backpack_open(open_state: bool) -> void:
	is_open = open_state
	if _backpack_panel != null and is_instance_valid(_backpack_panel):
		_backpack_panel.visible = is_open
	_refresh_ui()
	_update_layout_positions()


func has_item_in_hotbar(item_id: String) -> bool:
	for i in range(HOTBAR_SLOTS):
		var it: Dictionary = hotbar[i]
		if not it.is_empty() and String(it.get("id", "")) == item_id:
			return true
	return false


func add_item(item_data: Dictionary) -> void:
	if item_data.is_empty():
		return
	var copy: Dictionary = item_data.duplicate(true)
	for i in range(HOTBAR_SLOTS):
		if (hotbar[i] as Dictionary).is_empty():
			hotbar[i] = copy
			# Auto-equip into hand if nothing is currently equipped!
			if active_slot == -1:
				select_hotbar_slot(i)
			else:
				_refresh_ui()
			return
	backpack.append(copy)
	_refresh_ui()


func get_active_item() -> Dictionary:
	if active_slot >= 0 and active_slot < HOTBAR_SLOTS:
		return hotbar[active_slot] as Dictionary
	return {}


func set_active_cooldown(cd_left: float, cd_max: float) -> void:
	var ratio: float = (cd_left / maxf(cd_max, 0.05)) if cd_left > 0.0 else 0.0
	for i in range(_hotbar_btns.size()):
		var b: SlotButton = _hotbar_btns[i] as SlotButton
		if b != null:
			b.set_cooldown_ratio(ratio if i == active_slot else 0.0)


func _compact_hotbar() -> void:
	var active_item_ref: Dictionary = {}
	if active_slot >= 0 and active_slot < HOTBAR_SLOTS:
		active_item_ref = hotbar[active_slot] as Dictionary
	var non_empty: Array[Dictionary] = []
	for i in range(HOTBAR_SLOTS):
		var it: Dictionary = hotbar[i] as Dictionary
		if not it.is_empty():
			non_empty.append(it)
	for i in range(HOTBAR_SLOTS):
		if i < non_empty.size():
			hotbar[i] = non_empty[i]
		else:
			hotbar[i] = {}
	if active_item_ref.is_empty():
		active_slot = -1
	else:
		active_slot = -1
		for i in range(non_empty.size()):
			if hotbar[i] == active_item_ref:
				active_slot = i
				break


func consume_active_item() -> void:
	if active_slot >= 0 and active_slot < HOTBAR_SLOTS:
		hotbar[active_slot] = {}
		active_slot = -1
		if not is_open:
			_compact_hotbar()
		_refresh_ui()
		active_item_changed.emit({})


func select_hotbar_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= HOTBAR_SLOTS:
		return
	if active_slot == slot_idx:
		active_slot = -1
	else:
		var it: Dictionary = hotbar[slot_idx]
		if it.is_empty():
			active_slot = -1
		else:
			active_slot = slot_idx
	_refresh_ui()
	active_item_changed.emit(get_active_item())


func on_player_died(global_lose_when_dead: bool) -> void:
	if not global_lose_when_dead:
		return
	for i in range(HOTBAR_SLOTS):
		var it: Dictionary = hotbar[i]
		if not it.is_empty() and bool(it.get("lose_item_when_dead", true)):
			hotbar[i] = {}
	for i in range(backpack.size() - 1, -1, -1):
		if bool(backpack[i].get("lose_item_when_dead", true)):
			backpack.remove_at(i)
	if active_slot >= 0 and (hotbar[active_slot] as Dictionary).is_empty():
		active_slot = -1
	if not is_open:
		_compact_hotbar()
	_refresh_ui()
	active_item_changed.emit(get_active_item())


func handle_key_input(keycode: int) -> bool:
	if keycode == KEY_COMMA or keycode == KEY_QUOTELEFT:
		toggle_backpack()
		return true
	var slot: int = -1
	if keycode >= KEY_1 and keycode <= KEY_9:
		slot = keycode - KEY_1
	elif keycode == KEY_0:
		slot = 9
	if slot >= 0:
		select_hotbar_slot(slot)
		return true
	return false


func _get_slot_item(from_hotbar: bool, idx: int) -> Dictionary:
	if from_hotbar:
		if idx >= 0 and idx < HOTBAR_SLOTS:
			return hotbar[idx] as Dictionary
		return {}
	if idx >= 0 and idx < backpack.size():
		return backpack[idx]
	return {}


func _handle_slot_drop(drag: Dictionary, to_hotbar: bool, to_idx: int) -> void:
	var from_hb: bool = bool(drag.get("from_hotbar", true))
	var from_idx: int = int(drag.get("index", -1))
	if from_hb and to_hotbar:
		if from_idx < 0 or from_idx >= HOTBAR_SLOTS or to_idx < 0 or to_idx >= HOTBAR_SLOTS:
			return
		var tmp: Dictionary = hotbar[to_idx]
		hotbar[to_idx] = hotbar[from_idx]
		hotbar[from_idx] = tmp
		if active_slot == from_idx:
			active_slot = to_idx
	elif from_hb and not to_hotbar:
		if from_idx < 0 or from_idx >= HOTBAR_SLOTS:
			return
		var item: Dictionary = hotbar[from_idx]
		if item.is_empty():
			return
		if to_idx >= 0 and to_idx < backpack.size():
			hotbar[from_idx] = backpack[to_idx]
			backpack[to_idx] = item
		else:
			hotbar[from_idx] = {}
			backpack.append(item)
			if active_slot == from_idx:
				active_slot = -1
	elif not from_hb and to_hotbar:
		if from_idx < 0 or from_idx >= backpack.size() or to_idx < 0 or to_idx >= HOTBAR_SLOTS:
			return
		var b_item: Dictionary = backpack[from_idx]
		var existing: Dictionary = hotbar[to_idx]
		hotbar[to_idx] = b_item
		if existing.is_empty():
			backpack.remove_at(from_idx)
		else:
			backpack[from_idx] = existing
	_refresh_ui()
	active_item_changed.emit(get_active_item())


func _on_hotbar_btn_pressed(idx: int) -> void:
	select_hotbar_slot(idx)


func _on_hotbar_btn_hover(idx: int, entered: bool) -> void:
	if entered:
		_hovered_hotbar_slot = idx
	elif _hovered_hotbar_slot == idx:
		_hovered_hotbar_slot = -1
	_update_hotbar_hover_pill()


func _update_hotbar_hover_pill() -> void:
	if _tooltip_pill == null or _tooltip_label == null:
		return
	if _hovered_hotbar_slot >= 0 and _hovered_hotbar_slot < HOTBAR_SLOTS:
		var it: Dictionary = hotbar[_hovered_hotbar_slot] as Dictionary
		if not it.is_empty():
			_tooltip_label.text = String(it.get("name", "Item"))
			_tooltip_pill.visible = true
			_update_layout_positions()
			return
	_tooltip_pill.visible = false


func show_gear_hover_info(gear_id_num: int, gear_name: String, mouse_pos: Vector2) -> void:
	if _gear_hover_pill == null or _gear_hover_label == null:
		return
	if gear_id_num <= 0 or gear_name == "":
		_gear_hover_pill.visible = false
		return
	_gear_hover_label.text = "ID: %d  ·  %s" % [gear_id_num, gear_name]
	_gear_hover_pill.visible = true
	var p_sz: Vector2 = _gear_hover_pill.get_combined_minimum_size()
	_gear_hover_pill.size = p_sz
	var vp_sz: Vector2 = get_viewport_rect().size
	var gx: float = clampf(mouse_pos.x + 16.0, 8.0, maxf(8.0, vp_sz.x - p_sz.x - 8.0))
	var gy: float = clampf(mouse_pos.y - p_sz.y - 10.0, 8.0, maxf(8.0, vp_sz.y - p_sz.y - 8.0))
	_gear_hover_pill.position = Vector2(gx, gy)


func _on_backpack_item_pressed(b_idx: int) -> void:
	if b_idx < 0 or b_idx >= backpack.size():
		return
	var it: Dictionary = backpack[b_idx]
	for i in range(HOTBAR_SLOTS):
		if (hotbar[i] as Dictionary).is_empty():
			hotbar[i] = it
			backpack.remove_at(b_idx)
			if active_slot == -1:
				active_slot = i
			_refresh_ui()
			active_item_changed.emit(get_active_item())
			return
	var target_s: int = active_slot if active_slot >= 0 else 0
	var old_hb: Dictionary = hotbar[target_s]
	hotbar[target_s] = it
	backpack[b_idx] = old_hb
	_refresh_ui()
	active_item_changed.emit(get_active_item())


func _build_ui() -> void:
	# 1. Tooltip Pill above Hotbar
	_tooltip_pill = PanelContainer.new()
	_tooltip_pill.name = "TooltipPill"
	_tooltip_pill.visible = false
	_tooltip_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb: StyleBoxFlat = StyleBoxFlat.new()
	tsb.bg_color = Color(0.08, 0.10, 0.14, 0.88)
	tsb.set_corner_radius_all(8)
	tsb.content_margin_left = 14.0
	tsb.content_margin_right = 14.0
	tsb.content_margin_top = 6.0
	tsb.content_margin_bottom = 6.0
	_tooltip_pill.add_theme_stylebox_override("panel", tsb)
	add_child(_tooltip_pill)

	_tooltip_label = Label.new()
	_tooltip_label.text = ""
	_tooltip_label.add_theme_color_override("font_color", Color.WHITE)
	_tooltip_label.add_theme_font_size_override("font_size", 14)
	if RetroUI.gotham(600) != null:
		_tooltip_label.add_theme_font_override("font", RetroUI.gotham(600))
	_tooltip_pill.add_child(_tooltip_label)

	# 2. Bottom Expanding Hotbar Row (hidden when 0 items, grows wider as more items are added/equipped)
	_hotbar_panel = PanelContainer.new()
	_hotbar_panel.name = "HotbarPanel"
	_hotbar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hpsb: StyleBoxEmpty = StyleBoxEmpty.new()
	_hotbar_panel.add_theme_stylebox_override("panel", hpsb)
	add_child(_hotbar_panel)

	_hotbar_row = HBoxContainer.new()
	_hotbar_row.add_theme_constant_override("separation", 6)
	_hotbar_panel.add_child(_hotbar_row)

	for i in range(HOTBAR_SLOTS):
		var sb: SlotButton = SlotButton.new()
		sb.owner_ui = self
		sb.is_hotbar = true
		sb.slot_index = i
		sb.pressed.connect(_on_hotbar_btn_pressed.bind(i))
		sb.mouse_entered.connect(_on_hotbar_btn_hover.bind(i, true))
		sb.mouse_exited.connect(_on_hotbar_btn_hover.bind(i, false))
		_hotbar_row.add_child(sb)
		_hotbar_btns.append(sb)

	# 2b. GearWall Hover Info Pill (shows "ID: 1 · Speed Coil" when hovering over gears on the GearWall)
	_gear_hover_pill = PanelContainer.new()
	_gear_hover_pill.name = "GearWallHoverPill"
	_gear_hover_pill.visible = false
	_gear_hover_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsb: StyleBoxFlat = StyleBoxFlat.new()
	gsb.bg_color = Color(0.06, 0.09, 0.15, 0.92)
	gsb.border_color = Color("3b9eff")
	gsb.set_border_width_all(2)
	gsb.set_corner_radius_all(8)
	gsb.content_margin_left = 12.0
	gsb.content_margin_right = 12.0
	gsb.content_margin_top = 6.0
	gsb.content_margin_bottom = 6.0
	_gear_hover_pill.add_theme_stylebox_override("panel", gsb)
	add_child(_gear_hover_pill)

	_gear_hover_label = Label.new()
	_gear_hover_label.text = ""
	_gear_hover_label.add_theme_color_override("font_color", Color.WHITE)
	_gear_hover_label.add_theme_font_size_override("font_size", 14)
	if RetroUI.gotham(600) != null:
		_gear_hover_label.add_theme_font_override("font", RetroUI.gotham(600))
	_gear_hover_pill.add_child(_gear_hover_label)

	# 3. Classic Roblox Backpack Panel above Hotbar
	var drop_panel: BackpackDropZone = BackpackDropZone.new()
	drop_panel.owner_ui = self
	drop_panel.name = "BackpackPanel"
	drop_panel.custom_minimum_size = Vector2(654, 320)
	drop_panel.visible = false
	var psb: StyleBoxFlat = StyleBoxFlat.new()
	psb.bg_color = Color(0.12, 0.13, 0.15, 0.82)
	psb.border_color = Color(1, 1, 1, 0.16)
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(4)
	psb.content_margin_left = 14.0
	psb.content_margin_right = 14.0
	psb.content_margin_top = 10.0
	psb.content_margin_bottom = 12.0
	drop_panel.add_theme_stylebox_override("panel", psb)
	add_child(drop_panel)
	_backpack_panel = drop_panel

	var vcol: VBoxContainer = VBoxContainer.new()
	vcol.add_theme_constant_override("separation", 10)
	_backpack_panel.add_child(vcol)

	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vcol.add_child(head)

	_count_label = Label.new()
	_count_label.text = "Backpack (Drag items to Hotbar or Click to Equip)"
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.96, 0.92))
	_count_label.add_theme_font_size_override("font_size", 13)
	if RetroUI.gotham(600) != null:
		_count_label.add_theme_font_override("font", RetroUI.gotham(600))
	head.add_child(_count_label)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search"
	_search_edit.custom_minimum_size = Vector2(200, 28)
	_search_edit.text_changed.connect(func(_t: String) -> void: _refresh_ui())
	head.add_child(_search_edit)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vcol.add_child(scroll)

	_backpack_grid = GridContainer.new()
	_backpack_grid.columns = 9
	_backpack_grid.add_theme_constant_override("h_separation", 8)
	_backpack_grid.add_theme_constant_override("v_separation", 8)
	_backpack_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_backpack_grid)


func _style_slot_btn(b: SlotButton, item: Dictionary, is_selected: bool) -> void:
	if b.is_hotbar:
		b.set_slot_size(68.0 if is_selected else 58.0)
	else:
		b.set_slot_size(60.0)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.18, 0.25, 0.94) if is_selected else Color(0.11, 0.13, 0.17, 0.80)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(3 if is_selected else 1)
	if is_selected:
		sb.border_color = Color("3b9eff")
	elif not item.is_empty():
		sb.border_color = Color(1, 1, 1, 0.30)
	else:
		sb.border_color = Color(1, 1, 1, 0.14)
	b.add_theme_stylebox_override("normal", sb)
	var hb: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	hb.bg_color = sb.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("pressed", sb)


func _get_item_icon_tex(item_id: String) -> Texture2D:
	if item_id == "":
		return null
	if _icon_cache.has(item_id):
		return _icon_cache[item_id]
	var img: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	if item_id in ["sword", "flame_sword", "slow_sword", "super_sword", "venomshank", "icedagger", "windforce", "darkheart", "illumina"]:
		var b_col_a: Color = Color("e9ecef")
		var b_col_b: Color = Color("adb5bd")
		var g_col: Color = Color("fcc419")
		var h_col: Color = Color("1c7ed6")
		var thick: int = 3
		if item_id == "flame_sword":
			b_col_a = Color("ff6b00")
			b_col_b = Color("e03131")
			g_col = Color("fcc419")
			h_col = Color("7f1d1d")
		elif item_id in ["slow_sword", "icedagger"]:
			b_col_a = Color("339af0") if item_id == "icedagger" else Color("66d9e8")
			b_col_b = Color("1c7ed6") if item_id == "icedagger" else Color("1098ad")
			g_col = Color("74c0fc") if item_id == "icedagger" else Color("3bc9db")
			h_col = Color("0c4a6e")
			if item_id == "icedagger":
				thick = 2
		elif item_id == "venomshank":
			b_col_a = Color("51cf66")
			b_col_b = Color("2f9e44")
			g_col = Color("b2f2bb")
			h_col = Color("1b4332")
		elif item_id == "windforce":
			b_col_a = Color("74c0fc")
			b_col_b = Color("339af0")
			g_col = Color("e7f5ff")
			h_col = Color("1864ab")
		elif item_id == "darkheart":
			b_col_a = Color("212529")
			b_col_b = Color("9c36b5")
			g_col = Color("ae3ec9")
			h_col = Color("1f1924")
		elif item_id == "illumina":
			b_col_a = Color("ffdeeb")
			b_col_b = Color("faa2c1")
			g_col = Color("fcc2d7")
			h_col = Color("a61e4d")
			thick = 4
		elif item_id == "super_sword":
			b_col_a = Color("fff3bf")
			b_col_b = Color("fcc419")
			g_col = Color("be4bdb")
			h_col = Color("5f3dc4")
			thick = 4
		for step_i in range(14, 56):
			var bx: int = step_i
			var by: int = 63 - step_i
			for w in range(-thick + 1, thick):
				var px: int = clampi(bx + w, 0, 63)
				var py: int = clampi(by + w, 0, 63)
				img.set_pixel(px, py, b_col_a if w <= 0 else b_col_b)
		for g in range(-10, 11):
			for t in range(-2, 3):
				var gx: int = clampi(18 + g + t, 0, 63)
				var gy: int = clampi(45 + g - t, 0, 63)
				img.set_pixel(gx, gy, g_col)
		for h in range(6, 17):
			for w in range(-2, 3):
				img.set_pixel(clampi(h + w, 0, 63), clampi(63 - h + w, 0, 63), h_col if h > 9 else g_col)
	elif item_id in ["speed_coil", "gravity_coil", "fusion_coil", "heal_coil"]:
		var col_a: Color = Color("ff3b30")
		var col_b: Color = Color("ff3b30")
		if item_id == "gravity_coil":
			col_a = Color("339af0")
			col_b = Color("339af0")
		elif item_id == "fusion_coil":
			col_a = Color("ff3b30")
			col_b = Color("339af0")
		elif item_id == "heal_coil":
			col_a = Color("40c057")
			col_b = Color("69db7c")
		for y in range(10, 54):
			for x in range(10, 54):
				var d: float = Vector2(x - 32.0, y - 32.0).length()
				if (d >= 16.0 and d <= 22.0) or (d >= 8.0 and d <= 13.0):
					var c_use: Color = col_a if ((x + y) % 8 < 4) else col_b
					img.set_pixel(x, y, c_use.lightened(0.32) if (x + y) % 5 == 0 else c_use)
	elif item_id == "swelling_ball":
		for y in range(8, 56):
			for x in range(8, 56):
				var d: float = Vector2(x - 32.0, y - 32.0).length()
				if d <= 18.0:
					img.set_pixel(x, y, Color("ffd6e7") if d < 7.0 else (Color("ff2a85") if d < 14.0 else Color("a61e4d")))
				elif d >= 20.0 and d <= 22.5:
					img.set_pixel(x, y, Color("ff85c0"))
	elif item_id in ["healing_potion", "big_head_potion", "slateskin_potion"]:
		var pcol: Color = Color("40c057") if item_id == "healing_potion" else (Color("868e96") if item_id == "slateskin_potion" else Color("be4bdb"))
		for y in range(22, 54):
			for x in range(16, 48):
				var d: float = Vector2(x - 32.0, y - 38.0).length()
				if d <= 15.0:
					img.set_pixel(x, y, Color(0.88, 0.95, 1.0, 0.85) if d > 12.5 else pcol)
		for y in range(12, 24):
			for x in range(27, 37):
				img.set_pixel(x, y, Color("a66321") if y < 16 else Color(0.85, 0.92, 1.0, 0.9))
	elif item_id == "flying_carpet":
		var cols: Array[Color] = [Color("e03131"), Color("f59f00"), Color("2f9e44"), Color("1971c2"), Color("9c36b5")]
		for y in range(18, 46):
			for x in range(10, 54):
				var ci: int = clampi(int(float((x - 10) * cols.size()) / 44.0), 0, cols.size() - 1)
				img.set_pixel(x, y, Color("fcc419") if (y < 21 or y > 42) else cols[ci])
	elif item_id == "laser_gun":
		for y in range(22, 34):
			for x in range(12, 54):
				img.set_pixel(x, y, Color("00e5ff") if (x % 7 < 3 or x > 48) else Color("343a40"))
		for y in range(34, 48):
			for x in range(16, 26):
				img.set_pixel(x, y, Color("212529"))
	elif item_id == "rocket_launcher":
		for step_i in range(12, 52):
			var bx: int = step_i
			var by: int = 63 - step_i
			for w in range(-5, 6):
				var px: int = clampi(bx + w, 0, 63)
				var py: int = clampi(by + w, 0, 63)
				img.set_pixel(px, py, Color("e03131") if step_i > 44 else Color("495057"))
	elif item_id == "subspace_tripmine":
		for y in range(12, 52):
			for x in range(12, 52):
				var dx: float = absf(float(x) - 32.0)
				var dy: float = absf(float(y) - 32.0)
				var d: float = Vector2(dx, dy).length()
				if d <= 9.5:
					img.set_pixel(x, y, Color("ff66cc") if d < 5.0 else Color("ff00aa"))
				elif dx < 3.5 or dy < 3.5 or absf(dx - dy) < 3.0:
					if d <= 20.0:
						img.set_pixel(x, y, Color("2b2d42"))

	elif item_id in ["grappler", "grappler_v2"]:
		var gcol_main: Color = Color("00e5ff") if item_id == "grappler_v2" else Color("c0eb75")
		var gcol_sub: Color = Color("99e9f2") if item_id == "grappler_v2" else Color("8ce99a")
		for y in range(10, 54):
			for x in range(10, 54):
				var d: float = Vector2(x - 32.0, y - 32.0).length()
				if d >= 18.0 and d <= 24.0:
					img.set_pixel(x, y, gcol_main)
		for y2 in range(10, 40):
			for w2 in range(-2, 3):
				img.set_pixel(clampi(24 + w2, 0, 63), clampi(y2, 0, 63), gcol_sub)
		for prong_i in range(4 if item_id == "grappler_v2" else 3):
			for yy in range(8, 20):
				var px2: int = clampi(16 + prong_i * 7, 0, 63)
				img.set_pixel(px2, clampi(yy, 0, 63), gcol_main)
	elif item_id == "medkit":
		for y in range(16, 50):
			for x in range(10, 54):
				var is_cross: bool = (absf(float(x) - 32.0) <= 4.0 and absf(float(y) - 33.0) <= 11.0) or (absf(float(y) - 33.0) <= 4.0 and absf(float(x) - 32.0) <= 11.0)
				img.set_pixel(x, y, Color("e03131") if is_cross else Color("f8f9fa"))
		for y in range(10, 16):
			for x in range(24, 40):
				img.set_pixel(x, y, Color("343a40"))
	elif item_id == "rocket_boots":
		for y in range(14, 46):
			for x in range(14, 50):
				if (x >= 16 and x <= 28) or (x >= 36 and x <= 48) or (y >= 36):
					img.set_pixel(x, y, Color("fd7e14"))
		for y in range(46, 58):
			for x in range(18, 46):
				if (x >= 18 and x <= 26) or (x >= 38 and x <= 46):
					img.set_pixel(x, y, Color("ffd43b"))
	elif item_id == "spicy_sauce":
		for y in range(16, 56):
			for x in range(20, 44):
				var half_w: float = 12.0 if y > 28 else 7.0
				if absf(float(x) - 32.0) <= half_w:
					img.set_pixel(x, y, Color("ff6b35") if y > 30 else Color("fff3bf"))
		for y in range(8, 16):
			for x in range(28, 36):
				img.set_pixel(x, y, Color("c92a2a"))
	elif item_id in ["ghost_burger", "hamburger"]:
		var gb_bun: Color = Color("9be7ff") if item_id == "ghost_burger" else Color("f2ac57")
		var gb_fill: Color = Color("d0f4ff") if item_id == "ghost_burger" else Color("6b3f21")
		for y in range(12, 52):
			for x in range(12, 52):
				var dx: float = (float(x) - 32.0) / 21.0
				var dy: float = (float(y) - 32.0) / 21.0
				if dx * dx + dy * dy <= 1.0:
					img.set_pixel(x, y, gb_fill if absf(float(y) - 32.0) <= 5.0 else gb_bun)
	elif item_id == "sandwich":
		for y in range(14, 52):
			for x in range(12, 52):
				var span: int = int((1.0 - absf(float(y) - 33.0) / 20.0) * 20.0)
				if absf(float(x) - 32.0) <= float(span):
					img.set_pixel(x, y, Color("e8590c") if absf(float(y) - 33.0) <= 6.0 else Color("f5d38a"))
	elif item_id == "bloxy_cola":
		for y in range(10, 56):
			for x in range(22, 42):
				var band_y: bool = absf(float(y) - 33.0) <= 8.0
				img.set_pixel(x, y, Color("e03131") if band_y else Color("ced4da"))
		for y in range(8, 12):
			for x in range(26, 38):
				img.set_pixel(x, y, Color("adb5bd"))

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_icon_cache[item_id] = tex
	return tex


static func _get_item_flavor_text(item_id: String, iname: String) -> String:
	if item_id == "sword":
		return "[ID 5] Linked Sword — Click to Slash · Double-Click or Right-Click/E for Lunge Jump Boost!"
	if item_id == "flame_sword":
		return "[ID 6] Flame Sword (Firebrand) — Sets enemies on FIRE + Lunge Jump Boost!"
	if item_id == "slow_sword":
		return "[ID 7] Slow Sword — Freezes & Slows enemies by 75% + Lunge Jump Boost!"
	if item_id == "super_sword":
		return "[ID 8] Super Sword — Giant Greatsword with Super-Fast Lunge Dash & Massive Damage!"
	if item_id == "swelling_ball":
		return "[ID 9] Swelling Ball — HOLD Left-Click to Swell Bigger & Deal More Damage, Release to Launch!"
	if item_id == "speed_coil":
		return "[ID 1] Speed Coil — Doubles walk speed (Speed: 32) while equipped!"
	if item_id == "gravity_coil":
		return "[ID 2] Gravity Coil — Lowers gravity & boosts jump height while equipped!"
	if item_id == "fusion_coil":
		return "[ID 3] Fusion Coil — Combines Speed Coil (2x Speed) + Gravity Coil (Low Gravity & High Jump)!"
	if item_id == "heal_coil":
		return "[ID 4] Heal Coil — Passively regenerates +16 HP/sec while equipped!"
	if item_id == "healing_potion":
		return "[ID 10] Healing Potion — Click to drink and restore 65 HP (Infinite uses)!"
	if item_id == "big_head_potion":
		return "[ID 11] Big Head Potion — Click to drink for a giant head (Infinite uses)!"
	if item_id == "flying_carpet":
		return "[ID 12] Rainbow Magic Carpet — WASD to Fly · Space Up · C/Ctrl Down!"
	if item_id == "laser_gun":
		return "[ID 13] Hyperlaser Gun — Shoots a Cyan Plasma Orb that Insta-Kills anything it touches!"
	if item_id == "rocket_launcher":
		return "[ID 14] Rocket Launcher — Fires explosive RPG rockets!"
	if item_id == "subspace_tripmine":
		return "[ID 15] Subspace Tripmine — Drops a cloaking mine that explodes in a pink blast!"
	if item_id == "grappler":
		return "[ID 16] Grappler V1 — Aim & click to zip super fast (165 studs/s) to any surface!"
	if item_id == "spicy_sauce":
		return "[ID 17] Spicy Sauce — 3x walk speed for 10s, burns 4 HP/sec (Infinite uses)!"
	if item_id == "ghost_burger":
		return "[ID 18] Ghost Burger — Turn invisible for 8s + heal 10 HP (Infinite uses)!"
	if item_id == "hamburger":
		return "[ID 19] Hamburger — Restores 30 HP on every bite (Infinite uses)!"
	if item_id == "sandwich":
		return "[ID 20] Sandwich — Restores 45 HP on every bite (Infinite uses)!"
	if item_id == "bloxy_cola":
		return "[ID 21] Bloxy Cola — Restores 12 HP + slight 1.22x speed boost for 8s (Infinite uses)!"
	if item_id == "grappler_v2":
		return "[ID 22] Grappler V2 (Hyper) — Ultra-fast 235 studs/s long-range hook with upward arc!"
	if item_id == "medkit":
		return "[ID 23] Medkit — Classic SFOTH First-Aid Kit: restores +85 HP (Infinite uses)!"
	if item_id == "venomshank":
		return "[ID 24] Venomshank — Classic SFOTH Poison Sword: deals toxic acid damage over time + Lunge Jump!"
	if item_id == "icedagger":
		return "[ID 25] Icedagger — Classic SFOTH Ice Blade: freezes targets & Insta-Kills on Lunge!"
	if item_id == "windforce":
		return "[ID 26] Windforce — Classic SFOTH Wind Sword: +25% Speed, High Jump & Huge Knockback!"
	if item_id == "darkheart":
		return "[ID 27] Darkheart — Classic SFOTH Vampiric Sword: steals life (+25 HP) on every hit!"
	if item_id == "illumina":
		return "[ID 28] Illumina — Legendary SFOTH Sword: +32% Speed, High Lunge Jump & Sparkle Slash!"
	if item_id == "slateskin_potion":
		return "[ID 29] Slateskin Potion — Turns skin to stone (80% damage reduction for 12s, Infinite uses)!"
	if item_id == "rocket_boots":
		return "[ID 30] Rocket Boots — +35% Speed & hold Space in mid-air to jet-boost upward!"
	return iname


func _refresh_ui() -> void:
	var any_hotbar_visible: bool = false
	for i in range(_hotbar_btns.size()):
		var b: SlotButton = _hotbar_btns[i] as SlotButton
		var it: Dictionary = hotbar[i]
		var key_lbl: String = str((i + 1) % 10)
		b.text = ""
		b.num_label.text = key_lbl
		var show_slot: bool = is_open or (not it.is_empty())
		b.visible = show_slot
		if show_slot:
			any_hotbar_visible = true
		if it.is_empty():
			b.icon_rect.texture = null
			b.name_label.text = ""
			b.tooltip_text = "Slot %s (Empty — Drag item here)" % key_lbl
		else:
			var iid: String = String(it.get("id", ""))
			b.icon_rect.texture = _get_item_icon_tex(iid)
			b.name_label.text = String(it.get("short", ""))
			b.tooltip_text = "%s (Press %s or Click to equip)" % [String(it.get("name", "Item")), key_lbl]
		_style_slot_btn(b, it, active_slot == i)

	if _hotbar_panel != null and is_instance_valid(_hotbar_panel):
		_hotbar_panel.visible = any_hotbar_visible

	_update_hotbar_hover_pill()

	if _backpack_grid == null:
		return
	for ch in _backpack_grid.get_children():
		ch.queue_free()

	var filter: String = _search_edit.text.strip_edges().to_lower() if _search_edit != null else ""
	var total_items: int = 0
	for i in range(HOTBAR_SLOTS):
		if not (hotbar[i] as Dictionary).is_empty():
			total_items += 1
	total_items += backpack.size()
	if _count_label != null:
		_count_label.text = "Backpack (%d Items · Infinite Storage)" % total_items

	for idx in range(backpack.size()):
		var bit: Dictionary = backpack[idx]
		var bname: String = String(bit.get("name", "Item"))
		if filter != "" and not (filter in bname.to_lower()):
			continue
		var bb: SlotButton = SlotButton.new()
		bb.owner_ui = self
		bb.is_hotbar = false
		bb.slot_index = idx
		bb.text = ""
		bb.num_label.text = ""
		bb.icon_rect.texture = _get_item_icon_tex(String(bit.get("id", "")))
		bb.name_label.text = String(bit.get("short", "ITEM"))
		bb.tooltip_text = bname + " (Drag to Hotbar or Click to Equip)"
		_style_slot_btn(bb, bit, false)
		bb.pressed.connect(_on_backpack_item_pressed.bind(idx))
		_backpack_grid.add_child(bb)
	_update_layout_positions()
