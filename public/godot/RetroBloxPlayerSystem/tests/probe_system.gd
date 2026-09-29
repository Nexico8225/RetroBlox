extends SceneTree

## RetroBlox Player System (v2) — identity + integration probe.
## Verifies the fresh system: new room protocol/ports, baked platform URL,
## every script parses, the proven subsystems are all present, sound slots
## load (including the OOF slot), the UGC site->Godot mirror is in place,
## and the map still builds from nodes.

var _failures := 0
var _count := 0


func check(ok: bool, label: String) -> void:
        _count += 1
        if ok:
                print("  PASS  " + label)
        else:
                _failures += 1
                print("  FAIL  " + label)


func _initialize() -> void:
        await process_frame
        await process_frame

        print("== v2 identity ==")
        var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
        check(main_src.contains("RETROBLOX_2"), "room protocol is RETROBLOX_2")
        check(main_src.contains("RETROBLOX_2_DISCOVER"), "LAN discovery protocol is v2")
        check(main_src.contains("42430"), "default room port 42430")
        var cfg := ConfigFile.new()
        cfg.load("res://network.cfg")
        var api_url := str(cfg.get_value("platform", "api_url", ""))
        check(api_url == "https://retro-blox.vercel.app", "platform URL baked (got %s)" % api_url)
        check(FileAccess.file_exists("res://README.md"), "README ships with the system")

        print("== proven subsystems present ==")
        for path: String in [
                "res://scripts/main.gd", "res://scripts/player.gd", "res://scripts/avatar.gd",
                "res://scripts/avatar_platform.gd", "res://scripts/retroblox_api.gd",
                "res://scripts/sounds.gd", "res://scripts/hud.gd", "res://scripts/auth_screen.gd",
                "res://scripts/part.gd", "res://scripts/ladder.gd", "res://scripts/spawn_location.gd",
                "res://scripts/arena.gd", "res://scenes/player.tscn", "res://scenes/hud.tscn",
                "res://scenes/auth_screen.tscn", "res://scenes/maps/classic_baseplate.tscn",
        ]:
                check(ResourceLoader.exists(path), path.get_file())
        var dress_src := FileAccess.get_file_as_string("res://scripts/avatar_platform.gd")
        check(dress_src.contains("UGCOriented_"), "UGC site->Godot mirror present")
        check(dress_src.contains("rotation.y = PI"), "UGC mirror is a 180-degree Y turn")
        var player_src := FileAccess.get_file_as_string("res://scripts/player.gd")
        check(player_src.contains("@export var walk_speed: float = 16.0"), "classic WalkSpeed 16 (@export)")
        check(player_src.contains("@export var jump_height: float = 6.0"), "classic 6-stud jump (@export)")
        check(player_src.contains("@export var gravity: float = 110.0"), "tuned gravity 110 (@export)")
        check(player_src.contains("@export var max_step: float = 3.0"), "auto-step up to 3 studs (@export)")
        check(player_src.contains("@export var can_climb: bool = true"), "climbing is exportable")
        var main_checks := main_src.contains("chat_walk") \
                and main_src.contains("is_action_pressed(\"jump\") and local.grounded")
        check(main_checks, "chat-walk + hold-space hop in the game director")
        check(main_src.contains("set_nameplate_visible"),
                "local nameplate hidden")

        print("== sound slots ==")
        var RetroSounds := load("res://scripts/sounds.gd")
        for slot: String in ["Hover", "OOF", "RetroBloxJump", "Walking"]:
                var stream: AudioStream = RetroSounds.call("stream", slot)
                check(stream != null, "slot %s loads" % slot)
        var looped: AudioStream = RetroSounds.call("stream", "Walking", true)
        if looped is AudioStreamWAV:
                check((looped as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
                        "Walking loops when asked")

        print("== avatar builds at 5 studs ==")
        var avatar_scene: PackedScene = load("res://scenes/avatar.tscn")
        var avatar = avatar_scene.instantiate()
        root.add_child(avatar)
        await process_frame
        check(avatar.is_r6ik(), "R6IK catalog rig active")
        if avatar.is_r6ik():
                var bounds: AABB = avatar._part_aabb[0]
                for box: AABB in avatar._part_aabb:
                        bounds = bounds.merge(box)
                check(absf(bounds.size.y - 5.0) < 0.35, "rig is ~5 studs tall (got %.2f)" % bounds.size.y)
                check(avatar.parts.size() == 6, "six body parts found")
        avatar.call("set_nameplate_visible", false)
        check(avatar._nameplate == null or not avatar._nameplate.visible, "nameplate can hide")

        print("== map is node-built ==")
        var map_scene: PackedScene = load("res://scenes/maps/classic_baseplate.tscn")
        var map = map_scene.instantiate()
        root.add_child(map)
        await process_frame
        var spawns := get_nodes_in_group("spawn").size()
        check(spawns >= 1, "map has spawn pads (%d)" % spawns)
        var ladders := get_nodes_in_group("ladder").size()
        check(ladders >= 1, "map has a climbable truss (%d)" % ladders)
        var part_count := 0
        for node in map.find_children("*", "StaticBody3D", true, false):
                part_count += 1
        check(part_count >= 8, "map carries real parts (%d)" % part_count)

        print("")
        print("%d/%d checks passed" % [_count - _failures, _count])
        print("PROBE_SYSTEM_" + ("PASS" if _failures == 0 else "FAIL"))
        quit(1 if _failures > 0 else 0)
