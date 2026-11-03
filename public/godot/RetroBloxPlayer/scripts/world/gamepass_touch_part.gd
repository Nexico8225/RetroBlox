class_name GamePassTouchPart
extends Node3D
## Attach to any 3D Part or StaticBody3D:
## If LocalPlayer collides -> Opens the Roblox-style GamePass Popup for the chosen .tres file
## in res://gamepasses/ (e.g. "VIP") and deducts Tix from the player's account when bought!

signal purchased(pass_name: String, cost_tix: int)

const GamePassPromptScript: Script = preload("res://scripts/ui/gamepass_prompt.gd")

## Name of the .tres file inside res://gamepasses/ (e.g. "VIP", "SpeedBoost", "SuperJump", "GoldenSword")
@export var gamepass_name: String = "VIP"

## Optional public overrides (leave blank / -1 to use the values from res://gamepasses/<gamepass_name>.tres)
@export var custom_title: String = ""
@export_multiline var custom_description: String = ""
@export var custom_cost: int = -1
@export var custom_icon: Texture2D = null
@export var recipient_username: String = ""

var _last_touch_msec: int = 0


func _ready() -> void:
	_setup_collision_detector()


func _setup_collision_detector() -> void:
	if Engine.is_editor_hint():
		return
	var existing_area: Area3D = get_node_or_null("GamePassTouchArea") as Area3D
	if existing_area == null:
		existing_area = Area3D.new()
		existing_area.name = "GamePassTouchArea"
		existing_area.collision_layer = 0
		existing_area.collision_mask = 0xFFFFFFFF
		add_child(existing_area)
		var added_shape: bool = false
		for ch in get_children():
			if ch is CollisionShape3D:
				var dup: CollisionShape3D = (ch as CollisionShape3D).duplicate() as CollisionShape3D
				dup.scale = Vector3(1.08, 1.25, 1.08)
				existing_area.add_child(dup)
				added_shape = true
		if not added_shape:
			var fallback_cs: CollisionShape3D = CollisionShape3D.new()
			var box: BoxShape3D = BoxShape3D.new()
			box.size = Vector3(4.5, 2.5, 4.5)
			fallback_cs.shape = box
			fallback_cs.position = Vector3(0, 1.0, 0)
			existing_area.add_child(fallback_cs)

	if not existing_area.body_entered.is_connected(_on_body_entered):
		existing_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body == null or Engine.is_editor_hint():
		return
	# Check if the colliding body is LocalPlayer (or player character)
	var is_local_player: bool = (body is CharacterBody3D) and (body.name == "LocalPlayer" or body.get_script() != null)
	if not is_local_player:
		return

	var now: int = Time.get_ticks_msec()
	if now - _last_touch_msec < 1500:
		return
	_last_touch_msec = now

	var prompt: CanvasLayer = GamePassPromptScript.call(
		"popup",
		gamepass_name,
		custom_title,
		custom_description,
		custom_cost,
		custom_icon,
		recipient_username
	) as CanvasLayer
	if prompt != null and not prompt.is_connected("pass_purchased", _on_pass_purchased):
		prompt.connect("pass_purchased", _on_pass_purchased)


func _on_pass_purchased(p_name: String, p_cost: int) -> void:
	if p_name == gamepass_name:
		purchased.emit(p_name, p_cost)
