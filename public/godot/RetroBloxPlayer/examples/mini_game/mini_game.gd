extends Node3D

## MY FIRST RETROBLOX GAME — the 60-second dev-kit quickstart.
##
## The whole loop other devs need, in one small file:
##   1. drop in scenes/auth_screen.tscn     -> the RetroBlox login card
##   2. on login, drop in scenes/player.tscn -> capsule + account avatar
##   3. dress the avatar from the platform   -> same rules as the website
##   4. build YOUR game around it            -> here: 8 coins on a platform
##
## Run: open this scene in the editor and press F6 (Run Current Scene).
## Copy this folder into your own project and start building.

const AuthScreenScene := preload("res://scenes/auth_screen.tscn")
const PlayerScene := preload("res://scenes/player.tscn")

const COIN_COUNT := 8

var api              # the RetrobloxApi instance handed over by the login card
var player           # the local CharacterBody3D from scenes/player.tscn
var score: int = 0
var jump_serial: int = 0

@onready var score_label: Label = %ScoreLabel
@onready var hint_label: Label = %HintLabel
@onready var coins_root: Node3D = %Coins


func _ready() -> void:
	randomize()
	hint_label.text = "WASD / arrows to move   ·   Space to jump\nLog in below with your RetroBlox account — or play as guest"
	_spawn_coins()
	# 1) the login card — the exact same scene the main player uses
	var auth := AuthScreenScene.instantiate()
	add_child(auth)
	auth.completed.connect(_on_login)
	auth.guest_requested.connect(_on_guest)


func _on_login(api_inst, _username: String, _user_id: String, avatar_payload: Dictionary) -> void:
	api = api_inst
	_spawn_player(avatar_payload)


func _on_guest() -> void:
	_spawn_player({})


func _spawn_player(avatar_payload: Dictionary) -> void:
	if player != null:
		return
	# 2) the classic player: capsule movement + account avatar + chat bubble
	player = PlayerScene.instantiate()
	add_child(player)
	player.initialize(1, "You")
	player.position = Vector3(0, 3, 0)
	# 3) dress from the platform payload (colors + shirt/pants templates + UGC)
	if not avatar_payload.is_empty():
		await player.dress_from_payload(api, avatar_payload)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	# 4) YOUR game drives the player — direction, camera yaw, jump serial
	var direction := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Input.is_action_just_pressed("jump"):
		jump_serial += 1
	player.drive(delta, direction, 0.0, jump_serial, false)
	player.reconcile(delta)
	# fell off the platform? classic respawn
	if player.global_position.y < -12.0:
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(0, 3, 0)


func _process(delta: float) -> void:
	coins_root.rotate_y(delta * 0.8)


# ------------------------------------------------------------- the mini game

func _spawn_coins() -> void:
	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = 0.55
	coin_mesh.bottom_radius = 0.55
	coin_mesh.height = 0.12
	var coin_mat := StandardMaterial3D.new()
	coin_mat.albedo_color = Color("ffd34e")
	coin_mat.metallic = 0.6
	coin_mat.roughness = 0.25
	coin_mat.emission_enabled = true
	coin_mat.emission = Color("8a6d00")
	coin_mesh.material = coin_mat
	for i in COIN_COUNT:
		var coin := Area3D.new()
		coin.collision_layer = 0
		coin.collision_mask = 4            # players live on physics layer 4
		var mi := MeshInstance3D.new()
		mi.mesh = coin_mesh
		coin.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 1.1
		shape.height = 1.6
		cs.shape = shape
		cs.position.y = 0.8
		coin.add_child(cs)
		var angle := TAU * float(i) / float(COIN_COUNT)
		var ring := 6.0 + float(i % 3) * 4.0
		coin.position = Vector3(cos(angle) * ring, 1.2 + float(i % 2), sin(angle) * ring)
		coin.body_entered.connect(_on_coin_taken.bind(coin))
		coins_root.add_child(coin)


func _on_coin_taken(body: Node3D, coin: Node3D) -> void:
	if body != player:
		return
	score += 1
	score_label.text = "Coins: %d / %d" % [score, COIN_COUNT]
	coin.queue_free()
