class_name WorldBuilder
extends RefCounted
# Builds 3D worlds, applies stud materials, and configures Low/Medium/High/Ultra lighting tiers.
const STUD := 1.0
const STUD_SHADER_PATH := "res://assets/studs/part_studs.gdshader"
const STUD_TEX_PATH := "res://assets/studs/stud_tile.png"
const STUD_NORMAL_PATH := "res://assets/Materials/Studs 4x4 Normal Plastic.png"
const SPAWN_TEX_PATH := "res://assets/studs/SpawnPoint.png"

static var _stud_tex: Texture2D
static var _stud_normal_tex: Texture2D
static var _spawn_tex: Texture2D
static var _stud_shader: Shader


static func _scaled_group(root: Node3D, pos_units: Vector3) -> Node3D:
	var g := Node3D.new()
	g.position = pos_units
	g.scale = Vector3.ONE * STUD
	root.add_child(g)
	return g


static func configure_lighting(env: Environment, sun: DirectionalLight3D, def: Dictionary) -> void:
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(def.get("sky_top", "3b82c4"))
	sky_mat.sky_horizon_color = Color(def.get("sky_horizon", "9ec8e8"))
	sky_mat.ground_bottom_color = Color(def.get("sky_ground", "3a4e3c"))
	sky_mat.ground_horizon_color = Color(def.get("sky_horizon", "9ec8e8"))
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.10
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Balanced outdoor fill so grey baseplates read true mid-grey, never blown-out white
	env.ambient_light_energy = 0.42
	env.ambient_light_sky_contribution = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.92
	if bool(def.get("sky", true)) or bool(def.get("cloud_deck", false)):
		env.fog_enabled = true
		env.fog_light_color = Color("c5ddf0")
		env.fog_density = 0.0005 if not bool(def.get("cloud_deck", false)) else 0.0012
		env.fog_sky_affect = 0.04
	if sun != null:
		sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
		sun.light_energy = 0.80
		sun.light_color = Color("fff9ed")
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 110.0
		sun.shadow_blur = 0.85
		sun.shadow_bias = 0.03
		var settings: Node = Engine.get_main_loop().root.get_node_or_null("/root/Settings")
		if settings != null:
			_apply_sun_quality(sun, env, settings)
			settings.changed.connect(func(key: String, _value: Variant) -> void:
				if key in ["shadows", "graphics_quality"] and is_instance_valid(sun):
					_apply_sun_quality(sun, env, settings))


static func _apply_sun_quality(sun: DirectionalLight3D, env: Environment, settings: Node) -> void:
	var q := int(settings.get("graphics_quality"))
	var want_shadows := bool(settings.get("shadows"))
	sun.light_energy = 0.78
	sun.light_color = Color("fff8eb")
	sun.light_specular = 0.50
	var fill_light := sun.get_node_or_null("UltraSkyFill") as DirectionalLight3D
	if fill_light != null:
		fill_light.visible = false

	if env != null:
		env.glow_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.ssr_enabled = false
		env.adjustment_enabled = false
		env.fog_aerial_perspective = 0.0
		env.fog_sun_scatter = 0.0
		env.ambient_light_sky_contribution = 0.42
		env.ambient_light_energy = 0.38
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sm := env.sky.sky_material as ProceduralSkyMaterial
			sm.sun_angle_max = 18.0 if q == 3 else 24.0
			sm.sun_curve = 0.06 if q == 3 else 0.10
			sm.sky_energy_multiplier = 0.92 if q == 3 else 1.0

	match q:
		0: # Low — Most optimized (no shadows, no fog, fast rendering)
			sun.shadow_enabled = false
			if env != null:
				env.fog_enabled = false
				env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
				env.tonemap_exposure = 0.88
		1: # Medium — Balanced shadow range (65m)
			sun.shadow_enabled = want_shadows
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_blend_splits = false
			sun.directional_shadow_max_distance = 65.0
			sun.shadow_blur = 1.0
			sun.shadow_bias = 0.035
			sun.shadow_opacity = 0.80
			if env != null:
				env.fog_enabled = true
				env.fog_density = 0.0005
				env.fog_sky_affect = 0.04
				env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
				env.tonemap_exposure = 0.88
		2: # High — Crisp shadows (135m)
			sun.shadow_enabled = want_shadows
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_blend_splits = true
			sun.directional_shadow_max_distance = 135.0
			sun.shadow_blur = 0.80
			sun.shadow_bias = 0.025
			sun.shadow_opacity = 0.84
			if env != null:
				env.fog_enabled = true
				env.fog_density = 0.0005
				env.fog_sky_affect = 0.04
				env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
				env.tonemap_exposure = 0.86
		3: # Ultra — Less bright, rich natural contrast, high-precision 4-split blended shadows & realistic surface depth
			sun.shadow_enabled = want_shadows
			sun.light_energy = 0.72
			sun.light_color = Color(0.99, 0.95, 0.89)
			sun.light_specular = 0.65
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_blend_splits = true
			sun.directional_shadow_split_1 = 0.07
			sun.directional_shadow_split_2 = 0.20
			sun.directional_shadow_split_3 = 0.45
			sun.directional_shadow_max_distance = 175.0
			sun.shadow_blur = 0.55
			sun.shadow_bias = 0.015
			sun.shadow_normal_bias = 1.2
			sun.shadow_opacity = 0.88
			if env != null:
				env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
				env.tonemap_exposure = 0.78
				env.ambient_light_sky_contribution = 0.36
				env.ambient_light_energy = 0.32
				env.fog_enabled = true
				env.fog_light_color = Color(0.68, 0.79, 0.90)
				env.fog_density = 0.00045
				env.fog_sky_affect = 0.08
				env.fog_aerial_perspective = 0.22
				env.adjustment_enabled = true
				env.adjustment_brightness = 0.95
				env.adjustment_contrast = 1.08
				env.adjustment_saturation = 1.06


static func make_studded_material(color: Color) -> Material:
	return _part_material(color, "plastic", stud_texture(), false)


static func prepare_scene_world(world_root: Node3D) -> Array[Vector3]:
	var spawns: Array[Vector3] = []
	var tex := stud_texture()
	for child in world_root.get_children():
		if child is StaticBody3D:
			var sb := child as StaticBody3D
			if sb.is_in_group("ladder") or sb.is_in_group("climb"):
				sb.collision_layer |= 16
			if sb.has_method("_rebuild_visuals"):
				sb.call("_rebuild_visuals")
				if sb.is_in_group("spawn"):
					spawns.append(sb.position + Vector3(0.0, 0.7 * STUD, 0.0))
				continue
			var col_size := Vector3(4, 1, 4)
			for c in sb.get_children():
				if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
					col_size = ((c as CollisionShape3D).shape as BoxShape3D).size
				if c is MeshInstance3D:
					var mi := c as MeshInstance3D
					if mi.name == "SpawnDecal" or mi.name.begins_with("Decal"):
						continue
					var mat_kind := String(sb.get_meta("mat", "plastic"))
					var no_studs := bool(sb.get_meta("no_studs", false))
					var col_hex := String(sb.get_meta("color", ""))
					var col := Color(col_hex) if col_hex != "" else Color("8f8f8f")
					if col_hex == "":
						var mat_src: Material = mi.material_override
						if mat_src == null:
							mat_src = mi.get_surface_override_material(0)
						if mat_src == null and mi.mesh != null:
							mat_src = mi.mesh.material
						if mat_src is StandardMaterial3D:
							col = (mat_src as StandardMaterial3D).albedo_color
						elif mat_src is ShaderMaterial:
							var p_col: Variant = (mat_src as ShaderMaterial).get_shader_parameter("albedo")
							if p_col is Color:
								col = p_col
					mi.material_override = _part_material(col, mat_kind, tex, no_studs)
			if sb.is_in_group("spawn"):
				if sb.get_node_or_null("SpawnDecal") == null:
					_spawn_pad_visual(sb, Vector3.ZERO, col_size)
				spawns.append(sb.position + Vector3(0.0, col_size.y * 0.5 + 0.2 * STUD, 0.0))
	return spawns


static func build(def: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "World"

	var env := Environment.new()
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	root.add_child(sun)
	configure_lighting(env, sun, def)

	if bool(def.get("cloud_deck", false)):
		_cloud_deck(root)

	var spawns: Array[Vector3] = []
	var tex := stud_texture()
	for part in def.get("parts", []):
		_build_part(root, part, tex, spawns)

	for prop in def.get("props", []):
		_build_prop(root, prop, tex)

	return { "root": root, "spawns": spawns }


static func _vivid(c: Color, _strength := 1.0) -> Color:
	return c


static func _build_part(root: Node3D, part: Dictionary, tex: Texture2D, spawns: Array[Vector3]) -> void:
	var p: Array = part.get("p", [0, 0, 0])
	var s: Array = part.get("s", [4, 1, 4])
	var group: String = part.get("g", "")
	var mat_kind: String = part.get("m", "plastic")
	var pos := Vector3(float(p[0]), float(p[1]), float(p[2])) * STUD
	var size := Vector3(float(s[0]), float(s[1]), float(s[2])) * STUD
	var color := Color(part.get("c", "a3a2a5"))
	var shape: String = part.get("shape", "box")

	if group == "moving_platform" or String(part.get("type", "")) == "moving_platform":
		var mp_script := load("res://scripts/world/moving_platform.gd")
		if mp_script != null:
			var mp: Node3D = mp_script.new()
			mp.position = pos
			mp.set("block_size", Vector3(float(s[0]), float(s[1]), float(s[2])))
			mp.set("block_color", color)
			if part.has("point_a"):
				mp.set("point_a", _s3(part["point_a"], Vector3.ZERO))
			if part.has("point_b"):
				mp.set("point_b", _s3(part["point_b"], Vector3(0, 0, 14)))
			elif part.has("offset"):
				mp.set("point_b", _s3(part["offset"], Vector3(0, 0, 14)))
			if part.has("move_on_stand"):
				mp.set("move_on_player_stand", bool(part["move_on_stand"]))
			if part.has("move_mode"):
				mp.set("move_mode", int(part["move_mode"]))
			if part.has("easing"):
				mp.set("easing", String(part["easing"]))
			if part.has("duration"):
				mp.set("move_duration", float(part["duration"]))
			if part.has("wait"):
				mp.set("wait_time", float(part["wait"]))
			root.add_child(mp)
			return

	if group == "ladder" or group == "climb":
		var lad_body := StaticBody3D.new()
		lad_body.position = pos
		lad_body.collision_layer = 1 | 16
		lad_body.collision_mask = 0
		lad_body.add_to_group("ladder")
		var lc := CollisionShape3D.new()
		var lshape := BoxShape3D.new()
		lshape.size = size
		lc.shape = lshape
		lad_body.add_child(lc)
		root.add_child(lad_body)
		_ladder_visual(root, pos, size)
		return

	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var mesh_node := MeshInstance3D.new()
	var mesh: Mesh
	var col_shape: Shape3D
	match shape:
		"cyl":
			var cyl := CylinderMesh.new()
			cyl.height = size.y
			cyl.top_radius = size.x * 0.5
			cyl.bottom_radius = size.x * 0.5
			mesh = cyl
			var cshape := CylinderShape3D.new()
			cshape.height = size.y
			cshape.radius = size.x * 0.5
			col_shape = cshape
		"sphere":
			var sph := SphereMesh.new()
			sph.radius = size.x * 0.5
			sph.height = size.x
			mesh = sph
			var sshape := SphereShape3D.new()
			sshape.radius = size.x * 0.5
			col_shape = sshape
		_:
			var box := BoxMesh.new()
			box.size = size
			mesh = box
			var bshape := BoxShape3D.new()
			bshape.size = size
			col_shape = bshape
	shape_node.shape = col_shape
	body.add_child(shape_node)

	mesh_node.mesh = mesh
	mesh_node.material_override = _part_material(color, mat_kind, tex, part.get("no_studs", false))
	body.add_child(mesh_node)

	if shape == "box" and size.x >= 1.0 and size.y >= 1.0 and size.z >= 1.0:
		var occ := OccluderInstance3D.new()
		occ.name = "Occluder"
		var box_occ := BoxOccluder3D.new()
		box_occ.size = size
		occ.occluder = box_occ
		body.add_child(occ)

	if group != "":
		body.add_to_group(group)
	if part.has("damage"):
		body.set_meta("damage", float(part["damage"]))
	if part.has("heal"):
		body.set_meta("heal", float(part["heal"]))
	if group == "spawn":
		spawns.append(pos + Vector3(0.0, size.y * 0.5 + 0.2 * STUD, 0.0))
		_spawn_pad_visual(root, pos, size)
	if group == "checkpoint":
		body.set_meta("spawn", pos + Vector3(0.0, size.y * 0.5 + 0.2 * STUD, 0.0))
	if group == "goal":
		_goal_sparkle(root, pos + Vector3(0.0, size.y * 0.5 + 0.6 * STUD, 0.0))
	root.add_child(body)


static func _goal_sparkle(root: Node3D, at: Vector3) -> void:
	var fx := CPUParticles3D.new()
	fx.name = "GoalSparkle"
	fx.amount = 14
	fx.lifetime = 1.6
	fx.preprocess = 1.2
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fx.emission_sphere_radius = 2.2 * STUD
	fx.direction = Vector3.UP
	fx.spread = 30.0
	fx.initial_velocity_min = 0.6 * STUD
	fx.initial_velocity_max = 1.6 * STUD
	fx.gravity = Vector3.ZERO
	fx.scale_amount_min = 0.06 * STUD
	fx.scale_amount_max = 0.16 * STUD
	fx.mesh = BoxMesh.new()
	(fx.mesh as BoxMesh).size = Vector3.ONE
	fx.color = Color("ffe37a")
	fx.position = at
	root.add_child(fx)


static func _build_prop(root: Node3D, prop: Dictionary, tex: Texture2D) -> void:
	var p: Array = prop.get("p", [0, 0, 0])
	var pos := Vector3(float(p[0]), float(p[1]), float(p[2])) * STUD
	match String(prop.get("type", "")):
		"tree":
			_tree(root, pos, float(prop.get("h", 7.0)))
		"flower":
			_flower(root, pos, Color(prop.get("c", "e8333f")))
		"fence":
			_fence(root, pos, _s3(prop.get("s", [6, 1.4, 0.35]), Vector3(6, 1.4, 0.35)), prop.get("yaw", 0.0))
		"crate":
			_crate(root, pos, _s3(prop.get("s", [2.4, 2.4, 2.4]), Vector3(2.4, 2.4, 2.4)) * STUD)
		"cloud":
			_cloud(root, pos, float(prop.get("s", 6.0)))
		"cloudpad":
			var ps := _s3(prop.get("s", [8, 8]), Vector3(8, 8, 0))
			_cloudpad(root, pos, Vector2(float(ps[0]), float(ps[1])) * STUD, tex)
		"sign":
			_sign(root, pos, String(prop.get("title", "")), String(prop.get("text", "")),
				Vector2(float(prop.get("w", 14.0)), float(prop.get("h", 7.0))),
				float(prop.get("yaw", 0.0)), prop.get("c", "27c7d8"), prop.get("title_c", "ffd400"))
		"pipe":
			_pipe(root, pos, float(prop.get("h", 6.0)) * STUD, float(prop.get("r", 2.0)) * STUD)
		"arch":
			_arch(root, pos, float(prop.get("yaw", 0.0)))
		"house":
			_house(root, pos)
		"snow":
			_snow(root, pos, _s3(prop.get("s", [5, 2, 5]), Vector3(5, 2, 5)))


static func _s3(v: Variant, fallback: Vector3) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 2:
		return Vector3(float(v[0]), float(v[1]), fallback.z)
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return Vector3(float(v), float(v), float(v))
	return fallback


static func _tree(root: Node3D, pos: Vector3, h: float) -> void:
	var group := _scaled_group(root, pos)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.height = h * 0.55
	tm.top_radius = 0.42
	tm.bottom_radius = 0.55
	trunk.mesh = tm
	trunk.material_override = _flat_mat(Color("8a5a33"), 0.92)
	trunk.position = Vector3(0.0, h * 0.275, 0.0)
	group.add_child(trunk)
	var leaf := Color("2e9e3e")
	var canopy := Node3D.new()
	canopy.position = Vector3(0.0, h * 0.55, 0.0)
	group.add_child(canopy)
	var blobs: Array = [
		[Vector3(0.0, 1.4, 0.0), 2.6],
		[Vector3(1.3, 0.6, 0.5), 1.9],
		[Vector3(-1.2, 0.7, -0.4), 1.8],
	]
	for blob in blobs:
		var off: Vector3 = blob[0]
		var r: float = blob[1]
		var ball := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = r
		bm.height = r * 2.0
		ball.mesh = bm
		ball.material_override = _flat_mat(leaf, 0.85)
		ball.position = off
		canopy.add_child(ball)


static func _flower(root: Node3D, pos: Vector3, color: Color) -> void:
	var group := _scaled_group(root, pos)
	var stem := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.16, 1.1, 0.16)
	stem.mesh = sm
	stem.material_override = _flat_mat(Color("3e9b3e"), 0.85)
	stem.position = Vector3(0.0, 0.55, 0.0)
	group.add_child(stem)
	var head := Node3D.new()
	head.position = Vector3(0.0, 1.2, 0.0)
	group.add_child(head)
	var petal := Color(color)
	var yellow := Color("ffd400")
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var pet := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(1.0, 0.42, 0.72)
		pet.mesh = pm
		pet.material_override = _flat_mat(petal, 0.8)
		pet.position = dir * 0.62
		head.add_child(pet)
	var center := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.62, 0.5, 0.62)
	center.mesh = cm
	center.material_override = _flat_mat(yellow, 0.8)
	head.add_child(center)


static func _fence(root: Node3D, pos: Vector3, size: Vector3, yaw_deg: float) -> void:
	var wood := Color("7a4b28")
	var group := _scaled_group(root, pos)
	group.rotation_degrees.y = yaw_deg
	var rail_len := size.x
	for off in [-0.28, 0.28]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(rail_len, 0.22, 0.16)
		rail.mesh = rm
		rail.material_override = _flat_mat(wood, 0.9)
		rail.position = Vector3(0.0, size.y * (0.62 if off > 0 else 0.34), off)
		group.add_child(rail)
	var posts := int(rail_len / 2.4) + 1
	for i in range(posts):
		var px := -rail_len * 0.5 + (rail_len * float(i) / float(posts - 1)) if posts > 1 else 0.0
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.26, size.y + 0.3, 0.26)
		post.mesh = pm
		post.material_override = _flat_mat(wood.darkened(0.1), 0.9)
		post.position = Vector3(px, size.y * 0.5, 0.0)
		group.add_child(post)


static func _crate(root: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _flat_mat(Color("a3703f"), 0.9)
	body.add_child(mi)
	root.add_child(body)
	var frame := Color("6d4523")
	for axis in range(3):
		for sign_i in [-1.0, 1.0]:
			var bar := MeshInstance3D.new()
			var bm := BoxMesh.new()
			if axis == 0:
				bm.size = Vector3(size.x * 1.02, 0.24 * STUD, 0.24 * STUD)
				bar.position = Vector3(0.0, 0.0, sign_i * size.z * 0.51)
			elif axis == 1:
				bm.size = Vector3(0.24 * STUD, size.y * 1.02, 0.24 * STUD)
				bar.position = Vector3(sign_i * size.x * 0.51, 0.0, 0.0)
			else:
				bm.size = Vector3(0.24 * STUD, 0.24 * STUD, size.z * 1.02)
				bar.position = Vector3(0.0, sign_i * size.y * 0.51, 0.0)
			bar.mesh = bm
			bar.material_override = _flat_mat(frame, 0.9)
			body.add_child(bar)


static func _cloud(root: Node3D, pos: Vector3, scale: float) -> void:
	var group := _scaled_group(root, pos)
	var white := Color(1.0, 1.0, 1.0, 1.0)
	var puffs: Array = [
		[Vector3(0, 0, 0), 2.6], [Vector3(2.2, -0.3, 0.6), 2.0],
		[Vector3(-2.1, -0.4, -0.5), 2.1], [Vector3(0.7, 0.8, -0.7), 1.7],
	]
	for puff in puffs:
		var off: Vector3 = puff[0]
		var r: float = puff[1]
		var ball := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = r * scale * 0.22
		bm.height = r * scale * 0.44
		ball.mesh = bm
		var m := _flat_mat(white, 1.0)
		m.roughness = 1.0
		ball.material_override = m
		ball.position = off * scale * 0.35
		group.add_child(ball)


static func _cloud_deck(root: Node3D) -> void:
	var group := _scaled_group(root, Vector3.ZERO)
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(900.0, 3.0, 900.0)
	deck.mesh = dm
	var m := _flat_mat(Color("f6fbff"), 1.0)
	deck.material_override = m
	deck.position = Vector3(0.0, -36.5, 0.0)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(deck)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20250704
	for i in range(26):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(55.0, 330.0)
		var pos := Vector3(cos(ang) * dist, rng.randf_range(-34.0, -27.0), sin(ang) * dist)
		_cloud(group, pos, rng.randf_range(9.0, 17.0))


static func _cloudpad(root: Node3D, pos: Vector3, size: Vector2, _tex: Texture2D) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 1.2 * STUD, size.y)
	col.shape = shape
	body.add_child(col)
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(size.x, 1.2 * STUD, size.y)
	top.mesh = tm
	var white := Color("ffffff")
	var m := _flat_mat(white, 1.0)
	top.material_override = m
	body.add_child(top)
	root.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 7.0 + pos.z * 13.0) + 977
	var perim := int((size.x + size.y) * 0.5 / STUD)
	for i in range(perim * 2):
		var px := lerpf(-size.x * 0.5, size.x * 0.5, rng.randf())
		var pz := lerpf(-size.y * 0.5, size.y * 0.5, rng.randf())
		if absf(px) < size.x * 0.42 and absf(pz) < size.y * 0.42:
			continue
		var r := rng.randf_range(1.1, 2.0) * STUD
		var ball := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = r
		bm.height = r * 2.0
		ball.mesh = bm
		ball.material_override = _flat_mat(white, 1.0)
		ball.position = Vector3(px, rng.randf_range(-0.9, -0.2) * STUD, pz)
		body.add_child(ball)


static func _sign(root: Node3D, pos: Vector3, title: String, body_text: String, board: Vector2, yaw_deg: float, board_color: String, title_color: String) -> void:
	var group := _scaled_group(root, pos)
	group.rotation_degrees.y = yaw_deg
	for sx in [-board.x * 0.38, board.x * 0.38]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.5, board.y, 0.5)
		post.mesh = pm
		post.material_override = _flat_mat(Color("4f6f8f"), 0.6)
		post.position = Vector3(sx, 0.0, 0.0)
		group.add_child(post)
	var board_node := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(board.x, board.y, 0.5)
	board_node.mesh = bm
	var m := _flat_mat(Color(board_color), 0.55)
	board_node.material_override = m
	board_node.position = Vector3(0.0, board.y * 0.75, 0.0)
	group.add_child(board_node)
	if title != "":
		var title_label := Label3D.new()
		title_label.text = title
		title_label.font_size = 220
		title_label.pixel_size = 0.004
		title_label.outline_size = 18
		title_label.modulate = Color(title_color)
		title_label.outline_modulate = Color("123a44")
		title_label.position = Vector3(0.0, board.y * 1.12, 0.32)
		group.add_child(title_label)
	if body_text != "":
		var body_label := Label3D.new()
		body_label.text = body_text
		body_label.font_size = 120
		body_label.pixel_size = 0.004
		body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		body_label.modulate = Color("eafcff")
		body_label.outline_size = 8
		body_label.outline_modulate = Color(0.05, 0.15, 0.18, 0.8)
		body_label.position = Vector3(-board.x * 0.44, board.y * 0.72, 0.32)
		group.add_child(body_label)


static func _pipe(root: Node3D, pos: Vector3, h: float, r: float) -> void:
	var green := Color("2ea82e")
	var shaft := StaticBody3D.new()
	shaft.position = pos + Vector3(0.0, h * 0.5, 0.0)
	shaft.collision_layer = 1
	shaft.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.height = h
	shape.radius = r
	col.shape = shape
	shaft.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.height = h
	mesh.top_radius = r
	mesh.bottom_radius = r
	mi.mesh = mesh
	mi.material_override = _flat_mat(green, 0.55)
	shaft.add_child(mi)
	root.add_child(shaft)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.height = 1.2 * STUD
	rm.top_radius = r * 1.16
	rm.bottom_radius = r * 1.16
	rim.mesh = rm
	rim.material_override = _flat_mat(green.darkened(0.05), 0.55)
	rim.position = pos + Vector3(0.0, h - 0.4 * STUD, 0.0)
	root.add_child(rim)


static func _arch(root: Node3D, pos: Vector3, yaw_deg: float) -> void:
	var group := _scaled_group(root, pos)
	group.rotation_degrees.y = yaw_deg
	var brick := Color("c86a2e")
	for sx in [-3.2, 3.2]:
		var pillar := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(1.6, 10.0, 1.6)
		pillar.mesh = pm
		pillar.material_override = _flat_mat(brick, 0.85)
		pillar.position = Vector3(sx, 5.0, 0.0)
		group.add_child(pillar)
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(8.0, 2.2, 1.8)
	top.mesh = tm
	top.material_override = _flat_mat(brick, 0.85)
	top.position = Vector3(0.0, 10.8, 0.0)
	group.add_child(top)
	var board_mesh := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(5.2, 1.1, 0.5)
	board_mesh.mesh = sm
	board_mesh.material_override = _flat_mat(Color("20232a"), 0.7)
	board_mesh.position = Vector3(0.0, 12.4, 0.0)
	group.add_child(board_mesh)
	var sign_text := Label3D.new()
	sign_text.text = "NEW GAMES"
	sign_text.font_size = 96
	sign_text.pixel_size = 0.006
	sign_text.modulate = Color("7ee0ff")
	sign_text.position = Vector3(0.0, 12.4, 0.3)
	group.add_child(sign_text)
	var portal := MeshInstance3D.new()
	var pm2 := BoxMesh.new()
	pm2.size = Vector3(5.0, 9.0, 0.3)
	portal.mesh = pm2
	var glow := _flat_mat(Color("1b6fae"), 0.2)
	glow.emission_enabled = true
	glow.emission = Color("2f9ee8")
	glow.emission_energy_multiplier = 1.6
	portal.material_override = glow
	portal.position = Vector3(0.0, 4.6, 0.0)
	group.add_child(portal)


static func _house(root: Node3D, pos: Vector3) -> void:
	var group := _scaled_group(root, pos)
	var wall := Color("c9a06a")
	var walls := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(10, 7, 8)
	walls.mesh = wm
	walls.material_override = _flat_mat(wall, 0.9)
	walls.position = Vector3(0.0, 3.5, 0.0)
	group.add_child(walls)
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(11.4, 1.4, 9.4)
	roof.mesh = rm
	roof.material_override = _flat_mat(Color("8a2f2f"), 0.85)
	roof.position = Vector3(0.0, 7.7, 0.0)
	group.add_child(roof)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(2.2, 4.4, 0.3)
	door.mesh = dm
	door.material_override = _flat_mat(Color("5d3a20"), 0.9)
	door.position = Vector3(0.0, 2.2, 4.05)
	group.add_child(door)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.16
	km.height = 0.32
	knob.mesh = km
	knob.material_override = _flat_mat(Color("ffd400"), 0.4)
	knob.position = Vector3(0.7, 2.2, 4.25)
	group.add_child(knob)
	for wx in [-4.0, 4.0]:
		var window := MeshInstance3D.new()
		var wm2 := BoxMesh.new()
		wm2.size = Vector3(1.8, 1.8, 0.24)
		window.mesh = wm2
		window.material_override = _flat_mat(Color("9ed3f0"), 0.2)
		window.position = Vector3(wx, 4.2, 4.05)
		group.add_child(window)


static func _snow(root: Node3D, pos: Vector3, size: Vector3) -> void:
	var group := _scaled_group(root, pos)
	var mound := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size.x * 0.5
	sm.height = size.y * 2.0
	mound.mesh = sm
	mound.material_override = _flat_mat(Color("f4fbff"), 1.0)
	mound.position = Vector3(0.0, -size.y * 0.35, 0.0)
	group.add_child(mound)


static func stud_texture() -> Texture2D:
	if _stud_tex != null and is_instance_valid(_stud_tex):
		return _stud_tex
	var abs_path := ProjectSettings.globalize_path(STUD_TEX_PATH)
	if FileAccess.file_exists(abs_path):
		var raw_img := Image.load_from_file(abs_path)
		if raw_img != null and not raw_img.is_empty():
			raw_img.generate_mipmaps()
			_stud_tex = ImageTexture.create_from_image(raw_img)
			return _stud_tex
	if ResourceLoader.exists(STUD_TEX_PATH):
		var loaded: Texture2D = load(STUD_TEX_PATH)
		if loaded != null:
			_stud_tex = loaded
			return _stud_tex
	# Procedural fallback matching stud_tile.png
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var center := float(n) * 0.5
	var outer_r := float(n) * 0.33
	var inner_r := float(n) * 0.275
	for y in range(n):
		for x in range(n):
			var edge_d := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			var col := 0.80 if edge_d == 0 else (0.88 if edge_d == 1 else 0.94)
			var dx := float(x) + 0.5 - center
			var dy := float(y) + 0.5 - center
			var d := sqrt(dx * dx + dy * dy)
			var ldot := ((-dx / maxf(d, 0.001)) * 0.7071) + ((-dy / maxf(d, 0.001)) * 0.7071)
			if d <= inner_r:
				col = 0.98 + ldot * 0.03
			elif d <= outer_r:
				var tw := (d - inner_r) / (outer_r - inner_r)
				col = 0.84 + ldot * 0.24 * sin(tw * PI)
			img.set_pixel(x, y, Color(col, col, col, 1.0))
	img.generate_mipmaps()
	_stud_tex = ImageTexture.create_from_image(img)
	return _stud_tex


static func stud_normal_texture() -> Texture2D:
	if _stud_normal_tex != null and is_instance_valid(_stud_normal_tex):
		return _stud_normal_tex
	if ResourceLoader.exists(STUD_NORMAL_PATH):
		var loaded: Texture2D = load(STUD_NORMAL_PATH)
		if loaded != null:
			_stud_normal_tex = loaded
			return _stud_normal_tex
	var abs_path := ProjectSettings.globalize_path(STUD_NORMAL_PATH)
	if FileAccess.file_exists(abs_path):
		var raw_img := Image.load_from_file(abs_path)
		if raw_img != null and not raw_img.is_empty():
			raw_img.generate_mipmaps()
			_stud_normal_tex = ImageTexture.create_from_image(raw_img)
			return _stud_normal_tex
	return null


static func spawn_texture() -> Texture2D:
	if _spawn_tex != null and is_instance_valid(_spawn_tex):
		return _spawn_tex
	if ResourceLoader.exists(SPAWN_TEX_PATH):
		var loaded: Texture2D = load(SPAWN_TEX_PATH)
		if loaded != null:
			_spawn_tex = loaded
			return _spawn_tex
	var abs_path := ProjectSettings.globalize_path(SPAWN_TEX_PATH)
	if FileAccess.file_exists(abs_path):
		var raw_img := Image.load_from_file(abs_path)
		if raw_img != null and not raw_img.is_empty():
			raw_img.generate_mipmaps()
			_spawn_tex = ImageTexture.create_from_image(raw_img)
			return _spawn_tex
	return null


static func _flat_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


static func _part_material(color: Color, kind: String, tex: Texture2D, no_studs: bool) -> Material:
	if kind == "plastic" and not no_studs:
		if _stud_shader == null and ResourceLoader.exists(STUD_SHADER_PATH):
			_stud_shader = load(STUD_SHADER_PATH)
		if _stud_shader != null:
			var sm := ShaderMaterial.new()
			sm.shader = _stud_shader
			sm.set_shader_parameter("albedo", color)
			sm.set_shader_parameter("stud_tex", tex)
			var ntex := stud_normal_texture()
			if ntex != null:
				sm.set_shader_parameter("stud_normal_tex", ntex)
			sm.set_shader_parameter("stud_density", 1.0 / STUD)
			sm.set_shader_parameter("normal_depth", 1.35)
			sm.set_shader_parameter("roughness_val", 0.38)
			sm.set_shader_parameter("specular_val", 0.52)
			return sm
	var m := StandardMaterial3D.new()
	match kind:
		"metal":
			m.albedo_color = color
			m.metallic = 0.85
			m.roughness = 0.34
			m.metallic_specular = 0.85
		"neon":
			m.albedo_color = color
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = 1.25
			m.roughness = 0.6
		"wood":
			m.albedo_color = color.darkened(0.08)
			m.roughness = 0.92
		_:
			m.albedo_color = color
			m.roughness = 0.72
	if kind == "plastic" and not no_studs:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / STUD
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _ladder_visual(root: Node3D, pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("6b6f74")
	m.metallic = 0.75
	m.roughness = 0.45
	mi.material_override = m
	mi.position = pos
	root.add_child(mi)


static func _spawn_pad_visual(root: Node3D, pos: Vector3, size: Vector3) -> void:
	var decal := MeshInstance3D.new()
	decal.name = "SpawnDecal"
	var pm := PlaneMesh.new()
	var d_sz: float = minf(size.x, size.z) * 0.90
	pm.size = Vector2(d_sz, d_sz)
	decal.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.albedo_texture = spawn_texture()
	sm.roughness = 0.48
	sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	decal.material_override = sm
	decal.position = pos + Vector3(0.0, size.y * 0.5 + 0.02 * STUD, 0.0)
	root.add_child(decal)
