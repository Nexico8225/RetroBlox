import os

paths = [
    r"D:\Folders\RetroBlox\RetroBlox_SDK\scripts\core\scene_package_loader.gd",
    r"D:\Folders\RetroBlox\RetroBlox\public\godot\RetroBloxPlayer\scripts\core\scene_package_loader.gd"
]

patch_code = """
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
"""

for p in paths:
    if not os.path.exists(p):
        print("Skipping non-existent:", p)
        continue
    with open(p, "r", encoding="utf-8") as f:
        content = f.read()

    idx = content.find("static func parse_rbxpkg_bytes_in_ram")
    if idx != -1:
        new_content = content[:idx].rstrip() + "\n\n" + patch_code.strip() + "\n"
        with open(p, "w", encoding="utf-8") as f:
            f.write(new_content)
        print("Successfully patched scene_package_loader.gd in", p)
    else:
        print("Could not find parse_rbxpkg_bytes_in_ram in", p)
