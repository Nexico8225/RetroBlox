class_name Hotbar
extends HBoxContainer
## Classic bottom hotbar: slots 1-3 (Sword / Rocket / Trowel), keys 1-3 or click.
## Slot 0 = empty hands (key ` or clicking the active slot again).

signal tool_selected(index: int)

const NAMES := ["Sword", "Rocket", "Trowel"]
const KEYS := ["1", "2", "3"]

var _buttons: Array[Button] = []
var active: int = -1

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	position.y -= 96.0
	add_theme_constant_override("separation", 6)
	for i in range(NAMES.size()):
		var b := Button.new()
		b.text = "%s  %s" % [KEYS[i], NAMES[i]]
		b.custom_minimum_size = Vector2(86, 40)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: tool_selected.emit(i))
		b.mouse_entered.connect(func() -> void: Sfx.ui("ui_hover", -10.0))
		add_child(b)
		_buttons.append(b)
	set_active(-1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode >= KEY_1 and k.keycode <= KEY_3:
			var idx := int(k.keycode) - int(KEY_1)
			tool_selected.emit(idx if idx != active else -1)
		elif k.keycode == KEY_BACKQUOTE or k.keycode == KEY_0:
			tool_selected.emit(-1)

func set_active(index: int) -> void:
	active = index
	for i in range(_buttons.size()):
		var on := i == active
		_buttons[i].modulate = Color(1, 1, 1, 1.0) if on else Color(0.82, 0.85, 0.9, 0.75)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.22, 0.28, 0.34, 0.92) if on else Color(0.55, 0.6, 0.66, 0.72)
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.85, 0.24, 0.24, 1.0) if on else Color(0.3, 0.36, 0.42, 1.0)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 2
		_buttons[i].add_theme_stylebox_override("normal", sb)
		_buttons[i].add_theme_stylebox_override("hover", sb)
		_buttons[i].add_theme_stylebox_override("pressed", sb)
