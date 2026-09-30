extends Node3D

## A six-part classic block avatar. Two visual modes, one API:
##
##  1) R6IK mode (default) — the REAL catalog player model. A cleaned
##     build of the catalog rig ships prepackaged as
##     assets/models/R6IK_rig.scn; the raw R6IK.fbx sits un-imported in
##     assets/models/source/ (its empty helper meshes made the editor
##     spam import errors on every open). Every part can be painted or
##     dressed exactly like the site does it.
##  2) Box mode (fallback) — scenes/avatar.tscn's built-in box rig. Used
##     if someone strips the models folder. Nothing else changes.
##
## Both modes expose the same API avatar_platform.gd drives:
## set_part_color / set_part_textured / set_face / animate / burst.

# lazy-loaded at runtime — a preload() here would fail to parse on a
# project's very first open, before Godot has imported the .wav asset
var _oof_audio: AudioStream
const HEAD_INDEX: int = 0
const RIG_SCENE_PATH: String = "res://assets/models/R6IK_rig.scn"
const RIG_HEIGHT: float = 5.0  # STUDS: the classic character is exactly 5 studs tall

# the real R6IK animations, shipped inside the rig (old Roblox moves)
const ANIM_IDLE: StringName = &"Old_Idle"
const ANIM_WALK: StringName = &"Old_Walk"
const ANIM_JUMP: StringName = &"Old_Jump"
const ANIM_CLIMB: StringName = &"Climb"

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

# name aliases, ported from the site's src/lib/three/rig.ts so ANY rig
# exported with these part names just works
const PART_ALIASES: Array = [
        [HEAD, ["head"]],
        [TORSO, ["torso"]],
        [ARM_L, ["left arm", "leftarm", "arm l", "l arm"]],
        [ARM_R, ["right arm", "rightarm", "arm r", "r arm"]],
        [LEG_L, ["left leg", "leftleg", "leg l", "l leg"]],
        [LEG_R, ["right leg", "rightleg", "leg r", "r leg"]],
]

# characters allowed inside a $tag when stripping rig-name prefixes
const RIG_NAME_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789_"

# unique names of the box-fallback scene nodes (scenes/avatar.tscn)
const PIVOT_NODES: Array[String] = [
        "%HeadPivot", "%TorsoPivot", "%LeftArmPivot", "%RightArmPivot", "%LeftLegPivot", "%RightLegPivot",
]
const PART_NODES: Array[String] = [
        "%Head", "%Torso", "%LeftArm", "%RightArm", "%LeftLeg", "%RightLeg",
]

var parts: Array[MeshInstance3D] = []

var _pivots: Array[Node3D] = []          # swing pivots; head/torso stay null in R6IK mode
var _part_sizes: Array[Vector3] = []     # avatar-space size of every part
var _part_aabb: Array[AABB] = []         # avatar-space AABB of every part
var _mounts: Array[Node3D] = []          # axis-aligned anchor child per part (R6IK mode)
var _overlays: Dictionary = {}           # part index -> clothing overlay node
var _nameplate: Label3D
var _face_material: StandardMaterial3D
var _display_name: String = "Player"
var _peer_id: int = 0
var _built: bool = false
var _using_r6ik: bool = false
var _time: float = 0.0
var _face_boxes: Array[MeshInstance3D] = []
var _face_decal: MeshInstance3D
var _applied_colors: Dictionary = {}     # part index -> Color, reapplied if the rig upgrades
var _anim_player: AnimationPlayer        # the R6IK rig's own AnimationPlayer (old Roblox clips)
var _current_anim: StringName = &""
var debris_torso: RigidBody3D            # the falling torso after a death (death camera)


func _ready() -> void:
        _ensure_built(true)

func is_r6ik() -> bool:
        return _using_r6ik

## The avatar's real height in avatar-space units (the R6IK rig is built to
## exactly 5.0 — the same units the site's 5-stud rig uses, so UGC placements
## authored on the site map 1:1; the box fallback rig is whatever it measures).
## Measured from the actual part meshes so clothing/UGC code never hardcodes it.
func rig_height() -> float:
        _ensure_built()
        if not is_inside_tree():
                return RIG_HEIGHT
        var top := 0.0
        var any := false
        var inv := global_transform.affine_inverse()
        for part in parts:
                if part == null or not is_instance_valid(part) or part.mesh == null:
                        continue
                var box: AABB = inv * part.global_transform * part.mesh.get_aabb()
                top = maxf(top, box.position.y + box.size.y)
                any = true
        return top if any else RIG_HEIGHT

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
        _applied_colors[index] = color
        var mesh_instance := parts[index]
        for surface in mesh_instance.mesh.get_surface_count():
                mesh_instance.set_surface_override_material(surface, null)
        mesh_instance.material_override = _make_material(color)

## Dress one part with a pre-built zone-UV mesh + texture (the platform's
## shirt/pants pipeline). R6IK mode adds it as a clothing overlay that hugs
## the part and swings with it; box mode swaps the mesh, like classic parts.
func set_part_textured(index: int, mesh: Mesh, tex: Texture2D) -> void:
        _ensure_built()
        if index < 0 or index >= parts.size():
                return
        var mesh_instance := parts[index]
        var material := StandardMaterial3D.new()
        material.albedo_texture = tex
        material.roughness = 0.78
        if _using_r6ik:
                if _overlays.has(index) and is_instance_valid(_overlays[index]):
                        _overlays[index].queue_free()
                var overlay := MeshInstance3D.new()
                overlay.name = "ClothingOverlay_%d" % index
                overlay.mesh = mesh
                overlay.material_override = material
                # the mount is axis-aligned with the avatar and glued to the part,
                # so the clothing grows around the part and swings with the limb
                _mounts[index].add_child(overlay)
                overlay.scale = Vector3.ONE * 1.02
                _overlays[index] = overlay
        else:
                mesh_instance.mesh = mesh
                mesh_instance.material_override = null
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
        # front of the head, just off the surface (the rig faces -Z like the site)
        var host: Node3D = _mounts[HEAD_INDEX] if _using_r6ik else _pivots[HEAD_INDEX]
        host.add_child(quad)
        quad.position = Vector3(0.0, head_size.y * 0.04, -_part_aabb[HEAD_INDEX].size.z * 0.5 - 0.012)
        quad.rotation.y = PI
        _face_decal = quad

func clear_face() -> void:
        for face_box in _face_boxes:
                face_box.visible = false
        if _face_decal != null and is_instance_valid(_face_decal):
                _face_decal.queue_free()
        _face_decal = null

func animate(delta: float, speed: float, grounded: bool, climbing: bool = false) -> void:
        _ensure_built()
        _time += delta
        if _using_r6ik and _anim_player != null:
                _animate_r6ik(speed, grounded, climbing)
                return
        _animate_boxes(delta, speed, grounded, climbing)

## The real R6IK clips — Old_Idle / Old_Walk / Old_Jump / Climb, exactly the
## animations that ship inside the rig. The walk/climb clips are speed-scaled
## to the actual movement so feet do not slide; the jump clip plays once and
## holds its last frame until you land (classic old-Roblox jump).
func _animate_r6ik(speed: float, grounded: bool, climbing: bool) -> void:
        if _anim_player == null:
                return
        var next: StringName = ANIM_IDLE
        var rate := 1.0
        if climbing:
                next = ANIM_CLIMB
                rate = clampf(speed / 6.0, 0.5, 1.5)
        elif not grounded:
                next = ANIM_JUMP
        elif speed > 1.2:
                next = ANIM_WALK
                rate = clampf(speed / 8.0, 0.6, 2.2)
        # never play an animation the rig does not actually have — a missing
        # clip used to error every frame while walking
        if not _anim_player.has_animation(next):
                if not _anim_player.has_animation(ANIM_IDLE):
                        return
                next = ANIM_IDLE
                rate = 1.0
        if _current_anim != next:
                _current_anim = next
                # snappy jump, gentle blends everywhere else
                _anim_player.play(next, 0.16 if next != ANIM_JUMP else 0.08, rate if next != ANIM_JUMP else 1.35)
        # the walk/climb clips follow the player's real speed; everything
        # else resets to 1x so a stale 2x walk speed never leaks into the
        # idle or jump clips (the "anims break" bug)
        _anim_player.speed_scale = rate if (next == ANIM_WALK or next == ANIM_CLIMB) else 1.0

## Box-fallback rig: procedural limb swings, same classic feel.
func _animate_boxes(delta: float, speed: float, grounded: bool, climbing: bool) -> void:
        var movement: float = clampf(abs(speed) / 5.0, 0.0, 1.0)
        var walk_rate: float = 4.8 + movement * 2.0
        var swing: float = sin(_time * walk_rate) * movement
        if climbing:
                # alternating reach-up, like climbing a truss
                var alt := sin(_time * 6.5) * 0.9
                if _pivots[2] != null:
                        _pivots[2].rotation.x = -2.4 + alt * 0.4
                        _pivots[3].rotation.x = -2.4 - alt * 0.4
                        _pivots[4].rotation.x = alt * 0.5
                        _pivots[5].rotation.x = -alt * 0.5
                return
        # classic playground feel: arms/legs swing from the shoulder/hip,
        # arms fly up mid-air (matches the site's catalog player)
        if grounded:
                if _pivots[2] != null:
                        _pivots[2].rotation.x = swing * 0.7
                        _pivots[3].rotation.x = -swing * 0.7
                        _pivots[4].rotation.x = -swing * 0.66
                        _pivots[5].rotation.x = swing * 0.66
                        _pivots[2].rotation.z = sin(_time * 2.1) * 0.025 * (1.0 - movement)
                        _pivots[3].rotation.z = -sin(_time * 2.1) * 0.025 * (1.0 - movement)
                if _pivots[0] != null:
                        _pivots[0].rotation.x = sin(_time * 1.8) * 0.025
                        _pivots[1].rotation.x = sin(_time * 1.8 + 0.5) * 0.012
        else:
                if _pivots[2] != null:
                        _pivots[2].rotation.x = -2.6
                        _pivots[3].rotation.x = -2.6
                        _pivots[4].rotation.x = 0.35
                        _pivots[5].rotation.x = -0.35
                        _pivots[2].rotation.z = 0.0
                        _pivots[3].rotation.z = 0.0
                if _pivots[0] != null:
                        _pivots[0].rotation.x = 0.0
                        _pivots[1].rotation.x = 0.0
        if _pivots[4] != null:
                _pivots[4].rotation.z = 0.0
                _pivots[5].rotation.z = 0.0

func burst(world: Node3D, impulse_seed: int) -> void:
        _ensure_built()
        if world == null:
                return
        visible = false
        debris_torso = null
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
                if i == TORSO:
                        debris_torso = piece  # the camera follows this while dead

        var audio: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
        audio.name = "OriginalOof"
        audio.stream = _get_oof_audio()
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

## Lazy-load the classic oof sound on first use (never at parse time).
func _get_oof_audio() -> AudioStream:
        if _oof_audio == null:
                _oof_audio = load("res://assets/oof.wav")
        return _oof_audio

func set_local_hidden(hidden: bool) -> void:
        visible = not hidden

## Build once. Tries the real R6IK rig first (needs the tree for pivot
## wiring), falls back to the scene's box rig everywhere else.
func _ensure_built(allow_upgrade: bool = false) -> void:
        if _built:
                if allow_upgrade and not _using_r6ik and is_inside_tree():
                        _try_r6ik()
                return
        _built = true
        if is_inside_tree() and _try_r6ik():
                return
        _build_boxes()

## The real R6IK catalog model. Returns false when the FBX is not imported
## yet (fresh project, first open) — the box rig takes over until then.
func _try_r6ik() -> bool:
        var packed: PackedScene = load(RIG_SCENE_PATH)
        if packed == null:
                return false
        var inst: Node3D = packed.instantiate()
        if inst == null:
                return false
        _using_r6ik = true

        # ---- find the six body parts by name (site alias rules) ----
        var found: Dictionary = {}
        for node in inst.find_children("*", "MeshInstance3D", true, false):
                var mi := node as MeshInstance3D
                if mi.mesh == null:
                        continue
                var index := _match_part_name(mi.name, mi.mesh.resource_name)
                if index >= 0:
                        found[index] = mi
                else:
                        mi.visible = false  # IK helper planes, control meshes, etc.
        if found.size() < 6:
                # not the rig we expected — keep the box rig instead
                _using_r6ik = false
                inst.free()
                return false

        # ---- the rig's own AnimationPlayer carries the old Roblox clips
        # (Old_Idle / Old_Walk / Old_Jump / Climb ...) and its tracks drive the
        # visible body parts directly — so we USE it instead of silencing it.
        for node in inst.find_children("*", "AnimationPlayer", true, false):
                var anim_player := node as AnimationPlayer
                anim_player.autoplay = ""
                anim_player.stop()
                # IDLE processing: advances every frame, honoring speed_scale
                # (used to speed the walk clip up and down with the player)
                # LOOPING IS SET EXPLICITLY: if the FBX import dropped the loop
                # flag, the walk clip used to play once and freeze mid-stride
                # (the "walk anim sometimes does not play" bug)
                for looped in [ANIM_IDLE, ANIM_WALK, ANIM_CLIMB]:
                        var clip := anim_player.get_animation(looped)
                        if clip != null:
                                clip.loop_mode = Animation.LOOP_LINEAR
                # the jump clip must hold its last frame mid-air, not loop
                var jump_anim := anim_player.get_animation(ANIM_JUMP)
                if jump_anim != null:
                        jump_anim.loop_mode = Animation.LOOP_NONE
                _anim_player = anim_player

        # ---- normalize: RIG_HEIGHT tall, feet on y=0, centered on x/z ----
        # bounds are computed from REAL vertices — the FBX part nodes carry
        # tilted Blender rotations, and node-space AABBs would inflate
        var raw_bounds := AABB()
        var have_bounds := false
        var part_boxes: Dictionary = {}
        for index in found:
                var mi: MeshInstance3D = found[index]
                var chain := _chain_transform(mi, inst)
                var box := _vertex_aabb(mi.mesh, chain)
                part_boxes[index] = box
                raw_bounds = box if not have_bounds else raw_bounds.merge(box)
                have_bounds = true
        var scale := RIG_HEIGHT / maxf(raw_bounds.size.y, 0.0001)
        var raw_center := raw_bounds.get_center()
        var model := Node3D.new()
        model.name = "R6IKModel"
        model.scale = Vector3.ONE * scale
        model.position = Vector3(-raw_center.x * scale, -raw_bounds.position.y * scale, -raw_center.z * scale)
        model.add_child(inst)
        add_child(model)

        # ---- per-part data in avatar space + axis-aligned mounts ----
        parts.clear()
        _pivots.clear()
        _part_sizes.clear()
        _part_aabb.clear()
        _mounts.clear()
        for i in range(6):
                var mi: MeshInstance3D = found[i]
                var box: AABB = model.transform * part_boxes[i]
                parts.append(mi)
                _part_sizes.append(box.size)
                _part_aabb.append(box)
                var mount := Node3D.new()
                mount.name = "Mount_%d" % i
                mi.add_child(mount)
                # mount sits axis-aligned with the avatar and glued to the part:
                # clothing and face decals parent to it and follow limb swings
                var world_center := to_global(box.get_center())
                mount.transform = mi.global_transform.affine_inverse() * Transform3D(global_transform.basis, world_center)
                _mounts.append(mount)
        for i in range(6):
                _pivots.append(null)  # R6IK mode is driven by the AnimationPlayer, not pivots

        # ---- hide the box-fallback rig ----
        for i in range(6):
                var box_pivot := get_node_or_null(PIVOT_NODES[i])
                if box_pivot != null:
                        box_pivot.visible = false
        _collect_box_face_boxes()

        # ---- reapply anything painted before the upgrade ----
        for index in _applied_colors:
                var color: Color = _applied_colors[index]
                if index >= 0 and index < parts.size():
                        parts[index].material_override = _make_material(color)
        return true

## Box fallback — the classic rig that lives in scenes/avatar.tscn.
func _build_boxes() -> void:
        parts.clear()
        _pivots.clear()
        _part_sizes.clear()
        _part_aabb.clear()
        _mounts.clear()
        for i in range(PART_NODES.size()):
                var part: MeshInstance3D = get_node(PART_NODES[i])
                parts.append(part)
                _pivots.append(get_node(PIVOT_NODES[i]))
                var box := part.mesh as BoxMesh
                var size := box.size if box != null else Vector3.ONE
                _part_sizes.append(size)
                _part_aabb.append(AABB(-size * 0.5, size))
                _mounts.append(_pivots[i])
        _collect_box_face_boxes()
        _nameplate = get_node("%Nameplate")
        _nameplate.text = _display_name

func _collect_box_face_boxes() -> void:
        _face_material = get_node("%EyeLeft").material_override as StandardMaterial3D
        _face_boxes.assign([get_node("%EyeLeft"), get_node("%EyeRight"), get_node("%Mouth")])
        if _nameplate == null:
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
        if index == HEAD_INDEX and not _using_r6ik:
                # box debris keeps a simple face, cloned from the scene's eye/mouth boxes
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

## Transform chain from `node` up to (but excluding) `top`, child-first.
func _chain_transform(node: Node, top: Node) -> Transform3D:
        var xform := Transform3D.IDENTITY
        var current: Node = node
        while current != null and current != top:
                if current is Node3D:
                        xform = (current as Node3D).transform * xform
                current = current.get_parent()
        return xform

## Exact world-space bounds of a mesh: walks every vertex once. The FBX
## part nodes are rotated out of axis alignment by Blender's export, so
## transforming the local AABB would inflate the boxes and float decals.
func _vertex_aabb(mesh: Mesh, xform: Transform3D) -> AABB:
        var faces := mesh.get_faces()
        var box := AABB()
        var first := true
        for vertex in faces:
                var world := xform * vertex
                if first:
                        box = AABB(world, Vector3.ZERO)
                        first = false
                else:
                        box = box.expand(world)
        return box

## Site-compatible part-name matcher (see src/lib/three/rig.ts):
## lowercase, drop $tags, separators -> spaces, strip trailing digits.
func _match_part_name(node_name: String, mesh_name: String) -> int:
        for source in [node_name, mesh_name]:
                var norm := _norm_part_name(source)
                if norm.is_empty():
                        continue
                for entry in PART_ALIASES:
                        for alias in entry[1]:
                                if norm == alias or norm.begins_with(alias + " "):
                                        return int(entry[0])
        return -1

func _norm_part_name(raw: String) -> String:
        var s := raw.to_lower()
        var out := ""
        var i := 0
        while i < s.length():
                if s[i] == "$":
                        i += 1
                        while i < s.length() and RIG_NAME_CHARS.contains(s[i]):
                                i += 1
                else:
                        out += s[i]
                        i += 1
        out = out.replace("_", " ").replace(".", " ").replace("-", " ")
        var keep: Array[String] = []
        for token in out.split(" ", false):
                while token.length() > 1 and token.right(1) >= "0" and token.right(1) <= "9":
                        token = token.left(token.length() - 1)
                if token != "":
                        keep.append(token)
        return " ".join(keep)
