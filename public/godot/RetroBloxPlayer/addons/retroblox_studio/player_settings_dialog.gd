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
var _lose_items_check: CheckBox
var _shirt_edit: LineEdit
var _pants_edit: LineEdit


func _init() -> void:
	title = "RetroBlox - Player & Game Settings"
	size = Vector2i(430, 340)
	max_size = Vector2i(500, 420)
	ok_button_text = "Save & Close"


func _ready() -> void:
	confirmed.connect(_on_save_pressed)
	close_requested.connect(hide)
	_build_ui()
	_load_values()


func _build_ui() -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	scroll.add_child(vb)

	var top_bar: HBoxContainer = HBoxContainer.new()
	vb.add_child(top_bar)

	var title_lbl: Label = Label.new()
	title_lbl.text = "Player Movement & Rules"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 13)
	top_bar.add_child(title_lbl)

	var close_top_btn: Button = Button.new()
	close_top_btn.text = "X Close"
	close_top_btn.pressed.connect(hide)
	top_bar.add_child(close_top_btn)

	vb.add_child(HSeparator.new())

	_speed_spin = _add_row_spin(vb, "Walk Speed (studs/s):", 0.0, 10000.0, 0.5, 16.0)
	_jump_spin = _add_row_spin(vb, "Jump Power (studs):", 0.0, 10000.0, 0.5, 50.0)
	_grav_spin = _add_row_spin(vb, "Gravity (studs/s²):", 0.0, 10000.0, 0.1, 196.2)

	vb.add_child(HSeparator.new())

	var health_lbl: Label = Label.new()
	health_lbl.text = "Health, Damage & Inventory"
	health_lbl.add_theme_font_size_override("font_size", 13)
	vb.add_child(health_lbl)

	# Step = 1.0 (with min 0.0) so 100, 97, or any integer/decimal health works cleanly!
	_health_spin = _add_row_spin(vb, "Max Health:", 0.0, 100000.0, 1.0, 100.0)
	_regen_spin = _add_row_spin(vb, "Regen Rate (HP/s):", 0.0, 1000.0, 0.5, 1.0)

	_fall_damage_check = CheckBox.new()
	_fall_damage_check.text = "Enable Fall Damage"
	_fall_damage_check.button_pressed = true
	vb.add_child(_fall_damage_check)

	_shiftlock_check = CheckBox.new()
	_shiftlock_check.text = "Allow Shift Lock"
	_shiftlock_check.button_pressed = true
	vb.add_child(_shiftlock_check)

	_lose_items_check = CheckBox.new()
	_lose_items_check.text = "Lose Items When Dead (Default: On)"
	_lose_items_check.button_pressed = true
	vb.add_child(_lose_items_check)

	vb.add_child(HSeparator.new())

	var avatar_lbl: Label = Label.new()
	avatar_lbl.text = "Default Starter Clothing"
	avatar_lbl.add_theme_font_size_override("font_size", 13)
	vb.add_child(avatar_lbl)

	_shirt_edit = _add_row_edit(vb, "Default Shirt Asset ID:", "")
	_pants_edit = _add_row_edit(vb, "Default Pants Asset ID:", "")


func _add_row_spin(parent: Container, label_text: String, min_v: float, max_v: float, step_v: float, default_v: float) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var spin: SpinBox = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 0.01
	spin.custom_arrow_step = step_v
	spin.allow_greater = true
	spin.value = default_v
	spin.custom_minimum_size = Vector2(110, 0)
	row.add_child(spin)
	parent.add_child(row)
	return spin


func _add_row_edit(parent: Container, label_text: String, default_v: String) -> LineEdit:
	var row: HBoxContainer = HBoxContainer.new()
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var edit: LineEdit = LineEdit.new()
	edit.text = default_v
	edit.placeholder_text = "e.g. shirt_01"
	edit.custom_minimum_size = Vector2(130, 0)
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
	if _lose_items_check != null:
		_lose_items_check.button_pressed = bool(ProjectSettings.get_setting("player/features/lose_item_when_dead", true))
	if _shirt_edit != null:
		_shirt_edit.text = str(ProjectSettings.get_setting("player/appearance/default_shirt", ""))
	if _pants_edit != null:
		_pants_edit.text = str(ProjectSettings.get_setting("player/appearance/default_pants", ""))


func _on_save_pressed() -> void:
	ProjectSettings.set_setting("player/movement/walk_speed", maxf(0.1, float(_speed_spin.value)))
	ProjectSettings.set_setting("player/movement/jump_power", maxf(0.0, float(_jump_spin.value)))
	ProjectSettings.set_setting("player/movement/gravity", maxf(0.0, float(_grav_spin.value)))
	ProjectSettings.set_setting("player/health/max_health", maxf(1.0, float(_health_spin.value)))
	ProjectSettings.set_setting("player/health/health_regen_rate", maxf(0.0, float(_regen_spin.value)))
	ProjectSettings.set_setting("player/health/fall_damage_enabled", bool(_fall_damage_check.button_pressed))
	ProjectSettings.set_setting("player/features/shift_lock", bool(_shiftlock_check.button_pressed))
	if _lose_items_check != null:
		ProjectSettings.set_setting("player/features/lose_item_when_dead", bool(_lose_items_check.button_pressed))
	ProjectSettings.set_setting("player/appearance/default_shirt", _shirt_edit.text.strip_edges())
	ProjectSettings.set_setting("player/appearance/default_pants", _pants_edit.text.strip_edges())

	var err: int = ProjectSettings.save()
	if err == OK:
		settings_saved.emit()
