class_name MovingPlatform
extends AnimatableBody3D
## MovingPlatform — Moveable block for RetroBlox
## Goes wherever you want with configurable target offset, optional stand-to-move trigger,
## and customizable easing.

const STUD := 0.28

## Where the block moves to (relative to start position in world studs/units)
@export var target_offset := Vector3(0.0, 0.0, 24.0 * STUD)

## When ticked (true), only moves when the player stands on top of it.
## When unticked (false), continuously moves back and forth.
@export var move_on_player_stand := false

## Duration in seconds to travel to destination
@export var move_duration := 3.5

## Pause duration at each endpoint before returning
@export var wait_time := 1.0

## Easing curve for the movement
## Options: "linear", "sine_in_out", "quad_in_out", "cubic_in_out", "bounce_out", "elastic_out"
@export var easing := "sine_in_out"

## Size of the block (in studs)
@export var block_size := Vector3(6.0, 1.2, 6.0) * STUD

## Brick color
@export var block_color := Color("f5cd30")

var _start_pos := Vector3.ZERO
var _target_pos := Vector3.ZERO
var _is_moving := false
var _at_target := false
var _player_on_board := false
var _sensor: Area3D
var _tween: Tween


func _ready() -> void:
        sync_to_physics = true
        _start_pos = global_position
        _target_pos = _start_pos + target_offset
        _build_mesh_and_collision()
        _build_stand_sensor()

        if not move_on_player_stand:
                _start_continuous_loop()


func _build_mesh_and_collision() -> void:
        collision_layer = 1
        collision_mask = 0

        var cs := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = block_size
        cs.shape = box
        add_child(cs)

        var mi := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = block_size
        mi.mesh = bm

        var mat := StandardMaterial3D.new()
        mat.albedo_color = block_color
        mat.roughness = 0.72
        var stud_tex: Texture2D = WorldBuilderScript.stud_texture()
        if stud_tex != null:
                mat.albedo_texture = stud_tex
                mat.uv1_triplanar = true
                mat.uv1_world_triplanar = true
                mat.uv1_scale = Vector3.ONE / STUD
        mi.material_override = mat
        add_child(mi)


func _build_stand_sensor() -> void:
        _sensor = Area3D.new()
        _sensor.name = "StandSensor"
        _sensor.collision_layer = 0
        _sensor.collision_mask = 4  # Player layer
        _sensor.monitorable = false

        var cs := CollisionShape3D.new()
        var box := BoxShape3D.new()
        # Flat trigger sensor hovering right above top surface
        box.size = Vector3(block_size.x * 0.95, 0.4 * STUD, block_size.z * 0.95)
        cs.shape = box
        cs.position = Vector3(0.0, block_size.y * 0.5 + 0.2 * STUD, 0.0)
        _sensor.add_child(cs)
        add_child(_sensor)

        _sensor.body_entered.connect(_on_player_entered)
        _sensor.body_exited.connect(_on_player_exited)


func _on_player_entered(body: Node3D) -> void:
        if body.name.contains("Player") or body.is_in_group("player"):
                _player_on_board = true
                if move_on_player_stand and not _is_moving:
                        _move_to_next()


func _on_player_exited(body: Node3D) -> void:
        if body.name.contains("Player") or body.is_in_group("player"):
                _player_on_board = false
                if move_on_player_stand and not _is_moving and _at_target:
                        # Return to start after a short delay when player steps off
                        get_tree().create_timer(wait_time).timeout.connect(func() -> void:
                                if not _player_on_board and not _is_moving and _at_target:
                                        _move_to_next())


func _get_ease_and_trans() -> Array:
        var trans := Tween.TRANS_SINE
        var ease_type := Tween.EASE_IN_OUT
        match easing.to_lower():
                "linear":
                        trans = Tween.TRANS_LINEAR
                        ease_type = Tween.EASE_IN_OUT
                "quad_in_out":
                        trans = Tween.TRANS_QUAD
                        ease_type = Tween.EASE_IN_OUT
                "cubic_in_out":
                        trans = Tween.TRANS_CUBIC
                        ease_type = Tween.EASE_IN_OUT
                "expo_in_out":
                        trans = Tween.TRANS_EXPO
                        ease_type = Tween.EASE_IN_OUT
                "bounce_out":
                        trans = Tween.TRANS_BOUNCE
                        ease_type = Tween.EASE_OUT
                "elastic_out":
                        trans = Tween.TRANS_ELASTIC
                        ease_type = Tween.EASE_OUT
                _:
                        trans = Tween.TRANS_SINE
                        ease_type = Tween.EASE_IN_OUT
        return [trans, ease_type]


func _move_to_next() -> void:
        if _is_moving:
                return
        _is_moving = true
        var dest := _start_pos if _at_target else _target_pos
        var ease_cfg := _get_ease_and_trans()

        if _tween != null and _tween.is_valid():
                _tween.kill()
        _tween = create_tween()
        _tween.set_trans(ease_cfg[0])
        _tween.set_ease(ease_cfg[1])
        _tween.tween_property(self, "global_position", dest, move_duration)
        _tween.finished.connect(func() -> void:
                _is_moving = false
                _at_target = not _at_target
                if not move_on_player_stand:
                        get_tree().create_timer(wait_time).timeout.connect(_move_to_next)
                elif not _at_target and _player_on_board:
                        # Stood on it again at start -> move
                        get_tree().create_timer(wait_time).timeout.connect(func() -> void:
                                if _player_on_board and not _is_moving:
                                        _move_to_next()))


func _start_continuous_loop() -> void:
        get_tree().create_timer(0.5).timeout.connect(_move_to_next)
