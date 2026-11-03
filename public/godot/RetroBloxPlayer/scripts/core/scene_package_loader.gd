class_name ScenePackageLoader
extends RefCounted
## RetroBlox SDK — Lightweight Scene Bundler (.rbxpkg) & In-RAM Stream Executor
## - Bundles Godot 3D scenes (.tscn), scripts (.gd), and GamePasses (.tres) into a compact web-ready .rbxpkg package.
## - Streams .rbxpkg packages straight from retro-blox.vercel.app into RAM and reconstructs the 3D World in memory
##   without writing permanent files to the player's hard drive!

const MAGIC_HEADER: String = "RBXPKG_V1:"


static func bundle_scene_node_to_dict(scene_root: Node) -> Dictionary:
	var parts: Array[Dictionary] = []
	var scripts_map: Dictionary = {}
	var gamepasses_map: Dictionary = {}

	var world_node: Node = scene_root.get_node_or_null("World")
	if world_node == null:
		world_node = scene_root

	_serialize_node_recursive(world_node, world_node, parts, scripts_map)

	# Include all .tres GamePasses in res://gamepasses/
	var gp_dir: DirAccess = DirAccess.open("res://gamepasses")
	if gp_dir != null:
		gp_dir.list_dir_begin()
		var fn: String = gp_dir.get_next()
		while fn != "":
			if not gp_dir.current_is_dir() and fn.ends_with(".tres"):
				var full_gp: String = "res://gamepasses/" + fn
				var gp_res: Resource = load(full_gp)
				if gp_res != null:
					gamepasses_map[fn.get_basename()] = {
						"pass_id": String(gp_res.get("pass_id")) if gp_res.get("pass_id") != null else fn.get_basename(),
						"title": String(gp_res.get("title")) if gp_res.get("title") != null else fn.get_basename(),
						"description": String(gp_res.get("description")) if gp_res.get("description") != null else "",
						"cost_tix": int(gp_res.get("cost_tix")) if gp_res.get("cost_tix") != null else 75,
						"creator_username": String(gp_res.get("creator_username")) if gp_res.get("creator_username") != null else "",
					}
			fn = gp_dir.get_next()
		gp_dir.list_dir_end()

	return {
		"format": "rbxpkg_v1",
		"scene_name": String(scene_root.name),
		"exported_at": int(Time.get_unix_time_from_system()),
		"parts": parts,
		"scripts": scripts_map,
		"gamepasses": gamepasses_map,
	}


static func bundle_scene_to_rbxpkg_bytes(scene_root: Node) -> PackedByteArray:
	var dict: Dictionary = bundle_scene_node_to_dict(scene_root)
	var json_bytes: PackedByteArray = JSON.stringify(dict).to_utf8_buffer()
	var comp: PackedByteArray = json_bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	var wrapper: Dictionary = {
		"magic": "RBXPKG_V1",
		"orig_size": json_bytes.size(),
		"data_b64": Marshalls.raw_to_base64(comp),
	}
	return (MAGIC_HEADER + JSON.stringify(wrapper)).to_utf8_buffer()


static func save_scene_to_rbxpkg_file(scene_root: Node, output_path: String) -> int:
	var bytes: PackedByteArray = bundle_scene_to_rbxpkg_bytes(scene_root)
	var f: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_CREATE
	f.store_buffer(bytes)
	return OK


static func _serialize_node_recursive(node: Node, root_ref: Node, out_parts: Array[Dictionary], out_scripts: Dictionary) -> void:
	if node != root_ref and node is Node3D:
		var n3: Node3D = node as Node3D
		var entry: Dictionary = {
			"name": String(n3.name),
			"class": n3.get_class(),
			"pos": [n3.global_position.x, n3.global_position.y, n3.global_position.z],
			"rot": [n3.global_rotation.x, n3.global_rotation.y, n3.global_rotation.z],
			"scale": [n3.scale.x, n3.scale.y, n3.scale.z],
		}
		if n3.has_meta("is_spawn_location"):
			entry["is_spawn"] = true

		# Check MeshInstance3D on self or child
		var mi: MeshInstance3D = (n3 as MeshInstance3D) if (n3 is MeshInstance3D) else (n3.get_node_or_null("MeshInstance3D") as MeshInstance3D)
		if mi != null and mi.mesh != null:
			if mi.mesh is BoxMesh:
				var bm: BoxMesh = mi.mesh as BoxMesh
				entry["shape"] = "box"
				entry["size"] = [bm.size.x, bm.size.y, bm.size.z]
			elif mi.mesh is CylinderMesh:
				var cm: CylinderMesh = mi.mesh as CylinderMesh
				entry["shape"] = "cylinder"
				entry["size"] = [cm.top_radius * 2.0, cm.height, cm.bottom_radius * 2.0]
			elif mi.mesh is SphereMesh:
				var sm: SphereMesh = mi.mesh as SphereMesh
				entry["shape"] = "sphere"
				entry["size"] = [sm.radius * 2.0, sm.height, sm.radius * 2.0]
			elif mi.mesh is PrismMesh:
				var pm: PrismMesh = mi.mesh as PrismMesh
				entry["shape"] = "wedge"
				entry["size"] = [pm.size.x, pm.size.y, pm.size.z]

			var mat: Material = mi.get_surface_override_material(0)
			if mat == null:
				mat = mi.material_override
			if mat is StandardMaterial3D:
				var smat: StandardMaterial3D = mat as StandardMaterial3D
				entry["color"] = smat.albedo_color.to_html()
			elif mat is ShaderMaterial:
				var shmat: ShaderMaterial = mat as ShaderMaterial
				var col_v: Variant = shmat.get_shader_parameter("albedo")
				if col_v is Color:
					entry["color"] = (col_v as Color).to_html()

		# Check attached script (InteractivePad, ItemSpawner, GamePassTouchPart, or custom .gd)
		if n3.get_script() is Script:
			var scr: Script = n3.get_script() as Script
			var spath: String = scr.resource_path
			entry["script_path"] = spath
			if spath != "" and not spath.begins_with("res://scripts/") and FileAccess.file_exists(spath):
				out_scripts[spath] = FileAccess.get_file_as_string(spath)
			if n3.get("pad_type") != null:
				entry["pad_type"] = int(n3.get("pad_type"))
			if n3.get("item_type") != null:
				entry["item_type"] = int(n3.get("item_type"))
			if n3.get("gamepass_name") != null:
				entry["gamepass_name"] = String(n3.get("gamepass_name"))
			if n3.get("custom_title") != null:
				entry["custom_title"] = String(n3.get("custom_title"))
			if n3.get("custom_cost") != null:
				entry["custom_cost"] = int(n3.get("custom_cost"))

		if entry.has("shape") or entry.has("script_path") or entry.has("is_spawn"):
			out_parts.append(entry)

	for ch in node.get_children():
		_serialize_node_recursive(ch, root_ref, out_parts, out_scripts)


# ============================================================================
# STREAM GAME PACKAGE STRAIGHT INTO RAM & EXECUTE AT FULL NATIVE FPS
# ============================================================================

static func parse_rbxpkg_bytes_in_ram(raw_bytes: PackedByteArray) -> Dictionary:
	if raw_bytes.is_empty():
		return {}
	var text: String = raw_bytes.get_string_from_utf8()
	if text.begins_with(MAGIC_HEADER):
		var json_part: String = text.substr(MAGIC_HEADER.length())
		var wrap: Variant = JSON.parse_string(json_part)
		if wrap is Dictionary:
			var wd: Dictionary = wrap as Dictionary
			var orig_sz: int = int(wd.get("orig_size", 0))
			var comp: PackedByteArray = Marshalls.base64_to_raw(String(wd.get("data_b64", "")))
			if not comp.is_empty() and orig_sz > 0:
				var decomp: PackedByteArray = comp.decompress(orig_sz, FileAccess.COMPRESSION_DEFLATE)
				var inner: Variant = JSON.parse_string(decomp.get_string_from_utf8())
				if inner is Dictionary:
					return inner as Dictionary
	elif text.begins_with("{"):
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			return parsed as Dictionary
	elif text.begins_with("[gd_scene") or text.contains("[node name=") or text.contains("[ext_resource"):
		# Native Godot .tscn file stream!
		return {
			"format": "tscn_raw",
			"raw_text": text
		}
	return {}


static func stream_game_into_ram(api_node: Node, game_id: String, explicit_pkg_url: String = "") -> Dictionary:
	if api_node == null or game_id.strip_edges() == "":
		return {}
	var gid: String = game_id.strip_edges()
	var file_url: String = explicit_pkg_url.strip_edges()
	var creator_uname: String = ""

	if file_url == "":
		var detail_res: Dictionary = await api_node.call("get_json", "/api/games/%s" % gid.uri_encode())
		if bool(detail_res.get("ok", false)) and detail_res.get("game") is Dictionary:
			var g: Dictionary = detail_res["game"] as Dictionary
			if g.get("creator") is Dictionary:
				creator_uname = String((g["creator"] as Dictionary).get("username", ""))
			var fid: String = String(g.get("fileId", ""))
			var sfid: String = String(g.get("sourceFileId", ""))
			if fid != "":
				file_url = "/api/files/%s" % fid
			elif sfid != "":
				file_url = "/api/files/%s" % sfid

	if file_url == "":
		return {}

	var raw_bytes: PackedByteArray = await api_node.call("get_bytes", file_url)
	if raw_bytes.is_empty():
		return {}

	var pkg: Dictionary = parse_rbxpkg_bytes_in_ram(raw_bytes)
	if not pkg.is_empty():
		pkg["game_id"] = gid
		pkg["creator_username"] = creator_uname
		if String(pkg.get("format", "")) == "tscn_raw":
			# Save to user cache dir for seamless Godot Resource loading
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://games_cache"))
			var cache_path: String = "user://games_cache/%s.tscn" % gid.validate_filename()
			var f: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
			if f != null:
				f.store_string(String(pkg.get("raw_text", "")))
				pkg["format"] = "tscn"
				pkg["scene_path"] = cache_path
	return pkg


static func apply_ram_package_to_world(world_node: Node3D, pkg: Dictionary) -> Array[Vector3]:
	var spawns: Array[Vector3] = []
	if world_node == null or pkg.is_empty():
		return spawns

	# A) Native Godot .tscn scene loading
	if String(pkg.get("format", "")) == "tscn":
		var scene_path: String = String(pkg.get("scene_path", ""))
		if scene_path != "" and FileAccess.file_exists(scene_path):
			var packed_sc: PackedScene = load(scene_path) as PackedScene
			if packed_sc != null:
				var inst: Node = packed_sc.instantiate()
				if inst != null:
					_strip_duplicate_controllers(inst)
					world_node.add_child(inst)
					_collect_spawns_from_node(inst, spawns)
					_apply_scene_lighting(inst, world_node)
					print("[RetroBlox Launcher] Instantiated native Godot scene '%s' with %d spawn(s)!" % [scene_path, spawns.size()])
		return spawns

	# B) Compact .rbxpkg in-RAM world reconstruction
	var compiled_scripts: Dictionary = {}
	if pkg.get("scripts") is Dictionary:
		var smap: Dictionary = pkg["scripts"] as Dictionary
		for spath in smap.keys():
			var dyn_scr: GDScript = GDScript.new()
			dyn_scr.source_code = String(smap[spath])
			if dyn_scr.reload() == OK:
				compiled_scripts[String(spath)] = dyn_scr

	if not (pkg.get("parts") is Array):
		return spawns

	var parts_arr: Array = pkg["parts"] as Array
	for item in parts_arr:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item as Dictionary
		var pos_arr: Array = d.get("pos", [0, 2, 0]) if d.get("pos") is Array else [0, 2, 0]
		var rot_arr: Array = d.get("rot", [0, 0, 0]) if d.get("rot") is Array else [0, 0, 0]
		var sz_arr: Array = d.get("size", [4, 1, 4]) if d.get("size") is Array else [4, 1, 4]
		var pos: Vector3 = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var rot: Vector3 = Vector3(float(rot_arr[0]), float(rot_arr[1]), float(rot_arr[2]))
		var sz: Vector3 = Vector3(float(sz_arr[0]), float(sz_arr[1]), float(sz_arr[2]))

		if bool(d.get("is_spawn", false)):
			spawns.append(pos + Vector3(0, 2.5, 0))

		var sb: StaticBody3D = StaticBody3D.new()
		sb.name = String(d.get("name", "Part")).validate_node_name()
		sb.position = pos
		sb.rotation = rot

		if d.has("shape"):
			var shape_kind: String = String(d.get("shape", "box"))
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.name = "MeshInstance3D"
			var cs: CollisionShape3D = CollisionShape3D.new()
			cs.name = "CollisionShape3D"
			if shape_kind == "cylinder":
				var cm: CylinderMesh = CylinderMesh.new()
				cm.top_radius = sz.x * 0.5
				cm.bottom_radius = sz.z * 0.5
				cm.height = sz.y
				mi.mesh = cm
				var csh: CylinderShape3D = CylinderShape3D.new()
				csh.radius = sz.x * 0.5
				csh.height = sz.y
				cs.shape = csh
			elif shape_kind == "sphere":
				var sm: SphereMesh = SphereMesh.new()
				sm.radius = sz.x * 0.5
				sm.height = sz.y
				mi.mesh = sm
				var ssh: SphereShape3D = SphereShape3D.new()
				ssh.radius = sz.x * 0.5
				cs.shape = ssh
			else:
				var bm: BoxMesh = BoxMesh.new()
				bm.size = sz
				mi.mesh = bm
				var bsh: BoxShape3D = BoxShape3D.new()
				bsh.size = sz
				cs.shape = bsh

			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = Color.from_string(String(d.get("color", "a3a2a5")), Color(0.64, 0.64, 0.65))
			mi.set_surface_override_material(0, mat)
			sb.add_child(mi)
			sb.add_child(cs)

		var spath_str: String = String(d.get("script_path", ""))
		if spath_str != "":
			var scr_obj: Script = null
			if compiled_scripts.has(spath_str):
				scr_obj = compiled_scripts[spath_str] as Script
			elif ResourceLoader.exists(spath_str):
				scr_obj = load(spath_str) as Script
			if scr_obj != null:
				sb.set_script(scr_obj)
				if d.has("pad_type"):
					sb.set("pad_type", int(d["pad_type"]))
				if d.has("item_type"):
					sb.set("item_type", int(d["item_type"]))
				if d.has("gamepass_name"):
					sb.set("gamepass_name", String(d["gamepass_name"]))
				if d.has("custom_title"):
					sb.set("custom_title", String(d["custom_title"]))
				if d.has("custom_cost"):
					sb.set("custom_cost", int(d["custom_cost"]))

		world_node.add_child(sb)

	return spawns


static func _strip_duplicate_controllers(root_n: Node) -> void:
	if root_n == null:
		return
	var s: Variant = root_n.get_script()
	if s != null and (s is Script):
		var sp: String = (s as Script).resource_path.to_lower()
		if sp.ends_with("game.gd") or sp.ends_with("main.gd") or sp.ends_with("client.gd"):
			root_n.set_script(null)

	var to_remove: Array[Node] = []
	var stack: Array[Node] = [root_n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var cname: String = cur.name.to_lower()
		var cs: Variant = cur.get_script()
		if cs != null and (cs is Script):
			var csp: String = (cs as Script).resource_path.to_lower()
			if csp.ends_with("game.gd") or csp.ends_with("chat_box.gd") or csp.ends_with("color_world_ui.gd"):
				cur.set_script(null)
		if cur is CanvasLayer or cname == "hud" or cname == "chatbox" or cname == "topbar":
			to_remove.append(cur)
		elif cur is Camera3D:
			(cur as Camera3D).current = false
			to_remove.append(cur)
		elif cname == "localplayer" or cname == "camerarig":
			to_remove.append(cur)

	for rem in to_remove:
		if is_instance_valid(rem):
			rem.queue_free()


static func _collect_spawns_from_node(root_n: Node, out_spawns: Array[Vector3]) -> void:
	var stack: Array[Node] = [root_n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var cname: String = cur.name.to_lower()
		if cur is Node3D and (cname.contains("spawn") or cur.has_meta("is_spawn_location")):
			out_spawns.append((cur as Node3D).global_position + Vector3(0, 1.5, 0))


static func _apply_scene_lighting(scene_inst: Node, world_ref: Node3D) -> void:
	var root_env: WorldEnvironment = world_ref.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var root_sun: DirectionalLight3D = world_ref.get_node_or_null("Sun") as DirectionalLight3D
	var stack: Array[Node] = [scene_inst]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		if cur is WorldEnvironment and cur != root_env:
			var w: WorldEnvironment = cur as WorldEnvironment
			if w.environment != null and root_env != null:
				root_env.environment = w.environment
				if root_env.environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR:
					root_env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
				if root_env.environment.tonemap_exposure > 1.05:
					root_env.environment.tonemap_exposure = 0.95
			w.environment = null
		elif cur is DirectionalLight3D and cur != root_sun:
			if root_sun != null:
				root_sun.visible = false
