class_name InventoryUI
extends Control
# Roblox-style 10-slot Hotbar + Infinite Scrollable Backpack Inventory.
# Opens with ',' (Comma) or clicking the Topbar Backpack icon.
# Supports dragging items between Backpack and Hotbar slots, 1-0 number keys, and infinite storage.

signal active_item_changed(item_data: Dictionary)

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const HOTBAR_SLOTS := 10

var hotbar: Array = []
var backpack: Array[Dictionary] = []
var active_slot: int = -1
var is_open: bool = false

var _hotbar_holder: CenterContainer
var _hotbar_row: HBoxContainer
var _hotbar_btns: Array[Button] = []

var _backpack_panel: PanelContainer
var _search_edit: LineEdit
var _backpack_grid: GridContainer
var _count_label: Label


class SlotButton extends Button:
	var owner_ui: Control
	var is_hotbar: bool = true
	var slot_index: int = 0

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if owner_ui == null:
			return null
		var item: Dictionary = owner_ui.call("_get_slot_item", is_hotbar, slot_index)
		if item.is_empty():
			return null
		var preview = PanelContainer.new()
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.14, 0.22, 0.92)
		sb.border_color = item.get("color", Color.WHITE)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 10.0
		sb.content_margin_right = 10.0
		sb.content_margin_top = 6.0
		sb.content_margin_bottom = 6.0
		preview.add_theme_stylebox_override("panel", sb)
		var lbl = Label.new()
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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar.resize(HOTBAR_SLOTS)
	for i in range(HOTBAR_SLOTS):
		hotbar[i] = {}
	_build_ui()
	_refresh_ui()


func toggle_backpack() -> void:
	set_backpack_open(not is_open)


func set_backpack_open(open_state: bool) -> void:
	is_open = open_state
	if _backpack_panel != null and is_instance_valid(_backpack_panel):
		_backpack_panel.visible = is_open
	_refresh_ui()


func add_item(item_data: Dictionary) -> void:
	if item_data.is_empty():
		return
	var copy = item_data.duplicate(true)
	# Place in first empty hotbar slot if available, otherwise into infinite backpack!
	for i in range(HOTBAR_SLOTS):
		if (hotbar[i] as Dictionary).is_empty():
			hotbar[i] = copy
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


func consume_active_item() -> void:
	if active_slot >= 0 and active_slot < HOTBAR_SLOTS:
		hotbar[active_slot] = {}
		active_slot = -1
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
	_refresh_ui()
	active_item_changed.emit(get_active_item())


func handle_key_input(keycode: int) -> bool:
	if keycode == KEY_COMMA:
		toggle_backpack()
		return true
	var slot = -1
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
	var from_hb = bool(drag.get("from_hotbar", true))
	var from_idx = int(drag.get("index", -1))
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
	if is_open:
		var it: Dictionary = hotbar[idx]
		if not it.is_empty():
			hotbar[idx] = {}
			backpack.append(it)
			if active_slot == idx:
				active_slot = -1
			_refresh_ui()
			active_item_changed.emit(get_active_item())
			return
	select_hotbar_slot(idx)


func _on_backpack_item_pressed(b_idx: int) -> void:
	if b_idx < 0 or b_idx >= backpack.size():
		return
	var it: Dictionary = backpack[b_idx]
	for i in range(HOTBAR_SLOTS):
		if (hotbar[i] as Dictionary).is_empty():
			hotbar[i] = it
			backpack.remove_at(b_idx)
			_refresh_ui()
			return
	# If all 10 hotbar slots are full, swap with slot 0 (or active_slot)
	var target_s = active_slot if active_slot >= 0 else 0
	var old_hb: Dictionary = hotbar[target_s]
	hotbar[target_s] = it
	backpack[b_idx] = old_hb
	_refresh_ui()
	active_item_changed.emit(get_active_item())


func _build_ui() -> void:
	# 1. Bottom 10-Slot Hotbar
	_hotbar_holder = CenterContainer.new()
	_hotbar_holder.name = "HotbarHolder"
	_hotbar_holder.anchor_left = 0.0
	_hotbar_holder.anchor_top = 1.0
	_hotbar_holder.anchor_right = 1.0
	_hotbar_holder.anchor_bottom = 1.0
	_hotbar_holder.offset_top = -76.0
	_hotbar_holder.offset_bottom = -10.0
	_hotbar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotbar_holder)

	_hotbar_row = HBoxContainer.new()
	_hotbar_row.add_theme_constant_override("separation", 6)
	_hotbar_holder.add_child(_hotbar_row)

	for i in range(HOTBAR_SLOTS):
		var sb = SlotButton.new()
		sb.owner_ui = self
		sb.is_hotbar = true
		sb.slot_index = i
		sb.custom_minimum_size = Vector2(60, 60)
		sb.focus_mode = Control.FOCUS_NONE
		sb.clip_text = true
		sb.pressed.connect(_on_hotbar_btn_pressed.bind(i))
		_hotbar_row.add_child(sb)
		_hotbar_btns.append(sb)

	# 2. Infinite Backpack Inventory Panel (opens above Hotbar when pressing ',')
	var bp_center = CenterContainer.new()
	bp_center.name = "BackpackCenter"
	bp_center.anchor_left = 0.0
	bp_center.anchor_top = 1.0
	bp_center.anchor_right = 1.0
	bp_center.anchor_bottom = 1.0
	bp_center.offset_top = -440.0
	bp_center.offset_bottom = -84.0
	bp_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bp_center)

	var drop_panel = BackpackDropZone.new()
	drop_panel.owner_ui = self
	drop_panel.name = "BackpackPanel"
	drop_panel.custom_minimum_size = Vector2(654, 340)
	drop_panel.visible = false
	var psb = StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.08, 0.11, 0.94)
	psb.border_color = Color(1, 1, 1, 0.18)
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(12)
	psb.content_margin_left = 16.0
	psb.content_margin_right = 16.0
	psb.content_margin_top = 12.0
	psb.content_margin_bottom = 12.0
	drop_panel.add_theme_stylebox_override("panel", psb)
	bp_center.add_child(drop_panel)
	_backpack_panel = drop_panel

	var vcol = VBoxContainer.new()
	vcol.add_theme_constant_override("separation", 10)
	_backpack_panel.add_child(vcol)

	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vcol.add_child(head)

	var title = Label.new()
	title.text = "Backpack Inventory (Infinite Storage · Drag or Click Items)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", 14)
	if RetroUI.gotham(700) != null:
		title.add_theme_font_override("font", RetroUI.gotham(700))
	head.add_child(title)

	_count_label = Label.new()
	_count_label.text = "0 Items"
	_count_label.add_theme_color_override("font_color", Color("74c0fc"))
	_count_label.add_theme_font_size_override("font_size", 12)
	head.add_child(_count_label)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search items..."
	_search_edit.custom_minimum_size = Vector2(180, 28)
	_search_edit.text_changed.connect(func(_t: String) -> void: _refresh_ui())
	head.add_child(_search_edit)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vcol.add_child(scroll)

	_backpack_grid = GridContainer.new()
	_backpack_grid.columns = 8
	_backpack_grid.add_theme_constant_override("h_separation", 8)
	_backpack_grid.add_theme_constant_override("v_separation", 8)
	_backpack_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_backpack_grid)


func _style_slot_btn(b: Button, item: Dictionary, is_selected: bool) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.18, 0.25, 0.92) if is_selected else Color(0.07, 0.09, 0.13, 0.80)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2 if is_selected else 1)
	if is_selected:
		sb.border_color = Color("339af0")
	elif not item.is_empty():
		sb.border_color = (item.get("color", Color.WHITE) as Color).lightened(0.15)
	else:
		sb.border_color = Color(1, 1, 1, 0.16)
	b.add_theme_stylebox_override("normal", sb)
	var hb = sb.duplicate() as StyleBoxFlat
	hb.bg_color = sb.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("hover", hb)
	b.add_theme_stylebox_override("pressed", sb)
	if RetroUI.gotham(700) != null:
		b.add_theme_font_override("font", RetroUI.gotham(700))
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color.WHITE if not item.is_empty() else Color(1, 1, 1, 0.42))


func _refresh_ui() -> void:
	for i in range(_hotbar_btns.size()):
		var b = _hotbar_btns[i]
		var it: Dictionary = hotbar[i]
		var key_lbl = str((i + 1) % 10)
		if it.is_empty():
			b.text = key_lbl
			b.tooltip_text = "Slot %s (Empty)" % key_lbl
		else:
			b.text = "%s\n%s" % [key_lbl, String(it.get("short", "ITEM"))]
			b.tooltip_text = "%s (Click or press %s to equip · Drag to move)" % [String(it.get("name", "Item")), key_lbl]
		_style_slot_btn(b, it, active_slot == i)

	if _backpack_grid == null:
		return
	for ch in _backpack_grid.get_children():
		ch.queue_free()

	var filter = _search_edit.text.strip_edges().to_lower() if _search_edit != null else ""
	var total_items = 0
	for i in range(HOTBAR_SLOTS):
		if not (hotbar[i] as Dictionary).is_empty():
			total_items += 1
	total_items += backpack.size()
	if _count_label != null:
		_count_label.text = "%d Items (∞ Capacity)" % total_items

	for idx in range(backpack.size()):
		var bit: Dictionary = backpack[idx]
		var bname = String(bit.get("name", "Item"))
		if filter != "" and not (filter in bname.to_lower()):
			continue
		var bb = SlotButton.new()
		bb.owner_ui = self
		bb.is_hotbar = false
		bb.slot_index = idx
		bb.custom_minimum_size = Vector2(72, 64)
		bb.focus_mode = Control.FOCUS_NONE
		bb.text = String(bit.get("short", "ITEM")) + "\n" + bname.split(" ")[0]
		bb.tooltip_text = bname + " (Drag to Hotbar or Click to Equip)"
		_style_slot_btn(bb, bit, false)
		bb.pressed.connect(_on_backpack_item_pressed.bind(idx))
		_backpack_grid.add_child(bb)
