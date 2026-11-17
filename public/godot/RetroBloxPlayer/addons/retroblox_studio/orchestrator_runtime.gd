@tool
extends Node

# RetroBlox Orchestrator Runtime Component
# Executes visual scripting node graphs (Orchestrator Blueprints) attached to scene objects.

@export var graph_data: Dictionary = {}
@export var is_active: bool = true

var _variables: Dictionary = {}

func _ready() -> void:
	if not is_active:
		return
	_hook_parent_events()
	_execute_event("on_game_start", null)

func _hook_parent_events() -> void:
	var parent = get_parent()
	if parent == null:
		return

	# 1. Body Entered / Touched
	if parent is Area3D:
		var a := parent as Area3D
		if not a.body_entered.is_connected(_on_parent_body_entered):
			a.body_entered.connect(_on_parent_body_entered)
	elif parent is CollisionObject3D:
		# If static or rigid body, create a subtle trigger envelope if graph listens to touch
		if _has_event("on_touched"):
			var area = Area3D.new()
			area.name = "_OrchestratorTouchDetector"
			area.collision_layer = 0
			area.collision_mask = 4 # Players
			parent.call_deferred("add_child", area)
			var col = CollisionShape3D.new()
			var bs = BoxShape3D.new()
			bs.size = Vector3(4.2, 1.4, 2.2)
			col.shape = bs
			area.call_deferred("add_child", col)
			area.body_entered.connect(_on_parent_body_entered)

	# 2. Timer events
	if _has_event("on_timer"):
		var interval = float(graph_data.get("timer_interval", 1.0))
		if interval > 0.0:
			var t = Timer.new()
			t.wait_time = interval
			t.autostart = true
			add_child(t)
			t.timeout.connect(func(): _execute_event("on_timer", null))

func _has_event(event_name: String) -> bool:
	var nodes: Array = graph_data.get("nodes", [])
	for n in nodes:
		if n is Dictionary and String(n.get("type", "")) == event_name:
			return true
	return false

func _on_parent_body_entered(body: Node3D) -> void:
	_execute_event("on_touched", body)

func _execute_event(event_name: String, target_body: Node3D) -> void:
	var actions: Array = graph_data.get("actions", [])
	for act in actions:
		if not (act is Dictionary):
			continue
		var act_dict := act as Dictionary
		if String(act_dict.get("event", "")) != event_name and event_name != "":
			continue
		_perform_action(act_dict, target_body)

func _perform_action(action: Dictionary, target_body: Node3D) -> void:
	var action_type = String(action.get("type", ""))
	var delay = float(action.get("delay", 0.0))
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	match action_type:
		"damage":
			var dmg = float(action.get("amount", 20.0))
			if target_body != null and is_instance_valid(target_body):
				if target_body.has_method("take_damage"):
					target_body.call("take_damage", dmg)
				elif target_body.has_method("kill") and dmg >= 100.0:
					target_body.call("kill")
		"heal":
			var amount = float(action.get("amount", 25.0))
			if target_body != null and is_instance_valid(target_body):
				if target_body.has_method("heal"):
					target_body.call("heal", amount)
		"teleport":
			var target_pos = Vector3(
				float(action.get("x", 0.0)),
				float(action.get("y", 5.0)),
				float(action.get("z", 0.0))
			)
			if target_body != null and is_instance_valid(target_body):
				target_body.global_position = target_pos
		"give_gear":
			var gear_id = String(action.get("gear", "linked_sword"))
			if target_body != null and is_instance_valid(target_body):
				if target_body.has_method("equip_gear_by_name"):
					target_body.call("equip_gear_by_name", gear_id)
		"add_points":
			var pts = int(action.get("points", 10))
			if target_body != null and is_instance_valid(target_body):
				if target_body.has_method("add_points"):
					target_body.call("add_points", pts)
		"screen_shake":
			var trauma = float(action.get("trauma", 0.6))
			var cam = get_viewport().get_camera_3d()
			if cam != null:
				for ch in cam.get_children():
					if ch.has_method("add_trauma"):
						ch.call("add_trauma", trauma)
		"change_color":
			var parent = get_parent()
			if parent is MeshInstance3D:
				var mi := parent as MeshInstance3D
				if mi.material_override is StandardMaterial3D:
					(mi.material_override as StandardMaterial3D).albedo_color = Color(action.get("color", "#ff0000"))
		"toggle_visibility":
			var parent = get_parent()
			if parent is Node3D:
				(parent as Node3D).visible = not (parent as Node3D).visible
		"print_message":
			print("[Orchestrator] ", action.get("message", "Triggered!"))
