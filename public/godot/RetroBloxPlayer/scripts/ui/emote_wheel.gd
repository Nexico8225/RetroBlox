class_name EmoteWheel
extends Control
## EmoteWheel — the classic Roblox emote wheel, opened with the '.' (period) key.
## Renders an 8-slot radial wheel with the classic R6 emotes and custom UGC emotes.

signal emote_selected(clip_name: String)

const RetroUI := preload("res://scripts/ui/retro_theme.gd")

const DEFAULT_EMOTES: Array = [
        ["Wave", "wave", "👋", "1"],
        ["Point", "point", "👉", "2"],
        ["Cheer", "cheer", "🙌", "3"],
        ["Laugh", "laugh", "😆", "4"],
        ["Dance", "dance", "💃", "5"],
        ["Dance 2", "dance2", "🕺", "6"],
        ["Dance 3", "dance3", "✨", "7"],
        ["Sit", "sit", "🪑", "8"],
]

var _open := false
var _backdrop: ColorRect
var _wheel_panel: Control
var _center_btn: Button
var _slot_buttons: Array[Button] = []
var _emotes: Array = []


func _ready() -> void:
        name = "EmoteWheel"
        set_anchors_preset(Control.PRESET_FULL_RECT)
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        visible = false

        _backdrop = ColorRect.new()
        _backdrop.name = "Backdrop"
        _backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
        _backdrop.color = Color(0.0, 0.0, 0.0, 0.45)
        _backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
        _backdrop.gui_input.connect(_on_backdrop_input)
        add_child(_backdrop)

        _wheel_panel = Control.new()
        _wheel_panel.name = "WheelPanel"
        _wheel_panel.set_anchors_preset(Control.PRESET_CENTER)
        _wheel_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _wheel_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
        _wheel_panel.custom_minimum_size = Vector2(420, 420)
        add_child(_wheel_panel)

        _build_wheel()


func _build_wheel() -> void:
        # Outer ring glow / background
        var bg := Panel.new()
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        var bg_sb := StyleBoxFlat.new()
        bg_sb.bg_color = Color(0.10, 0.12, 0.16, 0.94)
        bg_sb.set_corner_radius_all(210)
        bg_sb.set_border_width_all(3)
        bg_sb.border_color = Color(1, 1, 1, 0.20)
        bg_sb.shadow_color = Color(0, 0, 0, 0.5)
        bg_sb.shadow_size = 24
        bg.add_theme_stylebox_override("panel", bg_sb)
        _wheel_panel.add_child(bg)

        # Center Close / Cancel Button
        _center_btn = Button.new()
        _center_btn.text = "✕\nCLOSE"
        _center_btn.custom_minimum_size = Vector2(90, 90)
        _center_btn.set_anchors_preset(Control.PRESET_CENTER)
        _center_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _center_btn.grow_vertical = Control.GROW_DIRECTION_BOTH
        _center_btn.focus_mode = Control.FOCUS_NONE
        var center_sb := StyleBoxFlat.new()
        center_sb.bg_color = Color(0.18, 0.20, 0.25, 0.95)
        center_sb.set_corner_radius_all(45)
        center_sb.set_border_width_all(2)
        center_sb.border_color = Color(1, 1, 1, 0.35)
        _center_btn.add_theme_stylebox_override("normal", center_sb)
        var center_hover := center_sb.duplicate() as StyleBoxFlat
        center_hover.bg_color = Color(0.70, 0.15, 0.18, 0.95)
        _center_btn.add_theme_stylebox_override("hover", center_hover)
        _center_btn.add_theme_font_override("font", RetroUI.gotham(700))
        _center_btn.add_theme_font_size_override("font_size", 12)
        _center_btn.pressed.connect(close)
        _wheel_panel.add_child(_center_btn)

        _refresh_slots()


func _refresh_slots() -> void:
        for b in _slot_buttons:
                if is_instance_valid(b):
                        b.queue_free()
        _slot_buttons.clear()

        _emotes = DEFAULT_EMOTES.duplicate()
        # Add custom account emotes if available
        var session_node: Node = get_node_or_null("/root/Session")
        if session_node != null and not session_node.get("is_guest"):
                var data: Dictionary = session_node.call("my_avatar_data")
                var custom_emotes: Variant = data.get("emotes", [])
                if custom_emotes is Array:
                        for item in custom_emotes:
                                if item is Dictionary:
                                        var name_str := String(item.get("name", "Custom"))
                                        var clip_str := String(item.get("clipName", name_str.to_lower()))
                                        _emotes.append([name_str, clip_str, "⭐", str(_emotes.size() + 1)])

        var count := mini(_emotes.size(), 8)
        var radius := 142.0
        var center := Vector2(210, 210)

        for i in range(count):
                var emote_info: Array = _emotes[i]
                var title: String = emote_info[0]
                var clip_id: String = emote_info[1]
                var icon: String = emote_info[2]
                var hotkey: String = emote_info[3]

                var angle := -PI / 2.0 + (TAU * float(i) / float(count))
                var pos := center + Vector2(cos(angle), sin(angle)) * radius

                var btn := Button.new()
                btn.text = "%s %s\n[%s]" % [icon, title, hotkey]
                btn.custom_minimum_size = Vector2(96, 52)
                btn.position = pos - Vector2(48, 26)
                btn.focus_mode = Control.FOCUS_NONE
                btn.add_theme_font_override("font", RetroUI.gotham(700))
                btn.add_theme_font_size_override("font_size", 11)

                var sb_norm := StyleBoxFlat.new()
                sb_norm.bg_color = Color(0.16, 0.19, 0.24, 0.90)
                sb_norm.set_corner_radius_all(10)
                sb_norm.set_border_width_all(1)
                sb_norm.border_color = Color(1, 1, 1, 0.20)
                btn.add_theme_stylebox_override("normal", sb_norm)

                var sb_hover := sb_norm.duplicate() as StyleBoxFlat
                sb_hover.bg_color = Color(0.0, 0.64, 1.0, 0.95)
                sb_hover.border_color = Color.WHITE
                btn.add_theme_stylebox_override("hover", sb_hover)

                btn.pressed.connect(func() -> void:
                        _pick_emote(clip_id))
                _wheel_panel.add_child(btn)
                _slot_buttons.append(btn)


func _pick_emote(clip: String) -> void:
        emote_selected.emit(clip)
        close()


func toggle() -> void:
        if _open:
                close()
        else:
                open()


func open() -> void:
        if _open:
                return
        _open = true
        _refresh_slots()
        visible = true
        modulate = Color(1, 1, 1, 0.0)
        _wheel_panel.scale = Vector2(0.85, 0.85)
        var tween := create_tween().set_parallel(true)
        tween.tween_property(self, "modulate:a", 1.0, 0.15)
        tween.tween_property(_wheel_panel, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
        if not _open:
                return
        _open = false
        var tween := create_tween().set_parallel(true)
        tween.tween_property(self, "modulate:a", 0.0, 0.12)
        tween.tween_property(_wheel_panel, "scale", Vector2(0.85, 0.85), 0.12)
        tween.chain().tween_callback(func() -> void:
                visible = false)


func is_wheel_open() -> bool:
        return _open


func _on_backdrop_input(event: InputEvent) -> void:
        if event is InputEventMouseButton and event.pressed:
                close()


func _unhandled_input(event: InputEvent) -> void:
        if not _open:
                if event is InputEventKey and event.pressed and not event.echo:
                        if event.keycode == KEY_PERIOD:
                                open()
                                get_viewport().set_input_as_handled()
                return

        if event is InputEventKey and event.pressed and not event.echo:
                if event.keycode == KEY_PERIOD or event.keycode == KEY_ESCAPE:
                        close()
                        get_viewport().set_input_as_handled()
                        return
                # Quick slot hotkeys 1-8
                if event.keycode >= KEY_1 and event.keycode <= KEY_8:
                        var idx := int(event.keycode - KEY_1)
                        if idx >= 0 and idx < _emotes.size():
                                _pick_emote(String(_emotes[idx][1]))
                                get_viewport().set_input_as_handled()
                                return
