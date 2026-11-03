extends PanelContainer
## Reusable Health & Stamina Bars HUD UI from the RetroBlox Toolbox.

@export var max_stamina: float = 100.0
@export var stamina_regen_per_sec: float = 18.0

var stamina: float = 100.0
var _hp_bar: ProgressBar
var _st_bar: ProgressBar

func _ready() -> void:
	_hp_bar = get_node_or_null("VBox/HealthBar") as ProgressBar
	_st_bar = get_node_or_null("VBox/StaminaBar") as ProgressBar

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	stamina = clampf(stamina + stamina_regen_per_sec * delta, 0.0, max_stamina)
	if _st_bar != null:
		_st_bar.max_value = max_stamina
		_st_bar.value = stamina
