@tool
extends AcceptDialog

# RetroBlox Studio - Player & Game Settings Dialog
# Allows creators to configure movement, health, and avatar properties without touching code.

signal settings_saved

var _speed_spin: SpinBox
var _jump_spin: SpinBox
var _grav_spin: SpinBox
var _health_spin: SpinBox
var _regen_spin: SpinBox
var _fall_damage_check: CheckBox
var _shiftlock_check: CheckBox
var _shirt_edit: LineEdit
var _pants_edit: LineEdit


func _init() -> void:
	title = "RetroBlox - Player & Game Settings"
	size = Vector2i(480, 440)
	ok_button_text = "Save Settings"


func _ready() -> void:
	confirmed.connect(_on_save_pressed)
	_build_ui()
	_load_values()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 360)
	add_child(scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	# --- Header ---
	var title_lbl := Label.new()
	title_lbl.text = "Player Movement & Rules"
	title_lbl.add_theme_font_size_override("font_size", 14)
	vb.add_child(title_lbl)

	var hs1 := HSeparator.new()
	vb.add_child(hs1)

	# Walk Speed
	_speed_spin = _add_row_spin(vb, "Walk Speed (studs/s):", 1.0, 200.0, 1.0, 16.0)

	# Jump Power
	_jump_spin = _add_row_spin(vb, "Jump Power (studs):", 0.0, 300.0, 1.0, 50.0)

	# Gravity
	_grav_spin = _add_row_spin(vb, "Gravity (studs/s²):", 0.0, 1000.0, 5.0, 196.2)

	# --- Health Section ---
	var hs2 := HSeparator.new()
	vb.add_child(hs2)

	var health_lbl := Label.new()
	health_lbl.text = "Health & Damage"
	health_lbl.add_theme_font_size_override("font_size", 14)
	vb.add_child(health_lbl)

	# Max Health
	_health_spin = _add_row_spin(vb, "Max Health:", 1.0, 10000.0, 5.0, 100.0)

	# Regen Rate
	_regen_spin = _add_row_spin(vb, "Regen Rate (HP/s):", 0.0, 100.0, 0.5, 1.0)

	# Fall Damage
	_fall_damage_check = CheckBox.new()
	_fall_damage_check.text = "Enable Fall Damage"
	_fall_damage_check.button_pressed = true
	vb.add_child(_fall_damage_check)

	# Shift Lock
	_shiftlock_check = CheckBox.new()
	_shiftlock_check.text = "Allow Shift Lock"
	_shiftlock_check.button_pressed = true
	vb.add_child(_shiftlock_check)

	# --- Avatar Section ---
	var hs3 := HSeparator.new()
	vb.add_child(hs3)

	var avatar_lbl := Label.new()
	avatar_lbl.text = "Default Starter Clothing"
	avatar_lbl.add_theme_font_size_override("font_size", 14)
	vb.add_child(avatar_lbl)

	_shirt_edit = _add_row_edit(vb, "Default Shirt Asset ID:", "")
	_pants_edit = _add_row_edit(vb, "Default Pants Asset ID:", "")


func _add_row_spin(parent: Container, label_text: String, min_v: float, max_v: float, step_v: float, default_v: float) -> SpinBox:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step_v
	spin.value = default_v
	spin.custom_minimum_size = Vector2(100, 0)
	row.add_child(spin)
	parent.add_child(row)
	return spin


func _add_row_edit(parent: Container, label_text: String, default_v: String) -> LineEdit:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var edit := LineEdit.new()
	edit.text = default_v
	edit.placeholder_text = "e.g. shirt_01"
	edit.custom_minimum_size = Vector2(140, 0)
	row.add_child(edit)
	parent.add_child(row)
	return edit


func _load_values() -> void:
	if _speed_spin != null:
		_speed_spin.value = float(ProjectSettings.get_setting("player/movement/walk_speed", 16.0))
	if _jump_spin != null:
		_jump_spin.value = float(ProjectSettings.get_setting("player/movement/jump_power", 50.0))
	if _grav_spin != null:
		_grav_spin.value = float(ProjectSettings.get_setting("player/movement/gravity", 196.2))
	if _health_spin != null:
		_health_spin.value = float(ProjectSettings.get_setting("player/health/max_health", 100.0))
	if _regen_spin != null:
		_regen_spin.value = float(ProjectSettings.get_setting("player/health/health_regen_rate", 1.0))
	if _fall_damage_check != null:
		_fall_damage_check.button_pressed = bool(ProjectSettings.get_setting("player/health/fall_damage_enabled", true))
	if _shiftlock_check != null:
		_shiftlock_check.button_pressed = bool(ProjectSettings.get_setting("player/features/shift_lock", true))
	if _shirt_edit != null:
		_shirt_edit.text = str(ProjectSettings.get_setting("player/appearance/default_shirt", ""))
	if _pants_edit != null:
		_pants_edit.text = str(ProjectSettings.get_setting("player/appearance/default_pants", ""))


func _on_save_pressed() -> void:
	ProjectSettings.set_setting("player/movement/walk_speed", float(_speed_spin.value))
	ProjectSettings.set_setting("player/movement/jump_power", float(_jump_spin.value))
	ProjectSettings.set_setting("player/movement/gravity", float(_grav_spin.value))
	ProjectSettings.set_setting("player/health/max_health", float(_health_spin.value))
	ProjectSettings.set_setting("player/health/health_regen_rate", float(_regen_spin.value))
	ProjectSettings.set_setting("player/health/fall_damage_enabled", bool(_fall_damage_check.button_pressed))
	ProjectSettings.set_setting("player/features/shift_lock", bool(_shiftlock_check.button_pressed))
	ProjectSettings.set_setting("player/appearance/default_shirt", _shirt_edit.text.strip_edges())
	ProjectSettings.set_setting("player/appearance/default_pants", _pants_edit.text.strip_edges())

	var err := ProjectSettings.save()
	if err == OK:
		settings_saved.emit()
