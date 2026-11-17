extends PanelContainer
## Reusable Coin & Points Counter HUD UI from the RetroBlox Toolbox.

@export var starting_coins: int = 100
@export var currency_name: String = "Coins"

var coins: int = 0
var _label: Label

func _ready() -> void:
	coins = starting_coins
	_label = get_node_or_null("HBox/CoinValueLabel") as Label
	var test_btn := get_node_or_null("HBox/AddCoinBtn") as Button
	if test_btn != null and not test_btn.pressed.is_connected(_on_test_add):
		test_btn.pressed.connect(_on_test_add)
	_refresh()

func add_coins(amount: int) -> void:
	coins += amount
	_refresh()

func _on_test_add() -> void:
	add_coins(10)

func _refresh() -> void:
	if _label != null:
		_label.text = "%s: %d" % [currency_name, coins]
