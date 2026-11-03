extends Control
# In-game Roblox-style chat box with Editable & Custom Quick Chat panel.

signal submitted(text: String)
signal opened
signal closed
signal unread(count: int)

const MAX_LINES := 60
const BG_FADE_DELAY := 3.5
const BG_FADE_SPEED := 3.0
const QUICK_CHAT_SAVE_PATH := "user://retroblox_quick_chat.json"
const DEFAULT_QUICK_PHRASES: Array[String] = [
	"Hello!",
	"Good game!",
	"Follow me!",
	"Watch out!",
	"Nice build!",
	"Need help over here!",
	"Want to team up?",
	"Thanks!",
]
const NAME_COLORS: Array = [
	"fd2943", "01a2ff", "02b857", "ffd30f", "c963ff",
	"ff8552", "3ecfff", "a1f24c", "ff6fc7", "f5cd30",
]

const RetroUI := preload("res://scripts/ui/retro_theme.gd")

var is_open := false
var is_reading := true
var log_collapsed := false

var _log: RichTextLabel
var _input_box: LineEdit
var _panel: PanelContainer
var _input_panel: PanelContainer
var _log_style: StyleBoxFlat
var _unread := 0
var _built := false
var _bg_timer := BG_FADE_DELAY
var _bg_alpha := 1.0

var _quick_chat_btn: Button
var _quick_panel: PanelContainer
var _quick_add_input: LineEdit
var _quick_list_box: VBoxContainer
var _edit_mode_btn: Button
var _is_editing_quick := false
var _editing_index := -1
var quick_phrases: Array[String] = []


func _ready() -> void:
	_load_quick_phrases()
	_ensure_ui()


func _load_quick_phrases() -> void:
	if not FileAccess.file_exists(QUICK_CHAT_SAVE_PATH):
		quick_phrases = DEFAULT_QUICK_PHRASES.duplicate()
		_save_quick_phrases()
		return
	var f := FileAccess.open(QUICK_CHAT_SAVE_PATH, FileAccess.READ)
	if f == null:
		quick_phrases = DEFAULT_QUICK_PHRASES.duplicate()
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		var loaded: Array[String] = []
		for item in (parsed as Array):
			var s := String(item).strip_edges()
			if s != "":
				loaded.append(s)
		quick_phrases = loaded
	else:
		quick_phrases = DEFAULT_QUICK_PHRASES.duplicate()


func _save_quick_phrases() -> void:
	var f := FileAccess.open(QUICK_CHAT_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(quick_phrases))


func _ensure_ui() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = get_node_or_null("LogPanel") as PanelContainer
	if _panel == null:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		offset_left = 10.0
		offset_top = 54.0
		offset_right = 404.0
		offset_bottom = 288.0

		_panel = PanelContainer.new()
		_panel.name = "LogPanel"
		_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		_panel.offset_bottom = -42.0
		add_child(_panel)

	_log_style = StyleBoxFlat.new()
	_log_style.bg_color = Color(0.04, 0.055, 0.075, 0.84)
	_log_style.set_corner_radius_all(8)
	_log_style.anti_aliasing = true
	_log_style.set_border_width_all(1)
	_log_style.border_color = Color(1.0, 1.0, 1.0, 0.14)
	_log_style.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	_log_style.shadow_size = 8
	_log_style.content_margin_left = 12.0
	_log_style.content_margin_right = 12.0
	_log_style.content_margin_top = 9.0
	_log_style.content_margin_bottom = 9.0
	_panel.add_theme_stylebox_override("panel", _log_style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var old_scroll := _panel.get_node_or_null("LogScroll") as Control
	if old_scroll != null:
		old_scroll.visible = false

	_log = _panel.get_node_or_null("LogLabel") as RichTextLabel
	if _log == null:
		_log = RichTextLabel.new()
		_log.name = "LogLabel"
		_panel.add_child(_log)

	_log.bbcode_enabled = true
	_log.scroll_active = true
	_log.scroll_following = true
	_log.selection_enabled = false
	_log.context_menu_enabled = false
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_font_size_override("bold_font_size", 14)
	_log.add_theme_color_override("default_color", RetroUI.NIGHT_INK)
	_log.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	_log.add_theme_constant_override("outline_size", 2)
	var chat_font: Font = RetroUI.source(400)
	if chat_font != null:
		_log.add_theme_font_override("normal_font", chat_font)
		_log.add_theme_font_override("bold_font", RetroUI.source(700))

	_input_panel = get_node_or_null("InputPanel") as PanelContainer
	if _input_panel == null:
		_input_panel = PanelContainer.new()
		_input_panel.name = "InputPanel"
		_input_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_input_panel.offset_top = -36.0
		add_child(_input_panel)

	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.04, 0.055, 0.075, 0.88)
	isb.set_corner_radius_all(8)
	isb.anti_aliasing = true
	isb.set_border_width_all(1)
	isb.border_color = Color(1.0, 1.0, 1.0, 0.16)
	isb.content_margin_left = 4.0
	isb.content_margin_right = 4.0
	isb.content_margin_top = 4.0
	isb.content_margin_bottom = 4.0
	_input_panel.add_theme_stylebox_override("panel", isb)

	var existing_input := _input_panel.get_node_or_null("ChatInput") as LineEdit
	if existing_input != null:
		_input_panel.remove_child(existing_input)

	var input_row := HBoxContainer.new()
	input_row.name = "InputRow"
	input_row.add_theme_constant_override("separation", 6)
	_input_panel.add_child(input_row)

	_input_box = existing_input if existing_input != null else LineEdit.new()
	_input_box.name = "ChatInput"
	_input_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(_input_box)

	_input_box.placeholder_text = "To chat click here or press \"/\" key"
	_input_box.max_length = 240
	_input_box.context_menu_enabled = false
	_input_box.add_theme_color_override("font_color", RetroUI.NIGHT_INK)
	_input_box.add_theme_color_override("font_placeholder_color", RetroUI.NIGHT_INK_FAINT)
	var well_sb := StyleBoxFlat.new()
	well_sb.bg_color = Color(0.02, 0.03, 0.045, 0.92)
	well_sb.set_corner_radius_all(6)
	well_sb.anti_aliasing = true
	well_sb.set_border_width_all(1)
	well_sb.border_color = Color(1.0, 1.0, 1.0, 0.14)
	well_sb.content_margin_left = 10.0
	well_sb.content_margin_right = 10.0
	well_sb.content_margin_top = 4.0
	well_sb.content_margin_bottom = 4.0
	_input_box.add_theme_stylebox_override("normal", well_sb)
	var well_focus := well_sb.duplicate() as StyleBoxFlat
	well_focus.border_color = Color(1.0, 1.0, 1.0, 0.45)
	_input_box.add_theme_stylebox_override("focus", well_focus)
	var book: Font = RetroUI.source(400)
	if book != null:
		_input_box.add_theme_font_override("font", book)
	_input_box.add_theme_font_size_override("font_size", 14)
	if not _input_box.text_submitted.is_connected(_on_submit):
		_input_box.text_submitted.connect(_on_submit)
	if not _input_box.gui_input.is_connected(_on_input_gui):
		_input_box.gui_input.connect(_on_input_gui)

	_quick_chat_btn = Button.new()
	_quick_chat_btn.name = "QuickChatBtn"
	_quick_chat_btn.text = "Quick Chat"
	_quick_chat_btn.custom_minimum_size = Vector2(88, 26)
	_quick_chat_btn.focus_mode = Control.FOCUS_NONE
	var qbtn_sb := StyleBoxFlat.new()
	qbtn_sb.bg_color = Color(0.12, 0.36, 0.68, 0.95)
	qbtn_sb.border_color = Color(0.45, 0.72, 1.0, 0.95)
	qbtn_sb.set_border_width_all(1)
	qbtn_sb.set_corner_radius_all(5)
	var qbtn_hov := qbtn_sb.duplicate() as StyleBoxFlat
	qbtn_hov.bg_color = Color(0.18, 0.46, 0.84, 1.0)
	qbtn_hov.border_color = Color("ffd43b")
	_quick_chat_btn.add_theme_stylebox_override("normal", qbtn_sb)
	_quick_chat_btn.add_theme_stylebox_override("hover", qbtn_hov)
	_quick_chat_btn.add_theme_stylebox_override("pressed", qbtn_sb)
	_quick_chat_btn.add_theme_color_override("font_color", Color.WHITE)
	_quick_chat_btn.add_theme_font_size_override("font_size", 12)
	if RetroUI.gotham(700) != null:
		_quick_chat_btn.add_theme_font_override("font", RetroUI.gotham(700))
	_quick_chat_btn.pressed.connect(toggle_quick_chat)
	input_row.add_child(_quick_chat_btn)

	_build_quick_chat_panel()

	visible = true
	_panel.visible = true
	_input_panel.visible = true
	_bg_timer = BG_FADE_DELAY
	_apply_bg_alpha(1.0)


func _build_quick_chat_panel() -> void:
	_quick_panel = PanelContainer.new()
	_quick_panel.name = "QuickChatPanel"
	_quick_panel.visible = false
	_quick_panel.position = Vector2(402.0, 0.0)
	_quick_panel.custom_minimum_size = Vector2(360.0, 300.0)
	var qpsb := StyleBoxFlat.new()
	qpsb.bg_color = Color(0.03, 0.04, 0.06, 0.92)
	qpsb.border_color = Color(0.45, 0.52, 0.64, 0.95)
	qpsb.set_border_width_all(2)
	qpsb.set_corner_radius_all(6)
	qpsb.content_margin_left = 10.0
	qpsb.content_margin_right = 10.0
	qpsb.content_margin_top = 8.0
	qpsb.content_margin_bottom = 8.0
	_quick_panel.add_theme_stylebox_override("panel", qpsb)
	add_child(_quick_panel)

	var vcol := VBoxContainer.new()
	vcol.add_theme_constant_override("separation", 6)
	_quick_panel.add_child(vcol)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	vcol.add_child(head)

	var title := Label.new()
	title.text = "QUICK CHAT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color("ffd43b"))
	title.add_theme_font_size_override("font_size", 13)
	if RetroUI.gotham(700) != null:
		title.add_theme_font_override("font", RetroUI.gotham(700))
	head.add_child(title)

	var btn_sb := StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.10, 0.12, 0.16, 0.92)
	btn_sb.border_color = Color(0.48, 0.52, 0.60, 0.90)
	btn_sb.set_border_width_all(1)
	btn_sb.set_corner_radius_all(4)
	btn_sb.content_margin_left = 6.0
	btn_sb.content_margin_right = 6.0

	_edit_mode_btn = Button.new()
	_edit_mode_btn.text = "Edit All"
	_edit_mode_btn.custom_minimum_size = Vector2(62, 22)
	_edit_mode_btn.focus_mode = Control.FOCUS_NONE
	_edit_mode_btn.add_theme_stylebox_override("normal", btn_sb)
	_edit_mode_btn.add_theme_color_override("font_color", Color.WHITE)
	_edit_mode_btn.add_theme_font_size_override("font_size", 11)
	_edit_mode_btn.pressed.connect(func() -> void:
		_is_editing_quick = not _is_editing_quick
		_editing_index = -1
		_edit_mode_btn.text = "Done" if _is_editing_quick else "Edit All"
		if not _is_editing_quick:
			_save_quick_phrases()
		_refresh_quick_chat_list()
	)
	head.add_child(_edit_mode_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Defaults"
	reset_btn.custom_minimum_size = Vector2(60, 22)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.add_theme_stylebox_override("normal", btn_sb)
	reset_btn.add_theme_color_override("font_color", Color("74c0fc"))
	reset_btn.add_theme_font_size_override("font_size", 11)
	reset_btn.pressed.connect(func() -> void:
		quick_phrases = DEFAULT_QUICK_PHRASES.duplicate()
		_is_editing_quick = false
		_editing_index = -1
		_edit_mode_btn.text = "Edit All"
		_save_quick_phrases()
		_refresh_quick_chat_list()
	)
	head.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(26, 22)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_stylebox_override("normal", btn_sb)
	close_btn.add_theme_color_override("font_color", Color("ff6b6b"))
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(func() -> void: _quick_panel.visible = false)
	head.add_child(close_btn)

	# Direct Quick-Add bar so users can add custom Quick Chat messages anytime
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 5)
	vcol.add_child(add_row)

	_quick_add_input = LineEdit.new()
	_quick_add_input.placeholder_text = "Add custom quick chat phrase..."
	_quick_add_input.max_length = 140
	_quick_add_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quick_add_input.custom_minimum_size = Vector2(210, 28)
	var add_in_sb := StyleBoxFlat.new()
	add_in_sb.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	add_in_sb.border_color = Color(0.35, 0.45, 0.60, 0.95)
	add_in_sb.set_border_width_all(1)
	add_in_sb.set_corner_radius_all(4)
	add_in_sb.content_margin_left = 8.0
	add_in_sb.content_margin_right = 8.0
	_quick_add_input.add_theme_stylebox_override("normal", add_in_sb)
	_quick_add_input.add_theme_color_override("font_color", Color.WHITE)
	_quick_add_input.add_theme_font_size_override("font_size", 12)
	_quick_add_input.text_submitted.connect(func(_t: String) -> void: _add_custom_quick_phrase())
	add_row.add_child(_quick_add_input)

	var add_btn := Button.new()
	add_btn.text = "+ Add"
	add_btn.custom_minimum_size = Vector2(58, 28)
	add_btn.focus_mode = Control.FOCUS_NONE
	var add_btn_sb := StyleBoxFlat.new()
	add_btn_sb.bg_color = Color(0.14, 0.48, 0.24, 0.96)
	add_btn_sb.border_color = Color(0.32, 0.82, 0.46, 0.96)
	add_btn_sb.set_border_width_all(1)
	add_btn_sb.set_corner_radius_all(4)
	add_btn.add_theme_stylebox_override("normal", add_btn_sb)
	add_btn.add_theme_color_override("font_color", Color.WHITE)
	add_btn.add_theme_font_size_override("font_size", 11)
	add_btn.pressed.connect(_add_custom_quick_phrase)
	add_row.add_child(add_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vcol.add_child(scroll)

	_quick_list_box = VBoxContainer.new()
	_quick_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quick_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_quick_list_box)

	# Bottom bar with drag-to-resize grip so players can resize the Quick Chat panel freely
	var foot := HBoxContainer.new()
	vcol.add_child(foot)
	var hint_lbl := Label.new()
	hint_lbl.text = "Scroll or drag corner to resize"
	hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_lbl.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72, 0.85))
	hint_lbl.add_theme_font_size_override("font_size", 10)
	foot.add_child(hint_lbl)

	var resize_grip := Button.new()
	resize_grip.text = "[Resize]"
	resize_grip.custom_minimum_size = Vector2(54, 18)
	resize_grip.focus_mode = Control.FOCUS_NONE
	resize_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	resize_grip.add_theme_font_size_override("font_size", 10)
	resize_grip.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var mm := ev as InputEventMouseMotion
			var new_sz := _quick_panel.custom_minimum_size + mm.relative
			new_sz.x = clampf(new_sz.x, 240.0, 680.0)
			new_sz.y = clampf(new_sz.y, 180.0, 560.0)
			_quick_panel.custom_minimum_size = new_sz
			_quick_panel.size = new_sz
	)
	foot.add_child(resize_grip)

	_refresh_quick_chat_list()


func _add_custom_quick_phrase() -> void:
	if _quick_add_input == null:
		return
	var txt := _quick_add_input.text.strip_edges()
	if txt == "":
		quick_phrases.append("New quick chat...")
		_editing_index = quick_phrases.size() - 1
	else:
		quick_phrases.append(txt)
		_quick_add_input.text = ""
		_editing_index = -1
	_save_quick_phrases()
	_refresh_quick_chat_list()


func toggle_quick_chat() -> void:
	_ensure_ui()
	if _quick_panel != null:
		_quick_panel.visible = not _quick_panel.visible
		if _quick_panel.visible:
			_wake_bg()
			_refresh_quick_chat_list()


func _refresh_quick_chat_list() -> void:
	if _quick_list_box == null:
		return
	for ch in _quick_list_box.get_children():
		ch.queue_free()

	if quick_phrases.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No Quick Chat phrases yet. Type a message above and click '+ Add'!"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_color_override("font_color", Color(0.72, 0.76, 0.84, 0.90))
		empty_lbl.add_theme_font_size_override("font_size", 12)
		_quick_list_box.add_child(empty_lbl)
		return

	for i in range(quick_phrases.size()):
		var phrase_txt: String = quick_phrases[i]
		var idx_capture: int = i
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_quick_list_box.add_child(row)

		if _is_editing_quick or _editing_index == i:
			var le := LineEdit.new()
			le.text = phrase_txt
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.custom_minimum_size = Vector2(200, 26)
			var lesb := StyleBoxFlat.new()
			lesb.bg_color = Color(0.08, 0.10, 0.14, 0.96)
			lesb.border_color = Color("ffd43b") if _editing_index == i else Color(0.55, 0.58, 0.64, 1.0)
			lesb.set_border_width_all(1)
			lesb.set_corner_radius_all(4)
			lesb.content_margin_left = 6.0
			lesb.content_margin_right = 6.0
			le.add_theme_stylebox_override("normal", lesb)
			le.placeholder_text = "Type quick chat phrase..."
			le.add_theme_color_override("font_color", Color.WHITE)
			le.add_theme_font_size_override("font_size", 12)
			le.text_changed.connect(func(new_t: String) -> void:
				if idx_capture >= 0 and idx_capture < quick_phrases.size():
					quick_phrases[idx_capture] = new_t
					_save_quick_phrases()
			)
			le.text_submitted.connect(func(_new_t: String) -> void:
				_editing_index = -1
				_save_quick_phrases()
				_refresh_quick_chat_list()
			)
			row.add_child(le)

			if not _is_editing_quick:
				var save_row_btn := Button.new()
				save_row_btn.text = "Save"
				save_row_btn.custom_minimum_size = Vector2(44, 26)
				save_row_btn.focus_mode = Control.FOCUS_NONE
				var ssb := StyleBoxFlat.new()
				ssb.bg_color = Color(0.14, 0.48, 0.24, 0.96)
				ssb.border_color = Color(0.32, 0.82, 0.46, 0.96)
				ssb.set_border_width_all(1)
				ssb.set_corner_radius_all(4)
				save_row_btn.add_theme_stylebox_override("normal", ssb)
				save_row_btn.add_theme_color_override("font_color", Color.WHITE)
				save_row_btn.add_theme_font_size_override("font_size", 11)
				save_row_btn.pressed.connect(func() -> void:
					_editing_index = -1
					_save_quick_phrases()
					_refresh_quick_chat_list()
				)
				row.add_child(save_row_btn)

			var del_btn := Button.new()
			del_btn.text = "Del"
			del_btn.custom_minimum_size = Vector2(36, 26)
			del_btn.focus_mode = Control.FOCUS_NONE
			var dsb := StyleBoxFlat.new()
			dsb.bg_color = Color(0.32, 0.10, 0.12, 0.95)
			dsb.border_color = Color("ff6b6b")
			dsb.set_border_width_all(1)
			dsb.set_corner_radius_all(4)
			del_btn.add_theme_stylebox_override("normal", dsb)
			del_btn.add_theme_color_override("font_color", Color("ff8787"))
			del_btn.add_theme_font_size_override("font_size", 11)
			del_btn.pressed.connect(func() -> void:
				if idx_capture >= 0 and idx_capture < quick_phrases.size():
					quick_phrases.remove_at(idx_capture)
					_editing_index = -1
					_save_quick_phrases()
					_refresh_quick_chat_list()
			)
			row.add_child(del_btn)
		else:
			var p_btn := Button.new()
			p_btn.text = phrase_txt
			p_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			p_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p_btn.custom_minimum_size = Vector2(215, 28)
			p_btn.focus_mode = Control.FOCUS_NONE
			var psb := StyleBoxFlat.new()
			psb.bg_color = Color(0.08, 0.11, 0.16, 0.92)
			psb.border_color = Color(0.45, 0.52, 0.64, 0.90)
			psb.set_border_width_all(1)
			psb.set_corner_radius_all(4)
			psb.content_margin_left = 8.0
			psb.content_margin_right = 8.0
			var phov := psb.duplicate() as StyleBoxFlat
			phov.bg_color = Color(0.15, 0.24, 0.38, 0.98)
			phov.border_color = Color("4dabf7")
			p_btn.add_theme_stylebox_override("normal", psb)
			p_btn.add_theme_stylebox_override("hover", phov)
			p_btn.add_theme_stylebox_override("pressed", psb)
			p_btn.add_theme_color_override("font_color", Color.WHITE)
			p_btn.add_theme_color_override("font_hover_color", Color("ffd43b"))
			p_btn.add_theme_font_size_override("font_size", 12)
			var send_txt: String = phrase_txt
			p_btn.pressed.connect(func() -> void:
				var clean := send_txt.strip_edges()
				if clean != "":
					_wake_bg()
					submitted.emit(clean)
			)
			row.add_child(p_btn)

			var edit_one_btn := Button.new()
			edit_one_btn.text = "Edit"
			edit_one_btn.custom_minimum_size = Vector2(40, 28)
			edit_one_btn.focus_mode = Control.FOCUS_NONE
			var esb := StyleBoxFlat.new()
			esb.bg_color = Color(0.12, 0.15, 0.22, 0.92)
			esb.border_color = Color(0.42, 0.48, 0.58, 0.90)
			esb.set_border_width_all(1)
			esb.set_corner_radius_all(4)
			edit_one_btn.add_theme_stylebox_override("normal", esb)
			edit_one_btn.add_theme_color_override("font_color", Color("ced4da"))
			edit_one_btn.add_theme_font_size_override("font_size", 11)
			edit_one_btn.pressed.connect(func() -> void:
				_editing_index = idx_capture
				_refresh_quick_chat_list()
			)
			row.add_child(edit_one_btn)

			var del_one_btn := Button.new()
			del_one_btn.text = "X"
			del_one_btn.custom_minimum_size = Vector2(26, 28)
			del_one_btn.focus_mode = Control.FOCUS_NONE
			var dsb2 := StyleBoxFlat.new()
			dsb2.bg_color = Color(0.24, 0.09, 0.11, 0.92)
			dsb2.border_color = Color(0.65, 0.25, 0.28, 0.90)
			dsb2.set_border_width_all(1)
			dsb2.set_corner_radius_all(4)
			del_one_btn.add_theme_stylebox_override("normal", dsb2)
			del_one_btn.add_theme_color_override("font_color", Color("ff8787"))
			del_one_btn.add_theme_font_size_override("font_size", 11)
			del_one_btn.pressed.connect(func() -> void:
				if idx_capture >= 0 and idx_capture < quick_phrases.size():
					quick_phrases.remove_at(idx_capture)
					_save_quick_phrases()
					_refresh_quick_chat_list()
			)
			row.add_child(del_one_btn)


func _process(delta: float) -> void:
	if not visible:
		return
	var mp := get_global_mouse_position()
	var hovered := get_global_rect().has_point(mp) or (_quick_panel != null and _quick_panel.visible and _quick_panel.get_global_rect().has_point(mp))
	if is_open or hovered or (_quick_panel != null and _quick_panel.visible):
		_bg_timer = BG_FADE_DELAY
		_bg_alpha = move_toward(_bg_alpha, 1.0, delta * 6.0)
	else:
		if _bg_timer > 0.0:
			_bg_timer -= delta
		else:
			_bg_alpha = move_toward(_bg_alpha, 0.0, delta * BG_FADE_SPEED)
	_apply_bg_alpha(_bg_alpha)


func _apply_bg_alpha(a: float) -> void:
	if _log_style != null:
		_log_style.bg_color = Color(0.04, 0.055, 0.075, 0.84 * a)
		_log_style.border_color = Color(1.0, 1.0, 1.0, 0.14 * a)
		_log_style.shadow_color = Color(0.0, 0.0, 0.0, 0.30 * a)
	if _input_panel != null and is_instance_valid(_input_panel):
		_input_panel.modulate.a = a
		_input_panel.mouse_filter = Control.MOUSE_FILTER_STOP if a > 0.05 else Control.MOUSE_FILTER_PASS
	if _log != null and is_instance_valid(_log):
		_log.scroll_active = a > 0.15


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.is_pressed():
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			var inside := get_global_rect().has_point(mb.global_position) or (_quick_panel != null and _quick_panel.visible and _quick_panel.get_global_rect().has_point(mb.global_position))
			if is_open and not inside:
				unfocus()
			elif not is_open and inside:
				_wake_bg()


func _wake_bg() -> void:
	_bg_timer = BG_FADE_DELAY
	_bg_alpha = 1.0
	_apply_bg_alpha(1.0)


func open() -> void:
	_ensure_ui()
	visible = true
	_panel.visible = true
	_input_panel.visible = true
	is_reading = true
	log_collapsed = false
	_wake_bg()
	_clear_unread()
	if not is_open:
		is_open = true
		_input_box.grab_focus()
		opened.emit()
	else:
		_input_box.grab_focus()


func unfocus() -> void:
	_ensure_ui()
	if not is_open:
		return
	is_open = false
	_input_box.release_focus()
	_bg_timer = BG_FADE_DELAY
	closed.emit()


func close() -> void:
	_ensure_ui()
	if is_open:
		is_open = false
		_input_box.text = ""
		_input_box.release_focus()
		closed.emit()
	is_reading = false
	_panel.visible = false
	_input_panel.visible = false
	if _quick_panel != null:
		_quick_panel.visible = false
	visible = false


func toggle_window() -> void:
	_ensure_ui()
	if visible:
		close()
	else:
		visible = true
		_panel.visible = true
		_input_panel.visible = true
		is_reading = true
		_wake_bg()
		_clear_unread()


func set_log_collapsed(collapsed: bool) -> void:
	_ensure_ui()
	log_collapsed = collapsed
	_panel.visible = not collapsed
	if not collapsed:
		_clear_unread()


func _clear_unread() -> void:
	_unread = 0
	unread.emit(0)


func _on_submit(text: String) -> void:
	var clean := text.strip_edges()
	_input_box.text = ""
	unfocus()
	if clean != "":
		submitted.emit(clean)


func _on_input_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		_wake_bg()
		if not is_open:
			open()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			unfocus()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_SHIFT:
			get_viewport().set_input_as_handled()


func is_typing() -> bool:
	if _quick_panel != null and _quick_panel.visible:
		if _is_editing_quick or _editing_index >= 0:
			return true
		if _quick_add_input != null and is_instance_valid(_quick_add_input) and _quick_add_input.has_focus():
			return true
	return is_open or (_input_box != null and is_instance_valid(_input_box) and _input_box.has_focus())


func is_chat_focused() -> bool:
	return is_typing()


func add_chat(username: String, _seq_id: int, text: String, name_color: String = "", _self_style := false, _uid := "") -> void:
	_ensure_ui()
	var color := _color_for(username, name_color)
	var line := " [b][color=#%s]%s:[/color][/b] %s" % [color, _esc(username), _esc(text)]
	_log.append_text(line + "\n")
	_count_unread()
	_prune()


func add_system(text: String) -> void:
	_ensure_ui()
	_log.append_text(" [color=#9cb3c9]%s[/color]\n" % _esc(text))
	_count_unread()
	_prune()


func _count_unread() -> void:
	if not visible or log_collapsed:
		_unread += 1
		unread.emit(_unread)


func _prune() -> void:
	if _log.get_total_character_count() > 12000:
		_log.clear()
		_log.append_text(" [color=#9cb3c9](chat trimmed)[/color]\n")


func _esc(text: String) -> String:
	var parts := text.split("[")
	for i in range(1, parts.size()):
		parts[i] = "[lb]" + parts[i]
	return "".join(parts)


func _color_for(username: String, requested: String) -> String:
	if requested != "":
		return requested.lstrip("#")
	var h := 0
	for i in range(username.length()):
		h = (h * 31 + username.unicode_at(i)) % 100000
	return String(NAME_COLORS[h % NAME_COLORS.size()])
