# res://scripts/apple_worm/game_hud.gd
class_name AppleWormHUD
extends Control

signal undo_requested
signal restart_requested
signal level_select_requested
signal next_level_requested

@onready var lbl_title: Label = $TopBar/Margin/HBox/LblTitle
@onready var lbl_moves: Label = $TopBar/Margin/HBox/LblMoves
@onready var btn_undo: Button = $TopBar/Margin/HBox/BtnUndo
@onready var btn_restart: Button = $TopBar/Margin/HBox/BtnRestart
@onready var btn_menu: Button = $TopBar/Margin/HBox/BtnMenu

@onready var win_modal: PanelContainer = $WinModal
@onready var lbl_win_moves: Label = $WinModal/VBox/LblWinMoves
@onready var btn_next: Button = $WinModal/VBox/HBox/BtnNext
@onready var btn_win_replay: Button = $WinModal/VBox/HBox/BtnReplay
@onready var btn_win_menu: Button = $WinModal/VBox/HBox/BtnMenu

@onready var fail_modal: PanelContainer = $FailModal
@onready var btn_fail_undo: Button = $FailModal/VBox/HBox/BtnFailUndo
@onready var btn_fail_retry: Button = $FailModal/VBox/HBox/BtnFailRetry

func _ready() -> void:
	win_modal.visible = false
	fail_modal.visible = false

	btn_undo.pressed.connect(func(): undo_requested.emit())
	btn_restart.pressed.connect(func(): restart_requested.emit())
	btn_menu.pressed.connect(func(): level_select_requested.emit())

	btn_next.pressed.connect(func(): next_level_requested.emit())
	btn_win_replay.pressed.connect(func(): restart_requested.emit())
	btn_win_menu.pressed.connect(func(): level_select_requested.emit())

	btn_fail_undo.pressed.connect(func():
		fail_modal.visible = false
		undo_requested.emit()
	)
	btn_fail_retry.pressed.connect(func():
		fail_modal.visible = false
		restart_requested.emit()
	)

func set_level_info(title: String) -> void:
	lbl_title.text = title
	win_modal.visible = false
	fail_modal.visible = false

func update_moves(moves: int) -> void:
	lbl_moves.text = "Moves: " + str(moves)

func show_win(moves: int) -> void:
	lbl_win_moves.text = "Completed in " + str(moves) + " moves!"
	win_modal.visible = true

func show_fail() -> void:
	fail_modal.visible = true
