extends Control
# In-game Roblox-style chat box where clicking off unfocuses input and inactivity fades only the dark background while keeping chat text visible.

signal submitted(text: String)
signal opened
signal closed
signal unread(count: int)

const MAX_LINES := 60
const BG_FADE_DELAY := 3.5
const BG_FADE_SPEED := 3.0
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


func _ready() -> void:
	_ensure_ui()


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

	_input_box = _input_panel.get_node_or_null("ChatInput") as LineEdit
	if _input_box == null:
		_input_box = LineEdit.new()
		_input_box.name = "ChatInput"
		_input_panel.add_child(_input_box)

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

	visible = true
	_panel.visible = true
	_input_panel.visible = true
	_bg_timer = BG_FADE_DELAY
	_apply_bg_alpha(1.0)


func _process(delta: float) -> void:
	if not visible:
		return
	var hovered := get_global_rect().has_point(get_global_mouse_position())
	if is_open or hovered:
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
			var inside := get_global_rect().has_point(mb.global_position)
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
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			unfocus()
			get_viewport().set_input_as_handled()


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
