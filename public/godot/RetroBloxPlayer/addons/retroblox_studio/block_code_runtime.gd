@tool
extends Node

# RetroBlox Block Code Runtime
# Executes Scratch/Blockly-style visual block stacks attached to any 3D part or node.

@export var blocks_data: Array = []
@export var is_active: bool = true

var _timer_nodes: Array[Timer] = []
var _is_running_stack: bool = false


func _ready() -> void:
	if Engine.is_editor_hint() or not is_active:
		return
	_setup_triggers()
	_run_event("when_start", null)


func _setup_triggers() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return

	var needs_touch := _has_event("when_touched")
	var needs_click := _has_event("when_clicked")

	if needs_touch:
		if parent is Area3D:
			var a := parent as Area3D
			if not a.body_entered.is_connected(_on_body_entered):
				a.body_entered.connect(_on_body_entered)
		elif parent is CollisionObject3D:
			var area := Area3D.new()
			area.name = "_BlockCodeTouchArea"
			area.collision_layer = 0
			area.collision_mask = 4 # Players layer
			parent.call_deferred("add_child", area)
			var col := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = _estimate_parent_size(parent) + Vector3(0.4, 0.4, 0.4)
			col.shape = bs
			area.call_deferred("add_child", col)
			area.body_entered.connect(_on_body_entered)

	if needs_click and parent is CollisionObject3D:
		var co := parent as CollisionObject3D
		if not co.input_event.is_connected(_on_parent_input_event):
			co.input_event.connect(_on_parent_input_event)

	# Setup any "every_seconds" event blocks
	for blk in blocks_data:
		if blk is Dictionary and String(blk.get("op", "")) == "every_seconds":
			var interval := maxf(0.05, float(blk.get("seconds", 1.0)))
			var t := Timer.new()
			t.wait_time = interval
			t.autostart = true
			add_child(t)
			t.timeout.connect(func(): _run_event("every_seconds", null))
			_timer_nodes.append(t)


func _estimate_parent_size(parent: Node) -> Vector3:
	for ch in parent.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			return (ch as MeshInstance3D).mesh.get_aabb().size
	return Vector3(4.0, 2.0, 4.0)


func _has_event(op_name: String) -> bool:
	for blk in blocks_data:
		if blk is Dictionary and String(blk.get("op", "")) == op_name:
			return true
	return false


func _on_body_entered(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body.has_method("take_damage") or body.is_in_group("player") or body.name.to_lower().contains("player"):
		_run_event("when_touched", body)


func _on_parent_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var player := _find_local_player()
		_run_event("when_clicked", player)


func _find_local_player() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var players := tree.get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node3D:
		return players[0] as Node3D
	return tree.root.find_child("LocalPlayer", true, false) as Node3D


func _run_event(event_op: String, target_body: Node3D) -> void:
	if not is_inside_tree():
		return
	var in_matching_event := false
	var i := 0
	while i < blocks_data.size():
		var blk_var = blocks_data[i]
		if not (blk_var is Dictionary):
			i += 1
			continue
		var blk := blk_var as Dictionary
		var op := String(blk.get("op", ""))
		if op in ["when_start", "when_touched", "when_clicked", "every_seconds"]:
			in_matching_event = (op == event_op)
			i += 1
			continue
		if not in_matching_event:
			i += 1
			continue

		if op == "repeat":
			var count := maxi(1, int(blk.get("count", 3)))
			var end_idx := _find_matching_end(i)
			var sub_blocks: Array = blocks_data.slice(i + 1, end_idx)
			for _r in range(count):
				if not is_inside_tree():
					return
				await _execute_sequence(sub_blocks, target_body)
			i = end_idx + 1
			continue
		elif op == "end_repeat":
			i += 1
			continue

		await _execute_single_block(blk, target_body)
		i += 1


func _find_matching_end(start_idx: int) -> int:
	var depth := 1
	var j := start_idx + 1
	while j < blocks_data.size():
		var b = blocks_data[j]
		if b is Dictionary:
			var op := String(b.get("op", ""))
			if op == "repeat":
				depth += 1
			elif op == "end_repeat":
				depth -= 1
				if depth <= 0:
					return j
		j += 1
	return blocks_data.size()


func _execute_sequence(seq: Array, target_body: Node3D) -> void:
	var i := 0
	while i < seq.size():
		if not is_inside_tree():
			return
		var b = seq[i]
		if b is Dictionary:
			await _execute_single_block(b as Dictionary, target_body)
		i += 1


func _execute_single_block(blk: Dictionary, target_body: Node3D) -> void:
	var op := String(blk.get("op", ""))
	var player := target_body if (target_body != null and is_instance_valid(target_body)) else _find_local_player()
	var parent := get_parent()

	match op:
		"wait":
			var secs := maxf(0.01, float(blk.get("seconds", 1.0)))
			if is_inside_tree():
				await get_tree().create_timer(secs).timeout
		"teleport_player":
			if player != null and is_instance_valid(player):
				player.global_position = Vector3(
					float(blk.get("x", 0.0)),
					float(blk.get("y", 5.0)),
					float(blk.get("z", 0.0))
				)
		"push_player":
			if player != null and is_instance_valid(player):
				var imp := Vector3(
					float(blk.get("x", 0.0)),
					float(blk.get("y", 40.0)),
					float(blk.get("z", 0.0))
				)
				if player.has_method("push"):
					player.call("push", imp)
				elif player.has_method("launch"):
					player.call("launch", imp)
				elif "velocity" in player:
					player.set("velocity", imp)
		"set_walk_speed":
			if player != null and is_instance_valid(player) and "walk_speed" in player:
				player.set("walk_speed", float(blk.get("speed", 24.0)))
		"set_jump_power":
			if player != null and is_instance_valid(player) and "jump_power" in player:
				player.set("jump_power", float(blk.get("power", 65.0)))
		"damage_player":
			var dmg := float(blk.get("amount", 25.0))
			if player != null and is_instance_valid(player):
				if player.has_method("take_damage"):
					player.call("take_damage", dmg)
				elif player.has_method("kill") and dmg >= 100.0:
					player.call("kill")
		"heal_player":
			var heal_amt := float(blk.get("amount", 25.0))
			if player != null and is_instance_valid(player) and player.has_method("heal"):
				player.call("heal", heal_amt)
		"give_gear":
			var gear_name := String(blk.get("gear", "ClassicSword"))
			if player != null and is_instance_valid(player):
				if player.has_method("give_gear"):
					player.call("give_gear", gear_name)
				elif player.has_method("equip_gear"):
					player.call("equip_gear", gear_name)
		"add_tix":
			var tix := int(blk.get("amount", 10))
			var sess := get_node_or_null("/root/Session")
			if sess != null and sess.has_method("add_tix"):
				sess.call("add_tix", tix)
		"set_part_color":
			var col := Color.from_string(String(blk.get("color", "#ff3b30")), Color.RED)
			if parent != null:
				_apply_color_recursive(parent, col)
		"set_part_visible":
			var vis := bool(blk.get("visible", true))
			if parent is Node3D:
				(parent as Node3D).visible = vis
			if parent is CollisionObject3D:
				for ch in parent.get_children():
					if ch is CollisionShape3D:
						(ch as CollisionShape3D).disabled = not vis
		"rotate_part":
			if parent is Node3D:
				var p3 := parent as Node3D
				p3.rotate_x(deg_to_rad(float(blk.get("x", 0.0))))
				p3.rotate_y(deg_to_rad(float(blk.get("y", 15.0))))
				p3.rotate_z(deg_to_rad(float(blk.get("z", 0.0))))
		"camera_shake":
			var intensity := float(blk.get("intensity", 0.5))
			var cam := get_viewport().get_camera_3d()
			if cam != null and cam.has_method("shake"):
				cam.call("shake", intensity)
		"play_sound":
			var snd := String(blk.get("sound", "click"))
			var sfx := get_node_or_null("/root/Sfx")
			if sfx != null:
				match snd:
					"click":
						if sfx.has_method("play_click"): sfx.call("play_click")
					"goal":
						if sfx.has_method("play_goal"): sfx.call("play_goal")
					"oof":
						if sfx.has_method("play_oof"): sfx.call("play_oof")
					"jump":
						if sfx.has_method("play_jump"): sfx.call("play_jump")
		"print_msg":
			print("[BlockCode] ", String(blk.get("message", "Hello RetroBlox!")))


func _apply_color_recursive(node: Node, col: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is ShaderMaterial:
			(mi.material_override as ShaderMaterial).set_shader_parameter("albedo", col)
		elif mi.material_override is StandardMaterial3D:
			(mi.material_override as StandardMaterial3D).albedo_color = col
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mi.material_override = mat
	for ch in node.get_children():
		_apply_color_recursive(ch, col)
