# res://scripts/apple_worm/main_menu.gd
class_name AppleWormMainMenu
extends Control

@onready var btn_play: Button = $Center/VBox/BtnPlay
@onready var btn_levels: Button = $Center/VBox/BtnLevels
@onready var btn_custom: Button = $Center/VBox/BtnCustom
@onready var btn_quit: Button = $Center/VBox/BtnQuit
@onready var custom_modal: PanelContainer = $CustomModal
@onready var btn_close_modal: Button = $CustomModal/VBox/BtnCloseModal

func _ready() -> void:
	custom_modal.visible = false
	btn_play.pressed.connect(_on_play)
	btn_levels.pressed.connect(_on_levels)
	btn_custom.pressed.connect(func(): custom_modal.visible = true)
	btn_close_modal.pressed.connect(func(): custom_modal.visible = false)
	btn_quit.pressed.connect(_on_quit)

func _on_play() -> void:
	var progress = LevelManager.load_progress()
	var unlocked = progress.get("unlocked", 1)
	var all = LevelManager.get_all_levels()
	var target = "res://levels/level_001.tscn"
	for lvl in all:
		if LevelManager._extract_number(lvl) == unlocked:
			target = lvl
			break
	if has_node("/root/AppleWormGlobal"):
		get_node("/root/AppleWormGlobal").selected_level = target
	get_tree().change_scene_to_file("res://scenes/apple_worm/apple_worm_game.tscn")

func _on_levels() -> void:
	get_tree().change_scene_to_file("res://scenes/apple_worm/level_selector.tscn")

func _on_quit() -> void:
	get_tree().quit()
