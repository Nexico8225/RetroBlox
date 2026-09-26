extends CanvasLayer

signal chat_submitted(message: String)
signal resume_requested
signal reset_requested
signal quit_requested
signal shiftlock_toggled(enabled: bool)
signal sensitivity_changed(value: float)
signal volume_changed(value: float)

const INK := Color("eaf3f3")
const MUTED := Color("a6bac2")
const GREEN := Color("02b757")
const GREEN_BRIGHT := Color("7ee08f")
const RED := Color("e2231a")
const PANEL := Color(0.043, 0.091, 0.115, 0.94)

var root: Control
var status_label: Label
var count_label: Label
var names_label: Label
var chat_log: RichTextLabel
var chat_entry: LineEdit
var menu: Control
var reset_button: Button
var toast: Label
var crosshair: Label
var history: Array[String] = []
var room_label: Label

# ESC menu widgets
var menu_room_label: Label
var menu_names_label: Label
var menu_count_label: Label
var shiftlock_button: Button
var sensitivity_slider: HSlider
var sensitivity_value: Label
var volume_slider: HSlider
var volume_value: Label
var roster_names: Array = []

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", INK)
	root.theme = theme
	_build_header()
	_build_roster()
	_build_chat()
	_build_help()
	_build_menu()

func _style(color: Color, radius: int = 16, border: Color = Color(0.28, 0.43, 0.45, 0.55)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.set_border_width_all(1)
	style.border_color = border
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

func _panel(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL))
	parent.add_child(panel)
	return panel

func _label(text: String, size: int = 16, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _build_header() -> void:
	var header := _panel(root)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 24
	header.offset_top = 22
	header.offset_right = -24
	header.offset_bottom = 96
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	header.add_child(row)
	var mark := _label("R", 34, RED)
	row.add_child(mark)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	row.add_child(title_box)
	title_box.add_child(_label("RETROBLOX", 23, INK))
	room_label = _label("Classic worlds, your way.", 12, MUTED)
	title_box.add_child(room_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	status_label = _label("Finding a room…", 14, GREEN_BRIGHT)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(status_label)
	var menu_button := Button.new()
	menu_button.text = "ESC  /  MENU"
	menu_button.custom_minimum_size = Vector2(132, 40)
	_button_style(menu_button, false)
	menu_button.pressed.connect(func(): set_menu(true))
	row.add_child(menu_button)

func _build_roster() -> void:
	var panel := _panel(root)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -254
	panel.offset_right = -24
	panel.offset_top = 112
	panel.offset_bottom = 250
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label("IN THIS GAME", 12, MUTED))
	count_label = _label("0 players", 17, GREEN_BRIGHT)
	box.add_child(count_label)
	names_label = _label("Waiting for connection…", 14, INK)
	names_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(names_label)

func _build_chat() -> void:
	var panel := _panel(root)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 24
	panel.offset_right = 388
	panel.offset_top = -270
	panel.offset_bottom = -24
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := HBoxContainer.new()
	box.add_child(title)
	title.add_child(_label("CHAT", 12, GREEN_BRIGHT))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(gap)
	title.add_child(_label("ENTER  ↵", 11, MUTED))
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = false
	chat_log.selection_enabled = true
	chat_log.scroll_following = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.add_theme_font_size_override("normal_font_size", 14)
	chat_log.add_theme_color_override("default_color", INK)
	box.add_child(chat_log)
	chat_entry = LineEdit.new()
	chat_entry.placeholder_text = "Say hello…"
	chat_entry.max_length = 180
	chat_entry.custom_minimum_size.y = 38
	chat_entry.add_theme_stylebox_override("normal", _style(Color("1d3943"), 8))
	chat_entry.add_theme_stylebox_override("focus", _style(Color("264751"), 8, GREEN))
	chat_entry.add_theme_font_size_override("font_size", 14)
	chat_entry.text_submitted.connect(_submit_chat)
	box.add_child(chat_entry)

func _build_help() -> void:
	var panel := _panel(root)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -640
	panel.offset_right = -24
	panel.offset_top = -91
	panel.offset_bottom = -24
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	box.add_child(_label("WASD  move     SPACE  jump     RMB  orbit     WHEEL  zoom", 13))
	box.add_child(_label("SHIFT  shift lock     ENTER  chat     ESC  menu", 12, MUTED))
	toast = _label("", 20, GREEN_BRIGHT)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	toast.offset_left = -300
	toast.offset_right = 300
	toast.offset_top = 110
	toast.offset_bottom = 145
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_shadow_color", Color("122d36"))
	toast.add_theme_constant_override("shadow_offset_x", 2)
	toast.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(toast)
	crosshair = _label("+", 22, Color(1, 1, 1, 0.8))
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -12
	crosshair.offset_right = 12
	crosshair.offset_top = -16
	crosshair.offset_bottom = 16
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.visible = false
	root.add_child(crosshair)

# ---------------------------------------------------------------- ESC menu

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(menu)
	var dim := ColorRect.new()
	dim.color = Color(0.018, 0.035, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(Color("10242e"), 20, Color(0.28, 0.43, 0.45, 0.4)))
	center.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(720, 0)
	card.add_child(column)

	# --- title row ---
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 14)
	column.add_child(title_row)
	var logo := _label("R", 34, RED)
	title_row.add_child(logo)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	title_row.add_child(title_box)
	title_box.add_child(_label("RETROBLOX", 26, INK))
	menu_room_label = _label("RetroBlox Baseplate", 13, MUTED)
	title_box.add_child(menu_room_label)
	var title_gap := Control.new()
	title_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_gap)
	var esc_hint := _label("ESC to resume", 12, MUTED)
	esc_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(esc_hint)

	# --- body: players | controls ---
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	column.add_child(body)

	var players_card := _panel(body)
	players_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var players_box := VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 8)
	players_card.add_child(players_box)
	players_box.add_child(_label("PLAYERS", 12, MUTED))
	menu_count_label = _label("1 player", 18, GREEN_BRIGHT)
	players_box.add_child(menu_count_label)
	menu_names_label = _label("", 14, INK)
	menu_names_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_names_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players_box.add_child(menu_names_label)

	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	controls.custom_minimum_size = Vector2(330, 0)
	body.add_child(controls)

	var resume := _menu_button("Resume Game", true)
	resume.pressed.connect(func(): resume_requested.emit())
	controls.add_child(resume)

	reset_button = _menu_button("Reset Character", false)
	reset_button.pressed.connect(func(): reset_requested.emit())
	controls.add_child(reset_button)

	shiftlock_button = _menu_button("Shift Lock:  OFF", false)
	shiftlock_button.pressed.connect(func(): shiftlock_toggled.emit(not _shiftlock_on))
	controls.add_child(shiftlock_button)

	var sensitivity_box := VBoxContainer.new()
	sensitivity_box.add_theme_constant_override("separation", 2)
	var sens_row := HBoxContainer.new()
	sens_row.add_child(_label("Camera Sensitivity", 13, MUTED))
	var sens_gap := Control.new()
	sens_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sens_row.add_child(sens_gap)
	sensitivity_value = _label("1.00x", 13, INK)
	sens_row.add_child(sensitivity_value)
	sensitivity_box.add_child(sens_row)
	sensitivity_slider = HSlider.new()
	sensitivity_slider.min_value = 0.4
	sensitivity_slider.max_value = 2.0
	sensitivity_slider.step = 0.05
	sensitivity_slider.custom_minimum_size = Vector2(0, 22)
	sensitivity_slider.value_changed.connect(func(v: float) -> void:
		sensitivity_value.text = "%.2fx" % v
		sensitivity_changed.emit(v)
	)
	sensitivity_box.add_child(sensitivity_slider)
	controls.add_child(sensitivity_box)

	var volume_box := VBoxContainer.new()
	volume_box.add_theme_constant_override("separation", 2)
	var vol_row := HBoxContainer.new()
	vol_row.add_child(_label("Volume", 13, MUTED))
	var vol_gap := Control.new()
	vol_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_row.add_child(vol_gap)
	volume_value = _label("100%", 13, INK)
	vol_row.add_child(volume_value)
	volume_box.add_child(vol_row)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = 1.0
	volume_slider.custom_minimum_size = Vector2(0, 22)
	volume_slider.value_changed.connect(func(v: float) -> void:
		volume_value.text = "%d%%" % int(roundf(v * 100.0))
		volume_changed.emit(v)
	)
	volume_box.add_child(volume_slider)
	controls.add_child(volume_box)

	var leave := _menu_button("Leave Game", false)
	leave.add_theme_color_override("font_color", Color("ff9a94"))
	leave.add_theme_color_override("font_hover_color", Color("ffb5b0"))
	leave.pressed.connect(func(): quit_requested.emit())
	controls.add_child(leave)

	var note := _label("The game keeps running while you are here — multiplayer never pauses.", 12, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note)
	menu.hide()

var _shiftlock_on := false

func set_shiftlock(enabled: bool) -> void:
	_shiftlock_on = enabled
	if shiftlock_button != null:
		shiftlock_button.text = "Shift Lock:  ON" if enabled else "Shift Lock:  OFF"

func set_sliders(sensitivity: float, volume: float) -> void:
	if sensitivity_slider != null:
		sensitivity_slider.set_value_no_signal(sensitivity)
		sensitivity_value.text = "%.2fx" % sensitivity
	if volume_slider != null:
		volume_slider.set_value_no_signal(volume)
		volume_value.text = "%d%%" % int(roundf(volume * 100.0))

func set_room_title(title: String) -> void:
	if menu_room_label != null:
		menu_room_label.text = title

func _button_style(button: Button, primary: bool) -> void:
	button.add_theme_stylebox_override("normal", _style(GREEN if primary else Color("213e49"), 10))
	button.add_theme_stylebox_override("hover", _style(Color("35d477") if primary else Color("305361"), 10, GREEN_BRIGHT))
	button.add_theme_stylebox_override("pressed", _style(Color("029a49") if primary else Color("142e38"), 10))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), 10, GREEN_BRIGHT))
	button.add_theme_stylebox_override("disabled", _style(Color("25333a"), 10))
	button.add_theme_color_override("font_color", Color("ffffff") if primary else INK)
	button.add_theme_color_override("font_hover_color", Color("ffffff") if primary else INK)
	button.add_theme_color_override("font_pressed_color", Color("ffffff") if primary else INK)
	button.add_theme_color_override("font_focus_color", Color("ffffff") if primary else INK)

func _menu_button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 17)
	_button_style(button, primary)
	return button

func set_menu(open: bool) -> void:
	menu.visible = open
	if open:
		_refresh_menu_roster()
		chat_entry.release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		var focused := root.get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()

func input_busy() -> bool:
	return menu.visible or chat_entry.has_focus()

func begin_chat() -> void:
	if not menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		chat_entry.grab_focus()

func _submit_chat(text: String) -> void:
	if not text.strip_edges().is_empty():
		chat_submitted.emit(text)
	chat_entry.clear()
	chat_entry.release_focus()

func add_chat(sender_name: String, message: String, system: bool = false) -> void:
	var prefix := "• " if system else sender_name + ": "
	history.append(prefix + message)
	if history.size() > 60:
		history.pop_front()
	chat_log.text = "\n\n".join(history)

func update_roster(entries: Array, local_id: int) -> void:
	roster_names = entries
	count_label.text = "%d %s" % [entries.size(), "player" if entries.size() == 1 else "players"]
	var lines: Array[String] = []
	for i in range(mini(entries.size(), 10)):
		var entry: Dictionary = entries[i]
		lines.append("• " + str(entry["name"]) + ("  (you)" if int(entry["id"]) == local_id else ""))
	if entries.size() > 10:
		lines.append("+ %d more" % (entries.size() - 10))
	if entries.size() == 1:
		lines.append("\nNo one else yet. Invite a friend!")
	elif entries.is_empty():
		lines.append("Waiting for connection…")
	names_label.text = "\n".join(lines)
	_refresh_menu_roster()

func _refresh_menu_roster() -> void:
	if menu_names_label == null:
		return
	menu_count_label.text = "%d %s in the game" % [roster_names.size(), "player" if roster_names.size() == 1 else "players"]
	var lines: Array[String] = []
	for entry in roster_names:
		lines.append("• " + str(entry["name"]))
	if roster_names.is_empty():
		lines.append("Waiting for connection…")
	menu_names_label.text = "\n".join(lines)

func set_status(text: String, connected: bool) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", GREEN_BRIGHT if connected else Color("ffd39d"))
