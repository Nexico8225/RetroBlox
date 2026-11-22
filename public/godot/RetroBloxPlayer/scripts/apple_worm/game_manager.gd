# res://scripts/apple_worm/game_manager.gd
class_name AppleWormGameManager
extends Node3D

signal level_completed
signal level_failed
signal moves_updated(count: int)

@export var current_level_path: String = ""

var level_instance: AppleWormLevel
var worm: WormCharacter
var camera: Camera3D
var sun: DirectionalLight3D
var env: WorldEnvironment

var segments: Array[Vector2i] = []
var facing: Vector2i = Vector2i.RIGHT
var move_count: int = 0
var is_animating: bool = false
var is_game_over: bool = false
var is_won: bool = false

# History for UNDO
var history_stack: Array[Dictionary] = []

func _ready() -> void:
	_setup_environment()
	if current_level_path != "":
		load_level(current_level_path)

func _setup_environment() -> void:
	# Camera
	camera = Camera3D.new()
	camera.name = "GameCamera"
	camera.current = true
	camera.position = Vector3(5, 5, 14)
	add_child(camera)

	# Sun
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_color = Color(1.0, 0.98, 0.92)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	# Environment Sky
	env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.65, 0.95) # Bright happy blue
	sky_mat.sky_horizon_color = Color(0.72, 0.88, 0.98)
	sky_mat.ground_bottom_color = Color(0.2, 0.45, 0.7)
	sky_mat.ground_horizon_color = Color(0.72, 0.88, 0.98)
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color(0.8, 0.85, 0.95)
	environment.ambient_light_energy = 0.8
	env.environment = environment
	add_child(env)

	# Worm
	worm = WormCharacter.new()
	worm.name = "Worm"
	add_child(worm)

func load_level(path: String) -> void:
	current_level_path = path
	is_animating = false
	is_game_over = false
	is_won = false
	move_count = 0
	history_stack.clear()

	if is_instance_valid(level_instance):
		level_instance.queue_free()

	var scene_res = load(path)
	if not scene_res:
		push_error("Failed to load level scene: " + path)
		return

	level_instance = scene_res.instantiate() as AppleWormLevel
	if not level_instance:
		push_error("Scene is not an AppleWormLevel: " + path)
		return

	add_child(level_instance)
	level_instance.scan_level_nodes()

	# Position camera
	camera.position = Vector3(level_instance.camera_center.x, level_instance.camera_center.y, level_instance.camera_distance)
	camera.look_at(Vector3(level_instance.camera_center.x, level_instance.camera_center.y, 0), Vector3.UP)

	# Spawn worm
	facing = level_instance.start_direction
	segments.clear()
	var cur = level_instance.start_tile
	# Tail extends opposite to initial facing
	var tail_step = -facing
	for i in range(level_instance.start_length):
		segments.append(cur + tail_step * i)

	worm.sync_segments(segments, facing, false)
	moves_updated.emit(move_count)

func _unhandled_input(event: InputEvent) -> void:
	if is_animating or is_won:
		return

	if event.is_action_pressed("ui_right") or event.is_action_pressed("move_right") or (event is InputEventKey and event.pressed and event.keycode == KEY_D):
		try_move(Vector2i.RIGHT)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left") or (event is InputEventKey and event.pressed and event.keycode == KEY_A):
		try_move(Vector2i.LEFT)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_up") or (event is InputEventKey and event.pressed and event.keycode == KEY_W):
		try_move(Vector2i.UP)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_down") or (event is InputEventKey and event.pressed and event.keycode == KEY_S):
		try_move(Vector2i.DOWN)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			restart_level()
		elif event.keycode == KEY_Z or event.keycode == KEY_U:
			undo_move()

func try_move(dir: Vector2i) -> void:
	if segments.size() < 1:
		return

	# Cannot directly reverse into segment 1 (neck)
	if segments.size() > 1 and (segments[0] + dir) == segments[1]:
		return

	var target = segments[0] + dir

	# Wall collision
	if level_instance.wall_tiles.has(target):
		return

	# Body / Tail collision:
	# If target is in ANY segment of the worm, cannot move because tail blocks!
	# Note: If not eating an apple, tail moves forward, but if tail is curled, it blocks!
	var will_eat_apple = level_instance.apple_tiles.has(target)
	for i in range(segments.size()):
		if i == segments.size() - 1 and not will_eat_apple:
			# Tail vacates its cell on normal step
			continue
		if segments[i] == target:
			return # BLOCKED by body/tail!

	# Save snapshot for UNDO
	_push_history()

	is_animating = true
	move_count += 1
	moves_updated.emit(move_count)
	facing = dir

	# Handle Apple Eating
	var apple_type_eaten = -1
	if will_eat_apple:
		var apple_node = level_instance.apple_tiles[target]
		apple_type_eaten = apple_node.apple_type
		level_instance.apple_tiles.erase(target)
		apple_node.visible = false

	# Advance worm body
	var new_segments: Array[Vector2i] = []
	new_segments.append(target)

	if apple_type_eaten == AppleItem.AppleType.RED:
		# Grow tail by +1 (keep all previous segments)
		for seg in segments:
			new_segments.append(seg)
	elif apple_type_eaten == AppleItem.AppleType.BLACK:
		# Shrink tail by -1 (minimum 2 segments)
		var keep_count = max(1, segments.size() - 1)
		for i in range(keep_count):
			new_segments.append(segments[i])
	elif apple_type_eaten == AppleItem.AppleType.GOLD:
		# 2x bigger! Double segments
		for seg in segments:
			new_segments.append(seg)
		for seg in segments:
			new_segments.append(seg)
	else:
		# Standard move (tail advances)
		for i in range(segments.size() - 1):
			new_segments.append(segments[i])

	segments = new_segments
	worm.sync_segments(segments, facing, true)

	# Wait for step animation
	await get_tree().create_timer(0.1).timeout

	# Check Win Condition
	if segments[0] == level_instance.portal_tile:
		_trigger_win()
		return

	# Run Cantilever Gravity check
	await _apply_gravity()

	# Check hazards / death
	_check_hazards()
	is_animating = false

func _apply_gravity() -> void:
	while not _is_worm_supported():
		# Fall 1 tile down
		var fallen: Array[Vector2i] = []
		for seg in segments:
			fallen.append(Vector2i(seg.x, seg.y - 1))
		segments = fallen
		worm.sync_segments(segments, facing, true)
		await get_tree().create_timer(0.08).timeout

		# Check if fallen out of bounds (abyss)
		var lowest_y = 999
		for seg in segments:
			lowest_y = min(lowest_y, seg.y)
		if lowest_y < -12:
			_trigger_fail()
			break

		# Check win condition during fall (if falls onto portal)
		if segments[0] == level_instance.portal_tile:
			_trigger_win()
			break

func _is_worm_supported() -> bool:
	for seg in segments:
		var below = Vector2i(seg.x, seg.y - 1)
		# Ground block below?
		if level_instance.wall_tiles.has(below):
			return true
		# Portal below?
		if below == level_instance.portal_tile:
			return true
	return false

func _check_hazards() -> void:
	for seg in segments:
		if level_instance.hazard_tiles.has(seg):
			_trigger_fail()
			return

func _push_history() -> void:
	var apples_state: Dictionary = {}
	for cell in level_instance.apple_tiles:
		apples_state[cell] = level_instance.apple_tiles[cell].apple_type

	var snapshot = {
		"segments": segments.duplicate(),
		"facing": facing,
		"moves": move_count,
		"apples": apples_state
	}
	history_stack.append(snapshot)

func undo_move() -> void:
	if history_stack.is_empty() or is_animating or is_won:
		return
	var snapshot = history_stack.pop_back()
	segments = snapshot["segments"]
	facing = snapshot["facing"]
	move_count = snapshot["moves"]
	is_game_over = false

	# Restore apples
	var saved_apples = snapshot["apples"]
	for child in level_instance.get_children():
		if child is AppleItem:
			var cell = Vector2i(round(child.position.x), round(child.position.y))
			if saved_apples.has(cell):
				child.visible = true
				level_instance.apple_tiles[cell] = child
			else:
				child.visible = false
				level_instance.apple_tiles.erase(cell)

	worm.sync_segments(segments, facing, false)
	moves_updated.emit(move_count)

func restart_level() -> void:
	load_level(current_level_path)

func _trigger_win() -> void:
	is_won = true
	# Victory swirl animation
	var tw = create_tween()
	tw.tween_property(worm.head_node, "scale", Vector3(0.1, 0.1, 0.1), 0.4)
	await tw.finished
	level_completed.emit()

func _trigger_fail() -> void:
	is_game_over = true
	level_failed.emit()
