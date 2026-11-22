class_name EmoteWheel
extends Control
# Interactive Emote Wheel for RetroBlox.
# Opened by pressing "." (Period key).
# Supports paging with < and > buttons and custom emotes from the website.

signal emote_selected(emote_id: String)
signal closed()

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const SLOTS_PER_PAGE: int = 8

const DEFAULT_EMOTES: Array[Dictionary] = [
	{ "id": "dance1", "name": "Dance 1" },
	{ "id": "dance2", "name": "Dance 2" },
	{ "id": "dance3", "name": "Dance 3" },
	{ "id": "laugh", "name": "Laugh" },
	{ "id": "wave", "name": "Wave" },
	{ "id": "point", "name": "Point" },
	{ "id": "cheer", "name": "Cheer" },
	{ "id": "sit", "name": "Sit" }
]

var _all_emotes: Array[Dictionary] = []
var _current_page: int = 0
var _center_label: Label
var _page_label: Label
var _buttons: Array[Button] = []
var _wheel_panel: Control


func _init() -> void:
	name = "EmoteWheel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	_build_ui()
	refresh_emotes()


func refresh_emotes() -> void:
	_all_emotes.clear()

	# 1. Custom emotes owned on website from Session
	var session_node: Node = get_node_or_null("/root/Session") if is_inside_tree() else null
	if session_node != null and "avatar" in session_node:
		var av: Dictionary = session_node.avatar
		var web_emotes: Array = av.get("emotes", [])
		for we in web_emotes:
			if we is Dictionary:
				var e_name: String = String(we.get("name", "Emote"))
				var e_id: String = String(we.get("name", "")).to_lower().replace(" ", "")
				_all_emotes.append({
					"id": e_id,
					"name": e_name,
					"custom": true
				})

	# 2. Add classic defaults (skip if duplicate id already present)
	for def in DEFAULT_EMOTES:
		var has_it := false
		for e in _all_emotes:
			if e["id"] == def["id"]:
				has_it = true
				break
		if not has_it:
			_all_emotes.append(def)

	_update_page()


func open() -> void:
	refresh_emotes()
	visible = true
	if _center_label != null:
		_center_label.text = "SELECT EMOTE"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	closed.emit()


func _build_ui() -> void:
	# Dark transparent backdrop that captures clicks outside the wheel to close
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.52)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			close()
	)
	add_child(bg)

	# Wheel container (centered)
	_wheel_panel = Control.new()
	_wheel_panel.custom_minimum_size = Vector2(440, 440)
	_wheel_panel.set_anchors_preset(Control.PRESET_CENTER)
	_wheel_panel.pivot_offset = Vector2(220, 220)
	_wheel_panel.position = -Vector2(220, 220)
	add_child(_wheel_panel)

	# Center circle background
	var center_circle := Panel.new()
	center_circle.custom_minimum_size = Vector2(130, 130)
	center_circle.position = Vector2(155, 155)
	var circle_style := StyleBoxFlat.new()
	circle_style.set_corner_radius_all(65)
	circle_style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
	circle_style.border_width_left = 3
	circle_style.border_width_top = 3
	circle_style.border_width_right = 3
	circle_style.border_width_bottom = 3
	circle_style.border_color = Color("00a2ff")
	center_circle.add_theme_stylebox_override("panel", circle_style)
	_wheel_panel.add_child(center_circle)

	# Center text
	_center_label = Label.new()
	_center_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_center_label.text = "SELECT EMOTE"
	_center_label.add_theme_font_size_override("font_size", 14)
	_center_label.add_theme_color_override("font_color", Color("ffffff"))
	_center_label.add_theme_font_override("font", RetroUI.arial(700))
	center_circle.add_child(_center_label)

	# Create 8 spoke buttons arranged in a ring around the center
	_buttons.clear()
	var radius := 142.0
	var btn_w := 98.0
	var btn_h := 46.0
	for i in range(SLOTS_PER_PAGE):
		var angle := (i * (2.0 * PI / float(SLOTS_PER_PAGE))) - (PI * 0.5)
		var bx := 220.0 + cos(angle) * radius - (btn_w * 0.5)
		var by := 220.0 + sin(angle) * radius - (btn_h * 0.5)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(btn_w, btn_h)
		btn.position = Vector2(bx, by)
		btn.clip_text = true
		btn.focus_mode = Control.FOCUS_NONE

		var norm_style := StyleBoxFlat.new()
		norm_style.set_corner_radius_all(8)
		norm_style.bg_color = Color(0.16, 0.17, 0.20, 0.95)
		norm_style.border_width_left = 2
		norm_style.border_width_top = 2
		norm_style.border_width_right = 2
		norm_style.border_width_bottom = 2
		norm_style.border_color = Color(0.32, 0.35, 0.42, 0.9)

		var hov_style := StyleBoxFlat.new()
		hov_style.set_corner_radius_all(8)
		hov_style.bg_color = Color(0.08, 0.35, 0.65, 0.98)
		hov_style.border_width_left = 2
		hov_style.border_width_top = 2
		hov_style.border_width_right = 2
		hov_style.border_width_bottom = 2
		hov_style.border_color = Color("38bdf8")

		btn.add_theme_stylebox_override("normal", norm_style)
		btn.add_theme_stylebox_override("hover", hov_style)
		btn.add_theme_stylebox_override("pressed", hov_style)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_font_override("font", RetroUI.arial(600))
		btn.add_theme_color_override("font_color", Color("f1f5f9"))

		var slot_idx := i
		btn.mouse_entered.connect(func() -> void:
			if btn.text != "":
				_center_label.text = btn.text.to_upper()
		)
		btn.mouse_exited.connect(func() -> void:
			_center_label.text = "SELECT EMOTE"
		)
		btn.pressed.connect(func() -> void:
			_on_slot_pressed(slot_idx)
		)

		_wheel_panel.add_child(btn)
		_buttons.append(btn)

	# Bottom bar with pagination controls < > and page number
	var nav_bar := HBoxContainer.new()
	nav_bar.custom_minimum_size = Vector2(240, 42)
	nav_bar.position = Vector2(100, 395)
	nav_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_wheel_panel.add_child(nav_bar)

	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.custom_minimum_size = Vector2(40, 36)
	prev_btn.focus_mode = Control.FOCUS_NONE
	prev_btn.add_theme_font_override("font", RetroUI.arial(700))
	prev_btn.add_theme_font_size_override("font_size", 18)
	prev_btn.add_theme_stylebox_override("normal", RetroUI.flat(6, Color("2b2b2b")))
	prev_btn.pressed.connect(_on_prev_page)
	nav_bar.add_child(prev_btn)

	_page_label = Label.new()
	_page_label.custom_minimum_size = Vector2(120, 36)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.text = "Page 1 / 1"
	_page_label.add_theme_font_override("font", RetroUI.arial(600))
	_page_label.add_theme_font_size_override("font_size", 14)
	_page_label.add_theme_color_override("font_color", Color("94a3b8"))
	nav_bar.add_child(_page_label)

	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.custom_minimum_size = Vector2(40, 36)
	next_btn.focus_mode = Control.FOCUS_NONE
	next_btn.add_theme_font_override("font", RetroUI.arial(700))
	next_btn.add_theme_font_size_override("font_size", 18)
	next_btn.add_theme_stylebox_override("normal", RetroUI.flat(6, Color("2b2b2b")))
	next_btn.pressed.connect(_on_next_page)
	nav_bar.add_child(next_btn)

	# Close button ✕
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(34, 34)
	close_btn.position = Vector2(395, 10)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_override("font", RetroUI.arial(700))
	close_btn.add_theme_stylebox_override("normal", RetroUI.flat(6, Color(0.3, 0.1, 0.1, 0.85)))
	close_btn.pressed.connect(close)
	_wheel_panel.add_child(close_btn)


func _update_page() -> void:
	var total_pages := maxi(1, int(ceili(float(_all_emotes.size()) / float(SLOTS_PER_PAGE))))
	_current_page = clampi(_current_page, 0, total_pages - 1)

	if _page_label != null:
		_page_label.text = "Page %d / %d" % [_current_page + 1, total_pages]

	var start_idx := _current_page * SLOTS_PER_PAGE
	for i in range(SLOTS_PER_PAGE):
		var btn: Button = _buttons[i]
		var e_idx := start_idx + i
		if e_idx < _all_emotes.size():
			var emote: Dictionary = _all_emotes[e_idx]
			btn.text = String(emote.get("name", "Emote"))
			btn.visible = true
			btn.disabled = false
		else:
			btn.text = ""
			btn.visible = false
			btn.disabled = true


func _on_prev_page() -> void:
	var total_pages := maxi(1, int(ceili(float(_all_emotes.size()) / float(SLOTS_PER_PAGE))))
	_current_page = (_current_page - 1 + total_pages) % total_pages
	_update_page()


func _on_next_page() -> void:
	var total_pages := maxi(1, int(ceili(float(_all_emotes.size()) / float(SLOTS_PER_PAGE))))
	_current_page = (_current_page + 1) % total_pages
	_update_page()


func _on_slot_pressed(slot_idx: int) -> void:
	var e_idx := _current_page * SLOTS_PER_PAGE + slot_idx
	if e_idx < _all_emotes.size():
		var emote: Dictionary = _all_emotes[e_idx]
		var eid: String = String(emote.get("id", ""))
		emote_selected.emit(eid)
		close()
