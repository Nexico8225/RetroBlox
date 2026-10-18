extends Node3D
## RemotePlayer — another member playing the same place right now, delivered
## by the presence feed (GET /api/placechat/{placeId}). Their avatar dresses
## from the platform exactly like yours does; positions lerp between
## heartbeats (~every 4 seconds), so they glide instead of teleport.

const AvatarRigScript := preload("res://scripts/player/avatar_rig.gd")
const AvatarDresserScript := preload("res://scripts/player/avatar_dresser.gd")
const ChatBubbleScript := preload("res://scripts/player/chat_bubble.gd")

var user_id := ""
var username := ""
var avatar: Node3D
var bubble: ChatBubble

var _target_pos := Vector3.ZERO
var _target_heading := 0.0
var _prev_pos := Vector3.ZERO
var _has_target := false
var _time := 0.0
var _anim_accum := 0.0    # v12.3: walk-phase time owed to the rig
var _anim_clock := 0.0    # v12.3: seconds until the next far/offscreen anim tick


func _init() -> void:
        avatar = AvatarRigScript.new()
        avatar.name = "Avatar"
        add_child(avatar)
        bubble = ChatBubbleScript.new()
        bubble.name = "ChatBubble"
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
        # v12.3 PERF: the walk rig is CPU work every frame for EVERY remote
        # player. Players far away or not on screen (behind you, behind a
        # wall) tick their animation at a quiet 4 Hz instead — movement
        # still glides smoothly (that part never sleeps), and nobody can
        # see a distant walk cycle anyway. Banked phase time keeps the
        # stride length identical when they come back into view.
        _anim_accum += delta
        _anim_clock -= delta
        var on_stage := true
        var cam := get_viewport().get_camera_3d()
        if cam != null:
                var head := global_position + Vector3(0.0, 2.5, 0.0)
                on_stage = global_position.distance_to(cam.global_position) < 70.0 \
                        and cam.is_position_in_frustum(head)
        if on_stage or _anim_clock <= 0.0:
                var speed := before.distance_to(global_position) / maxf(delta, 0.0001)
                avatar.call("animate", maxf(_anim_accum, 0.0001), speed, true, false)
                _anim_accum = 0.0
                _anim_clock = 0.0 if on_stage else 0.25


## The classic white bubble over their head for a few seconds.
func show_bubble(message: String) -> void:
        bubble.show_text(message)


func fade_out() -> void:
        # simple leave: drop the node (a fade needs a Tween per player — keep it snappy)
        queue_free()
