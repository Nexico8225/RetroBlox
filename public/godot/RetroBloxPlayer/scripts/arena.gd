extends Node3D

## The world. TWO ways to build it, same nodes and scenes:
##
##  1) WEB SYNC (the normal path) — main.gd downloads the place's map JSON
##     from the RetroBlox website (GET /api/game/places/{slug}) and calls
##     apply_map_data(). This script instantiates the SAME RetroPart /
##     SpawnLocation / RetroLadder scenes the editor uses, so a web map is
##     made of the very same nodes people build with by hand.
##
##  2) SCENE MAPS (offline / creators) — open scenes/maps/classic_baseplate.tscn
##     in the editor and add RetroPart / SpawnLocation / RetroLadder instances
##     to build anything (see README). If the website cannot be reached, the
##     bundled scene loads so the game is always playable.
##
## STUDS — every number is in studs (1 unit = 1 stud, a player is 5 tall).

const MAP_SCENE_PATH: String = "res://scenes/maps/classic_baseplate.tscn"
const PART_SCENE_PATH: String = "res://scenes/part.tscn"
const SPAWN_SCENE_PATH: String = "res://scenes/spawn_location.tscn"
const LADDER_SCENE_PATH: String = "res://scenes/ladder.tscn"

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
var _spawn_cursor: int = 0
var _map_root: Node3D
var _loaded_scene_path: String = ""   # which map is live right now (debug/status)
var _sun: DirectionalLight3D          # main sun — quality settings toggle its shadows
var _fill: DirectionalLight3D


func _ready() -> void:
        _make_environment()
        _map_root = Node3D.new()
        _map_root.name = "Map"
        add_child(_map_root)
        _load_map()


func spawn_point(index: int) -> Vector3:
        # pads come from the map's SpawnLocation nodes (pad top + a breath)
        if not _spawn_pads.is_empty():
                var safe_index: int = abs(index) % _spawn_pads.size()
                return _spawn_pads[safe_index]
        var safe: int = abs(index) % FALLBACK_SPAWNS.size()
        return FALLBACK_SPAWNS[safe]


func current_map_name() -> String:
        return _loaded_scene_path


## WEB MAP — build the world from the place's data JSON (the website's copy).
## Format: {"parts":[{"name","p":[x,y,z],"s":[w,h,d],"color":"#rrggbb"}],
##          "spawns":[...], "ladders":[...]} — studs, positions are centers.
## Returns "" on success, otherwise a short human-readable reason.
func apply_map_data(data: Dictionary) -> String:
        var parts: Array = data.get("parts", [])
        var spawns: Array = data.get("spawns", [])
        var ladders: Array = data.get("ladders", [])
        if parts.is_empty():
                return "the map has no parts"
        _clear_map()
        var map := Node3D.new()
        map.name = "WebMap"
        _map_root.add_child(map)

        var built := 0
        for entry in parts:
                if _spawn_map_node(map, PART_SCENE_PATH, entry):
                        built += 1
        for entry in spawns:
                _spawn_map_node(map, SPAWN_SCENE_PATH, entry)
        for entry in ladders:
                _spawn_map_node(map, LADDER_SCENE_PATH, entry)

        _collect_spawn_pads()
        _loaded_scene_path = "web:%d parts" % built
        print("[RetroBlox] web map built: %d parts, %d spawns, %d ladders" % [built, spawns.size(), ladders.size()])
        if built == 0:
                return "no part in the map could be built"
        return ""


## Instance one map node from data. Returns true when it landed.
func _spawn_map_node(parent: Node3D, scene_path: String, entry: Variant) -> bool:
        if not (entry is Dictionary):
                return false
        var packed: PackedScene = load(scene_path)
        if packed == null:
                return false
        var node: Node3D = packed.instantiate() as Node3D
        if node == null:
                return false
        var item: Dictionary = entry
        var p: Array = item.get("p", [0.0, 0.0, 0.0])
        if p is Array and p.size() == 3:
                node.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
        if "size" in node:
                var s: Array = item.get("s", [])
                if s is Array and s.size() == 3:
                        node.set("size", Vector3(float(s[0]), float(s[1]), float(s[2])))
        if "color" in node:
                var hex := String(item.get("color", ""))
                if hex.begins_with("#") and hex.is_valid_html_color():
                        node.set("color", Color.html(hex))
        node.name = String(item.get("name", "Part"))
        parent.add_child(node)
        return true


## Instance the bundled map scene (offline fallback + creator maps).
## Missing map? A flat stud-accurate plate drops in so the game never has
## nowhere to stand.
func _load_map() -> void:
        var map: Node3D = null
        if ResourceLoader.exists(MAP_SCENE_PATH):
                var packed: PackedScene = load(MAP_SCENE_PATH)
                if packed != null:
                        map = packed.instantiate() as Node3D
        if map == null:
                map = _make_fallback_plate()
        _clear_map()
        _map_root.add_child(map)
        _collect_spawn_pads()
        _loaded_scene_path = MAP_SCENE_PATH


## Remove every SpawnLocation pad position from the CURRENT map (also reads
## the group after the nodes enter the tree, so web-built pads count too).
func _collect_spawn_pads() -> void:
        _spawn_pads.clear()
        _spawn_cursor = 0
        for node in get_tree().get_nodes_in_group("spawn"):
                var pad := node as RetroPart
                if pad == null or not pad.is_inside_tree():
                        continue
                # only pads that actually live under this arena's map
                var walker: Node = pad
                var under_map := false
                while walker != null:
                        if walker == _map_root:
                                under_map = true
                                break
                        walker = walker.get_parent()
                if not under_map:
                        continue
                var top: float = pad.global_position.y + pad.size.y * 0.5
                _spawn_pads.append(Vector3(pad.global_position.x, top + 0.15, pad.global_position.z))
        if _spawn_pads.is_empty():
                print("[RetroBlox] map has no SpawnLocation pads — using default spawns")


func _clear_map() -> void:
        for child in _map_root.get_children():
                # detach NOW — queue_free alone defers deletion to the frame
                # end, and the old pads would still answer the "spawn" group
                # while the new map is being built
                _map_root.remove_child(child)
                child.queue_free()
        _spawn_pads.clear()
        _spawn_cursor = 0


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
        sun.directional_shadow_max_distance = 120.0
        add_child(sun)
        _sun = sun

        # sky/ground fill — the "hemisphere" stand-in from the site playground:
        # soft green-tinted light from the opposite side, no shadows
        var fill: DirectionalLight3D = DirectionalLight3D.new()
        fill.name = "SkyFill"
        fill.rotation_degrees = Vector3(-28.0, 142.0, 0.0)
        fill.light_color = Color("#bfe0d0")
        fill.light_energy = 0.30
        fill.shadow_enabled = false
        add_child(fill)
        _fill = fill


## ---- quality hooks (main.gd's settings drive these) -------------------

func set_sun_shadows(enabled: bool) -> void:
        if _sun != null:
                _sun.shadow_enabled = enabled


func set_shadow_distance(distance: float) -> void:
        if _sun != null:
                _sun.directional_shadow_max_distance = maxf(distance, 10.0)
