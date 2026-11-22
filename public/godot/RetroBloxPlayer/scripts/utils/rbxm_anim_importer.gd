class_name RbxmAnimImporter
extends RefCounted

## RbxmAnimImporter
## Parses Roblox KeyframeSequence animations (.rbxm / .rbxmx) and converts them
## directly into Godot 4.x Animation resources for R6 characters and custom rigs.

const R6_PART_MAPPING := {
	"Torso": "Torso",
	"Head": "Head",
	"Right Arm": "Pivot_3",
	"RightArm": "Pivot_3",
	"Left Arm": "Pivot_2",
	"LeftArm": "Pivot_2",
	"Right Leg": "Pivot_5",
	"RightLeg": "Pivot_5",
	"Left Leg": "Pivot_4",
	"LeftLeg": "Pivot_4",
	"HumanoidRootPart": "Torso"
}

static func import_animation_file(file_path: String) -> Animation:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		printerr("[RbxmAnimImporter] Failed to open file: ", file_path)
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()

	if bytes.size() >= 8 and bytes.slice(0, 8).get_string_from_ascii() == "<roblox!":
		return import_from_rbxm_binary(bytes, file_path.get_file().get_basename())

	var content := bytes.get_string_from_utf8()
	if content.contains("<roblox") or content.contains("KeyframeSequence"):
		return import_from_rbxmx_xml(content, file_path.get_file().get_basename())

	printerr("[RbxmAnimImporter] Unrecognized .rbxm/.rbxmx format: ", file_path)
	return null

static func import_from_rbxmx_xml(xml_text: String, default_name: String = "RobloxAnim") -> Animation:
	var parser := XMLParser.new()
	var err := parser.open_buffer(xml_text.to_utf8_buffer())
	if err != OK:
		printerr("[RbxmAnimImporter] Failed to parse XML")
		return null

	var anim := Animation.new()
	anim.resource_name = default_name
	anim.loop_mode = Animation.LOOP_LINEAR

	var current_kf_time: float = 0.0
	var max_time: float = 0.0

	# Map bone -> Array of [time: float, quat: Quaternion, pos: Vector3]
	var tracks_data: Dictionary = {}

	var in_item := false
	var item_class := ""
	var in_props := false
	var prop_name := ""
	var pose_name := ""
	var current_element := ""

	var reading_cframe := false
	var cf_x := 0.0
	var cf_y := 0.0
	var cf_z := 0.0
	var cf_r00 := 1.0
	var cf_r01 := 0.0
	var cf_r02 := 0.0
	var cf_r10 := 0.0
	var cf_r11 := 1.0
	var cf_r12 := 0.0
	var cf_r20 := 0.0
	var cf_r21 := 0.0
	var cf_r22 := 1.0

	while parser.read() == OK:
		var node_type := parser.get_node_type()

		if node_type == XMLParser.NODE_ELEMENT:
			var el_name := parser.get_node_name()
			current_element = el_name

			if el_name == "Item":
				item_class = parser.get_named_attribute_value_safe("class")
				if item_class == "Keyframe":
					pose_name = ""
				elif item_class == "Pose":
					pose_name = ""
			elif el_name == "Properties":
				in_props = true
			elif el_name == "CoordinateFrame":
				if parser.get_named_attribute_value_safe("name") == "CFrame":
					reading_cframe = true
					cf_x = 0.0; cf_y = 0.0; cf_z = 0.0
					cf_r00 = 1.0; cf_r01 = 0.0; cf_r02 = 0.0
					cf_r10 = 0.0; cf_r11 = 1.0; cf_r12 = 0.0
					cf_r20 = 0.0; cf_r21 = 0.0; cf_r22 = 1.0
			elif el_name in ["string", "float", "bool", "token", "int"]:
				prop_name = parser.get_named_attribute_value_safe("name")

		elif node_type == XMLParser.NODE_TEXT:
			var text := parser.get_node_data().strip_edges()
			if in_props and text.length() > 0:
				if prop_name == "Name":
					if item_class == "KeyframeSequence":
						anim.resource_name = text
					elif item_class == "Pose":
						pose_name = text
				elif prop_name == "Time" and item_class == "Keyframe":
					current_kf_time = text.to_float()
					if current_kf_time > max_time:
						max_time = current_kf_time
				elif prop_name == "Loop" and item_class == "KeyframeSequence":
					anim.loop_mode = Animation.LOOP_LINEAR if text.to_lower() == "true" else Animation.LOOP_NONE

			if reading_cframe and text.length() > 0:
				match current_element:
					"X": cf_x = text.to_float()
					"Y": cf_y = text.to_float()
					"Z": cf_z = text.to_float()
					"R00": cf_r00 = text.to_float()
					"R01": cf_r01 = text.to_float()
					"R02": cf_r02 = text.to_float()
					"R10": cf_r10 = text.to_float()
					"R11": cf_r11 = text.to_float()
					"R12": cf_r12 = text.to_float()
					"R20": cf_r20 = text.to_float()
					"R21": cf_r21 = text.to_float()
					"R22": cf_r22 = text.to_float()

		elif node_type == XMLParser.NODE_ELEMENT_END:
			var end_el := parser.get_node_name()
			if end_el == "CoordinateFrame" and reading_cframe:
				reading_cframe = false
				if pose_name.length() > 0:
					var basis := Basis(
						Vector3(cf_r00, cf_r10, cf_r20),
						Vector3(cf_r01, cf_r11, cf_r21),
						Vector3(cf_r02, cf_r12, cf_r22)
					).orthonormalized()
					var quat := basis.get_rotation_quaternion()
					var pos := Vector3(cf_x, cf_y, cf_z)
					var target_bone = R6_PART_MAPPING.get(pose_name, pose_name)

					if not tracks_data.has(target_bone):
						tracks_data[target_bone] = []
					tracks_data[target_bone].append({
						"time": current_kf_time,
						"quat": quat,
						"pos": pos
					})
			elif end_el == "Properties":
				in_props = false
			elif end_el == "Item":
				pass

	anim.length = maxf(max_time, 0.1)

	# Build Godot Animation tracks
	for bone in tracks_data.keys():
		var keys: Array = tracks_data[bone]
		# Rotation track (as euler or quaternion rotation)
		var rot_track_idx := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(rot_track_idx, NodePath(bone))
		for k in keys:
			anim.rotation_track_insert_key(rot_track_idx, k["time"], k["quat"])

		if bone == "Torso":
			var pos_track_idx := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(pos_track_idx, NodePath(bone))
			for k in keys:
				anim.position_track_insert_key(pos_track_idx, k["time"], k["pos"])

	print("[RbxmAnimImporter] Successfully imported animation '", anim.resource_name, "' (Length: ", anim.length, "s, Tracks: ", anim.get_track_count(), ")")
	return anim


static func _decompress_lz4(src: PackedByteArray, uncompressed_len: int) -> PackedByteArray:
	var dst := PackedByteArray()
	dst.resize(uncompressed_len)
	var si: int = 0
	var di: int = 0
	var slen: int = src.size()
	while si < slen:
		var tok: int = src[si]
		si += 1
		var ll: int = tok >> 4
		if ll == 15:
			var b: int = 255
			while b == 255 and si < slen:
				b = src[si]
				si += 1
				ll += b
		for _i in range(ll):
			if si >= slen or di >= uncompressed_len:
				break
			dst[di] = src[si]
			si += 1
			di += 1
		if si >= slen or di >= uncompressed_len:
			break
		var off: int = src[si] | (src[si + 1] << 8)
		si += 2
		if off == 0:
			break
		var ml: int = (tok & 0x0f) + 4
		if (tok & 0x0f) == 15:
			var b2: int = 255
			while b2 == 255 and si < slen:
				b2 = src[si]
				si += 1
				ml += b2
		var mp: int = di - off
		for _j in range(ml):
			if di >= uncompressed_len:
				break
			dst[di] = dst[mp]
			di += 1
			mp += 1
	return dst


static func _read_u32_le(b: PackedByteArray, off: int) -> int:
	return b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24)


static func _read_interleaved_i32(d: PackedByteArray, off: int, cnt: int) -> Array[int]:
	var out: Array[int] = []
	out.resize(cnt)
	for i in range(cnt):
		var raw: int = (d[off + i] << 24) | (d[off + cnt + i] << 16) | (d[off + cnt * 2 + i] << 8) | d[off + cnt * 3 + i]
		var val: int = ((raw >> 1) & 0x7fffffff) ^ -(raw & 1)
		out[i] = val
	return out


static func _read_interleaved_f32(d: PackedByteArray, off: int, cnt: int) -> Array[float]:
	var out: Array[float] = []
	out.resize(cnt)
	var spb := StreamPeerBuffer.new()
	spb.big_endian = true
	for i in range(cnt):
		var rot: int = (d[off + i] << 24) | (d[off + cnt + i] << 16) | (d[off + cnt * 2 + i] << 8) | d[off + cnt * 3 + i]
		var raw: int = ((rot >> 1) & 0x7fffffff) | ((rot & 1) << 31)
		spb.clear()
		spb.put_u32(raw)
		spb.seek(0)
		out[i] = spb.get_float()
	return out


static func _orient_id_to_quat(oid: int) -> Quaternion:
	var norms: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
		Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)
	]
	var idx: int = oid - 1
	var r_idx: int = (idx / 6) % 6
	var u_idx: int = idx % 6
	var r: Vector3 = norms[r_idx] if r_idx >= 0 and r_idx < 6 else Vector3(1, 0, 0)
	var u: Vector3 = norms[u_idx] if u_idx >= 0 and u_idx < 6 else Vector3(0, 1, 0)
	var f: Vector3 = r.cross(u)
	var basis := Basis(r, u, f).orthonormalized()
	return basis.get_rotation_quaternion()


static func import_from_rbxm_binary(bytes: PackedByteArray, default_name: String = "RobloxAnim") -> Animation:
	if bytes.size() < 32:
		return null
	var pos: int = 32
	var classes: Dictionary = {}
	var instances: Dictionary = {}

	while pos + 16 <= bytes.size():
		var chunk_name := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var comp_len: int = _read_u32_le(bytes, pos + 4)
		var uncomp_len: int = _read_u32_le(bytes, pos + 8)
		pos += 16
		if chunk_name.begins_with("END"):
			break
		var raw_len: int = uncomp_len if comp_len == 0 else comp_len
		if pos + raw_len > bytes.size():
			break
		var raw_slice := bytes.slice(pos, pos + raw_len)
		pos += raw_len
		var data: PackedByteArray = raw_slice if comp_len == 0 else _decompress_lz4(raw_slice, uncomp_len)

		if chunk_name == "INST":
			var p: int = 0
			var class_id: int = _read_u32_le(data, p); p += 4
			var name_len: int = _read_u32_le(data, p); p += 4
			var cls_name := data.slice(p, p + name_len).get_string_from_utf8(); p += name_len
			p += 1 # has_additional
			var inst_count: int = _read_u32_le(data, p); p += 4
			var deltas := _read_interleaved_i32(data, p, inst_count)
			var ids: Array[int] = []
			var acc: int = 0
			for d in deltas:
				acc += d
				ids.append(acc)
				instances[acc] = {
					"id": acc,
					"cls": cls_name,
					"parent": -1,
					"name": cls_name,
					"loop": true,
					"time": 0.0,
					"pos": Vector3.ZERO,
					"quat": Quaternion.IDENTITY,
					"has_cf": false
				}
			classes[class_id] = {"cls": cls_name, "ids": ids}
		elif chunk_name == "PROP":
			var p: int = 0
			var class_id: int = _read_u32_le(data, p); p += 4
			var prop_len: int = _read_u32_le(data, p); p += 4
			var prop_name := data.slice(p, p + prop_len).get_string_from_utf8(); p += prop_len
			var prop_type: int = data[p]; p += 1
			if not classes.has(class_id):
				continue
			var ids: Array = classes[class_id]["ids"]
			var cnt: int = ids.size()
			if prop_type == 0x01 and prop_name == "Name":
				for i in range(cnt):
					if p + 4 > data.size():
						break
					var slen: int = _read_u32_le(data, p); p += 4
					var val := data.slice(p, p + slen).get_string_from_utf8(); p += slen
					instances[ids[i]]["name"] = val
			elif prop_type == 0x02 and prop_name == "Loop":
				for i in range(cnt):
					if p < data.size():
						instances[ids[i]]["loop"] = data[p] != 0
						p += 1
			elif prop_type == 0x04 and prop_name == "Time":
				var vals := _read_interleaved_f32(data, p, cnt)
				for i in range(cnt):
					instances[ids[i]]["time"] = vals[i]
			elif prop_type == 0x10 and prop_name == "CFrame":
				var quats: Array[Quaternion] = []
				var spb := StreamPeerBuffer.new()
				spb.big_endian = false
				for i in range(cnt):
					if p >= data.size():
						quats.append(Quaternion.IDENTITY)
						continue
					var oid: int = data[p]; p += 1
					if oid == 0 and p + 36 <= data.size():
						spb.clear()
						spb.put_data(data.slice(p, p + 36))
						spb.seek(0)
						var r00 := spb.get_float(); var r01 := spb.get_float(); var r02 := spb.get_float()
						var r10 := spb.get_float(); var r11 := spb.get_float(); var r12 := spb.get_float()
						var r20 := spb.get_float(); var r21 := spb.get_float(); var r22 := spb.get_float()
						p += 36
						var basis := Basis(
							Vector3(r00, r10, r20),
							Vector3(r01, r11, r21),
							Vector3(r02, r12, r22)
						).orthonormalized()
						quats.append(basis.get_rotation_quaternion())
					else:
						quats.append(_orient_id_to_quat(oid))
				if p + cnt * 12 <= data.size():
					var xs := _read_interleaved_f32(data, p, cnt)
					var ys := _read_interleaved_f32(data, p + cnt * 4, cnt)
					var zs := _read_interleaved_f32(data, p + cnt * 8, cnt)
					for i in range(cnt):
						instances[ids[i]]["pos"] = Vector3(xs[i], ys[i], zs[i])
						instances[ids[i]]["quat"] = quats[i]
						instances[ids[i]]["has_cf"] = true
		elif chunk_name == "PRNT":
			var p: int = 1
			var cnt: int = _read_u32_le(data, p); p += 4
			var cdeltas := _read_interleaved_i32(data, p, cnt)
			var pdeltas := _read_interleaved_i32(data, p + cnt * 4, cnt)
			var ca: int = 0
			var pa: int = 0
			for i in range(cnt):
				ca += cdeltas[i]
				pa += pdeltas[i]
				if instances.has(ca):
					instances[ca]["parent"] = pa

	# Build children lookup & locate KeyframeSequence
	var children_of: Dictionary = {}
	var kfs_id: int = -1
	for iid in instances.keys():
		var inst: Dictionary = instances[iid]
		var pid: int = inst["parent"]
		if not children_of.has(pid):
			children_of[pid] = []
		children_of[pid].append(iid)
		if inst["cls"] == "KeyframeSequence" and kfs_id == -1:
			kfs_id = iid

	if kfs_id == -1:
		printerr("[RbxmAnimImporter] No KeyframeSequence found in binary .rbxm")
		return null

	var kfs_inst: Dictionary = instances[kfs_id]
	var anim := Animation.new()
	var kfs_name: String = str(kfs_inst["name"])
	anim.resource_name = kfs_name if kfs_name.length() > 0 else default_name
	anim.loop_mode = Animation.LOOP_LINEAR if bool(kfs_inst["loop"]) else Animation.LOOP_NONE

	var tracks_data: Dictionary = {}
	var max_time: float = 0.0
	var kf_ids: Array = children_of.get(kfs_id, [])
	for kf_id in kf_ids:
		var kf: Dictionary = instances[kf_id]
		if kf["cls"] != "Keyframe":
			continue
		var t: float = float(kf["time"])
		if t > max_time:
			max_time = t
		var stack: Array = children_of.get(kf_id, []).duplicate()
		while stack.size() > 0:
			var cur_id: int = stack.pop_back()
			var cur: Dictionary = instances[cur_id]
			if cur["cls"] == "Pose" and bool(cur["has_cf"]):
				var target_bone: String = R6_PART_MAPPING.get(cur["name"], cur["name"])
				if not tracks_data.has(target_bone):
					tracks_data[target_bone] = []
				tracks_data[target_bone].append({
					"time": t,
					"quat": cur["quat"],
					"pos": cur["pos"]
				})
			for ch_id in children_of.get(cur_id, []):
				stack.append(ch_id)

	anim.length = maxf(max_time, 0.1)
	for bone in tracks_data.keys():
		var keys: Array = tracks_data[bone]
		keys.sort_custom(func(a, b): return a["time"] < b["time"])
		var rot_idx := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(rot_idx, NodePath(bone))
		for k in keys:
			anim.rotation_track_insert_key(rot_idx, k["time"], k["quat"])
		if bone == "Torso":
			var pos_idx := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(pos_idx, NodePath(bone))
			for k in keys:
				anim.position_track_insert_key(pos_idx, k["time"], k["pos"])

	print("[RbxmAnimImporter] Successfully imported binary .rbxm '", anim.resource_name, "' (Length: ", anim.length, "s, Tracks: ", anim.get_track_count(), ")")
	return anim
