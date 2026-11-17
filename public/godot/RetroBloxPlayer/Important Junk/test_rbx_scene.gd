extends SceneTree

func _init() -> void:
	print("Testing load of scenes/retroblox.tscn with game.gd...")
	var ps: PackedScene = load("res://scenes/retroblox.tscn")
	if ps == null:
		printerr("FAILED to load retroblox.tscn")
		quit(1)
		return
	print("retroblox.tscn loaded successfully!")
	var inst: Node = ps.instantiate()
	if inst == null:
		printerr("FAILED to instantiate retroblox.tscn")
		quit(1)
		return
	print("retroblox.tscn instantiated with script: ", inst.get_script().resource_path)
	inst.free()
	print("ALL RETROBLOX SCENE & GAME.GD CHECKS PASSED!")
	quit(0)
