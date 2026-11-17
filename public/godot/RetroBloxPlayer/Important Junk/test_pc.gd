
@tool
extends SceneTree

func _init() -> void:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(92, 92)
	pc.clip_contents = true
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pc.add_child(tr)
	var btn := Button.new()
	btn.flat = true
	pc.add_child(btn)
	print('PanelContainer created successfully!')
	quit()
