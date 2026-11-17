extends SceneTree

func _init() -> void:
	print("Testing load of game.gd...")
	var s: Script = load("res://scripts/game/game.gd")
	if s == null:
		printerr("FAILED to load game.gd")
		quit(1)
		return
	print("game.gd parsed and loaded cleanly with 0 errors!")
	quit(0)
