# RetrobloxChat — the classic Roblox chat.
#
#   - feed in the top-left ("Name: message")
#   - press "/" to chat, Enter to send, Esc to cancel
#   - every message also pops as a bubble above your character
#
# Chat is LOCAL in this build (singleplayer sandbox): messages land in the
# feed and above your head. When the platform's realtime relay lands, the
# same feed is what multiplayer messages flow through.
class_name RetrobloxChat
extends CanvasLayer

signal message_sent(text: String)

var player_name := "Player"

var _feed: VBoxContainer
var _input: LineEdit
var _hint: Label
var _open := false


func _ready() -> void:
	layer = 10

	var root := Control.new()
	root.name = "ChatRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ---- feed (top-left) ----
	_feed = VBoxContainer.new()
	_feed.name = "Feed"
	_feed.position = Vector2(8, 8)
	_feed.custom_minimum_size = Vector2(460, 10)
	_feed.add_theme_constant_override("separation", 2)
	root.add_child(_feed)

	# ---- input (bottom-left) ----
	_input = LineEdit.new()
	_input.name = "ChatInput"
	_input.placeholder_text = "To chat click here or press the / key"
	_input.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_input.position = Vector2(8, -36)
	_input.custom_minimum_size = Vector2(430, 26)
	_input.visible = false
	_input.text_submitted.connect(_on_submitted)
	root.add_child(_input)

	_hint = Label.new()
	_hint.text = 'Press "/" to chat'
	_hint.position = Vector2(10, -1)
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.modulate = Color(1, 1, 1, 0.6)
	root.add_child(_hint)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(10, -24)

	# keep the feed inside the window when messages pile up
	_feed.child_entered_tree.connect(func(_n: Node) -> void:
		while _feed.get_child_count() > 10:
			var oldest := _feed.get_child(0)
			_feed.remove_child(oldest)
			oldest.queue_free()
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_SLASH and not _open:
			open()
			get_viewport().set_input_as_handled()
		elif key == KEY_ESCAPE and _open:
			close()
			get_viewport().set_input_as_handled()


func open() -> void:
	_open = true
	_input.visible = true
	_hint.visible = false
	_input.grab_focus()
	_input.text = "/"


func close() -> void:
	_open = false
	_input.visible = false
	_hint.visible = true
	_input.release_focus()


func _on_submitted(text: String) -> void:
	var msg := text.strip_edges().trim_prefix("/")
	if msg != "":
		add_message(player_name, msg)
		message_sent.emit(msg)
	close()


## A line in the feed. Classic chat had colored names — keep a stable
## pleasant blue for the local player, like the old "Player:" lines.
func add_message(who: String, text: String) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(460, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "[color=#4da6ff][b]%s:[/b][/color] %s" % [_escape(who), _escape(text)]
	_feed.add_child(label)


func _escape(s: String) -> String:
	return s.replace("[", "(").replace("]", ")")
