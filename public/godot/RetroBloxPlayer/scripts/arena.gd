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


func _ready() -> void:
        _make_environment()
        _load_map()


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
        for node in get_tree().get_nodes_in_group("spawn"):
                var pad := node as RetroPart
                if pad == null:
                        continue
                var top: float = pad.global_position.y + pad.size.y * 0.5
                _spawn_pads.append(Vector3(pad.global_position.x, top + 0.15, pad.global_position.z))
        if _spawn_pads.is_empty():
                print("[RetroBlox] map has no SpawnLocation pads — using default spawns")


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
        # bright, even ambient like the site's hemisphere light — shadowed
        # sides stay colorful instead of going muddy
        environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        environment.ambient_light_color = Color("e6f2f7")
        environment.ambient_light_energy = 0.9
        environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
        environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
        var sky: Sky = Sky.new()
        var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
        sky_material.sky_top_color = Color("#4fa8e8")
        sky_material.sky_horizon_color = Color("#c8e8f2")
        sky_material.ground_bottom_color = Color("#5f9e7d")
        sky_material.ground_horizon_color = Color("#cfe8c0")
        sky_material.sun_angle_max = 20.0
        sky.sky_material = sky_material
        environment.sky = sky
        world_environment.environment = environment
        add_child(world_environment)

        # the main sun — clean white and strong, matching the catalog lighting
        var sun: DirectionalLight3D = DirectionalLight3D.new()
        sun.name = "WarmSun"
        sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
        sun.light_color = Color("#ffffff")
        sun.light_energy = 1.15
        sun.shadow_enabled = true
        sun.directional_shadow_max_distance = 200.0
        add_child(sun)

        # sky/ground fill — the "hemisphere" stand-in from the site playground:
        # soft green-tinted light from the opposite side, no shadows
        var fill: DirectionalLight3D = DirectionalLight3D.new()
        fill.name = "SkyFill"
        fill.rotation_degrees = Vector3(-28.0, 142.0, 0.0)
        fill.light_color = Color("#bfe0d0")
        fill.light_energy = 0.30
        fill.shadow_enabled = false
        add_child(fill)
