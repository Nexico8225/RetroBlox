extends Control
## ChatBox — the TOP-LEFT chat, dark translucent + rounded like the modern
## classic client: log under the topbar pill, input line always visible
## underneath. Shows the last stretch of lines with colored names, Enter
## opens the input, Enter again sends, Esc closes. The LOG can collapse to
## nothing — unread messages then count on the topbar chat button's red
## badge. Plain text only — nothing can inject markup.
##
## v3.11: F READS — a read-only mode that shows the log WITHOUT grabbing
## the keyboard, so you can catch up on chat while you keep moving. The
## "#1" seq chips are gone from lines, and the panels are rounder + more
## translucent (matching the mono menu).

signal submitted(text: String)
signal opened
signal closed
signal unread(count: int)

## v3.6: the chat button + ENTER fully TOGGLE the chat — closing hides the
## LOG **and the typing line together** (they used to leave the input
## dangling). While hidden, new messages still stack the red unread badge.

const MAX_LINES := 60
const NAME_COLORS: Array = [
        "ffd34e", "7ad154", "5aa8e8", "e8845a", "c07ae8",
        "5ad1c0", "e85a9b", "a8e85a", "e8d05a", "8a9bb0",
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
        # v3.11: translucent ink glass, rounder corners, bold white edge
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.03, 0.035, 0.05, 0.62)
        sb.set_corner_radius_all(10)
        sb.border_color = Color(1, 1, 1, 0.18)
        sb.set_border_width_all(2)
        sb.content_margin_left = 10.0
        sb.content_margin_right = 10.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
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
        _log.add_theme_color_override("default_color", Color(0.94, 0.96, 0.98))
        _panel.add_child(_log)

        _input_panel = PanelContainer.new()
        _input_panel.name = "InputPanel"
        var isb := StyleBoxFlat.new()
        isb.bg_color = Color(0.03, 0.035, 0.05, 0.78)
        isb.set_corner_radius_all(10)
        isb.border_color = Color(1, 1, 1, 0.24)
        isb.set_border_width_all(2)
        isb.content_margin_left = 8.0
        isb.content_margin_right = 8.0
        isb.content_margin_top = 4.0
        isb.content_margin_bottom = 4.0
        _input_panel.add_theme_stylebox_override("panel", isb)
        _input_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        _input_panel.offset_top = -36.0
        add_child(_input_panel)

        _input = LineEdit.new()
        _input.placeholder_text = "ENTER to chat  ·  F just reads, keeps you moving"
        _input.max_length = 240
        _input.context_menu_enabled = false
        _input.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
        _input.add_theme_color_override("font_placeholder_color", Color(0.62, 0.68, 0.74))
        # the typing line speaks in the retro pixel voice when it ships
        var pixel: Font = RetroUI.pixel_font()
        if pixel != null:
                _input.add_theme_font_override("font", pixel)
                _input.add_theme_font_size_override("font_size", 10)
        else:
                _input.add_theme_font_size_override("font_size", 14)
        _input.text_submitted.connect(_on_submit)
        _input.gui_input.connect(_on_input_gui)
        _input_panel.add_child(_input)

        # v3.6: the chat starts TUCKED AWAY — you spawn into a clean world
        # and the topbar badge counts anything said while it is hidden.
        # ENTER or the chat button opens it (log + type box as one widget).
        _panel.visible = false
        _input_panel.visible = false


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


## The whole chat goes away — log AND the type box, nothing left dangling.
func close() -> void:
        if not is_open:
                return
        is_open = false
        is_reading = false
        _input.text = ""
        _input.release_focus()
        _panel.visible = false
        _input_panel.visible = false
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
                # clicking the always-visible input opens the chat (the log
                # un-collapses so you can see what everyone is saying)
                if not is_open:
                        open()
                        get_viewport().set_input_as_handled()
        elif event is InputEventKey and event.is_pressed() and not event.is_echo():
                var key := event as InputEventKey
                if key.keycode == KEY_ESCAPE:
                        close()
                        get_viewport().set_input_as_handled()


## One chat line. name_color is a hex string. v3.11: the "#1" seq chips are
## GONE (you asked) — a clean "Name: text" line. seq_id is kept in the
## signature so existing callers don't break, but it is no longer shown.
func add_chat(username: String, seq_id: int, text: String, name_color: String = "", self_style := false) -> void:
        var color := _color_for(username, name_color)
        var line := "[b][color=#%s]%s:[/color][/b] %s" % [color, _esc(username), _esc(text)]
        if self_style:
                line = "[i]" + line + "[/i]"
        _log.append_text(line + "\n")
        _count_unread()
        _prune()


func add_system(text: String) -> void:
        _log.append_text("[color=#9fb6c8][i]%s[/i][/color]\n" % _esc(text))
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
                _log.append_text("[color=#9fb6c8][i](chat trimmed)[/i][/color]\n")


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
