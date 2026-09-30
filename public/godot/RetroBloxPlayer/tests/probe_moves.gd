extends SceneTree

## Movement rules probe — the playtest batch, verified in-engine:
##   1. login handoff frees the auth screen (the "Ready!" deadlock)
##   2. collide + press W = teleported ON TOP of a 1-stud step
##   3. ladder: no climb when facing away; climb when facing + holding W
##   4. ladder: SPACE jumps off (climb ends, real upward velocity)
##   5. fast 1.2s respawn + death camera focus
## Run with:  godot --headless --path . --script res://tests/probe_moves.gd

var failures: Array[String] = []
var step := 0
var wait_frames := 0
var main: Node3D
var player: CharacterBody3D
var _stair_top: float = 0.0
var _stair_tries: int = 0

func check(condition: bool, label: String) -> void:
        if condition:
                print("  ok    " + label)
        else:
                failures.append(label)
                printerr("  FAIL  " + label)

func _initialize() -> void:
        print("== RetroBlox movement rules probe ==")
        var scene: PackedScene = load("res://main.tscn")
        main = scene.instantiate()
        root.add_child(main)

func _drive(times: int, direction: Vector2, yaw: float) -> void:
        for i in range(times):
                player.drive(1.0 / 60.0, direction, yaw, player.consumed_jump, false)

func _process(_delta: float) -> bool:
        if wait_frames > 0:
                wait_frames -= 1
                return false
        match step:
                0:
                        # --- stage 1: the login handoff (no more "Ready!" deadlock) ---
                        step += 1
                        var api_script: GDScript = load("res://scripts/retroblox_api.gd")
                        var api: RefCounted = api_script.new("https://retro-blox.vercel.app")
                        main._finish_auth(api, "ProbeUser%d" % (randi() % 100000), "9999", {})
                        wait_frames = 30
                1:
                        check(main.auth == null, "login frees the auth card (no more 'Ready!' deadlock)")
                        # headless sandbox has no LAN: force the deterministic solo path
                        if main.phase != "playing":
                                main._begin_solo()
                        wait_frames = 30
                        check(main.players.size() == 1, "the world spawns the local player")
                        player = main.players.get(1) if main.players.has(1) else null
                        if player == null:
                                check(false, "local player exists")
                                _finish()
                                return true
                        check(player.alive, "player is alive and ready")
                        step += 1
                        wait_frames = 5
                2:
                        # --- stage 2: stair teleport — collide + press W ---
                        var step1: Node3D = _find_by_name(root, "Step1")
                        if step1 == null:
                                check(false, "stairs found in the map")
                                _finish()
                                return true
                        _stair_top = step1.global_position.y + 0.5   # 1-stud step top = y 1.0
                        # spawn right against the +Z face of Step1, facing -Z (yaw 0)
                        player.global_position = Vector3(0.0, 0.1, -15.2)
                        player.velocity = Vector3.ZERO
                        main.camera_yaw = 0.0
                        player.heading = 0.0
                        step += 1
                        _stair_tries = 0
                        wait_frames = 3
                3:
                        # hold W into the step; each round simulates ~1.5 s
                        _stair_tries += 1
                        _drive(90, Vector2(0.0, -1.0), 0.0)
                        if player.global_position.y >= _stair_top - 0.2 or _stair_tries >= 30:
                                check(player.global_position.y >= _stair_top - 0.2,
                                        "walk into a 1-stud step + W = on top (y=%.2f, top=%.2f)" % [player.global_position.y, _stair_top])
                                step += 1
                                wait_frames = 3
                4:
                        # --- stage 3: ladder rules — stand in front of the truss ---
                        var truss: Node3D = _find_by_name(root, "Truss")
                        if truss == null:
                                check(false, "truss found in the map")
                                _finish()
                                return true
                        # truss center (-14.5, 6, 0); player on its +Z side
                        player.global_position = Vector3(-14.5, 0.1, 1.6)
                        player.velocity = Vector3.ZERO
                        main.camera_yaw = PI     # looking AWAY from the truss
                        player.heading = PI
                        wait_frames = 20         # real physics ticks so the sensor sees the area
                        step += 1
                5:
                        _drive(30, Vector2(0.0, -1.0), PI)
                        check(not player.climbing, "facing AWAY from the ladder + W does NOT climb")
                        # now face the truss and hold W
                        player.global_position = Vector3(-14.5, 0.1, 1.6)
                        player.velocity = Vector3.ZERO
                        main.camera_yaw = 0.0
                        player.heading = 0.0
                        wait_frames = 10
                        step += 1
                6:
                        _drive(30, Vector2(0.0, -1.0), 0.0)
                        check(player.climbing, "facing the ladder + holding W climbs")
                        step += 1
                7:
                        # --- stage 4: SPACE jumps off the ladder (while climbing) ---
                        player.drive(1.0 / 60.0, Vector2.ZERO, 0.0, player.consumed_jump + 1, false)
                        check(not player.climbing, "SPACE ends climb mode")
                        check(player.velocity.y > 10.0, "SPACE on the ladder gives a real jump (vy=%.1f)" % player.velocity.y)
                        check(player._climb_cooldown > 0.0, "jump-off starts the re-latch cooldown")
                        step += 1
                8:
                        # --- stage 5: fast respawn + death camera focus ---
                        check(is_equal_approx(main.RESPAWN_SECONDS, 1.2), "respawn timer is the fast 1.2s")
                        var focus: Vector3 = player.death_focus()
                        check(focus != Vector3.ZERO, "death camera focus works")
                        _finish()
                        return true
        return false

func _find_by_name(node: Node, target: String) -> Node:
        if node.name == target:
                return node
        for child in node.get_children():
                var found := _find_by_name(child, target)
                if found != null:
                        return found
        return null

func _finish() -> void:
        if failures.is_empty():
                print("== ALL MOVEMENT PROBES PASSED ==")
                quit(0)
        else:
                printerr("== %d PROBE(S) FAILED ==" % failures.size())
                quit(1)
