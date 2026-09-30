extends CanvasLayer

## The in-game HUD, built from scenes/hud.tscn — open that scene in the
## editor to move or restyle any panel. This script keeps the behavior:
## chat (with the website's Text FX!), roster, status line, the ESC menu,
## the settings inside it, UI sounds and UI animations.

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

# --- the website's Text FX (src/lib/textfx.tsx), same tags, same feel ---
# animated tags carried by custom RichTextEffects in scripts/fx/
const FX_EFFECTS: Array[String] = ["shake", "wiggle", "swirl", "wave", "bounce", "rainbow", "glow", "neon", "fire", "ice", "sparkle", "pulse", "flip", "ghost", "tilt"]
# plain color tags
const FX_COLORS: Dictionary = {
        "red": "e53935", "blue": "1e88e5", "green": "43a047",
        "gold": "d9a418", "pink": "ec407a", "purple": "9c27b0",
}
# alias the web's toolbar name: Whirly button writes [swirl]
const FX_ALIAS: Dictionary = {"whirly": "swirl", "wiggly": "wiggle"}

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

var history: Array = []   # entries: {s: String, m: String, sys: bool}
var roster_names: Array = []
var _shiftlock_on := false
var chat_open := false
var _unread := 0

# --- UI sounds: tiny retro blips synthesized at startup (no asset files) ---
var _snd_hover: AudioStreamWAV
var _snd_click: AudioStreamWAV
var _snd_open: AudioStreamWAV
var _snd_close: AudioStreamWAV
var _ui_audio: AudioStreamPlayer

# --- UI animation tween working set ---
var _menu_tween: Tween
var _chat_base_x: float = -1.0
var _roster_base_x: float = -1.0
var _viewer_panel: PanelContainer
var _viewer_tween: Tween

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
        # the chat log understands the website's Text FX markup
        chat_log.bbcode_enabled = true
        chat_log.custom_effects = [
                load("res://scripts/fx/fx_shake.gd"), load("res://scripts/fx/fx_wiggle.gd"),
                load("res://scripts/fx/fx_swirl.gd"), load("res://scripts/fx/fx_wave.gd"),
                load("res://scripts/fx/fx_bounce.gd"), load("res://scripts/fx/fx_rainbow.gd"),
                load("res://scripts/fx/fx_glow.gd"), load("res://scripts/fx/fx_neon.gd"),
                load("res://scripts/fx/fx_fire.gd"), load("res://scripts/fx/fx_ice.gd"),
                load("res://scripts/fx/fx_sparkle.gd"), load("res://scripts/fx/fx_pulse.gd"),
                load("res://scripts/fx/fx_flip.gd"), load("res://scripts/fx/fx_ghost.gd"),
                load("res://scripts/fx/fx_tilt.gd"),
        ]
        _build_health_bar()
        _build_toolbar()
        _build_viewer_panel()
        _apply_classic_style()
        _setup_ui_sounds()
        _wire_button_fx()


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
        # References are captured FIRST, because %Name lookups on a node that
        # was re-parented mid-_ready are unreliable — and re-register the
        # owner so the unique names keep resolving for everyone else.
        var menu_btn: Button = %MenuButton
        var chat_btn: Button = %ChatButton
        var people_btn: Button = %PeopleButton
        for button: Button in [menu_btn, chat_btn, people_btn]:
                var owner_node: Node = button.owner
                button.get_parent().remove_child(button)
                row.add_child(button)
                if owner_node != null:
                        button.owner = null
                        button.owner = owner_node
                _style_toolbar_button(button)
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
                _play(_snd_open)
                _animate_menu_in()
        else:
                _play(_snd_close)
                var focused := root.get_viewport().gui_get_focus_owner()
                if focused != null:
                        focused.release_focus()

## The ESC card pops in with a little back-eased bounce — like Roblox's menu.
func _animate_menu_in() -> void:
        var card := root.get_node_or_null("Menu/Center/Card") as PanelContainer
        if card == null:
                return
        if _menu_tween != null and _menu_tween.is_valid():
                _menu_tween.kill()
        card.pivot_offset = card.size * 0.5
        card.modulate.a = 0.0
        card.scale = Vector2(0.88, 0.88)
        _menu_tween = create_tween().set_parallel(true)
        _menu_tween.tween_property(card, "scale", Vector2.ONE, 0.21).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        _menu_tween.tween_property(card, "modulate:a", 1.0, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func input_busy() -> bool:
        return menu.visible or chat_entry.has_focus()

## Bottom-left CHAT button — shows/hides the chat panel like the classic
## chat bubble. ENTER or "/" opens the chat too (see begin_chat).
func _on_chat_button() -> void:
        toggle_chat(not chat_open)

func _on_people_button() -> void:
        var showing: bool = roster_panel.visible and not bool(roster_panel.get_meta("closing", false))
        toggle_people(not showing)

func toggle_chat(open: bool) -> void:
        chat_open = open
        _unread = 0 if open else _unread
        if open:
                chat_panel.visible = true
                chat_panel.remove_meta("closing")
                chat_panel.modulate.a = 1.0
                chat_button.text = ""
                _animate_panel_in(chat_panel)
                _play(_snd_open)
                begin_chat()
        else:
                chat_entry.release_focus()
                _play(_snd_close)
                _fade_panel_out(chat_panel)

func toggle_people(open: bool) -> void:
        if open:
                roster_panel.visible = true
                roster_panel.remove_meta("closing")
                roster_panel.modulate.a = 1.0
                _animate_panel_in(roster_panel)
                _play(_snd_open)
        else:
                _play(_snd_close)
                _fade_panel_out(roster_panel)

func begin_chat() -> void:
        chat_open = true
        _unread = 0
        chat_button.text = ""
        if not chat_panel.visible or chat_panel.get_meta("closing", false):
                chat_panel.visible = true
                chat_panel.remove_meta("closing")
                chat_panel.modulate.a = 1.0
                _animate_panel_in(chat_panel)
        if not menu.visible:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
                chat_entry.grab_focus()

func _submit_chat(text: String) -> void:
        if not text.strip_edges().is_empty():
                chat_submitted.emit(text)
        chat_entry.clear()
        chat_entry.release_focus()

func add_chat(sender_name: String, message: String, system: bool = false) -> void:
        history.append({"s": sender_name, "m": message, "sys": system})
        if history.size() > 60:
                history.pop_front()
        var lines: Array[String] = []
        for entry in history:
                if entry["sys"]:
                        lines.append("[color=#68757c]• %s[/color]" % fx_to_bbcode(str(entry["m"])))
                else:
                        lines.append("[color=#0d69ac][b]%s:[/b][/color] %s" % [_escape_bb(str(entry["s"])), fx_to_bbcode(str(entry["m"]))])
        chat_log.text = "\n\n".join(lines)
        if chat_log.get_v_scroll_bar() != null:
                chat_log.scroll_to_line(chat_log.get_line_count())
        # hidden chat counts unread messages on the CHAT button
        if not chat_open:
                _unread += 1
                chat_button.text = str(_unread)
                _pop(chat_button)

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


# ================================================================ text fx

static func _fx_known_pattern() -> String:
        var names: Array[String] = []
        names.append_array(FX_EFFECTS)
        for k in FX_COLORS:
                names.append(str(k))
        for k in FX_ALIAS:
                names.append(str(k))
        return "|".join(names)


## Escape plain text so RichTextLabel shows it literally.
static func _escape_bb(text: String) -> String:
        return text.replace("[", "[lb]").replace("]", "[rb]")


static func _fx_open_tag(tag: String) -> String:
        if FX_COLORS.has(tag):
                return "[color=#%s]" % str(FX_COLORS[tag])
        if tag == "big":
                return "[font_size=26]"
        return "[%s]" % tag


static func _fx_close_tag(tag: String) -> String:
        if FX_COLORS.has(tag):
                return "[/color]"
        if tag == "big":
                return "[/font_size]"
        return "[/%s]" % tag


## Translate the website's [tag]…[/tag] markup into chat BBCode — same tags,
## same stacking rules as src/lib/textfx.tsx. Unknown tags stay literal text;
## everything else is escaped so players cannot inject markup.
static func fx_to_bbcode(message: String) -> String:
        var re := RegEx.new()
        if re.compile("\\[(/?)(%s)\\]" % _fx_known_pattern()) != OK:
                return _escape_bb(message)
        var open_stack: Array[String] = []
        var out := ""
        var pos := 0
        while true:
                var m := re.search(message, pos)
                if m == null:
                        break
                out += _escape_bb(message.substr(pos, m.get_start() - pos))
                var tag := m.get_string(2).to_lower()
                if FX_ALIAS.has(tag):
                        tag = str(FX_ALIAS[tag])
                if m.get_string(1) == "/":
                        var idx := open_stack.rfind(tag)
                        if idx >= 0:
                                # close everything the web's parser would close here
                                while open_stack.size() > idx:
                                        out += _fx_close_tag(open_stack.pop_back())
                else:
                        out += _fx_open_tag(tag)
                        open_stack.append(tag)
                pos = m.get_end()
        out += _escape_bb(message.substr(pos))
        while not open_stack.is_empty():
                out += _fx_close_tag(open_stack.pop_back())
        return out


## Strip every known FX tag — used for the plain-text chat bubbles.
static func strip_fx(message: String) -> String:
        var re := RegEx.new()
        if re.compile("\\[(/?)(%s)\\]" % _fx_known_pattern()) != OK:
                return message
        return re.sub(message, "", true)


# ================================================================ ui sounds

## Tiny retro UI blips, synthesized once at startup — no asset files needed,
## and the master volume slider shapes them like everything else.
func _setup_ui_sounds() -> void:
        _snd_hover = _synth_blip(920.0, 0.045, 0.22, false)
        _snd_click = _synth_blip(540.0, 0.07, 0.3, true)
        _snd_open = _synth_sweep(430.0, 950.0, 0.11, 0.3)
        _snd_close = _synth_sweep(780.0, 360.0, 0.1, 0.26)
        _ui_audio = AudioStreamPlayer.new()
        _ui_audio.name = "UISounds"
        add_child(_ui_audio)


func _synth_blip(freq: float, dur: float, vol: float, square: bool) -> AudioStreamWAV:
        var rate := 22050
        var n := int(rate * dur)
        var data := PackedByteArray()
        data.resize(n * 2)
        for i in range(n):
                var t := float(i) / float(rate)
                var env := 1.0 - float(i) / float(n)
                var v := sin(TAU * freq * t)
                if square:
                        v = signf(v) * 0.6
                data.encode_s16(i * 2, int(clampf(v * env * vol, -1.0, 1.0) * 32000.0))
        return _finish_wav(data, rate)


func _synth_sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
        var rate := 22050
        var n := int(rate * dur)
        var data := PackedByteArray()
        data.resize(n * 2)
        var phase := 0.0
        for i in range(n):
                var k := float(i) / float(n)
                var env := 1.0 - k
                var freq := lerpf(f0, f1, k)
                phase += TAU * freq / float(rate)
                data.encode_s16(i * 2, int(clampf(sin(phase) * env * vol, -1.0, 1.0) * 32000.0))
        return _finish_wav(data, rate)


func _finish_wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
        var wav := AudioStreamWAV.new()
        wav.format = AudioStreamWAV.FORMAT_16_BITS
        wav.mix_rate = rate
        wav.stereo = false
        wav.data = data
        return wav


func _play(sound: AudioStreamWAV) -> void:
        if sound == null or _ui_audio == null:
                return
        _ui_audio.stream = sound
        _ui_audio.play()


# ============================================================== ui buttons

## Every button in the HUD gets the retro treatment: hover tick, click thock,
## and a soft scale pop under the cursor.
func _wire_button_fx() -> void:
        _wire_button_fx_rec(root)


func _wire_button_fx_rec(from: Node) -> void:
        for child in from.get_children():
                if child is Button:
                        var b := child as Button
                        b.mouse_entered.connect(_on_btn_hover.bind(b))
                        b.mouse_exited.connect(_on_btn_unhover.bind(b))
                        b.pressed.connect(_on_btn_pressed)
                if child is Control:
                        _wire_button_fx_rec(child)


func _btn_tween(b: Button) -> Tween:
        if b.has_meta("fx_tween"):
                var old: Tween = b.get_meta("fx_tween")
                if old != null and old.is_valid():
                        old.kill()
        var tw := create_tween()
        b.set_meta("fx_tween", tw)
        return tw


func _on_btn_hover(b: Button) -> void:
        _play(_snd_hover)
        b.pivot_offset = b.size * 0.5
        _btn_tween(b).tween_property(b, "scale", Vector2(1.07, 1.07), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_btn_unhover(b: Button) -> void:
        _btn_tween(b).tween_property(b, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_btn_pressed() -> void:
        _play(_snd_click)


# ============================================================ panel anims

## Panels fade + gently swell in, and fade away when closed.
func _animate_panel_in(panel: Control) -> void:
        panel.pivot_offset = Vector2(0.0, panel.size.y * 0.5)
        panel.scale = Vector2(0.97, 0.97)
        var tw := create_tween().set_parallel(true)
        tw.tween_property(panel, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _fade_panel_out(panel: Control) -> void:
        panel.set_meta("closing", true)
        var tw := create_tween()
        tw.tween_property(panel, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
        tw.tween_callback(func() -> void:
                panel.visible = false
                panel.modulate.a = 1.0
                panel.remove_meta("closing"))


func _pop(c: Control) -> void:
        c.pivot_offset = c.size * 0.5
        var tw := create_tween()
        tw.tween_property(c, "scale", Vector2(1.24, 1.24), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tw.tween_property(c, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ============================================================ avatar viewer

## The bottom-center banner for the avatar-viewer load state: the avatar is
## on stage, the camera works, movement is waiting for the first key.
func _build_viewer_panel() -> void:
        _viewer_panel = PanelContainer.new()
        _viewer_panel.name = "ViewerHint"
        _viewer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _viewer_panel.add_theme_stylebox_override("panel", _classic_panel_style())
        _viewer_panel.anchor_left = 0.5
        _viewer_panel.anchor_right = 0.5
        _viewer_panel.anchor_top = 1.0
        _viewer_panel.anchor_bottom = 1.0
        _viewer_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
        _viewer_panel.offset_top = -96.0
        _viewer_panel.offset_bottom = -46.0
        var box := VBoxContainer.new()
        box.name = "ViewerBox"
        box.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var title := Label.new()
        title.name = "ViewerTitle"
        title.add_theme_color_override("font_color", CLASSIC_BLUE)
        title.add_theme_font_size_override("font_size", 14)
        title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var body := Label.new()
        body.name = "ViewerLabel"
        body.add_theme_color_override("font_color", CLASSIC_INK)
        body.add_theme_font_size_override("font_size", 11)
        body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        box.add_child(title)
        box.add_child(body)
        _viewer_panel.add_child(box)
        _viewer_panel.visible = false
        _viewer_panel.modulate.a = 0.0
        root.add_child(_viewer_panel)


func set_viewer_mode(on: bool, who: String) -> void:
        if _viewer_panel == null:
                return
        if _viewer_tween != null and _viewer_tween.is_valid():
                _viewer_tween.kill()
        if on:
                var title := _viewer_panel.get_node("ViewerTitle") as Label
                var body := _viewer_panel.get_node("ViewerLabel") as Label
                title.text = "Welcome, %s!" % who
                body.text = "This is YOUR avatar — spin the camera, SHIFT for shift lock.\nPress a move key or SPACE to start playing!"
                _viewer_panel.visible = true
                _viewer_panel.modulate.a = 0.0
                _play(_snd_open)
                _viewer_tween = create_tween()
                _viewer_tween.tween_property(_viewer_panel, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        else:
                _viewer_tween = create_tween()
                _viewer_tween.tween_property(_viewer_panel, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
                _viewer_tween.tween_callback(func() -> void: _viewer_panel.visible = false)
