extends PanelContainer
## Reusable Server / Round Announcement Top Banner UI from the RetroBlox Toolbox.

@export var default_message: String = "Welcome to the Server!"
@export var auto_hide_seconds: float = 0.0

var _lbl: Label
var _timer: float = 0.0

func _ready() -> void:
	_lbl = get_node_or_null("BannerLabel") as Label
	if _lbl != null:
		_lbl.text = default_message
	if auto_hide_seconds > 0.0:
		_timer = auto_hide_seconds

func announce(msg: String, duration: float = 5.0) -> void:
	visible = true
	if _lbl != null:
		_lbl.text = msg
	_timer = duration

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _timer <= 0.0:
		return
	_timer -= delta
	if _timer <= 0.0:
		visible = false
