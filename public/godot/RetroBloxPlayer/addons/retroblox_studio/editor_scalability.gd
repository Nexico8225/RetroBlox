@tool
extends RefCounted

# RetroBlox Studio: Editor Scalability & Toaster Optimization System
# Inspired by Unreal Engine Scalability Presets (Epic -> Low/Toaster).
# Highly optimizes the Godot 3D Editor Viewport without affecting the exported game.

const CONFIG_PATH = "user://retroblox_editor_scalability.json"

enum QualityPreset {
	EPIC,
	HIGH,
	MEDIUM,
	LOW_TOASTER
}

var current_preset: QualityPreset = QualityPreset.HIGH
var occlusion_culling_enabled: bool = true
var low_processor_mode: bool = false
var editor_fps_cap: int = 60
var scaling_3d: float = 1.0

var _plugin_ref: EditorPlugin = null

func setup(plugin: EditorPlugin) -> void:
	_plugin_ref = plugin
	load_saved_settings()
	apply_current_settings()

func load_saved_settings() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var d := parsed as Dictionary
		current_preset = int(d.get("preset", QualityPreset.HIGH)) as QualityPreset
		occlusion_culling_enabled = bool(d.get("occlusion_culling", true))
		low_processor_mode = bool(d.get("low_processor_mode", false))
		editor_fps_cap = int(d.get("fps_cap", 60))
		scaling_3d = float(d.get("scaling_3d", 1.0))

func save_settings() -> void:
	var f = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return
	var data: Dictionary = {
		"preset": int(current_preset),
		"occlusion_culling": occlusion_culling_enabled,
		"low_processor_mode": low_processor_mode,
		"fps_cap": editor_fps_cap,
		"scaling_3d": scaling_3d
	}
	f.store_string(JSON.stringify(data, "\t"))

func set_preset(preset: QualityPreset) -> void:
	current_preset = preset
	match preset:
		QualityPreset.EPIC:
			scaling_3d = 1.0
			editor_fps_cap = 144
			low_processor_mode = false
			occlusion_culling_enabled = true
		QualityPreset.HIGH:
			scaling_3d = 1.0
			editor_fps_cap = 60
			low_processor_mode = false
			occlusion_culling_enabled = true
		QualityPreset.MEDIUM:
			scaling_3d = 0.85
			editor_fps_cap = 60
			low_processor_mode = true
			occlusion_culling_enabled = true
		QualityPreset.LOW_TOASTER:
			# Runs butter-smooth on 10-year old dual-core laptops & Intel HD graphics!
			scaling_3d = 0.60
			editor_fps_cap = 30
			low_processor_mode = true
			occlusion_culling_enabled = true

	save_settings()
	apply_current_settings()

func apply_current_settings() -> void:
	# 1. Low processor usage mode (idle sleep so laptop stays cool and fans quiet)
	OS.low_processor_usage_mode = low_processor_mode
	if low_processor_mode:
		OS.low_processor_usage_mode_sleep_usec = 33000 if current_preset == QualityPreset.LOW_TOASTER else 16000
	else:
		OS.low_processor_usage_mode_sleep_usec = 0

	# 2. Maximum FPS cap in editor
	Engine.max_fps = editor_fps_cap

	# 3. Apply to Editor 3D Viewports
	if _plugin_ref == null:
		return

	var ei = _plugin_ref.get_editor_interface()
	if ei == null:
		return

	# Iterate over editor 3D viewports (indices 0 to 3)
	for i in range(4):
		var vp: SubViewport = ei.get_editor_viewport_3d(i)
		if vp == null:
			continue

		# 3D Resolution Scale
		vp.scaling_3d_scale = scaling_3d
		vp.scaling_3d_mode = SubViewport.SCALING_3D_MODE_BILINEAR if scaling_3d < 1.0 else SubViewport.SCALING_3D_MODE_BILINEAR

		# Anti-Aliasing (MSAA)
		if current_preset == QualityPreset.EPIC:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		elif current_preset == QualityPreset.HIGH:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		else:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED

		# In-Editor Occlusion Culling
		vp.use_occlusion_culling = occlusion_culling_enabled

func toggle_occlusion_culling(enabled: bool) -> void:
	occlusion_culling_enabled = enabled
	save_settings()
	apply_current_settings()

func toggle_low_processor(enabled: bool) -> void:
	low_processor_mode = enabled
	save_settings()
	apply_current_settings()

func set_fps_cap(fps: int) -> void:
	editor_fps_cap = fps
	save_settings()
	apply_current_settings()

func apply_perf_setting(id: int) -> void:
	match id:
		0:
			set_preset(QualityPreset.EPIC)
		1:
			set_preset(QualityPreset.HIGH)
		2:
			set_preset(QualityPreset.MEDIUM)
		3:
			set_preset(QualityPreset.LOW_TOASTER)
		10:
			toggle_occlusion_culling(not occlusion_culling_enabled)
		11:
			toggle_low_processor(not low_processor_mode)
		20:
			set_fps_cap(30)
		21:
			set_fps_cap(60)
		22:
			set_fps_cap(144)
		30:
			generate_scene_occluders()

func generate_scene_occluders() -> int:
	if _plugin_ref == null:
		return 0
	var ei = _plugin_ref.get_editor_interface()
	if ei == null:
		return 0
	var root: Node = ei.get_edited_scene_root()
	if root == null:
		return 0
	var total: int = generate_box_occluders_for_scene(root)
	print("[RetroBlox Scalability] Generated %d occlusion culling instances for scene." % total)
	return total

func generate_box_occluders_for_scene(scene_root: Node) -> int:
	if scene_root == null:
		return 0
	var count = 0
	# 1. Static bodies and mesh instances
	for node in scene_root.find_children("*", "Node3D"):
		if node is StaticBody3D or node is CSGBox3D or node is MeshInstance3D:
			if node.get_node_or_null("BoxOccluder") != null:
				continue
			var occ_size: Vector3 = Vector3.ZERO
			if node is CSGBox3D:
				occ_size = (node as CSGBox3D).size
			elif node is MeshInstance3D:
				var mi := node as MeshInstance3D
				if mi.mesh is BoxMesh:
					occ_size = (mi.mesh as BoxMesh).size
				elif mi.mesh != null:
					occ_size = mi.mesh.get_aabb().size
			elif node is StaticBody3D:
				for ch in node.get_children():
					if ch is MeshInstance3D:
						var mi := ch as MeshInstance3D
						if mi.mesh is BoxMesh:
							occ_size = (mi.mesh as BoxMesh).size
						elif mi.mesh != null:
							occ_size = mi.mesh.get_aabb().size
						break
					elif ch is CollisionShape3D:
						var cs := ch as CollisionShape3D
						if cs.shape is BoxShape3D:
							occ_size = (cs.shape as BoxShape3D).size
							break

			if occ_size.length_squared() > 1.0:
				var occ_inst = OccluderInstance3D.new()
				occ_inst.name = "BoxOccluder"
				var box_occ = BoxOccluder3D.new()
				box_occ.size = occ_size
				occ_inst.occluder = box_occ
				node.add_child(occ_inst, true)
				occ_inst.owner = scene_root
				count += 1
	return count
