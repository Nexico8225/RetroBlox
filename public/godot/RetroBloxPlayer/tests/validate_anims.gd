extends SceneTree

## Animation slot system validation — run with:
##   godot --headless --path . --script res://tests/validate_anims.gd
##
## Checks: rig clips slot-map correctly, name normalization + alias rules,
## user clip override (built in-memory, no files needed), loop rules, and
## that play_slot actually plays the resolved clips.

var passed: int = 0
var failed: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
        if ok:
                passed += 1
                print("PASS  ", name)
        else:
                failed += 1
                print("FAIL  ", name, "  ", detail)

func _initialize() -> void:
        var Rbx := load("res://scripts/rbx_animations.gd")

        # ---- 1) name normalization
        var probe: RefCounted = Rbx.new()
        check("norm: Left_Arm", probe._norm("Left_Arm") == "left arm")
        check("norm: $tag stripping", probe._norm("Torso$R6IK") == "torso")
        check("norm: My-Cool Walk 2", probe._norm("My-Cool Walk 2") == "my cool walk")
        check("norm: digits trimmed", probe._norm("Plane_002") == "plane")

        # ---- 2) alias mapping on a fake rig clip set
        var fake_clips := {
                "Old_Idle": Animation.new(), "Idle": Animation.new(),
                "Old_Walk": Animation.new(), "Walk": Animation.new(),
                "Run": Animation.new(), "Old_Jump": Animation.new(),
                "Climb": Animation.new(), "Sit": Animation.new(),
        }
        var slots: RefCounted = Rbx.new()
        slots._apply_candidates(fake_clips, false)
        # rig's old clips keep the classic feel
        check("slot idle -> Old_Idle", slots.resolve("idle") == "Old_Idle", slots.describe())
        check("slot walk -> Old_Walk", slots.resolve("walk") == "Old_Walk")
        check("slot jump -> Old_Jump", slots.resolve("jump") == "Old_Jump")
        check("slot climb -> Climb", slots.resolve("climb") == "Climb")
        check("slot run -> Run", slots.resolve("run") == "Run")
        check("slot sit -> Sit", slots.resolve("sit") == "Sit")
        # fall falls back to jump (the classic: falling holds the jump pose)
        check("slot fall -> falls back to jump", slots.resolve("fall") == "Old_Jump")
        check("has_slot", slots.has_slot("walk") and not slots.has_slot("nope"))

        # ---- 3) user clip override via a live AnimationPlayer
        var player := AnimationPlayer.new()
        var lib := AnimationLibrary.new()
        for clip_name in fake_clips:
                lib.add_animation(clip_name, fake_clips[clip_name])
        player.add_animation_library("", lib)
        root.add_child(player)
        var loader: RefCounted = Rbx.new()
        loader.attach(player)
        # inject a user clip named like a Blender export ("Walk 2" -> walk)
        var user_walk := Animation.new()
        lib.add_animation("user_1_Walk 2", user_walk)
        loader._remap_all_slots(player)
        check("user clip wins walk slot", loader.resolve("walk") == "user_1_Walk 2", loader.describe())
        check("idle untouched by user walk", loader.resolve("idle") == "Old_Idle")

        # ---- 4) play_slot drives the AnimationPlayer
        var played: bool = loader.play_slot(player, "walk", 0.16, 1.5)
        check("play_slot plays resolved clip", played and player.current_animation == "user_1_Walk 2")
        check("play_slot sets speed_scale", is_equal_approx(player.speed_scale, 1.5))
        loader.play_slot(player, "idle", 0.16, 1.0)
        check("play_slot switches slots", player.current_animation == "Old_Idle")
        check("play_slot missing slot is a no-op", not loader.play_slot(player, "nope", 0.1, 1.0))

        # ---- 5) the avatar wires everything up
        var avatar_scene: PackedScene = load("res://scenes/avatar.tscn")
        var avatar = avatar_scene.instantiate()
        root.add_child(avatar)
        await process_frame
        if avatar.is_r6ik():
                check("avatar rig slots: idle", avatar.anims.has_slot("idle"))
                check("avatar rig slots: walk", avatar.anims.has_slot("walk"))
                check("avatar rig slots: jump", avatar.anims.has_slot("jump"))
                check("avatar rig slots: climb", avatar.anims.has_slot("climb"))
                # loop rules: walk cycles, jump holds
                var walk_clip: String = avatar.anims.resolve("walk")
                var jump_clip: String = avatar.anims.resolve("jump")
                var walk_anim: Animation = avatar._anim_player.get_animation(walk_clip)
                var jump_anim: Animation = avatar._anim_player.get_animation(jump_clip)
                check("walk clip loops", walk_anim.loop_mode == Animation.LOOP_LINEAR)
                check("jump clip holds (no loop)", jump_anim.loop_mode == Animation.LOOP_NONE)
                # animation actually advances the walk cycle
                avatar.animate(0.1, 16.0, true, false)
                check("avatar animate plays walk", avatar._anim_player.current_animation == walk_clip,
                        avatar._anim_player.current_animation)
        else:
                check("avatar uses R6IK rig", false, "FBX not imported — run --import first")

        print("%d passed, %d failed" % [passed, failed])
        quit(1 if failed > 0 else 0)
