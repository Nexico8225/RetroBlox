@tool
extends SceneTree

func _init() -> void:
	var path: String = "C:/Users/Neixco8225/AppData/Roaming/Godot/app_userdata/RetroBlox Player/retroblox_toolbox_models/published_palmtree_icon.png"
	var img: Image = Image.load_from_file(path)
	if img == null:
		print("Failed to load image from:", path)
		quit(1)
		return
	print("Loaded img:", img.get_size())
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	
	var tile: VBoxContainer = VBoxContainer.new()
	tile.custom_minimum_size = Vector2(96, 162)
	
	var thumb_container: PanelContainer = PanelContainer.new()
	thumb_container.custom_minimum_size = Vector2(92, 92)
	thumb_container.clip_contents = true
	tile.add_child(thumb_container)
	
	var tex_rect: TextureRect = TextureRect.new()
	tex_rect.texture = tex
	tex_rect.custom_minimum_size = Vector2(80, 80)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex_rect.offset_left = 6.0
	tex_rect.offset_top = 6.0
	tex_rect.offset_right = -6.0
	tex_rect.offset_bottom = -6.0
	thumb_container.add_child(tex_rect)
	
	var root: Control = Control.new()
	root.size = Vector2(300, 500)
	root.add_child(tile)
	
	# Simulate frame draw / layout
	tile.set_size(Vector2(96, 162))
	thumb_container.set_size(Vector2(92, 92))
	
	print("thumb_container min size:", thumb_container.get_combined_minimum_size(), "size:", thumb_container.size)
	print("tex_rect min size:", tex_rect.get_combined_minimum_size(), "size:", tex_rect.size, "pos:", tex_rect.position)
	quit(0)
