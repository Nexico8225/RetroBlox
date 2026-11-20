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
	var content := file.get_as_text()
	file.close()

	if content.contains("<roblox") or content.contains("KeyframeSequence"):
		return import_from_rbxmx_xml(content, file_path.get_file().get_basename())
	
	printerr("[RbxmAnimImporter] Binary .rbxm not XML. Converting fallback clip for: ", file_path)
	var fallback := Animation.new()
	fallback.resource_name = file_path.get_file().get_basename()
	fallback.length = 1.0
	fallback.loop_mode = Animation.LOOP_LINEAR
	return fallback

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
