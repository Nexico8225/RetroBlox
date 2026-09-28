extends Node3D

## The world. Maps are SCENES built from nodes — open
## scenes/maps/classic_baseplate.tscn in the editor and add RetroPart /
## SpawnLocation / RetroLadder instances to build anything (see README).
## This script only provides the sky + sun and points players at spawns;
## swap the map by editing the path below (or replace the map scene's
## contents entirely — devs keep full control).

const MAP_SCENE_PATH: String = "res://scenes/maps/classic_baseplate.tscn"

# fallback spawns used when the map has no SpawnLocation pads
const FALLBACK_SPAWNS: Array[Vector3] = [
        Vector3(0.0, 0.1, 7.0),
        Vector3(0.0, 0.1, -7.0),
        Vector3(7.0, 0.1, 0.0),
        Vector3(-7.0, 0.1, 0.0),
        Vector3(5.0, 0.1, 5.0),
        Vector3(-5.0, 0.1, -5.0),
        Vector3(5.0, 0.1, -5.0),
        Vector3(-5.0, 0.1, 5.0),
]

var _spawn_pads: Array[Vector3] = []
var _map_root: Node3D = null

# auto-ladder rule — a plain part "looks like a ladder" (and climbs like
# one) when it hangs off a wall exactly like the classic rung/truss builds:
# 1-3 studs of part between you and the wall, with a ~1 stud air gap behind
# it (mounted on spacers). Everything else stays a normal, unclimbable part.
const AUTO_LADDER_MIN_DEPTH: float = 1.0
const AUTO_LADDER_MAX_DEPTH: float = 3.0
const AUTO_LADDER_GAP_MIN: float = 0.45
const AUTO_LADDER_GAP_MAX: float = 1.6


func _ready() -> void:
        _make_environment()
        _load_map()
        _auto_ladder_pass.call_deferred()


func spawn_point(index: int) -> Vector3:
        # pads come from the map's SpawnLocation nodes (pad top + a breath)
        if not _spawn_pads.is_empty():
                var safe_index: int = abs(index) % _spawn_pads.size()
                return _spawn_pads[safe_index]
        var safe: int = abs(index) % FALLBACK_SPAWNS.size()
        return FALLBACK_SPAWNS[safe]


## Instance the map scene and collect its SpawnLocation pads. Missing map?
## A flat stud-accurate plate drops in so the game never has nowhere to stand.
func _load_map() -> void:
        var map: Node3D = null
        if ResourceLoader.exists(MAP_SCENE_PATH):
                var packed: PackedScene = load(MAP_SCENE_PATH)
                if packed != null:
                        map = packed.instantiate() as Node3D
        if map == null:
                map = _make_fallback_plate()
        add_child(map)
        _map_root = map
        for node in get_tree().get_nodes_in_group("spawn"):
                var pad := node as RetroPart
                if pad == null:
                        continue
                var top: float = pad.global_position.y + pad.size.y * 0.5
                _spawn_pads.append(Vector3(pad.global_position.x, top + 0.15, pad.global_position.z))
        if _spawn_pads.is_empty():
                print("[RetroBlox] map has no SpawnLocation pads — using default spawns")


## Give a qualifying part its climb zone: an Area3D on layer 16 in the
## "ladder" group, covering the part plus a reach margin on the open face,
## publishing the climbable direction for the jump-off.
func _grant_climb_area(part: RetroPart, local_outward: Vector3) -> void:
        var area := Area3D.new()
        area.name = "AutoClimbArea"
        area.collision_layer = 16
        area.collision_mask = 0
        area.monitoring = false
        area.add_to_group("ladder")
        area.set_meta("outward", local_outward)
        var reach := local_outward.abs() * 1.2                # open-face margin
        var width_axis := Vector3(1.0, 0.0, 0.0) if absf(local_outward.z) > 0.5 else Vector3(0.0, 0.0, 1.0)
        var shape := BoxShape3D.new()
        # ±1 stud of extra height: stacked rungs' zones must OVERLAP vertically
        # so a climb chains from one rung onto the next without flickering off
        shape.size = part.size + reach + width_axis * 0.6 + Vector3(0.0, 2.0, 0.0)
        var shape_node := CollisionShape3D.new()
        shape_node.shape = shape
        shape_node.position = local_outward * 0.6             # margin sticks out, not in
        area.add_child(shape_node)
        part.add_child(area)


func _make_fallback_plate() -> Node3D:
        var root := Node3D.new()
        root.name = "FallbackPlate"
        var part := RetroPart.new()
        part.name = "Baseplate"
        part.size = Vector3(128.0, 2.0, 128.0)
        part.color = Color(0.157, 0.498, 0.278)
        part.position = Vector3(0.0, -1.0, 0.0)
        root.add_child(part)
        return root


func _make_environment() -> void:
        var world_environment: WorldEnvironment = WorldEnvironment.new()
        world_environment.name = "FriendlySky"
        var environment: Environment = Environment.new()
        environment.background_mode = Environment.BG_SKY
        # CLASSIC ROBLOX LIGHT — the old renderer's recipe: one strong white
        # sun, flat mid-grey ambient, LINEAR tonemap (filmic muddies every
        # color). Tops catch the sun and glow, sides fall back to a clean
        # half-light, undersides go properly dark. Bright, punchy, readable.
        environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        environment.ambient_light_color = Color(0.5, 0.5, 0.52)  # the classic 128-grey ambient
        environment.ambient_light_energy = 1.0
        environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
        environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
        var sky: Sky = Sky.new()
        var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
        sky_material.sky_top_color = Color("#2f74c9")       # classic deep blue overhead
        sky_material.sky_horizon_color = Color("#d3ecf9")   # pale, bright horizon band
        sky_material.ground_bottom_color = Color("#47795f")
        sky_material.ground_horizon_color = Color("#d9edd2")
        sky_material.sun_angle_max = 28.0
        sky.sky_material = sky_material
        environment.sky = sky
        world_environment.environment = environment
        add_child(world_environment)

        # the main sun — bright white and steep enough that TOPS are the
        # brightest face (the classic look), crisp soft shadows
        var sun: DirectionalLight3D = DirectionalLight3D.new()
        sun.name = "WarmSun"
        sun.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
        sun.light_color = Color("#fffef7")
        sun.light_energy = 1.1
        sun.shadow_enabled = true
        sun.shadow_opacity = 0.72
        sun.shadow_blur = 1.1
        sun.directional_shadow_max_distance = 160.0
        add_child(sun)

        # a whisper of cool fill from the opposite side so the shaded face
        # keeps its color — the old renderer's sky bounce, kept subtle
        var fill: DirectionalLight3D = DirectionalLight3D.new()
        fill.name = "SkyFill"
        fill.rotation_degrees = Vector3(-24.0, 148.0, 0.0)
        fill.light_color = Color("#d9ecff")
        fill.light_energy = 0.18
        fill.shadow_enabled = false
        add_child(fill)


## AUTO-LADDERS — run once after the map settles. Every plain RetroPart
## that matches the classic ladder silhouette gets a climb zone on its
## open face, so maps built from rungs and truss-shaped parts (1-3 studs
## deep, 1 stud off the wall) climb with NO script or special node.
func _auto_ladder_pass() -> void:
        if _map_root == null or not is_inside_tree():
                return
        await get_tree().process_frame   # let the map's collision shapes settle
        if _map_root == null or not is_inside_tree():
                return
        var space := get_world_3d().direct_space_state
        if space == null:
                return
        for node in _map_root.find_children("*", "RetroPart", true, false):
                var part := node as RetroPart
                if part == null or part is RetroLadder or not part.can_collide:
                        continue
                if part.find_child("AutoClimbArea", false, false) != null:
                        continue   # already granted — the pass stays idempotent
                for axis in [[Vector3.RIGHT, 0], [Vector3.LEFT, 0], [Vector3.BACK, 2], [Vector3.FORWARD, 2]]:
                        var local_dir: Vector3 = axis[0]
                        # depth = the part's size along this axis (1-3 studs)
                        var depth: float = part.size.x if int(axis[1]) == 0 else part.size.z
                        if depth < AUTO_LADDER_MIN_DEPTH or depth > AUTO_LADDER_MAX_DEPTH:
                                continue
                        var world_dir: Vector3 = (part.global_transform.basis * local_dir).normalized()
                        if world_dir.length_squared() < 0.5:
                                continue
                        # is there a wall ~1 stud behind this face?
                        var from: Vector3 = part.global_position + world_dir * (depth * 0.5 + 0.05)
                        var query := PhysicsRayQueryParameters3D.create(
                                from, from + world_dir * (AUTO_LADDER_GAP_MAX + 0.25), 1, [part.get_rid()])
                        var hit := space.intersect_ray(query)
                        if hit.is_empty():
                                continue
                        # the hit must be a wall face LOOKING back at us: a flush
                        # part (no air gap) starts the ray inside the wall and only
                        # finds a backface — flush builds stay plain and unclimbable
                        var hit_normal: Vector3 = hit["normal"]
                        if hit_normal.dot(world_dir) > -0.7:
                                continue
                        var gap: float = from.distance_to(hit["position"]) - 0.05
                        if gap < AUTO_LADDER_GAP_MIN or gap > AUTO_LADDER_GAP_MAX:
                                continue
                        _grant_climb_area(part, -local_dir)
                        break   # one climb zone per part is enough
