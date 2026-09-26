# RetrobloxPlayer — the classic character controller, 1:1 with old Roblox.
#
#   WALK SPEED   16 studs/s   (classic default)
#   JUMP POWER   50           (classic JumpPower)
#   GRAVITY      196.2        (classic workspace gravity)
#
# Camera: third-person orbit — hold RIGHT mouse to turn, wheel to zoom
# (0.5..40 studs), exactly like the classic camera. The character faces
# the direction it moves.
#
# Animations come from the official R6IK.fbx and use the ORIGINAL classic
# clips: old_walk, old_jump, old_idle.
class_name RetrobloxPlayer
extends CharacterBody3D

const WALK_SPEED := 16.0
const JUMP_VELOCITY := 50.0
const GRAVITY := 196.2
const TURN_SPEED := 12.0          # how fast the character faces movement
const CAMERA_MIN := 0.5
const CAMERA_MAX := 40.0
const CAMERA_DEFAULT := 12.5

var api: RetrobloxApi
var avatar: Dictionary = {}
var display_name := "Player"

var _yaw_pivot: Node3D
var _spring: SpringArm3D
var _camera: Camera3D
var _model_root: Node3D
var _anim: AnimationPlayer
var _current_anim := ""
var _bubble: Label3D
var _bubble_timer := 0.0


func _ready() -> void:
        # a 5-stud R6 capsule (radius 1, height 5, standing on y=0)
        var shape := CapsuleShape3D.new()
        shape.radius = 1.0
        shape.height = 5.0
        var collider := CollisionShape3D.new()
        collider.shape = shape
        collider.position = Vector3(0, 2.5, 0)
        add_child(collider)

        # camera rig: yaw pivot on the character, spring arm behind the head
        _yaw_pivot = Node3D.new()
        _yaw_pivot.name = "CameraYaw"
        _yaw_pivot.position = Vector3(0, 4.5, 0)
        add_child(_yaw_pivot)
        _spring = SpringArm3D.new()
        _spring.spring_length = CAMERA_DEFAULT
        _spring.collision_mask = 1
        _yaw_pivot.add_child(_spring)
        _camera = Camera3D.new()
        _camera.fov = 70.0
        _camera.current = true
        _spring.add_child(_camera)
        _pitch(-0.18)

        # chat bubble above the head
        _bubble = Label3D.new()
        _bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        _bubble.position = Vector3(0, 6.1, 0)
        _bubble.pixel_size = 0.01
        _bubble.font_size = 40
        _bubble.outline_size = 8
        _bubble.modulate = Color.WHITE
        _bubble.outline_modulate = Color(0, 0, 0, 0.85)
        _bubble.text = ""
        add_child(_bubble)


## Build the character model: the official R6IK.fbx, normalized to 5 studs,
## dressed with the account avatar (colors + clothing + face + 3D UGC).
func build_model() -> void:
        _model_root = Node3D.new()
        _model_root.name = "Rig"
        add_child(_model_root)

        var packed: PackedScene = load("res://models/R6IK.fbx")
        if packed == null:
                push_error("[RetroBlox] R6IK.fbx failed to import — open the project in the Godot editor once.")
                return
        var fbx: Node3D = packed.instantiate() as Node3D
        _model_root.add_child(fbx)

        # the Blender export faces -Z; turn it to face +Z like the website does
        fbx.rotation.y = PI

        # normalize: 5 studs tall, feet on y=0, centered on x/z
        var aabb := _model_aabb(fbx)
        if aabb.size.y > 0.001:
                var s := AvatarBuilder.RIG_HEIGHT / aabb.size.y
                fbx.scale = Vector3.ONE * s
                fbx.position = Vector3(
                        -(aabb.get_center().x) * s,
                        -aabb.position.y * s,
                        -(aabb.get_center().z) * s
                )

        # find the animation player + classic clips
        _anim = _find_anim_player(fbx)
        if _anim:
                _play("old_idle", true)

        # dress the rig with the account avatar (network work, then done)
        if api != null and not avatar.is_empty():
                await AvatarBuilder.apply(api, _model_root, avatar)


func _model_aabb(root: Node3D) -> AABB:
        var total := AABB()
        var first := true
        var stack := [root]
        while stack.size() > 0:
                var node: Node = stack.pop_back()
                if node is MeshInstance3D and (node as MeshInstance3D).mesh:
                        var mi := node as MeshInstance3D
                        var aabb: AABB = mi.transform * mi.mesh.get_aabb()
                        if first:
                                total = aabb
                                first = false
                        else:
                                total = total.merge(aabb)
                for child in node.get_children():
                        stack.append(child)
        return total


func _find_anim_player(root: Node) -> AnimationPlayer:
        var stack := [root]
        while stack.size() > 0:
                var node: Node = stack.pop_back()
                if node is AnimationPlayer:
                        return node
                for child in node.get_children():
                        stack.append(child)
        return null


## Show a chat bubble above the head for a few seconds.
func say(text: String) -> void:
        _bubble.text = text
        _bubble_timer = 6.0


func _physics_process(delta: float) -> void:
        if not is_on_floor():
                velocity.y -= GRAVITY * delta
                _play("old_jump")
        else:
                var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
                var dir := Vector3(input.x, 0, input.y)
                # camera-relative movement (classic Roblox: WASD relative to camera)
                dir = (_yaw_pivot.global_transform.basis * dir)
                dir.y = 0
                dir = dir.normalized() * input.length()
                if Input.is_action_just_pressed("jump"):
                        velocity.y = JUMP_VELOCITY
                        _play("old_jump", true)
                velocity.x = dir.x * WALK_SPEED
                velocity.z = dir.z * WALK_SPEED
                if dir.length() > 0.05:
                        if _current_anim != "old_walk":
                                _play("old_walk")
                        # face the movement direction (+Z is the model's forward)
                        var target_yaw := atan2(dir.x, dir.z)
                        _model_root.rotation.y = lerp_angle(_model_root.rotation.y, target_yaw, TURN_SPEED * delta)
                else:
                        if _current_anim != "old_idle":
                                _play("old_idle")

        move_and_slide()

        if _bubble_timer > 0.0:
                _bubble_timer -= delta
                if _bubble_timer <= 0.0:
                        _bubble.text = ""


func _unhandled_input(event: InputEvent) -> void:
        # right-mouse drag = orbit the camera (classic)
        if event is InputEventMouseButton:
                if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
                        _spring.spring_length = clampf(_spring.spring_length - 1.0, CAMERA_MIN, CAMERA_MAX)
                elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
                        _spring.spring_length = clampf(_spring.spring_length + 1.0, CAMERA_MIN, CAMERA_MAX)
        if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
                _yaw_pivot.rotation.y -= event.relative.x * 0.008
                _pitch(_pitch_current + event.relative.y * 0.008)


var _pitch_current := -0.18

func _pitch(value: float) -> void:
        _pitch_current = clampf(value, -1.2, 0.9)
        _spring.rotation.x = _pitch_current


# ---------------------------------------------------------------- animations

## Play one of the classic clips by fuzzy name (old_walk / old_jump / old_idle).
func _play(classic: String, restart := false) -> void:
        if _anim == null:
                return
        if _current_anim == classic and not restart:
                return
        var anims := _anim.get_animation_list()
        var pick := ""
        for a in anims:
                if a.to_lower().contains(classic):
                        pick = a
                        break
        if pick == "":
                # graceful fallbacks so the character never freezes without clips
                if classic == "old_jump":
                        return
                for a in anims:
                        if classic == "old_idle" and a.to_lower().contains("walk"):
                                continue
                        pick = a
                        break
        if pick == "":
                return
        _current_anim = classic
        _anim.play(pick, 0.15)
