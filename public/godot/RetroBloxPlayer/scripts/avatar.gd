extends Node3D

## A six-part classic block avatar, built from scenes/avatar.tscn.
## Open that scene in the editor to resize or restyle any part — the script
## finds the nodes by their unique names and paints them at runtime.
## The RetroBlox platform dresses it: see avatar_platform.gd (colors, clothing
## textures, face, UGC). Main gameplay code can configure it before or after
## adding it to the tree.

const OOF_AUDIO: AudioStream = preload("res://assets/oof.wav")
const HEAD_INDEX: int = 0

# classic noob defaults — guests and brand-new accounts wear these
const NOOB_HEAD := Color("f5cd30")
const NOOB_TORSO := Color("0d69ac")
const NOOB_LEGS := Color("7ab53e")

# part indices — same order as the platform's colors (head, torso, armL, armR, legL, legR)
const HEAD := 0
const TORSO := 1
const ARM_L := 2
const ARM_R := 3
const LEG_L := 4
const LEG_R := 5

# unique names of the scene nodes this script drives (scenes/avatar.tscn)
const PIVOT_NODES: Array[String] = [
        "%HeadPivot", "%TorsoPivot", "%LeftArmPivot", "%RightArmPivot", "%LeftLegPivot", "%RightLegPivot",
]
const PART_NODES: Array[String] = [
        "%Head", "%Torso", "%LeftArm", "%RightArm", "%LeftLeg", "%RightLeg",
]

var parts: Array[MeshInstance3D] = []

var _pivots: Array[Node3D] = []
var _part_sizes: Array[Vector3] = []
var _nameplate: Label3D
var _face_material: StandardMaterial3D
var _display_name: String = "Player"
var _peer_id: int = 0
var _built: bool = false
var _time: float = 0.0
var _face_boxes: Array[MeshInstance3D] = []
var _face_decal: MeshInstance3D

func _ready() -> void:
        _ensure_built()

func configure(peer_id: int, display_name: String) -> void:
        _peer_id = peer_id
        _display_name = display_name
        _ensure_built()
        _paint_noob()
        set_display_name(display_name)

func set_display_name(value: String) -> void:
        _display_name = value
        if _nameplate != null:
                _nameplate.text = value

## Paint one body part a solid color (texture-free).
func set_part_color(index: int, color: Color) -> void:
        _ensure_built()
        if index < 0 or index >= parts.size():
                return
        var mesh_instance := parts[index]
        for surface in mesh_instance.mesh.get_surface_count():
                mesh_instance.set_surface_override_material(surface, null)
        mesh_instance.material_override = _make_material(color)

## Replace a part's mesh (the platform swaps BoxMesh for zone-UV clothing
## meshes) and paint it with a texture on every face.
func set_part_textured(index: int, mesh: Mesh, tex: Texture2D) -> void:
        _ensure_built()
        if index < 0 or index >= parts.size():
                return
        var mesh_instance := parts[index]
        mesh_instance.mesh = mesh
        mesh_instance.material_override = null
        var material := StandardMaterial3D.new()
        material.albedo_texture = tex
        material.roughness = 0.78
        mesh_instance.material_override = material

## Swap the boxy eyes+mouth for the account's real face decal.
func set_face(tex: Texture2D, face_scale: float) -> void:
        _ensure_built()
        if tex == null:
                return
        clear_face()
        var head_size := _part_sizes[HEAD_INDEX]
        var w: float = head_size.x * 0.62 * clampf(face_scale, 0.5, 2.0)
        var quad := MeshInstance3D.new()
        quad.name = "FaceDecal"
        var mesh := QuadMesh.new()
        mesh.size = Vector2(w, w)
        quad.mesh = mesh
        var material := StandardMaterial3D.new()
        material.albedo_texture = tex
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        quad.material_override = material
        # front of the head, just off the surface (head faces -Z like the site rig)
        quad.position = Vector3(0.0, head_size.y * 0.04, -head_size.z * 0.5 - 0.012)
        quad.rotation.y = PI
        _pivots[HEAD_INDEX].add_child(quad)
        _face_decal = quad

func clear_face() -> void:
        for face_box in _face_boxes:
                face_box.visible = false
        if _face_decal != null and is_instance_valid(_face_decal):
                _face_decal.queue_free()
        _face_decal = null

func animate(delta: float, speed: float, grounded: bool) -> void:
        _ensure_built()
        _time += delta
        var movement: float = clampf(abs(speed) / 5.0, 0.0, 1.0)
        var walk_rate: float = 4.8 + movement * 2.0
        var swing: float = sin(_time * walk_rate) * movement
        if grounded:
                _pivots[2].rotation.x = swing * 0.62
                _pivots[3].rotation.x = -swing * 0.62
                _pivots[4].rotation.x = -swing * 0.66
                _pivots[5].rotation.x = swing * 0.66
                _pivots[2].rotation.z = sin(_time * 2.1) * 0.025 * (1.0 - movement)
                _pivots[3].rotation.z = -sin(_time * 2.1) * 0.025 * (1.0 - movement)
        else:
                # A readable midair pose, still gentle enough not to look stiff.
                _pivots[2].rotation.x = -0.36
                _pivots[3].rotation.x = 0.36
                _pivots[4].rotation.x = 0.22
                _pivots[5].rotation.x = -0.22
                _pivots[2].rotation.z = 0.0
                _pivots[3].rotation.z = 0.0
        _pivots[4].rotation.z = 0.0
        _pivots[5].rotation.z = 0.0
        if grounded:
                _pivots[0].rotation.x = sin(_time * 1.8) * 0.025
                _pivots[1].rotation.x = sin(_time * 1.8 + 0.5) * 0.012
        else:
                _pivots[0].rotation.x = 0.0
                _pivots[1].rotation.x = 0.0

func burst(world: Node3D, impulse_seed: int) -> void:
        _ensure_built()
        if world == null:
                return
        visible = false
        var debris_group: Node3D = Node3D.new()
        debris_group.name = "AvatarBreakup"
        world.add_child(debris_group)
        debris_group.global_position = global_position

        var rng: RandomNumberGenerator = RandomNumberGenerator.new()
        rng.seed = abs(impulse_seed) * 104729 + 13
        for i in range(parts.size()):
                var piece: RigidBody3D = _make_debris_piece(debris_group, i)
                var outward: Vector3 = Vector3(
                        rng.randf_range(-4.8, 4.8),
                        rng.randf_range(4.0, 7.5),
                        rng.randf_range(-4.8, 4.8)
                )
                # Initial velocities work before the first physics step computes inertia.
                piece.linear_velocity = outward
                piece.angular_velocity = Vector3(
                        rng.randf_range(-5.5, 5.5),
                        rng.randf_range(-5.5, 5.5),
                        rng.randf_range(-5.5, 5.5)
                )

        var audio: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
        audio.name = "OriginalOof"
        audio.stream = OOF_AUDIO
        audio.max_distance = 40.0
        audio.unit_size = 10.0
        audio.volume_db = 0.0
        debris_group.add_child(audio)
        audio.position = Vector3.ZERO
        audio.play()
        # This timer belongs to the world tree, not the avatar.  It remains valid if
        # gameplay code frees the avatar during respawn.
        var cleanup_timer: SceneTreeTimer = world.get_tree().create_timer(5.0)
        cleanup_timer.timeout.connect(debris_group.queue_free)

func set_local_hidden(hidden: bool) -> void:
        visible = not hidden

## The scene (scenes/avatar.tscn) provides every node; this only wires up the
## arrays the gameplay code drives. Runs once, even outside the tree.
func _ensure_built() -> void:
        if _built:
                return
        _built = true
        parts.clear()
        _pivots.clear()
        _part_sizes.clear()
        for i in range(PART_NODES.size()):
                var part: MeshInstance3D = get_node(PART_NODES[i])
                parts.append(part)
                _pivots.append(get_node(PIVOT_NODES[i]))
                var box := part.mesh as BoxMesh
                _part_sizes.append(box.size if box != null else Vector3.ONE)
        _face_material = get_node("%EyeLeft").material_override as StandardMaterial3D
        _face_boxes.assign([get_node("%EyeLeft"), get_node("%EyeRight"), get_node("%Mouth")])
        _nameplate = get_node("%Nameplate")
        _nameplate.text = _display_name

func _paint_noob() -> void:
        set_part_color(HEAD, NOOB_HEAD)
        set_part_color(TORSO, NOOB_TORSO)
        set_part_color(ARM_L, NOOB_HEAD)
        set_part_color(ARM_R, NOOB_HEAD)
        set_part_color(LEG_L, NOOB_LEGS)
        set_part_color(LEG_R, NOOB_LEGS)

func _make_debris_piece(debris_group: Node3D, index: int) -> RigidBody3D:
        var source: MeshInstance3D = parts[index]
        var piece: RigidBody3D = RigidBody3D.new()
        piece.name = "BrokenPart_%d" % index
        piece.collision_layer = 2
        piece.collision_mask = 3
        piece.mass = 0.7
        piece.linear_damp = 0.35
        piece.angular_damp = 0.45
        debris_group.add_child(piece)
        piece.global_transform = source.global_transform

        var mesh_copy: MeshInstance3D = MeshInstance3D.new()
        mesh_copy.name = "Mesh"
        mesh_copy.mesh = source.mesh
        mesh_copy.material_override = source.material_override
        for surface: int in range(source.mesh.get_surface_count()):
                var override := source.get_surface_override_material(surface)
                if override != null:
                        mesh_copy.set_surface_override_material(surface, override)
        piece.add_child(mesh_copy)
        var collision: CollisionShape3D = CollisionShape3D.new()
        var shape: BoxShape3D = BoxShape3D.new()
        shape.size = _part_sizes[index]
        collision.shape = shape
        piece.add_child(collision)
        if index == HEAD_INDEX:
                # debris keeps a simple face, cloned from the scene's eye/mouth boxes
                for face_box in _face_boxes:
                        var clone := MeshInstance3D.new()
                        clone.mesh = face_box.mesh
                        clone.material_override = face_box.material_override
                        clone.position = face_box.position
                        piece.add_child(clone)
        return piece

func _make_material(color: Color) -> StandardMaterial3D:
        var material: StandardMaterial3D = StandardMaterial3D.new()
        material.albedo_color = color
        material.roughness = 0.78
        return material
