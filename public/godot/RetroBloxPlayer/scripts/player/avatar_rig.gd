extends Node3D
## AvatarRig — the classic six-part block avatar, rebuilt for the new player.
##
## Two visual modes behind one tiny API:
##   1) R6IK mode (default) — the real catalog model. The same R6IK.fbx rig
##      the website's avatar editor renders ships in assets/models/. Limbs
##      swing from its own AnimationPlayer (the old Roblox clips).
##   2) Box mode (fallback) — a code-built classic box body used on first
##      open before Godot imported the FBX, or without a models folder.
##
## The rig is EXACTLY 5 studs tall (classic R6 height) in both modes, so
## creator-placed 3D UGC lands 1:1 with the website's 5-stud rig.

const HEAD := 0
const TORSO := 1
const ARM_L := 2
const ARM_R := 3
const LEG_L := 4
const LEG_R := 5
const HEAD_INDEX := 0

const RIG_SCENE_PATH := "res://assets/models/R6IK.fbx"
const RIG_HEIGHT := 5.0
const SITE_RIG_HEIGHT := 5.0

const ANIM_IDLE := &"Old_Idle"
const ANIM_WALK := &"Old_Walk"
const ANIM_JUMP := &"Old_Jump"
const ANIM_CLIMB := &"Climb"

# classic noob defaults — guests and brand-new accounts wear these
const NOOB_HEAD := Color("f5cd30")
const NOOB_TORSO := Color("0d69ac")
const NOOB_ARMS := Color("f5cd30")
const NOOB_LEGS := Color("7ab53e")

# name aliases, ported from the site's rig so any part naming convention works
const PART_ALIASES: Array = [
        [HEAD, ["head"]],
        [TORSO, ["torso"]],
        [ARM_L, ["left arm", "leftarm", "arm l", "l arm"]],
        [ARM_R, ["right arm", "rightarm", "arm r", "r arm"]],
        [LEG_L, ["left leg", "leftleg", "leg l", "l leg"]],
        [LEG_R, ["right leg", "rightleg", "leg r", "r leg"]],
]
const RIG_NAME_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789_"

# classic R6 proportions (studs) for the code-built box body
const BOX_LEG_H := 2.0
const BOX_TORSO := Vector3(2.0, 2.0, 1.0)
const BOX_ARM := Vector3(1.0, 2.0, 1.0)
const BOX_LEG := Vector3(1.0, 2.0, 1.0)
const BOX_HEAD := Vector3(1.15, 1.15, 1.15)

var parts: Array[MeshInstance3D] = []
var HEAD_PIVOT_Y := 0.0  # head center height, set by the active mode

var _pivots: Array[Node3D] = []
var _part_sizes: Array[Vector3] = []
var _part_aabb: Array[AABB] = []
var _mounts: Array[Node3D] = []
var _overlays: Dictionary = {}
var _nameplate: Label3D
var _face_decal: MeshInstance3D
var _display_name := "Player"
var _built := false
var _using_r6ik := false
var _time := 0.0
var _applied_colors: Dictionary = {}
var _anim_player: AnimationPlayer
var _current_anim := &""
var _oof_audio: AudioStream


func _ready() -> void:
        _ensure_built(true)


func is_r6ik() -> bool:
        return _using_r6ik


func setup(p_name: String) -> void:
        _display_name = p_name
        _ensure_built()
        paint_noob()
        set_display_name(p_name)


func set_display_name(value: String) -> void:
        _display_name = value
        if _nameplate != null:
                _nameplate.text = value


func paint_noob() -> void:
        set_part_color(HEAD, NOOB_HEAD)
        set_part_color(TORSO, NOOB_TORSO)
        set_part_color(ARM_L, NOOB_ARMS)
        set_part_color(ARM_R, NOOB_ARMS)
        set_part_color(LEG_L, NOOB_LEGS)
        set_part_color(LEG_R, NOOB_LEGS)


## Paint one body part a solid color (texture-free).
func set_part_color(index: int, color: Color) -> void:
        _ensure_built()
        if index < 0 or index >= parts.size():
                return
        _applied_colors[index] = color
        var mi := parts[index]
        if mi.mesh == null:
                return
        for surface in mi.mesh.get_surface_count():
                mi.set_surface_override_material(surface, null)
        mi.material_override = _make_material(color)


## Dress one part with a zone-UV box mesh + texture (the shirt/pants pipeline).
func set_part_textured(index: int, mesh: Mesh, tex: Texture2D) -> void:
        _ensure_built()
        if index < 0 or index >= parts.size():
                return
        var mi := parts[index]
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
                _mounts[index].add_child(overlay)
                overlay.scale = Vector3.ONE * 1.02
                _overlays[index] = overlay
        else:
                mi.mesh = mesh
                mi.material_override = material


## Put a face decal on the FRONT of the head (-Z).
func set_face(tex: Texture2D, face_scale: float) -> void:
        _ensure_built()
        if tex == null:
                return
        if _face_decal != null and is_instance_valid(_face_decal):
                _face_decal.queue_free()
                _face_decal = null
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
        var host: Node3D = _mounts[HEAD_INDEX]
        host.add_child(quad)
        quad.position = Vector3(0.0, head_size.y * 0.04, -head_size.z * 0.5 - 0.012)
        quad.rotation.y = PI
        _face_decal = quad


func animate(delta: float, speed: float, grounded: bool, climbing: bool = false) -> void:
        _ensure_built()
        _time += delta
        if _using_r6ik and _anim_player != null:
                _animate_r6ik(speed, grounded, climbing)
                return
        _animate_boxes(delta, speed, grounded, climbing)


func _animate_r6ik(speed: float, grounded: bool, climbing: bool) -> void:
        var next: StringName = ANIM_IDLE
        var rate := 1.0
        if climbing:
                next = ANIM_CLIMB
                rate = clampf(speed / 6.0, 0.5, 1.5)
        elif not grounded:
                next = ANIM_JUMP
        elif speed > 1.2:
                next = ANIM_WALK
                rate = clampf(speed / 8.0, 0.8, 2.2)
        if _current_anim != next:
                _current_anim = next
                _anim_player.play(next, 0.16 if next != ANIM_JUMP else 0.08, rate if next != ANIM_JUMP else 1.35)
        elif next == ANIM_WALK or next == ANIM_CLIMB:
                _anim_player.speed_scale = rate


func _animate_boxes(delta: float, speed: float, grounded: bool, climbing: bool) -> void:
        var movement := clampf(absf(speed) / 5.0, 0.0, 1.0)
        var walk_rate := 4.8 + movement * 2.0
        var swing := sin(_time * walk_rate) * movement
        if climbing:
                var alt := sin(_time * 6.5) * 0.9
                _pivots[ARM_L].rotation.x = -2.4 + alt * 0.4
                _pivots[ARM_R].rotation.x = -2.4 - alt * 0.4
                _pivots[LEG_L].rotation.x = alt * 0.5
                _pivots[LEG_R].rotation.x = -alt * 0.5
                return
        if grounded:
                _pivots[ARM_L].rotation.x = swing * 0.7
                _pivots[ARM_R].rotation.x = -swing * 0.7
                _pivots[LEG_L].rotation.x = -swing * 0.66
                _pivots[LEG_R].rotation.x = swing * 0.66
                _pivots[ARM_L].rotation.z = sin(_time * 2.1) * 0.025 * (1.0 - movement)
                _pivots[ARM_R].rotation.z = -sin(_time * 2.1) * 0.025 * (1.0 - movement)
                _pivots[HEAD].rotation.x = sin(_time * 1.8) * 0.025
                _pivots[TORSO].rotation.x = sin(_time * 1.8 + 0.5) * 0.012
        else:
                _pivots[ARM_L].rotation.x = -2.6
                _pivots[ARM_R].rotation.x = -2.6
                _pivots[ARM_L].rotation.z = 0.0
                _pivots[ARM_R].rotation.z = 0.0
                _pivots[LEG_L].rotation.x = 0.35
                _pivots[LEG_R].rotation.x = -0.35
                _pivots[HEAD].rotation.x = 0.0
                _pivots[TORSO].rotation.x = 0.0


## Oof! — the classic breakup, used by death and reset.
func burst(world: Node3D, impulse_seed: int) -> void:
        _ensure_built()
        if world == null:
                return
        visible = false
        var debris := Node3D.new()
        debris.name = "AvatarBreakup"
        world.add_child(debris)
        debris.global_position = global_position
        var rng := RandomNumberGenerator.new()
        rng.seed = abs(impulse_seed) * 104729 + 13
        for i in range(parts.size()):
                var piece := _make_debris_piece(debris, i)
                piece.linear_velocity = Vector3(
                        rng.randf_range(-4.8, 4.8), rng.randf_range(4.0, 7.5), rng.randf_range(-4.8, 4.8))
                piece.angular_velocity = Vector3(
                        rng.randf_range(-5.5, 5.5), rng.randf_range(-5.5, 5.5), rng.randf_range(-5.5, 5.5))
        var audio := AudioStreamPlayer3D.new()
        audio.name = "OriginalOof"
        audio.stream = _get_oof_audio()
        audio.max_distance = 40.0
        audio.unit_size = 10.0
        debris.add_child(audio)
        audio.play()
        var cleanup := world.get_tree().create_timer(5.0)
        cleanup.timeout.connect(debris.queue_free)


func _get_oof_audio() -> AudioStream:
        if _oof_audio == null:
                _oof_audio = load("res://assets/oof.wav")
        return _oof_audio


# ---------------------------------------------------------------- building

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
## yet (fresh unzip, first open) — the box rig takes over until then.
func _try_r6ik() -> bool:
        var packed: PackedScene = load(RIG_SCENE_PATH)
        if packed == null:
                return false
        var inst: Node3D = packed.instantiate()
        if inst == null:
                return false
        var found: Dictionary = {}
        for node in inst.find_children("*", "MeshInstance3D", true, false):
                var mi := node as MeshInstance3D
                if mi.mesh == null:
                        continue
                var index := _match_part_name(mi.name, mi.mesh.resource_name)
                if index >= 0:
                        found[index] = mi
                else:
                        mi.visible = false
        if found.size() < 6:
                inst.free()
                return false
        _using_r6ik = true

        for node in inst.find_children("*", "AnimationPlayer", true, false):
                var ap := node as AnimationPlayer
                ap.autoplay = ""
                ap.stop()
                var jump_anim := ap.get_animation(ANIM_JUMP)
                if jump_anim != null:
                        jump_anim.loop_mode = Animation.LOOP_NONE
                _anim_player = ap

        # normalize: RIG_HEIGHT tall, feet on y=0, centered on x/z — bounds from
        # REAL vertices (the FBX part nodes carry tilted Blender rotations)
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
                var world_center := to_global(box.get_center())
                mount.transform = mi.global_transform.affine_inverse() * Transform3D(global_transform.basis, world_center)
                _mounts.append(mount)
                if i == HEAD_INDEX:
                        HEAD_PIVOT_Y = box.get_center().y
        for i in range(6):
                _pivots.append(null)

        _nameplate = _make_nameplate()
        _nameplate.position = Vector3(0.0, RIG_HEIGHT + 0.9, 0.0)
        add_child(_nameplate)
        _nameplate.text = _display_name

        for index in _applied_colors:
                if index >= 0 and index < parts.size():
                        parts[index].material_override = _make_material(_applied_colors[index])
        return true


## Code-built classic box body — 5 studs tall, feet on y=0, facing -Z.
func _build_boxes() -> void:
        parts.clear()
        _pivots.clear()
        _part_sizes.clear()
        _part_aabb.clear()
        _mounts.clear()
        if _face_decal != null and is_instance_valid(_face_decal):
                _face_decal = null

        # limbs hang from pivots at shoulder (y=4) / hip (y=2)
        var limb_defs: Array = [
                [HEAD, Vector3(0, 4.0 + BOX_HEAD.y * 0.5 - 0.05, 0), BOX_HEAD, null],
                [TORSO, Vector3(0, 3.0, 0), BOX_TORSO, null],
                [ARM_L, Vector3(-1.5, 3.0, 0), BOX_ARM, Vector3(-1.5, 4.0, 0)],
                [ARM_R, Vector3(1.5, 3.0, 0), BOX_ARM, Vector3(1.5, 4.0, 0)],
                [LEG_L, Vector3(-0.5, 1.0, 0), BOX_LEG, Vector3(-0.5, 2.0, 0)],
                [LEG_R, Vector3(0.5, 1.0, 0), BOX_LEG, Vector3(0.5, 2.0, 0)],
        ]
        for def in limb_defs:
                var index: int = def[0]
                var center: Vector3 = def[1]
                var size: Vector3 = def[2]
                var pivot_pos: Variant = def[3]
                var holder: Node3D
                if pivot_pos != null:
                        var pivot := Node3D.new()
                        pivot.name = "Pivot_%d" % index
                        pivot.position = pivot_pos
                        add_child(pivot)
                        var mesh_node := MeshInstance3D.new()
                        mesh_node.name = "Part_%d" % index
                        mesh_node.position = center - pivot_pos  # limb center relative to its pivot
                        pivot.add_child(mesh_node)
                        holder = pivot
                        _pivots.append(pivot)
                else:
                        var mesh_node := MeshInstance3D.new()
                        mesh_node.name = "Part_%d" % index
                        mesh_node.position = center
                        add_child(mesh_node)
                        holder = mesh_node
                        _pivots.append(mesh_node)
                var mesh := BoxMesh.new()
                mesh.size = size
                var mi: MeshInstance3D
                if pivot_pos != null:
                        mi = holder.get_child(holder.get_child_count() - 1) as MeshInstance3D
                else:
                        mi = holder as MeshInstance3D
                mi.mesh = mesh
                parts.append(mi)
                _part_sizes.append(size)
                _part_aabb.append(AABB(-size * 0.5, size))
                var mount := Node3D.new()
                mount.name = "Mount_%d" % index
                mount.position = Vector3(0.0, 0.0, 0.0)
                holder.add_child(mount)
                # axis-aligned mount glued to the part's center (boxes are unrotated)
                if pivot_pos != null:
                        mount.position = center - pivot_pos
                else:
                        mount.position = Vector3.ZERO
                _mounts.append(mount)
        HEAD_PIVOT_Y = 4.0 + BOX_HEAD.y * 0.5 - 0.05

        _nameplate = _make_nameplate()
        _nameplate.position = Vector3(0.0, RIG_HEIGHT + 0.9, 0.0)
        add_child(_nameplate)
        _nameplate.text = _display_name


func _make_nameplate() -> Label3D:
        var label := Label3D.new()
        label.name = "Nameplate"
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.no_depth_test = true
        label.pixel_size = 0.012
        label.font_size = 44
        label.outline_size = 8
        label.modulate = Color.WHITE
        label.outline_modulate = Color(0, 0, 0, 0.85)
        label.text = _display_name
        return label


func _make_debris_piece(debris: Node3D, index: int) -> RigidBody3D:
        var source: MeshInstance3D = parts[index]
        var piece := RigidBody3D.new()
        piece.name = "BrokenPart_%d" % index
        piece.collision_layer = 2
        piece.collision_mask = 3
        piece.mass = 0.7
        piece.linear_damp = 0.35
        piece.angular_damp = 0.45
        debris.add_child(piece)
        piece.global_transform = source.global_transform
        var mesh_copy := MeshInstance3D.new()
        mesh_copy.name = "Mesh"
        mesh_copy.mesh = source.mesh
        mesh_copy.material_override = source.material_override
        for surface: int in range(source.mesh.get_surface_count()):
                var override := source.get_surface_override_material(surface)
                if override != null:
                        mesh_copy.set_surface_override_material(surface, override)
        piece.add_child(mesh_copy)
        var collision := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = _part_sizes[index]
        collision.shape = shape
        piece.add_child(collision)
        return piece


func _make_material(color: Color) -> StandardMaterial3D:
        var material := StandardMaterial3D.new()
        material.albedo_color = color
        material.roughness = 0.78
        return material


# ---------------------------------------------------------------- rig math

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


## Site-compatible part-name matcher: lowercase, drop $tags, separators ->
## spaces, strip trailing digits.
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
