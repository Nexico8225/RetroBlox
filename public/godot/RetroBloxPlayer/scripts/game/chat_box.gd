extends Control
## ChatBox — the TOP-LEFT chat, dark translucent like the classic client:
## the TYPE BOX is ALWAYS visible (the authentic "To chat click here or
## press / key" line), the log opens when you click it / press Enter.
## CLICK the type box -> you are typing. CLICK OFF (or ESC) -> the keyboard
## goes back to the game. Every line carries the speaker's name.
## Unread messages count on the topbar chat button's red badge while the
## log is hidden. Plain text only — nothing can inject markup.
##
## v3.11: F READS — a read-only mode that shows the log WITHOUT grabbing
## the keyboard, so you can catch up on chat while you keep moving.
## v12.1: RETRO NIGHT — the dark glass float is back (the white paper chat
## was blinding), names wear the CLASSIC bright palette.

signal submitted(text: String)
signal opened
signal closed
signal unread(count: int)

## v3.6: the chat button + ENTER fully TOGGLE the chat — closing hides the
## LOG (the type box stays — it is the chat's front door). While the log is
## hidden, new messages stack the red unread badge.

const MAX_LINES := 60
## v12.1: the CLASSIC BRIGHT name palette — every name pops on the dark
## glass the way the old client's chat read.
const NAME_COLORS: Array = [
        "fd2943", "01a2ff", "02b857", "ffd30f", "c963ff",
        "ff8552", "3ecfff", "a1f24c", "ff6fc7", "f5cd30",
]

const RetroUI := preload("res://scripts/ui/retro_theme.gd")

var _log: RichTextLabel
var _input: LineEdit
var _panel: PanelContainer
var _input_panel: PanelContainer
var is_open := false
var is_reading := false        # v3.11: log shown, keyboard free, you keep moving
var log_collapsed := false
var _unread := 0


func _init() -> void:
        # top-left corner, just under the topbar pill — where chatting lives
        set_anchors_preset(Control.PRESET_TOP_LEFT)
        offset_left = 10.0
        offset_top = 54.0
        offset_right = 404.0
        offset_bottom = 288.0

        _panel = PanelContainer.new()
        _panel.name = "LogPanel"
        # v12.1: the RETRO NIGHT chat float — dark translucent glass, ONE
        # thin light frame (the classic client read), light ink on it
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.05, 0.062, 0.08, 0.88)
        sb.set_corner_radius_all(8)
        sb.anti_aliasing = true
        sb.set_border_width_all(1)
        sb.border_color = Color(1, 1, 1, 0.16)
        sb.shadow_color = Color(0, 0, 0, 0.35)
        sb.shadow_size = 8
        sb.content_margin_left = 12.0
        sb.content_margin_right = 12.0
        sb.content_margin_top = 9.0
        sb.content_margin_bottom = 9.0
        _panel.add_theme_stylebox_override("panel", sb)
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.offset_bottom = -42.0
        add_child(_panel)

        _log = RichTextLabel.new()
        _log.bbcode_enabled = true
        _log.scroll_active = true
        _log.scroll_following = true
        _log.selection_enabled = false
        _log.context_menu_enabled = false
        _log.add_theme_font_size_override("normal_font_size", 14)
        _log.add_theme_font_size_override("bold_font_size", 14)
        _log.add_theme_color_override("default_color", RetroUI.NIGHT_INK)
        var chat_font: Font = RetroUI.source(400)
        if chat_font != null:
                _log.add_theme_font_override("normal_font", chat_font)
                _log.add_theme_font_override("bold_font", RetroUI.source(700))
        _panel.add_child(_log)

        _input_panel = PanelContainer.new()
        _input_panel.name = "InputPanel"
        var isb := StyleBoxFlat.new()
        isb.bg_color = Color(0.05, 0.062, 0.08, 0.88)
        isb.set_corner_radius_all(8)
        isb.anti_aliasing = true
        isb.set_border_width_all(1)
        isb.border_color = Color(1, 1, 1, 0.16)
        isb.content_margin_left = 4.0
        isb.content_margin_right = 4.0
        isb.content_margin_top = 4.0
        isb.content_margin_bottom = 4.0
        _input_panel.add_theme_stylebox_override("panel", isb)
        _input_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        _input_panel.offset_top = -36.0
        add_child(_input_panel)

        _input = LineEdit.new()
        # the AUTHENTIC placeholder — the exact line the real client shows
        _input.placeholder_text = "To chat click here or press / key"
        _input.max_length = 240
        _input.context_menu_enabled = false
        _input.add_theme_color_override("font_color", RetroUI.NIGHT_INK)
        _input.add_theme_color_override("font_placeholder_color", RetroUI.NIGHT_INK_FAINT)
        var well_sb := StyleBoxFlat.new()
        well_sb.bg_color = Color(0.02, 0.03, 0.045, 0.92)
        well_sb.set_corner_radius_all(6)
        well_sb.anti_aliasing = true
        well_sb.set_border_width_all(1)
        well_sb.border_color = RetroUI.NIGHT_EDGE
        well_sb.content_margin_left = 8.0
        well_sb.content_margin_right = 8.0
        well_sb.content_margin_top = 4.0
        well_sb.content_margin_bottom = 4.0
        _input.add_theme_stylebox_override("normal", well_sb)
        var well_focus := well_sb.duplicate() as StyleBoxFlat
        well_focus.border_color = RetroUI.SITE_BLUE_HI
        _input.add_theme_stylebox_override("focus", well_focus)
        var book: Font = RetroUI.source(400)
        if book != null:
                _input.add_theme_font_override("font", book)
                _input.add_theme_font_size_override("font_size", 14)
        else:
                _input.add_theme_font_size_override("font_size", 14)
        _input.text_submitted.connect(_on_submit)
        _input.gui_input.connect(_on_input_gui)
        _input_panel.add_child(_input)

        # v12.1: the type box is the chat's FRONT DOOR — always visible.
        # Click it and you are typing (the log un-hides); click off and the
        # keyboard goes back to the game (game.gd closes the chat on any
        # click that lands outside this widget). The LOG starts hidden —
        # the topbar badge counts anything said until you open it.
        _panel.visible = false


func open() -> void:
        if is_open:
                return
        is_open = true
        is_reading = false          # typing mode replaces read mode
        log_collapsed = false
        visible = true
        _panel.visible = true
        _input_panel.visible = true
        _clear_unread()
        _input.grab_focus()
        opened.emit()


## The whole chat log goes away — the type box STAYS (it is the front
## door you click to come back).
func close() -> void:
        if not is_open:
                return
        is_open = false
        is_reading = false
        _input.text = ""
        _input.release_focus()
        _panel.visible = false
        closed.emit()


# ---- v3.11 READ MODE — the F key -----------------------------------------

## F shows the log WITHOUT the type box and WITHOUT grabbing the keyboard:
## read everything while you keep running. F again (or ESC) hides it.
func toggle_read() -> void:
        if is_reading:
                close_read()
        else:
                open_read()


func open_read() -> void:
        if is_open or is_reading:
                return
        is_reading = true
        log_collapsed = false
        visible = true
        _panel.visible = true
        _input_panel.visible = false
        _clear_unread()
        _input.release_focus()


func close_read() -> void:
        if not is_reading:
                return
        is_reading = false
        _panel.visible = false
        visible = false


## The topbar chat button: collapse/expand the LOG (typing stays separate).
func set_log_collapsed(collapsed: bool) -> void:
        log_collapsed = collapsed
        _panel.visible = not collapsed
        if not collapsed:
                _clear_unread()


func _clear_unread() -> void:
        _unread = 0
        unread.emit(0)


func _on_submit(text: String) -> void:
        var clean := text.strip_edges()
        close()
        if clean != "":
                submitted.emit(clean)


func _on_input_gui(event: InputEvent) -> void:
        if event is InputEventMouseButton and event.is_pressed():
                # clicking the always-visible type box opens the chat (the
                # log un-hides so you can see what everyone is saying) and
                # hands you the keyboard
                if not is_open:
                        open()
                        get_viewport().set_input_as_handled()
        elif event is InputEventKey and event.is_pressed() and not event.is_echo():
                var key := event as InputEventKey
                if key.keycode == KEY_ESCAPE:
                        close()
                        get_viewport().set_input_as_handled()


## One chat line — the speaker's name in the
## classic bright palette, then the message. name_color is a hex string.
## v3.11: the "#1" seq chips are GONE (you asked) — a clean line.
func add_chat(username: String, _seq_id: int, text: String, name_color: String = "", self_style := false, uid := "") -> void:
        var color := _color_for(username, name_color)
        var line := " [b][color=#%s]%s:[/color][/b] %s" % [color, _esc(username), _esc(text)]
        if self_style:
                line = "[i]" + line + "[/i]"
        _log.append_text(line + "\n")
        _count_unread()
        _prune()




func add_system(text: String) -> void:
        _log.append_text("[color=#8ea6bd][i]%s[/i][/color]\n" % _esc(text))
        _count_unread()
        _prune()


## While the log is hidden OR you are only peeking (read mode counts as
## reading — nothing new is "unread" while it is on screen).
func _count_unread() -> void:
        if log_collapsed or (not is_open and not is_reading):
                _unread += 1
                unread.emit(_unread)


func _prune() -> void:
        # RichTextLabel has no line counter — track by clearing when huge
        if _log.get_total_character_count() > 12000:
                _log.clear()
                _log.append_text("[color=#8ea6bd][i](chat trimmed)[/i][/color]\n")


func _esc(text: String) -> String:
        # bbcode escape: replace every "[" with the [lb] literal tag. A lone "]"
        # never opens a tag, so it renders literally and stays safe.
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
