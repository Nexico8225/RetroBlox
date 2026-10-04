extends CanvasLayer

## The in-game HUD, built from scenes/hud.tscn — open that scene in the
## editor to move or restyle any panel. This script keeps the behavior:
## chat, roster, status line, the ESC menu, and the settings inside it.

signal chat_submitted(message: String)
signal resume_requested
signal reset_requested
signal quit_requested
signal shiftlock_toggled(enabled: bool)
signal sensitivity_changed(value: float)
signal volume_changed(value: float)
signal jump_pressed
signal quality_changed(preset: String)
signal render_scale_changed(value: float)
signal shadows_changed(enabled: bool)
signal fov_changed(value: float)
signal show_fps_changed(enabled: bool)
signal touch_mode_changed(mode: String)
signal settings_closed

const INK := Color("eaf3f3")
const MUTED := Color("a6bac2")
const GREEN := Color("02b757")
const GREEN_BRIGHT := Color("7ee08f")
const RED := Color("e2231a")
const PANEL := Color(0.043, 0.091, 0.115, 0.94)

# --- the classic 2008 palette (old Roblox UI) ---
const CLASSIC_PANEL := Color("d9dde0")      # light grey beveled panel
const CLASSIC_BORDER := Color("7a8288")
const CLASSIC_INK := Color("1b2a34")        # dark text on the grey
const CLASSIC_FACE := Color("f2f4f5")       # inner white-ish area
const CLASSIC_BTN := Color("cfd4d8")
const CLASSIC_BTN_HOVER := Color("dde2e6")
const CLASSIC_BTN_DOWN := Color("b8bfc5")
const CLASSIC_BLUE := Color("0d69ac")

# unique names inside scenes/hud.tscn
@onready var root: Control = $Root
@onready var status_label: Label = %StatusLabel
@onready var count_label: Label = %CountLabel
@onready var names_label: Label = %NamesLabel
@onready var chat_panel: PanelContainer = %ChatPanel
@onready var chat_log: RichTextLabel = %ChatLog
@onready var chat_entry: LineEdit = %ChatEntry
@onready var chat_button: Button = %ChatButton
@onready var people_button: Button = %PeopleButton
@onready var roster_panel: PanelContainer = %RosterPanel
@onready var menu: Control = %Menu
@onready var reset_button: Button = %ResetButton
@onready var toast: Label = %Toast
@onready var crosshair: Label = %Crosshair
@onready var room_label: Label = %RoomLabel
@onready var menu_room_label: Label = %MenuRoomLabel
@onready var menu_count_label: Label = %MenuCountLabel
@onready var menu_names_label: Label = %MenuNamesLabel
@onready var shiftlock_button: Button = %ShiftlockButton
@onready var sensitivity_slider: HSlider = %SensitivitySlider
@onready var sensitivity_value: Label = %SensitivityValue
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value: Label = %VolumeValue

var history: Array[String] = []
var roster_names: Array = []
var _shiftlock_on := false
var chat_open := false
var _unread := 0

# classic health bar — built in code so scenes/hud.tscn stays untouched
var _health_fill: ColorRect
var _health_value: Label
var _health_ratio := 1.0            # what the bar shows (eases toward target)
var _health_target := 1.0
var _health_flash := 0.0
var _last_health := 100.0

const HEALTH_BAR_W := 170.0
const HEALTH_BAR_H := 12.0


func _ready() -> void:
        %MenuButton.pressed.connect(set_menu.bind(true))
        %ResumeBtn.pressed.connect(_on_resume_pressed)
        %ResetButton.pressed.connect(_on_reset_pressed)
        %ShiftlockButton.pressed.connect(_on_shiftlock_pressed)
        %LeaveBtn.pressed.connect(_on_leave_pressed)
        %SensitivitySlider.value_changed.connect(_on_sensitivity_moved)
        %VolumeSlider.value_changed.connect(_on_volume_moved)
        chat_entry.text_submitted.connect(_submit_chat)
        chat_button.pressed.connect(_on_chat_button)
        people_button.pressed.connect(_on_people_button)
        _build_health_bar()
        _build_toolbar()
        _build_fps_counter()
        _build_touch_controls()
        _build_settings_card()
        _add_settings_menu_button()
        _apply_classic_style()


## The classic TOP-LEFT icon toolbar — menu / chat / people, grey beveled
## buttons with icons, exactly where the old toolbar sat.
func _build_toolbar() -> void:
        var toolbar := PanelContainer.new()
        toolbar.name = "Toolbar"
        toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
        toolbar.add_theme_stylebox_override("panel", _classic_panel_style())
        toolbar.anchor_left = 0.0
        toolbar.anchor_right = 0.0
        toolbar.anchor_top = 0.0
        toolbar.anchor_bottom = 0.0
        toolbar.offset_left = 10.0
        toolbar.offset_top = 10.0
        toolbar.offset_right = 10.0
        var row := HBoxContainer.new()
        row.name = "Buttons"
        row.add_theme_constant_override("separation", 4)
        toolbar.add_child(row)
        root.add_child(toolbar)

        # move the three real buttons into the toolbar (signals stay wired).
        # CAPTURE THEM FIRST: removing a node from the tree drops its
        # unique-name ("%Name") registration, so a %lookup after the move
        # returns null — the toolbar used to error and lose its icons.
        var menu_btn: Button = %MenuButton
        var chat_btn: Button = chat_button
        var people_btn: Button = people_button
        for button in [menu_btn, chat_btn, people_btn]:
                var btn := button as Button
                btn.get_parent().remove_child(btn)
                row.add_child(btn)
                _style_toolbar_button(btn)
        menu_btn.icon = load("res://assets/icons/menu.png")
        menu_btn.tooltip_text = "Menu (ESC)"
        chat_btn.icon = load("res://assets/icons/chat.png")
        chat_btn.tooltip_text = "Chat (/)"
        people_btn.icon = load("res://assets/icons/people.png")
        people_btn.tooltip_text = "Players"
        toolbar.reset_size()


func _style_toolbar_button(button: Button) -> void:
        button.text = ""
        button.custom_minimum_size = Vector2(38.0, 30.0)
        button.expand_icon = true
        button.focus_mode = Control.FOCUS_NONE
        button.add_theme_stylebox_override("normal", _classic_button_style(CLASSIC_BTN))
        button.add_theme_stylebox_override("hover", _classic_button_style(CLASSIC_BTN_HOVER))
        button.add_theme_stylebox_override("pressed", _classic_button_style(CLASSIC_BTN_DOWN))
        button.add_theme_color_override("font_color", CLASSIC_INK)


## Old-Roblox look for every HUD surface: light grey beveled panels, dark
## ink text, white chat log. Applied over the scene's dark theme in code.
func _apply_classic_style() -> void:
        var panel := _classic_panel_style()
        for node: Control in [chat_panel, roster_panel]:
                node.add_theme_stylebox_override("panel", panel)
        # header becomes a floating label strip (the toolbar replaces the bar)
        var header := root.get_node_or_null("Header") as PanelContainer
        if header != null:
                header.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
        chat_log.add_theme_color_override("default_color", CLASSIC_INK)
        chat_log.add_theme_stylebox_override("normal", _classic_inner_style())
        chat_entry.add_theme_color_override("font_color", CLASSIC_INK)
        chat_entry.add_theme_color_override("font_placeholder_color", Color(0.45, 0.5, 0.55))
        chat_entry.add_theme_stylebox_override("normal", _classic_inner_style())
        chat_entry.placeholder_text = "To chat, click here or press /"
        for label: Control in [%CountLabel, %NamesLabel]:
                label.add_theme_color_override("font_color", CLASSIC_INK)
        var title_label := root.get_node_or_null("ChatPanel/ChatBox/ChatTitle/ChatTitleLabel") as Label
        if title_label != null:
                title_label.add_theme_color_override("font_color", CLASSIC_INK)
        var enter_hint := root.get_node_or_null("ChatPanel/ChatBox/ChatTitle/EnterHint") as Label
        if enter_hint != null:
                enter_hint.add_theme_color_override("font_color", CLASSIC_INK)
                enter_hint.text = "/  ↵"
        var help_panel := root.get_node_or_null("HelpPanel") as PanelContainer
        if help_panel != null:
                help_panel.add_theme_stylebox_override("panel", panel)
                for line in help_panel.get_child(0).get_children():
                        (line as Label).add_theme_color_override("font_color", CLASSIC_INK)
                var hint := help_panel.get_child(0).get_child(1) as Label
                if hint != null:
                        hint.text = "SHIFT  shift lock     /  chat     ESC  menu"
        # the ESC menu card
        var card := root.get_node_or_null("Menu/Center/Card") as PanelContainer
        if card != null:
                card.add_theme_stylebox_override("panel", panel)
                _style_menu_labels(card)


func _style_menu_labels(from: Node) -> void:
        for child in from.get_children():
                if child is Label:
                        var label := child as Label
                        var is_title: bool = label.text == "RETROBLOX"
                        label.add_theme_color_override("font_color", CLASSIC_BLUE if is_title else CLASSIC_INK)
                elif child is Button:
                        _style_dialog_button(child as Button)
                elif child is Container or child is Control:
                        _style_menu_labels(child)


func _style_dialog_button(button: Button) -> void:
        button.add_theme_stylebox_override("normal", _classic_button_style(CLASSIC_BTN))
        button.add_theme_stylebox_override("hover", _classic_button_style(CLASSIC_BTN_HOVER))
        button.add_theme_stylebox_override("pressed", _classic_button_style(CLASSIC_BTN_DOWN))
        button.add_theme_color_override("font_color", CLASSIC_INK)


func _classic_panel_style() -> StyleBoxFlat:
        var style := StyleBoxFlat.new()
        style.bg_color = CLASSIC_PANEL
        style.border_color = CLASSIC_BORDER
        style.set_border_width_all(2)
        style.set_corner_radius_all(4)
        style.set_content_margin_all(8)
        return style


func _classic_inner_style() -> StyleBoxFlat:
        var style := _classic_panel_style()
        style.bg_color = CLASSIC_FACE
        style.set_content_margin_all(5)
        return style


func _classic_button_style(bg: Color) -> StyleBoxFlat:
        var style := StyleBoxFlat.new()
        style.bg_color = bg
        style.border_color = Color("5c666e")
        style.set_border_width_all(1)
        style.set_corner_radius_all(3)
        style.content_margin_left = 6
        style.content_margin_right = 6
        style.content_margin_top = 4
        style.content_margin_bottom = 4
        return style


func _on_resume_pressed() -> void:
        resume_requested.emit()

func _on_reset_pressed() -> void:
        reset_requested.emit()

func _on_shiftlock_pressed() -> void:
        shiftlock_toggled.emit(not _shiftlock_on)

func _on_leave_pressed() -> void:
        quit_requested.emit()

func _on_sensitivity_moved(value: float) -> void:
        sensitivity_value.text = "%.2fx" % value
        sensitivity_changed.emit(value)

func _on_volume_moved(value: float) -> void:
        volume_value.text = "%d%%" % int(roundf(value * 100.0))
        volume_changed.emit(value)


func set_shiftlock(enabled: bool) -> void:
        _shiftlock_on = enabled
        if shiftlock_button != null:
                shiftlock_button.text = "Shift Lock:  ON" if enabled else "Shift Lock:  OFF"

func set_sliders(sensitivity: float, volume: float) -> void:
        sensitivity_slider.set_value_no_signal(sensitivity)
        sensitivity_value.text = "%.2fx" % sensitivity
        volume_slider.set_value_no_signal(volume)
        volume_value.text = "%d%%" % int(roundf(volume * 100.0))

func set_room_title(title: String) -> void:
        if menu_room_label != null:
                menu_room_label.text = title

func set_menu(open: bool) -> void:
        menu.visible = open
        if open:
                _refresh_menu_roster()
                chat_entry.release_focus()
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
                # a held joystick finger must not keep walking into the menu
                joystick_vector = Vector2.ZERO
                if _joystick != null and _joystick is TouchJoystick:
                        (_joystick as TouchJoystick).finger = -1
                        (_joystick as TouchJoystick)._center_knob()
        else:
                var focused := root.get_viewport().gui_get_focus_owner()
                if focused != null:
                        focused.release_focus()

func input_busy() -> bool:
        return menu.visible or chat_entry.has_focus()

## Bottom-left CHAT button — shows/hides the chat panel like the classic
## chat bubble. ENTER or "/" opens the chat too (see begin_chat).
func _on_chat_button() -> void:
        toggle_chat(not chat_open)

func _on_people_button() -> void:
        toggle_people(not roster_panel.visible)

func toggle_chat(open: bool) -> void:
        chat_open = open
        chat_panel.visible = open
        if open:
                _unread = 0
                chat_button.text = ""
                begin_chat()
        else:
                chat_entry.release_focus()

func toggle_people(open: bool) -> void:
        roster_panel.visible = open

func begin_chat() -> void:
        chat_open = true
        chat_panel.visible = true
        _unread = 0
        chat_button.text = ""
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
        # hidden chat counts unread messages on the CHAT button
        if not chat_open:
                _unread += 1
                chat_button.text = str(_unread)

func update_roster(entries: Array, local_id: Variant = "") -> void:
        roster_names = entries
        count_label.text = "%d %s" % [entries.size(), "player" if entries.size() == 1 else "players"]
        var lines: Array[String] = []
        for i in range(mini(entries.size(), 10)):
                var entry: Dictionary = entries[i]
                lines.append("• " + str(entry["name"]) + ("  (you)" if str(entry["id"]) == str(local_id) else ""))
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


## The classic top-right health bar — label + a green bar that reddens as
## it drains and flashes when you take damage. Built in code: no scene edit.
func _build_health_bar() -> void:
        var panel := PanelContainer.new()
        panel.name = "HealthBar"
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var style := StyleBoxFlat.new()
        style.bg_color = PANEL
        style.border_color = Color("223038")
        style.set_border_width_all(2)
        style.set_content_margin_all(6)
        panel.add_theme_stylebox_override("panel", style)
        # anchored top-right, out of every other panel's way
        panel.anchor_left = 1.0
        panel.anchor_right = 1.0
        panel.offset_left = -(HEALTH_BAR_W + 30.0)
        panel.offset_right = -12.0
        panel.offset_top = 12.0

        var box := VBoxContainer.new()
        box.mouse_filter = Control.MOUSE_FILTER_IGNORE

        var head := HBoxContainer.new()
        head.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var title := Label.new()
        title.text = "Health"
        title.add_theme_font_size_override("font_size", 10)
        title.add_theme_color_override("font_color", MUTED)
        _health_value = Label.new()
        _health_value.text = "100 / 100"
        _health_value.add_theme_font_size_override("font_size", 10)
        _health_value.add_theme_color_override("font_color", INK)
        _health_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _health_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        head.add_child(title)
        head.add_child(_health_value)

        var track := ColorRect.new()
        track.mouse_filter = Control.MOUSE_FILTER_IGNORE
        track.color = Color("10181d")
        track.custom_minimum_size = Vector2(HEALTH_BAR_W, HEALTH_BAR_H)
        _health_fill = ColorRect.new()
        _health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _health_fill.color = GREEN
        _health_fill.position = Vector2.ZERO
        _health_fill.size = Vector2(HEALTH_BAR_W, HEALTH_BAR_H)
        track.add_child(_health_fill)

        box.add_child(head)
        box.add_child(track)
        panel.add_child(box)
        root.add_child(panel)

## Local player health (main.gd connects the player's health_changed here).
func set_health(health: float, max_health: float) -> void:
        var safe_max := maxf(max_health, 1.0)
        _health_target = clampf(health / safe_max, 0.0, 1.0)
        if health < _last_health - 0.01:
                _health_flash = 0.35
        _last_health = health
        _health_value.text = "%d / %d" % [int(roundf(health)), int(roundf(safe_max))]

func _process(delta: float) -> void:
        if _health_fill == null:
                return
        # the bar eases toward its target and flashes white on damage
        _health_ratio = lerpf(_health_ratio, _health_target, 1.0 - exp(-12.0 * delta))
        if _health_flash > 0.0:
                _health_flash = maxf(_health_flash - delta, 0.0)
        _health_fill.size = Vector2(HEALTH_BAR_W * _health_ratio, HEALTH_BAR_H)
        var c := RED.lerp(GREEN, _health_ratio)
        if _health_flash > 0.0:
                c = c.lerp(Color.WHITE, _health_flash)
        _health_fill.color = c
        # FPS counter (visible only when Settings > Show FPS is on)
        if _fps_label != null and _fps_label.get_parent().visible:
                _fps_accum -= delta
                if _fps_accum <= 0.0:
                        _fps_accum = 0.5
                        var fps := Engine.get_frames_per_second()
                        _fps_label.text = "%d FPS" % fps
                        var fps_color := GREEN_BRIGHT if fps >= 50 else (Color("ffd39d") if fps >= 30 else RED)
                        _fps_label.add_theme_color_override("font_color", fps_color)
        # joystick vector feeds main.gd even when the finger rests still
        if _joystick != null and _joystick is TouchJoystick:
                joystick_vector = (_joystick as TouchJoystick).vector


## ======================================================================
##  MOBILE / TOUCH CONTROLS — built in code, classic grey style.
##  A virtual joystick bottom-left, big JUMP button bottom-right, small
##  Reset + Shift Lock buttons above it. main.gd reads joystick_vector,
##  consumes jump_pressed, and drags the camera on free screen space.
## ======================================================================

const JOY_SIZE := 148.0
const JOY_KNOB := 60.0
const TOUCH_BTN := 92.0

var joystick_vector: Vector2 = Vector2.ZERO   # y<0 = forward (like Input.get_vector)
var touch_enabled: bool = false
var settings_open: bool = false

var _touch_layer: Control
var _joystick: Control
var _jump_btn: Button
var _touch_reset_btn: Button
var _touch_shift_btn: Button
var _reserved: Array[Control] = []

# --- settings card state ---
var _settings_panel: Control
var _quality_option: OptionButton
var _render_slider: HSlider
var _render_value: Label
var _shadows_btn: Button
var _fov_slider: HSlider
var _fov_value: Label
var _fps_btn: Button
var _touch_option: OptionButton
var _fps_label: Label
var _fps_accum: float = 0.0

const QUALITY_NAMES: Array[String] = ["Auto", "Low", "Medium", "High"]
const QUALITY_KEYS: Array[String] = ["auto", "low", "medium", "high"]
const TOUCH_NAMES: Array[String] = ["Auto", "On", "Off"]
const TOUCH_KEYS: Array[String] = ["auto", "on", "off"]


## The virtual joystick: a circle you drag; vector follows the knob.
class TouchJoystick extends Control:
        var vector: Vector2 = Vector2.ZERO
        var finger: int = -1
        var knob: Control
        var track_radius: float = 44.0
        var on_release: Callable

        func _init() -> void:
                custom_minimum_size = Vector2(148.0, 148.0)
                size = custom_minimum_size
                mouse_filter = Control.MOUSE_FILTER_STOP
                var base := Panel.new()
                var base_style := StyleBoxFlat.new()
                base_style.bg_color = Color(0.62, 0.68, 0.71, 0.45)
                base_style.set_corner_radius_all(74)
                base_style.set_border_width_all(2)
                base_style.border_color = Color(0.35, 0.4, 0.43, 0.7)
                base.add_theme_stylebox_override("panel", base_style)
                base.mouse_filter = Control.MOUSE_FILTER_IGNORE
                base.set_anchors_preset(Control.PRESET_FULL_RECT)
                add_child(base)
                knob = Panel.new()
                var knob_style := StyleBoxFlat.new()
                knob_style.bg_color = Color(0.95, 0.96, 0.97, 0.9)
                knob_style.set_corner_radius_all(30)
                knob_style.set_border_width_all(2)
                knob_style.border_color = Color(0.3, 0.35, 0.38, 0.8)
                knob.add_theme_stylebox_override("panel", knob_style)
                knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
                knob.size = Vector2(60.0, 60.0)
                knob.position = Vector2(44.0, 44.0)
                add_child(knob)

        func _gui_input(event: InputEvent) -> void:
                if event is InputEventScreenTouch:
                        if event.pressed and finger == -1:
                                finger = event.index
                                _track(event.position)
                        elif not event.pressed and event.index == finger:
                                finger = -1
                                _center_knob()
                        accept_event()
                elif event is InputEventScreenDrag and event.index == finger:
                        _track(event.position)
                        accept_event()

        func _track(at: Vector2) -> void:
                var center := size * 0.5
                var offset := at - center
                if offset.length() > track_radius:
                        offset = offset.normalized() * track_radius
                knob.position = center + offset - knob.size * 0.5
                vector = offset / track_radius

        func _center_knob() -> void:
                knob.position = size * 0.5 - knob.size * 0.5
                vector = Vector2.ZERO
                if on_release.is_valid():
                        on_release.call()

        ## Mouse-drag support so desktop testers can try it too.
        func _unhandled_input(event: InputEvent) -> void:
                pass


func _build_touch_controls() -> void:
        _touch_layer = Control.new()
        _touch_layer.name = "TouchControls"
        _touch_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
        _touch_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _touch_layer.visible = false
        root.add_child(_touch_layer)

        _joystick = TouchJoystick.new()
        _joystick.name = "Joystick"
        _joystick.anchor_left = 0.0
        _joystick.anchor_right = 0.0
        _joystick.anchor_top = 1.0
        _joystick.anchor_bottom = 1.0
        _joystick.offset_left = 26.0
        _joystick.offset_top = -(148.0 + 30.0)
        _joystick.offset_right = 26.0 + 148.0
        _joystick.offset_bottom = -30.0
        (_joystick as TouchJoystick).on_release = func(): joystick_vector = Vector2.ZERO
        _touch_layer.add_child(_joystick)
        _reserved.append(_joystick)

        _jump_btn = _make_touch_button("JUMP", Vector2(-(92.0 + 30.0), -(92.0 + 34.0)))
        _jump_btn.button_down.connect(func(): jump_pressed.emit())
        _reserved.append(_jump_btn)

        _touch_reset_btn = _make_touch_button("RESET", Vector2(-(48.0 + 32.0), -(48.0 + 34.0 + 92.0 + 12.0)), 48.0)
        _touch_reset_btn.pressed.connect(func(): reset_requested.emit())
        _reserved.append(_touch_reset_btn)

        _touch_shift_btn = _make_touch_button("LOCK", Vector2(-(48.0 + 32.0), -(48.0 + 34.0 + 92.0 + 12.0 + 48.0 + 10.0)), 48.0)
        _touch_shift_btn.pressed.connect(func(): shiftlock_toggled.emit(not _shiftlock_on))
        _reserved.append(_touch_shift_btn)


func _make_touch_button(text_value: String, offsets: Vector2, side: float = 92.0) -> Button:
        var button := Button.new()
        button.name = "Touch_" + text_value
        button.text = text_value
        button.add_theme_font_size_override("font_size", 15 if side > 60.0 else 11)
        button.add_theme_color_override("font_color", CLASSIC_INK)
        button.add_theme_color_override("font_pressed_color", CLASSIC_INK)
        button.add_theme_color_override("font_hover_color", CLASSIC_INK)
        button.anchor_left = 1.0
        button.anchor_right = 1.0
        button.anchor_top = 1.0
        button.anchor_bottom = 1.0
        button.offset_left = offsets.x
        button.offset_top = offsets.y
        button.offset_right = offsets.x + side
        button.offset_bottom = offsets.y + side
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.81, 0.85, 0.88, 0.82)
        style.set_corner_radius_all(int(side * 0.5))
        style.set_border_width_all(2)
        style.border_color = Color("5c666e")
        var style_down: StyleBoxFlat = style.duplicate()
        style_down.bg_color = Color(0.62, 0.68, 0.72, 0.9)
        button.add_theme_stylebox_override("normal", style)
        button.add_theme_stylebox_override("hover", style)
        button.add_theme_stylebox_override("pressed", style_down)
        _touch_layer.add_child(button)
        return button


## Show/hide the touch layer (main.gd decides from the setting + device).
func set_touch_enabled(enabled: bool) -> void:
        touch_enabled = enabled
        if _touch_layer != null:
                _touch_layer.visible = enabled
        if not enabled:
                joystick_vector = Vector2.ZERO
        if enabled:
                _apply_touch_sizing()


## True when a screen point belongs to a HUD control the camera must not
## steal (joystick, buttons, chat, roster, menu…).
func is_point_reserved(pos: Vector2) -> bool:
        for control in _reserved:
                if control != null and is_instance_valid(control) and control.is_visible_in_tree():
                        if control.get_global_rect().has_point(pos):
                                return true
        if chat_panel != null and chat_panel.is_visible_in_tree():
                if chat_panel.get_global_rect().has_point(pos):
                        return true
        if roster_panel != null and roster_panel.is_visible_in_tree():
                if roster_panel.get_global_rect().has_point(pos):
                        return true
        var toolbar := root.get_node_or_null("Toolbar") as Control
        if toolbar != null and toolbar.get_global_rect().has_point(pos):
                return true
        var help_panel := root.get_node_or_null("HelpPanel") as Control
        if help_panel != null and help_panel.get_global_rect().has_point(pos):
                return true
        return false


## ======================================================================
##  FPS COUNTER — top center, tiny panel, off until Settings > Show FPS.
## ======================================================================

func _build_fps_counter() -> void:
        var panel := PanelContainer.new()
        panel.name = "FpsCounter"
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var style := StyleBoxFlat.new()
        style.bg_color = PANEL
        style.border_color = Color("223038")
        style.set_border_width_all(2)
        style.set_content_margin_all(4)
        panel.add_theme_stylebox_override("panel", style)
        panel.anchor_left = 0.5
        panel.anchor_right = 0.5
        panel.offset_left = -34.0
        panel.offset_right = 34.0
        panel.offset_top = 10.0
        _fps_label = Label.new()
        _fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _fps_label.add_theme_font_size_override("font_size", 12)
        _fps_label.add_theme_color_override("font_color", INK)
        panel.add_child(_fps_label)
        panel.visible = false
        root.add_child(panel)


func set_show_fps(enabled: bool) -> void:
        if _fps_label != null:
                _fps_label.get_parent().visible = enabled


## ======================================================================
##  SETTINGS CARD — quality preset, draw scale, shadows, FOV, FPS counter,
##  touch controls. Opens from the ESC menu; fully code-built.
## ======================================================================

func _build_settings_card() -> void:
        _settings_panel = Control.new()
        _settings_panel.name = "SettingsPanel"
        _settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _settings_panel.visible = false
        root.add_child(_settings_panel)

        var dim := ColorRect.new()
        dim.name = "Dim"
        dim.color = Color(0.02, 0.05, 0.07, 0.55)
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        dim.mouse_filter = Control.MOUSE_FILTER_STOP
        _settings_panel.add_child(dim)

        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        _settings_panel.add_child(center)

        var card := PanelContainer.new()
        card.name = "SettingsCard"
        card.add_theme_stylebox_override("panel", _classic_panel_style())
        center.add_child(card)

        var scroll := ScrollContainer.new()
        scroll.custom_minimum_size = Vector2(430.0, 400.0)
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        card.add_child(scroll)

        var column := VBoxContainer.new()
        column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        column.size_flags_vertical = Control.SIZE_EXPAND_FILL
        column.add_theme_constant_override("separation", 8)
        scroll.add_child(column)

        var title := Label.new()
        title.text = "SETTINGS"
        title.add_theme_font_size_override("font_size", 20)
        title.add_theme_color_override("font_color", CLASSIC_BLUE)
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        column.add_child(title)

        # --- quality preset ---
        _quality_option = OptionButton.new()
        for preset_name in QUALITY_NAMES:
                _quality_option.add_item(preset_name)
        _quality_option.item_selected.connect(func(index: int):
                quality_changed.emit(QUALITY_KEYS[index]))
        column.add_child(_settings_row("Quality", _quality_option))

        # --- draw scale ---
        _render_slider = HSlider.new()
        _render_slider.min_value = 0.5
        _render_slider.max_value = 1.0
        _render_slider.step = 0.05
        _render_slider.custom_minimum_size = Vector2(150.0, 26.0)
        _render_slider.value_changed.connect(func(value: float):
                _render_value.text = "%d%%" % int(roundf(value * 100.0))
                render_scale_changed.emit(value))
        _render_value = Label.new()
        _render_value.text = "100%"
        _render_value.custom_minimum_size = Vector2(44.0, 0)
        column.add_child(_settings_row("Draw Scale", _render_slider, _render_value))

        # --- shadows ---
        _shadows_btn = _make_toggle_button("Shadows")
        _shadows_btn.pressed.connect(func():
                shadows_changed.emit(_shadows_btn.text == "OFF"))
        column.add_child(_settings_row("Shadows", _shadows_btn))

        # --- field of view ---
        _fov_slider = HSlider.new()
        _fov_slider.min_value = 60.0
        _fov_slider.max_value = 100.0
        _fov_slider.step = 1.0
        _fov_slider.custom_minimum_size = Vector2(150.0, 26.0)
        _fov_slider.value_changed.connect(func(value: float):
                _fov_value.text = "%d" % int(value)
                fov_changed.emit(value))
        _fov_value = Label.new()
        _fov_value.text = "70"
        _fov_value.custom_minimum_size = Vector2(44.0, 0)
        column.add_child(_settings_row("Field of View", _fov_slider, _fov_value))

        # --- show fps ---
        _fps_btn = _make_toggle_button("FPS Counter")
        _fps_btn.pressed.connect(func():
                show_fps_changed.emit(_fps_btn.text == "OFF"))
        column.add_child(_settings_row("Show FPS", _fps_btn))

        # --- touch controls ---
        _touch_option = OptionButton.new()
        for touch_name in TOUCH_NAMES:
                _touch_option.add_item(touch_name)
        _touch_option.item_selected.connect(func(index: int):
                touch_mode_changed.emit(TOUCH_KEYS[index]))
        column.add_child(_settings_row("Touch Controls", _touch_option))

        var note := Label.new()
        note.text = "Auto quality drops to Low if the game runs slow.\nLower Draw Scale = big speed boost on phones."
        note.add_theme_font_size_override("font_size", 11)
        note.add_theme_color_override("font_color", Color("3c4a54"))
        note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        column.add_child(note)

        var back := Button.new()
        back.text = "Back"
        _style_dialog_button(back)
        back.pressed.connect(close_settings)
        column.add_child(back)


func _settings_row(row_label: String, control: Control, value_label: Label = null) -> HBoxContainer:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        var label := Label.new()
        label.text = row_label
        label.custom_minimum_size = Vector2(120.0, 0)
        label.add_theme_color_override("font_color", CLASSIC_INK)
        row.add_child(label)
        control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(control)
        if value_label != null:
                value_label.add_theme_color_override("font_color", CLASSIC_INK)
                row.add_child(value_label)
        return row


func _make_toggle_button(toggle_text: String) -> Button:
        var button := Button.new()
        button.text = "OFF"
        button.custom_minimum_size = Vector2(64.0, 26.0)
        button.pressed.connect(func():
                button.text = "ON" if button.text == "OFF" else "OFF")
        return button


func _add_settings_menu_button() -> void:
        var controls_box := reset_button.get_parent() as Container
        if controls_box == null:
                return
        var button := Button.new()
        button.name = "SettingsButton"
        button.text = "Settings…"
        _style_dialog_button(button)
        button.pressed.connect(open_settings)
        var leave := get_node_or_null("%LeaveBtn") as Control
        controls_box.add_child(button)
        if leave != null:
                controls_box.move_child(button, leave.get_index())


func open_settings() -> void:
        settings_open = true
        if _settings_panel != null:
                _settings_panel.visible = true


func close_settings() -> void:
        settings_open = false
        if _settings_panel != null:
                _settings_panel.visible = false
        settings_closed.emit()


## Push current settings into the card (no signals fired).
func set_settings_state(quality: String, render_scale: float, shadows: bool, fov: float, show_fps: bool, touch_mode: String) -> void:
        if _quality_option != null:
                var q_index := QUALITY_KEYS.find(quality)
                _quality_option.selected = q_index if q_index >= 0 else 0
        if _render_slider != null:
                _render_slider.set_value_no_signal(render_scale)
                _render_value.text = "%d%%" % int(roundf(render_scale * 100.0))
        if _shadows_btn != null:
                _shadows_btn.text = "ON" if shadows else "OFF"
        if _fov_slider != null:
                _fov_slider.set_value_no_signal(fov)
                _fov_value.text = "%d" % int(fov)
        if _fps_btn != null:
                _fps_btn.text = "ON" if show_fps else "OFF"
        if _touch_option != null:
                var t_index := TOUCH_KEYS.find(touch_mode)
                _touch_option.selected = t_index if t_index >= 0 else 0
        set_show_fps(show_fps)


## Bigger toolbar buttons + a nudge for the touch layer when mobile is on.
func _apply_touch_sizing() -> void:
        var toolbar := root.get_node_or_null("Toolbar") as Control
        if toolbar == null:
                return
        for button in toolbar.get_child(0).get_children():
                (button as Button).custom_minimum_size = Vector2(46.0, 38.0)
        toolbar.reset_size()
