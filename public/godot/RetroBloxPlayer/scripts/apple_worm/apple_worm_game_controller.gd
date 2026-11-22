# res://scripts/apple_worm/apple_worm_game_controller.gd
class_name AppleWormGameController
extends Node

@onready var manager: AppleWormGameManager = $GameManager
@onready var hud: AppleWormHUD = $HUD

var current_path: String = ""

func _ready() -> void:
	manager.level_completed.connect(_on_level_completed)
	manager.level_failed.connect(_on_level_failed)
	manager.moves_updated.connect(_on_moves_updated)

	hud.undo_requested.connect(func(): manager.undo_move())
	hud.restart_requested.connect(func(): manager.restart_level())
	hud.next_level_requested.connect(_on_next_level)
	hud.level_select_requested.connect(_on_level_select)

	# If GlobalState or argument provided, load that level; else load level 1 or unlocked level
	var target = "res://levels/level_001.tscn"
	if has_node("/root/AppleWormGlobal"):
		var global = get_node("/root/AppleWormGlobal")
		if global.selected_level != "":
			target = global.selected_level
	start_level(target)

func start_level(path: String) -> void:
	current_path = path
	manager.load_level(path)
	var title = "Apple Worm"
	if is_instance_valid(manager.level_instance):
		title = manager.level_instance.level_title
	hud.set_level_info(title)

func _on_moves_updated(count: int) -> void:
	hud.update_moves(count)

func _on_level_completed() -> void:
	var num = LevelManager._extract_number(current_path)
	LevelManager.save_progress(num, manager.move_count)
	hud.show_win(manager.move_count)

func _on_level_failed() -> void:
	hud.show_fail()

func _on_next_level() -> void:
	var next_path = LevelManager.get_next_level(current_path)
	if next_path != "":
		start_level(next_path)
	else:
		_on_level_select()

func _on_level_select() -> void:
	get_tree().change_scene_to_file("res://scenes/apple_worm/level_selector.tscn")
