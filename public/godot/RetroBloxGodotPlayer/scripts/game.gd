# game.gd — the RetroBlox Player entry point.
#
# Flow: login screen (server URL + your RetroBlox account) ->
#       GET /api/platform/me  -> the ACCOUNT-WIDE avatar ->
#       spawn the R6IK character wearing it, classic physics + chat.
#
# Everything is built here in code so the package ships tiny and
# readable — the world is a classic baseplate.
extends Node3D

var api: RetrobloxApi
var player: RetrobloxPlayer
var chat: RetrobloxChat

var _login_ui: CanvasLayer
var _server_edit: LineEdit
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _status: Label
var _login_btn: Button
var _logging_in := false


func _ready() -> void:
	_setup_input_map()
	_build_world()
	_build_login_ui()


# ---------------------------------------------------------------- input map

func _setup_input_map() -> void:
	_add_key("move_forward", [KEY_W, KEY_UP])
	_add_key("move_back", [KEY_S, KEY_DOWN])
	_add_key("move_left", [KEY_A, KEY_LEFT])
	_add_key("move_right", [KEY_D, KEY_RIGHT])
	_add_key("jump", [KEY_SPACE])


func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- the world

## A classic baseplate: flat green ground, soft sky, one sunny light.
func _build_world() -> void:
	# sky
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.38, 0.65, 0.95)
	sky_mat.sky_horizon_color = Color(0.83, 0.91, 0.96)
	sky_mat.ground_bottom_color = Color(0.2, 0.35, 0.2)
	sky_mat.ground_horizon_color = Color(0.73, 0.82, 0.7)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# sun
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	# the baseplate — a 512x512 stud slab with a proper collision body
	var ground := StaticBody3D.new()
	ground.name = "Baseplate"
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(512, 1, 512)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.66, 0.34)
	mesh.material_override = mat
	ground.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(512, 1, 512)
	col.shape = shape
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	ground.position = Vector3(0, -0.5, 0)  # top surface at y=0
	add_child(ground)


# ---------------------------------------------------------------- login UI

func _build_login_ui() -> void:
	_login_ui = CanvasLayer.new()
	_login_ui.layer = 20
	add_child(_login_ui)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_login_ui.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.94, 0.94)
	style.border_color = Color(0.8, 0.8, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var logo := Label.new()
	logo.text = "RETROBLOX"
	logo.add_theme_font_size_override("font_size", 30)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_color_override("font_color", Color(0.86, 0.2, 0.17))
	box.add_child(logo)

	var sub := Label.new()
	sub.text = "Sign in to wear your real avatar"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.3, 0.35, 0.4))
	box.add_child(sub)

	box.add_child(_spacer(4))

	_server_edit = _add_field(box, "Server URL", _guess_server_url())
	_user_edit = _add_field(box, "Username", "")
	_pass_edit = _add_field(box, "Password", "")
	_pass_edit.secret = true

	_login_btn = Button.new()
	_login_btn.text = "Log In"
	_login_btn.custom_minimum_size = Vector2(0, 34)
	_login_btn.pressed.connect(_on_login)
	box.add_child(_login_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.55, 0.1, 0.08))
	box.add_child(_status)

	var hint := Label.new()
	hint.text = "Your account avatar follows you into every game —\ndress it up on the website first."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	box.add_child(hint)


func _guess_server_url() -> String:
	# playing from the same machine the site runs on? default there.
	return "http://localhost:3000"


func _add_field(parent: Control, label_text: String, value: String) -> LineEdit:
	var lab := Label.new()
	lab.text = label_text
	lab.add_theme_font_size_override("font_size", 11)
	parent.add_child(lab)
	var edit := LineEdit.new()
	edit.text = value
	edit.custom_minimum_size = Vector2(0, 30)
	edit.text_submitted.connect(func(_t: String) -> void: _on_login())
	parent.add_child(edit)
	return edit


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _on_login() -> void:
	if _logging_in:
		return
	var server := _server_edit.text.strip_edges()
	var user := _user_edit.text.strip_edges()
	var passw := _pass_edit.text
	if server.begins_with("http") == false:
		server = "http://" + server
	if server.is_empty() or user.is_empty() or passw.is_empty():
		_status.text = "Fill in the server URL, username and password."
		return
	_logging_in = true
	_login_btn.disabled = true
	_status.add_theme_color_override("font_color", Color(0.2, 0.3, 0.45))
	_status.text = "Signing in..."

	api = RetrobloxApi.new(server)
	api.debug = OS.is_debug_build()

	var res: Dictionary = await api.login(user, passw)
	if not res.get("ok", false):
		_status.add_theme_color_override("font_color", Color(0.7, 0.12, 0.1))
		_status.text = String(res.get("error", "Login failed"))
		_logging_in = false
		_login_btn.disabled = false
		return

	_status.text = "Signed in as %s — fetching your avatar..." % api.username
	var me: Dictionary = await api.get_me()
	if not me.get("ok", false):
		_status.add_theme_color_override("font_color", Color(0.7, 0.12, 0.1))
		_status.text = String(me.get("error", "Could not load the avatar"))
		_logging_in = false
		_login_btn.disabled = false
		return

	_spawn_player(me.get("avatar", {}), String(me.get("username", api.username)))


# ---------------------------------------------------------------- the player

func _spawn_player(avatar: Dictionary, who: String) -> void:
	_login_ui.visible = false

	player = RetrobloxPlayer.new()
	player.name = "Player"
	player.api = api
	player.avatar = avatar
	player.display_name = who
	add_child(player)
	player.position = Vector3(0, 3, 0)
	await player.build_model()

	chat = RetrobloxChat.new()
	chat.player_name = who
	add_child(chat)
	chat.message_sent.connect(func(text: String) -> void:
		if player != null:
			player.say(text)
	)
	chat.add_message("[RetroBlox]", "Welcome %s! Press / to chat, WASD to move, Space to jump, right-drag to look." % who)
