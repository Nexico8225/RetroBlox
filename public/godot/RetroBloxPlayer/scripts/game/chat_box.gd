extends Control
## ChatBox — the TOP-LEFT chat, light translucent + rounded like the 2016
## site: log under the topbar pill, input line always visible underneath.
## Shows the last stretch of lines with colored names, Enter opens the
## input, Enter again sends, Esc closes. The LOG can collapse to nothing —
## unread messages then count on the topbar chat button's red badge. Plain
## text only — nothing can inject markup.
##
## v3.11: F READS — a read-only mode that shows the log WITHOUT grabbing
## the keyboard, so you can catch up on chat while you keep moving. The
## "#1" seq chips are gone from lines.
## v4.0: the daylight skid — white glass panels, ink text, quiet borders.

signal submitted(text: String)
signal opened
signal closed
signal unread(count: int)

## v3.6: the chat button + ENTER fully TOGGLE the chat — closing hides the
## LOG **and the typing line together** (they used to leave the input
## dangling). While hidden, new messages still stack the red unread badge.

const MAX_LINES := 60
const NAME_COLORS: Array = [
        "c9960f", "3f8f22", "0f76c9", "c2502f", "8a3fc9",
        "0f96a8", "c91f6e", "5f8f0f", "a8820f", "5d6b80",
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
        # v4.0: white daylight glass, quiet border, round corners
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(1, 1, 1, 0.88)
        sb.set_corner_radius_all(12)
        sb.border_color = Color("c9d3dc")
        sb.set_border_width_all(1)
        sb.shadow_color = Color(0.1, 0.18, 0.28, 0.10)
        sb.shadow_size = 8
        sb.shadow_offset = Vector2(0, 3)
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
        _log.add_theme_color_override("default_color", Color("1e2733"))
        _panel.add_child(_log)

        _input_panel = PanelContainer.new()
        _input_panel.name = "InputPanel"
        var isb := StyleBoxFlat.new()
        isb.bg_color = Color(1, 1, 1, 0.92)
        isb.set_corner_radius_all(12)
        isb.border_color = Color("c9d3dc")
        isb.set_border_width_all(1)
        isb.shadow_color = Color(0.1, 0.18, 0.28, 0.10)
        isb.shadow_size = 8
        isb.shadow_offset = Vector2(0, 3)
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
        _input.add_theme_color_override("font_color", Color("1e2733"))
        _input.add_theme_color_override("font_placeholder_color", Color("97a1ad"))
        # the typing line speaks in the clean book voice when it ships
        var book: Font = RetroUI.clean_book()
        if book != null:
                _input.add_theme_font_override("font", book)
                _input.add_theme_font_size_override("font_size", 14)
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
        _log.append_text("[color=#8a95a1][i]%s[/i][/color]\n" % _esc(text))
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
                _log.append_text("[color=#8a95a1][i](chat trimmed)[/i][/color]\n")


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
