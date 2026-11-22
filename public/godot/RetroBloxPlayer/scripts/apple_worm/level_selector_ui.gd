# res://scripts/apple_worm/level_selector_ui.gd
class_name AppleWormLevelSelector
extends Control

const ITEMS_PER_PAGE = 25

@onready var grid_container: GridContainer = $Margin/VBox/Scroll/Grid
@onready var lbl_page: Label = $Margin/VBox/Footer/LblPage
@onready var btn_prev: Button = $Margin/VBox/Footer/BtnPrev
@onready var btn_next: Button = $Margin/VBox/Footer/BtnNext
@onready var btn_back: Button = $Margin/VBox/Header/BtnBack
@onready var lbl_total: Label = $Margin/VBox/Header/LblTotal

var all_levels: Array[String] = []
var progress_data: Dictionary = {}
var current_page: int = 0
var max_pages: int = 1

func _ready() -> void:
	btn_back.pressed.connect(_on_back)
	btn_prev.pressed.connect(_on_prev_page)
	btn_next.pressed.connect(_on_next_page)

	all_levels = LevelManager.get_all_levels()
	progress_data = LevelManager.load_progress()
	max_pages = max(1, ceili(float(all_levels.size()) / float(ITEMS_PER_PAGE)))
	lbl_total.text = "Discovered " + str(all_levels.size()) + " Levels"

	_render_page()

func _render_page() -> void:
	# Clear existing buttons
	for child in grid_container.get_children():
		child.queue_free()

	lbl_page.text = "Page " + str(current_page + 1) + " of " + str(max_pages)
	btn_prev.disabled = (current_page == 0)
	btn_next.disabled = (current_page >= max_pages - 1)

	var start_idx = current_page * ITEMS_PER_PAGE
	var end_idx = min(start_idx + ITEMS_PER_PAGE, all_levels.size())
	var unlocked_limit = progress_data.get("unlocked", 1)
	var completed_dict = progress_data.get("completed", {})

	for i in range(start_idx, end_idx):
		var path = all_levels[i]
		var level_num = LevelManager._extract_number(path)
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(100, 75)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var is_unlocked = (level_num <= unlocked_limit or i == 0)
		var is_completed = completed_dict.has(str(level_num))

		if is_completed:
			btn.text = "Level %d\n★ %d Moves" % [level_num, completed_dict[str(level_num)]]
			btn.modulate = Color(0.3, 0.9, 0.4) # Green card
		elif is_unlocked:
			btn.text = "Level %d\n[ Play ]" % level_num
			btn.modulate = Color(1.0, 0.85, 0.2) # Gold current card
		else:
			btn.text = "Level %d\n🔒 Locked" % level_num
			btn.disabled = true
			btn.modulate = Color(0.6, 0.6, 0.6)

		if is_unlocked:
			btn.pressed.connect(func(): _load_level(path))

		grid_container.add_child(btn)

func _load_level(path: String) -> void:
	if has_node("/root/AppleWormGlobal"):
		get_node("/root/AppleWormGlobal").selected_level = path
	get_tree().change_scene_to_file("res://scenes/apple_worm/apple_worm_game.tscn")

func _on_prev_page() -> void:
	if current_page > 0:
		current_page -= 1
		_render_page()

func _on_next_page() -> void:
	if current_page < max_pages - 1:
		current_page += 1
		_render_page()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/apple_worm/main_menu.tscn")
