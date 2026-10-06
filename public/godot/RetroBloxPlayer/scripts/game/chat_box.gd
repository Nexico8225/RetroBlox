extends Control
## ChatBox — the classic bottom-left chat. Shows the last stretch of lines
## with colored names (#seqId chips included), Enter opens the input, Enter
## again sends, Esc closes. Plain text only — nothing can inject markup.

signal submitted(text: String)
signal opened
signal closed

const MAX_LINES := 60
const NAME_COLORS: Array = [
        "ffd34e", "7ad154", "5aa8e8", "e8845a", "c07ae8",
        "5ad1c0", "e85a9b", "a8e85a", "e8d05a", "8a9bb0",
]

var _log: RichTextLabel
var _input: LineEdit
var _panel: PanelContainer
var _input_panel: PanelContainer
var is_open := false
var _known_ids: Dictionary = {}


func _init() -> void:
        set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
        offset_left = 10.0
        offset_bottom = -10.0
        offset_top = -232.0
        offset_right = 470.0
        grow_vertical = Control.GROW_DIRECTION_BEGIN

        _panel = PanelContainer.new()
        _panel.name = "LogPanel"
        # chat log floats on translucent dark, like every classic client
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.06, 0.10, 0.14, 0.62)
        sb.set_border_width_all(1)
        sb.border_color = Color(0, 0, 0, 0.5)
        sb.set_corner_radius_all(4)
        sb.content_margin_left = 8.0
        sb.content_margin_right = 8.0
        sb.content_margin_top = 6.0
        sb.content_margin_bottom = 6.0
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
        _log.add_theme_color_override("default_color", Color(0.92, 0.95, 0.98))
        _panel.add_child(_log)

        _input_panel = PanelContainer.new()
        _input_panel.name = "InputPanel"
        var isb := StyleBoxFlat.new()
        isb.bg_color = Color(0.98, 0.99, 1.0, 0.96)
        isb.set_border_width_all(2)
        isb.border_color = Color("51626f")
        isb.set_corner_radius_all(3)
        isb.content_margin_left = 6.0
        isb.content_margin_right = 6.0
        isb.content_margin_top = 3.0
        isb.content_margin_bottom = 3.0
        _input_panel.add_theme_stylebox_override("panel", isb)
        _input_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        _input_panel.offset_top = -36.0
        _input_panel.visible = false
        add_child(_input_panel)

        _input = LineEdit.new()
        _input.placeholder_text = "To chat click here or press ENTER"
        _input.max_length = 240
        _input.add_theme_color_override("font_color", Color("1a242e"))
        _input.add_theme_font_size_override("font_size", 14)
        _input.text_submitted.connect(_on_submit)
        _input.gui_input.connect(_on_input_gui)
        _input_panel.add_child(_input)


func open() -> void:
        if is_open:
                return
        is_open = true
        _input_panel.visible = true
        _input.grab_focus()
        opened.emit()


func close() -> void:
        if not is_open:
                return
        is_open = false
        _input.text = ""
        _input_panel.visible = false
        _input.release_focus()
        closed.emit()


func _on_submit(text: String) -> void:
        var clean := text.strip_edges()
        close()
        if clean != "":
                submitted.emit(clean)


func _on_input_gui(event: InputEvent) -> void:
        if event is InputEventKey and event.is_pressed() and not event.is_echo():
                var key := event as InputEventKey
                if key.keycode == KEY_ESCAPE:
                        close()
                        get_viewport().set_input_as_handled()


## One chat line. name_color is a hex string; seq_id <= 0 hides the chip.
func add_chat(username: String, seq_id: int, text: String, name_color: String = "", self_style := false) -> void:
        var tag := username
        if seq_id > 0:
                tag = "%s #%d" % [username, seq_id]
        var color := _color_for(username, name_color)
        var line := "[b][color=#%s]%s:[/color][/b] %s" % [color, _esc(tag), _esc(text)]
        if self_style:
                line = "[i]" + line + "[/i]"
        _log.append_text(line + "\n")
        _prune()


func add_system(text: String) -> void:
        _log.append_text("[color=#9fb6c8][i]%s[/i][/color]\n" % _esc(text))
        _prune()


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
        var hash := 0
        for i in range(username.length()):
                hash = (hash * 31 + username.unicode_at(i)) % 100000
        return String(NAME_COLORS[hash % NAME_COLORS.size()])
