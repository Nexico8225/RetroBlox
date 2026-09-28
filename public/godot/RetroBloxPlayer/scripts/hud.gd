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
@onready var menu_button: Button = %MenuButton
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
        menu_button.pressed.connect(set_menu.bind(true))
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
        # NOTE: use the captured references, never %Name — reparenting a node
        # into a code-created container breaks Godot's unique-name lookup.
        for button in [menu_button, chat_button, people_button]:
                var btn := button as Button
                btn.get_parent().remove_child(btn)
                row.add_child(btn)
                _style_toolbar_button(btn)
        menu_button.icon = load("res://assets/icons/menu.png")
        menu_button.tooltip_text = "Menu (ESC)"
        chat_button.icon = load("res://assets/icons/chat.png")
        chat_button.tooltip_text = "Chat (/)"
        people_button.icon = load("res://assets/icons/people.png")
        people_button.tooltip_text = "Players"
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
