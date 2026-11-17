extends PanelContainer
## Reusable In-Game Shop UI Window with scrollable item list from the RetroBlox Toolbox.

signal item_purchased(item_name: String, price: int)

@export var shop_title: String = "ITEM SHOP"

func _ready() -> void:
	var title_lbl := get_node_or_null("VBox/Header/TitleLabel") as Label
	if title_lbl != null:
		title_lbl.text = shop_title
	var close_btn := get_node_or_null("VBox/Header/CloseBtn") as Button
	if close_btn != null:
		close_btn.pressed.connect(func() -> void: visible = false)
	for i in range(1, 4):
		var btn := get_node_or_null("VBox/Scroll/Items/ItemRow%d/BuyBtn" % i) as Button
		var name_lbl := get_node_or_null("VBox/Scroll/Items/ItemRow%d/ItemName" % i) as Label
		if btn != null and name_lbl != null:
			var item_txt := name_lbl.text
			var cost := i * 25
			btn.pressed.connect(func() -> void:
				item_purchased.emit(item_txt, cost)
				btn.text = "Owned"
			)
