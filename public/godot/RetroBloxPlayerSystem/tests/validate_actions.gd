extends SceneTree

## Fails loudly if any input action the game reads is missing from
## project.godot — run with:
##   godot --headless --path . --script res://tests/validate_actions.gd

func _init() -> void:
	var missing: Array = []
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
		if not InputMap.has_action(action):
			missing.append(action)
			print("MISSING ACTION: ", action)
		else:
			print("ok: ", action)
	if missing.is_empty():
		print("ALL INPUT ACTIONS DEFINED")
		quit(0)
	else:
		print("Add the missing actions to the [input] section of project.godot")
		quit(1)
