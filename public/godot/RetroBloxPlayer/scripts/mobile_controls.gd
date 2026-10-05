class_name MobileControls
extends CanvasLayer
## Touch controls: left virtual joystick (move), right JUMP button.
## Only instantiated when the device reports a touchscreen.

signal move_changed(vec: Vector2)
signal jump_pressed

var _knob: Control
var _base: Control
var _touch_index: int = -1
var _origin: Vector2 = Vector2.ZERO
const RADIUS := 90.0

func _ready() -> void:
	layer = 20
	_base = Control.new()
	_base.position = Vector2(40, 0)
	_base.size = Vector2(RADIUS * 2, RADIUS * 2)
	_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_base.position = Vector2(44, -44 - RADIUS * 2)
	var base_bg := Panel.new()
	base_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.26, 0.32, 0.4)
	sb.set_corner_radius_all(RADIUS)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.35)
	base_bg.add_theme_stylebox_override("panel", sb)
	_base.add_child(base_bg)
	_knob = Control.new()
	var knob_bg := Panel.new()
	knob_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ksb := StyleBoxFlat.new()
	ksb.bg_color = Color(0.85, 0.24, 0.24, 0.75)
	ksb.set_corner_radius_all(28)
	knob_bg.add_theme_stylebox_override("panel", ksb)
	_knob.add_child(knob_bg)
	_knob.size = Vector2(56, 56)
	_knob.position = Vector2(RADIUS - 28, RADIUS - 28)
	_base.add_child(_knob)
	add_child(_base)

	var jump := Button.new()
	jump.text = "JUMP"
	jump.custom_minimum_size = Vector2(110, 110)
	jump.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	jump.position = Vector2(-150, -150)
	jump.focus_mode = Control.FOCUS_NONE
	var jsb := StyleBoxFlat.new()
	jsb.bg_color = Color(0.55, 0.6, 0.66, 0.6)
	jsb.set_corner_radius_all(55)
	jsb.set_border_width_all(2)
	jsb.border_color = Color(0.85, 0.24, 0.24, 0.9)
	jump.add_theme_stylebox_override("normal", jsb)
	jump.add_theme_stylebox_override("hover", jsb)
	jump.add_theme_stylebox_override("pressed", jsb)
	jump.pressed.connect(func() -> void: jump_pressed.emit())
	add_child(jump)

func _gui_input_base(event: InputEvent) -> void:
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and t.position.x < 340 and t.position.y > 260 and _touch_index == -1:
			_touch_index = t.index
			_origin = t.position
		elif not t.pressed and t.index == _touch_index:
			_touch_index = -1
			move_changed.emit(Vector2.ZERO)
			_knob.position = Vector2(RADIUS - 28, RADIUS - 28)
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _touch_index:
		var d := event as InputEventScreenDrag
		var v := (d.position - _origin) / RADIUS
		if v.length() > 1.0:
			v = v.normalized()
		move_changed.emit(v)
		_knob.position = Vector2(RADIUS - 28, RADIUS - 28) + v * (RADIUS - 30.0)
