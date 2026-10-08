extends Node3D
## RemotePlayer — another member playing the same place right now, delivered
## by the presence feed (GET /api/placechat/{placeId}). Their avatar dresses
## from the platform exactly like yours does; positions lerp between
## heartbeats (~every 4 seconds), so they glide instead of teleport.

const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")

var user_id := ""
var username := ""
var avatar: Node3D
var bubble: Label3D

var _target_pos := Vector3.ZERO
var _target_heading := 0.0
var _prev_pos := Vector3.ZERO
var _has_target := false
var _bubble_left := 0.0
var _time := 0.0


func _init() -> void:
        avatar = AvatarRigScript.new()
        avatar.name = "Avatar"
        add_child(avatar)
        bubble = Label3D.new()
        bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        bubble.pixel_size = 0.008
        bubble.font_size = 30
        bubble.outline_size = 8
        bubble.width = 220.0
        bubble.outline_modulate = Color(0, 0, 0, 0.9)
        bubble.visible = false
        bubble.position = Vector3(0.0, 6.8, 0.0)
        add_child(bubble)


func setup(p_user_id: String, p_name: String) -> void:
        user_id = p_user_id
        username = p_name
        name = "Remote_%s" % p_user_id
        avatar.call("setup", p_name)


## Dress from a /api/users/{id}/avatar payload ({} = classic noob).
func dress(api, payload: Dictionary) -> void:
        if payload.is_empty():
                return
        await AvatarDresserScript.apply(api, avatar, payload)


## Feed one presence heartbeat.
func update_state(pos: Vector3, heading: float) -> void:
        _prev_pos = global_position if _has_target else pos
        _target_pos = pos
        _target_heading = heading
        if not _has_target:
                global_position = pos
                _has_target = true


func _process(delta: float) -> void:
        _time += delta
        if not _has_target:
                return
        var k := 1.0 - exp(-6.0 * delta)
        var before := global_position
        global_position = global_position.lerp(_target_pos, k)
        avatar.rotation.y = lerp_angle(avatar.rotation.y, _target_heading, 1.0 - exp(-10.0 * delta))
        var speed := before.distance_to(global_position) / maxf(delta, 0.0001)
        avatar.call("animate", delta, speed, true, false)
        if _bubble_left > 0.0:
                _bubble_left -= delta
                bubble.visible = _bubble_left > 0.0


func show_bubble(message: String) -> void:
        var words := message.split(" ")
        var lines: Array[String] = []
        var current := ""
        for word in words:
                if current.length() + word.length() > 26 and not current.is_empty():
                        lines.append(current)
                        current = ""
                current += (" " if not current.is_empty() else "") + word.left(26)
                if lines.size() >= 3:
                        break
        if lines.size() < 3 and not current.is_empty():
                lines.append(current)
        bubble.text = "\n".join(lines)
        _bubble_left = 5.5
        bubble.visible = true


func fade_out() -> void:
        # simple leave: drop the node (a fade needs a Tween per player — keep it snappy)
        queue_free()
