extends SceneTree

## Guards the FULL climb contract, on real physics, frame by frame:
##   - entry gate: only W + FACING the face + close to it climbs
##   - riding: W up, S down, no input hangs
##   - jump-off: SPACE leaps away and a cooldown keeps you off while you fall
##   - crest: riding past a segment's top vaults onto the ledge
##   - bottom: sliding past the bottom lets go
##   - stacking: two rungs with a 1 stud gap chain into one continuous climb
##   - auto-ladder: thin+gapped parts climb, flush walls stay plain
##   - sizes: capsule and avatar are exactly 5 studs (1 stud = 0.28 m)
##   - lighting: classic Roblox environment (linear, grey ambient, strong sun)
## Run with:
##   godot --headless --path . --script res://tests/probe_climb.gd

const ArenaScript := preload("res://scripts/arena.gd")
const LadderScene := preload("res://scenes/ladder.tscn")
const PlayerScene := preload("res://scenes/player.tscn")

const DELTA: float = 1.0 / 60.0

var failures: Array = []


func _ok(condition: bool, label: String) -> void:
        if condition:
                print("ok: ", label)
        else:
                failures.append(label)
                print("FAIL: ", label)


func _first_zone(part: Node) -> Area3D:
        var zones: Array = part.find_children("AutoClimbArea*", "Area3D", false, false)
        return zones[0] as Area3D if not zones.is_empty() else null


func _make_part(parent: Node, part_name: String, pos: Vector3, part_size: Vector3) -> RetroPart:
        var part := RetroPart.new()
        part.name = part_name
        part.size = part_size
        part.color = Color("a3a2a5")
        parent.add_child(part)
        part.global_position = pos
        return part


## Drive the player for N physics frames with a fixed input.
## `jumps` bumps jump_serial on the first frame only.
func _drive(player: CharacterBody3D, frames: int, direction: Vector2, yaw: float, jumps: int = 0) -> void:
        for i in range(frames):
                var serial: int = 1 if (jumps > 0 and i == 0) else 0
                player.drive(DELTA, direction, yaw, serial, false)
                await physics_frame


func _reset(player: CharacterBody3D, pos: Vector3) -> void:
        player.global_position = pos
        player.velocity = Vector3.ZERO


func _initialize() -> void:
        await process_frame

        # ---- a real arena: environment + baseplate map ----
        var world := Node3D.new()
        world.name = "ProbeArena"
        world.set_script(ArenaScript)
        root.add_child(world)
        await process_frame
        await process_frame
        var map_root: Node = world.get("_map_root")
        if map_root == null:
                print("FAIL: arena has no map root")
                quit(1)
                return

        # ---- the classic rig: wall + rungs hanging off it ----
        # wall occupies z in [4.5, 5.5], open face pointing -Z
        _make_part(map_root, "Wall", Vector3(0.0, 6.0, 5.0), Vector3(12.0, 12.0, 1.0))
        # rung 1: 2 studs deep, exactly 1 stud of air to the wall
        var rung1 := _make_part(map_root, "Rung1", Vector3(0.0, 4.0, 2.5), Vector3(4.0, 0.6, 2.0))
        # rung 2: one stud of air ABOVE rung 1 (the stacked-studs build)
        var rung2 := _make_part(map_root, "Rung2", Vector3(0.0, 5.6, 2.5), Vector3(4.0, 0.6, 2.0))
        # flush rung: touches the wall — a wall, not a ladder
        var flush_rung := _make_part(map_root, "FlushRung", Vector3(6.0, 4.0, 3.5), Vector3(4.0, 0.6, 2.0))
        # FLOATING STACK — two 1-stud-deep platforms stacked with a 1 stud
        # vertical gap and NO wall anywhere. The user's exact build: walk to
        # the edge, face it, W climbs, the climb chains across the gap.
        # (Placed in an empty corner — the map's own LadderTower lives at x=-14.)
        var slab1 := _make_part(map_root, "Slab1", Vector3(-40.0, 3.5, 20.0), Vector3(1.0, 3.0, 4.0))
        var slab2 := _make_part(map_root, "Slab2", Vector3(-40.0, 7.5, 20.0), Vector3(1.0, 3.0, 4.0))
        # a real truss: 12 studs tall, spans y in [-2, 10]
        var truss := LadderScene.instantiate() as Node3D
        truss.name = "Truss"
        map_root.add_child(truss)
        truss.global_position = Vector3(12.0, 4.0, 0.0)

        await world._auto_ladder_pass()

        # ---- auto-ladder grants ----
        var z1 := _first_zone(rung1)
        var z2 := _first_zone(rung2)
        _ok(z1 != null and z1.is_in_group("ladder"), "rung 1 (1 stud gap, 2 deep) is climbable")
        _ok(z2 != null, "rung 2 (stacked, 1 stud gap) is climbable")
        _ok(_first_zone(flush_rung) == null,
                "flush rung (no gap) stays unclimbable — backface guard")
        if z1 != null:
                _ok(z1.get_meta("outward", Vector3.ZERO) == Vector3.FORWARD,
                        "rung 1 climb face points away from the wall")
        # ---- the floating stack: thin platforms climb from ANY open side ----
        var slab1_zones: Array = slab1.find_children("AutoClimbArea*", "Area3D", false, false)
        var slab2_zones: Array = slab2.find_children("AutoClimbArea*", "Area3D", false, false)
        _ok(slab1_zones.size() >= 2, "floating slab 1 gets a zone per open side (%d)" % slab1_zones.size())
        _ok(slab2_zones.size() >= 2, "floating slab 2 gets a zone per open side (%d)" % slab2_zones.size())
        var slab1_outs: Array = []
        for zone in slab1_zones:
                slab1_outs.append(zone.get_meta("outward", Vector3.ZERO))
        _ok(slab1_outs.has(Vector3.RIGHT) and slab1_outs.has(Vector3.LEFT),
                "slab 1 climb faces are the thin (open) sides")

        # ---- the player ----
        var player := PlayerScene.instantiate() as CharacterBody3D
        root.add_child(player)
        player.initialize(1, "Probe")
        await physics_frame
        await physics_frame

        # ===== 1. the facing gate =====
        _reset(player, Vector3(0.0, 0.05, 0.6))
        await _drive(player, 12, Vector2(0, -1), 0.0)          # facing AWAY from the face
        _ok(not player.climbing, "facing away + W does not climb")
        _reset(player, Vector3(0.0, 0.05, 0.6))
        await _drive(player, 12, Vector2(0, -1), PI / 2.0)     # facing sideways
        _ok(not player.climbing, "facing sideways + W does not climb")

        # ===== 2. entry: face the rung, press W =====
        _reset(player, Vector3(0.0, 0.05, 0.6))
        await _drive(player, 15, Vector2(0, -1), PI)           # wish = +Z, into the face
        _ok(player.climbing, "facing the rung + W climbs")
        _ok(player.velocity.y > 4.0, "W rides up")
        var gap: float = player._face_gap(z1)
        _ok(gap > 0.4 and gap < 1.4, "face gap measured sanely (%.2f)" % gap)

        # ===== 3. hang on the spot =====
        await _drive(player, 5, Vector2.ZERO, PI)
        _ok(player.climbing and absf(player.velocity.y) < 0.01, "no input hangs on the spot")

        # ===== 4. S lets go when the face's bottom is above you =====
        # hanging under rung 1 (its bottom is at 3.7, we are at ~2.3):
        # S = go down = off the climbable, just like going up past the top
        var hang_y: float = player.global_position.y
        await _drive(player, 10, Vector2(0, 1), PI)
        _ok(not player.climbing, "S past the face's bottom lets go")
        _ok(player.global_position.y < hang_y, "S drops you down")

        # ===== 5. jump-off + cooldown: THE regression =====
        # fresh climb state, grabbed from the ground below the rung
        _reset(player, Vector3(0.0, 1.5, 0.6))
        await _drive(player, 30, Vector2.ZERO, PI)             # settle + clear any cooldown
        await _drive(player, 8, Vector2(0, -1), PI)            # grab and rise
        _ok(player.climbing, "climbing before the jump-off")
        var jump_y: float = player.global_position.y
        await _drive(player, 1, Vector2.ZERO, PI, 1)           # SPACE while climbing
        _ok(not player.climbing, "SPACE lets go of the climbable")
        _ok(player.velocity.y > 40.0, "the leap goes up")
        _ok(player.velocity.z < -10.0, "the leap pushes AWAY from the face")
        var restuck := false
        var apex_y: float = jump_y
        for i in range(21):                                     # hold W through the whole cooldown
                player.drive(DELTA, Vector2(0, -1), PI, 0, false)
                await physics_frame
                apex_y = maxf(apex_y, player.global_position.y)
                if player.climbing:
                        restuck = true
        _ok(not restuck, "holding W during the leap does NOT re-stick (cooldown)")
        var landed_off := false
        for i in range(120):                                    # hands off — come down and land
                player.drive(DELTA, Vector2.ZERO, PI, 0, false)
                await physics_frame
                apex_y = maxf(apex_y, player.global_position.y)
                if player.is_on_floor() and not player.climbing:
                        landed_off = true
                        break
        _ok(landed_off, "the leap ends standing somewhere, still off the climbable")
        _ok(player.global_position.y < apex_y - 0.3,
                "you come back down after the leap (apex %.2f -> %.2f)" % [apex_y, player.global_position.y])

        # ===== 6. stacked rungs chain into one climb =====
        _reset(player, Vector3(0.0, 1.0, 0.6))
        var chained := false       # still climbing while crossing the 1-stud gap
        var mounted := false
        for i in range(240):
                player.drive(DELTA, Vector2(0, -1), PI, 0, false)
                await physics_frame
                var y: float = player.global_position.y
                if player.climbing and y > 4.31 and y < 5.29:
                        chained = true
                if not player.climbing and player.is_on_floor() and y > 5.5:
                        mounted = true
                        break
        _ok(chained, "climb chains off rung 1 onto rung 2 through the gap")
        _ok(mounted, "the stacked climb mounts the top rung")
        var final_y: float = player.global_position.y
        _ok(final_y > 5.7 and final_y < 6.8, "standing on rung 2's top (y=%.2f)" % final_y)

        # ===== 7. truss: ride to the top and vault onto it =====
        _reset(player, Vector3(12.0, 0.05, 1.6))
        var truss_mounted := false
        for i in range(300):
                player.drive(DELTA, Vector2(0, -1), 0.0, 0, false)   # wish -Z, into the truss face
                await physics_frame
                if not player.climbing and player.is_on_floor() and player.global_position.y > 9.0:
                        truss_mounted = true
                        break
        _ok(truss_mounted, "riding the truss to the top vaults onto it (y=%.2f)" % player.global_position.y)

        # ===== 8. bottom detach: S to the floor lets go =====
        _reset(player, Vector3(12.0, 0.05, 1.6))
        await _drive(player, 30, Vector2.ZERO, 0.0)            # settle + clear the vault cooldown
        await _drive(player, 10, Vector2(0, -1), 0.0)          # grab the truss from the ground
        _ok(player.climbing, "grabs the truss with W")
        var descending := false
        var reached_floor := false
        for i in range(150):
                player.drive(DELTA, Vector2(0, 1), 0.0, 0, false)   # hold S all the way down
                await physics_frame
                if player.climbing and player.velocity.y < -8.5:
                        descending = true
                if player.is_on_floor() and not player.climbing and player.global_position.y < 0.5:
                        reached_floor = true
                        break
        _ok(descending, "S descends the truss")
        _ok(reached_floor, "riding S to the bottom lets go on the floor")

        # ===== 9. sizes: everything is 5 studs =====
        var capsule := (player.get_node("Collision") as CollisionShape3D).shape as CapsuleShape3D
        _ok(capsule.height == 5.0, "capsule is exactly 5 studs tall")
        var parts_aabb: Array = player.get_node("Avatar").get("_part_aabb")
        var box := AABB()
        var have := false
        for part_box in parts_aabb:
                box = box.merge(part_box) if have else part_box
                have = true
        _ok(have and box.size.y > 4.8 and box.size.y <= 5.15,
                "avatar visual height is 5 studs (%.3f)" % box.size.y)
        _ok(player.STUD_METERS == 0.28, "1 stud = 0.28 meters")
        print("size check: 5 studs = %.2f m, avatar = %.3f studs tall" % [5.0 * player.STUD_METERS, box.size.y])

        # ===== 10. classic Roblox lighting =====
        var env_node := world.get_node_or_null("FriendlySky") as WorldEnvironment
        _ok(env_node != null, "world environment exists")
        if env_node != null:
                var env := env_node.environment
                _ok(env.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "linear tonemap (no filmic muddiness)")
                _ok(env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "flat ambient color source")
                _ok(absf(env.ambient_light_energy - 1.0) < 0.01, "ambient energy 1.0")
        var sun := world.get_node_or_null("WarmSun") as DirectionalLight3D
        _ok(sun != null and sun.light_energy >= 1.0 and sun.shadow_enabled,
                "strong sun with shadows")

        # ===== 11. the user's exact build: stacked 0.28 m (1 stud) platforms =====
        _reset(player, Vector3(-38.6, 0.05, 20.0))
        await _drive(player, 30, Vector2.ZERO, PI / 2.0)       # settle, cool down
        await _drive(player, 10, Vector2(0, -1), PI / 2.0)     # face -X, W into slab 1
        _ok(player.climbing, "walking to a 1-stud platform's edge + facing it + W climbs")
        var slab_chained := false
        var slab_mounted := false
        for i in range(300):
                player.drive(DELTA, Vector2(0, -1), PI / 2.0, 0, false)
                await physics_frame
                var y: float = player.global_position.y
                if player.climbing and y > 5.0 and y < 6.0:
                        slab_chained = true   # crossing the 1 stud gap BETWEEN the slabs
                if not player.climbing and player.is_on_floor() and y > 9.0:
                        slab_mounted = true
                        break
        _ok(slab_chained, "the stack chains across the 1 stud gap (climb off one, onto the next)")
        _ok(slab_mounted, "the floating stack mounts the top slab (y=%.2f)" % player.global_position.y)

        # ===== 12. can_climb = the dev kill switch =====
        _reset(player, Vector3(0.0, 0.05, 0.6))
        player.can_climb = false
        await _drive(player, 12, Vector2(0, -1), PI)
        _ok(not player.climbing, "can_climb = false blocks climbing entirely")
        player.can_climb = true

        # ===== 13. inspector-editable exports =====
        for exported in ["walk_speed", "jump_height", "gravity", "can_climb", "climb_speed",
                        "jump_up_gravity_scale", "walk_acceleration", "air_acceleration",
                        "ladder_jump", "ladder_push", "play_footsteps", "play_jump_sound",
                        "play_land_sound"]:
                _ok(player.get(exported) != null, "player export exists: %s" % exported)
        _ok(absf(float(player.jump_height) - 6.0) < 0.01, "jump height default 6 studs")
        _ok(float(player.jump_up_gravity_scale) < 1.0, "jump rise is eased (no more snap)")

        # ===== 14. UGC scale: site rig and game rig are BOTH 5 studs =====
        var platform_script := load("res://scripts/avatar_platform.gd")
        _ok(int(platform_script.RIG_HEIGHT) == 5, "avatar_platform rig height 5 studs (UGC fix)")
        _ok(absf(float(platform_script.UGC_SCALE) - 1.0) < 0.001,
                "UGC scale is 1.0 — site placements apply verbatim (no more shrunken hats)")

        # ===== 15. lighting: bright classic, but NOT oversaturated =====
        var env2 := world.get_node_or_null("FriendlySky") as WorldEnvironment
        if env2 != null and env2.environment != null:
                _ok(env2.environment.adjustment_enabled, "saturation adjustment enabled")
                _ok(env2.environment.adjustment_saturation < 0.9,
                        "saturation pulled back (%.2f — the 'too saturated' fix)" % env2.environment.adjustment_saturation)

        player.queue_free()
        if failures.is_empty():
                print("CLIMB PROBE OK")
                quit(0)
        else:
                for failure in failures:
                        print("FAIL: ", failure)
                quit(1)
