extends SceneTree

## One-off dev tool: build a clean R6IK rig scene from the FBX import.
##
## The FBX carries empty helper/IK meshes (Plane_002 & friends) that make
## Godot's FBX importer log "surfaces.is_empty()" / "mesh->get_mesh()
## is_null()" errors on EVERY editor open. This tool strips every
## MeshInstance3D with no renderable mesh, drops animation tracks that
## pointed at them, and packs the remaining rig — meshes, materials,
## skeleton and all 8 animation clips — into a self-contained
## res://assets/models/R6IK_rig.scn so the raw FBX can be fenced out of
## the import pipeline with a .gdignore folder.
##
## Usage (after --import):
##   godot --headless --path . --script tests/build_clean_rig.gd

const SRC := "res://assets/models/R6IK.fbx"
const OUT := "res://assets/models/R6IK_rig.scn"


func _init() -> void:
	var packed: PackedScene = load(SRC)
	if packed == null:
		print("STRIP_FAILED: cannot load FBX")
		quit(1)
		return
	var root: Node3D = packed.instantiate()

	# ---- 1. collect broken nodes (no mesh / zero surfaces) ----
	var broken: Array[Node] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			broken.append(mi)
	print("BROKEN_NODES: ", broken.size())
	for b in broken:
		print("  - removing: ", b.name)

	# ---- 2. drop animation tracks targeting the removed nodes ----
	var removed_tracks := 0
	for b in broken:
		removed_tracks += _strip_tracks(root, b)

	# ---- 3. remove the broken nodes ----
	for b in broken:
		b.get_parent().remove_child(b)
		b.free()

	# ---- 4. sanity: every remaining mesh must be renderable ----
	var kept: Array[String] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi2 := node as MeshInstance3D
		if mi2.mesh != null and mi2.mesh.get_surface_count() > 0:
			kept.append(String(mi2.name))
	print("KEPT_MESHES: ", kept)

	# ---- 5. animations must have survived ----
	for node in root.find_children("*", "AnimationPlayer", true, false):
		var ap := node as AnimationPlayer
		print("ANIMS: ", ap.get_animation_list())

	# ---- 6. pack + save ----
	var out := PackedScene.new()
	var err := out.pack(root)
	if err != OK:
		print("STRIP_FAILED: pack error ", err)
		root.free()
		quit(1)
		return
	err = ResourceSaver.save(out, OUT)
	root.free()
	if err != OK:
		print("STRIP_FAILED: save error ", err)
		quit(1)
		return
	print("STRIP_OK removed_tracks=", removed_tracks)
	quit(0)


## Remove every animation track whose node path resolves to `gone`
## (compared as a node path relative to each AnimationPlayer's root).
func _strip_tracks(scene_root: Node, gone: Node) -> int:
	var removed := 0
	var gone_rel_paths: Array[String] = []
	for node in scene_root.find_children("*", "AnimationPlayer", true, false):
		var ap := node as AnimationPlayer
		var anim_root: Node = ap.get_node_or_null(ap.root_node)
		if anim_root == null:
			continue
		var rel := _rel_path(anim_root, gone)
		if rel != "" and not gone_rel_paths.has(rel):
			gone_rel_paths.append(rel)
	for node in scene_root.find_children("*", "AnimationPlayer", true, false):
		var ap2 := node as AnimationPlayer
		for lib_name in ap2.get_animation_library_list():
			var lib := ap2.get_animation_library(lib_name)
			for anim_name in lib.get_animation_list():
				var anim := lib.get_animation(anim_name)
				var doomed: Array[int] = []
				for t in range(anim.get_track_count()):
					var np := anim.track_get_path(t)
					var names := String(np.get_concatenated_names())
					for rel in gone_rel_paths:
						if names == rel or names.begins_with(rel + "/"):
							doomed.append(t)
							break
				for i in range(doomed.size() - 1, -1, -1):
					anim.track_remove(doomed[i])
					removed += 1
	return removed


## Node path of `node` as seen from `from_` — "" when unrelated.
func _rel_path(from_: Node, node: Node) -> String:
	var parts: Array[String] = []
	var cur: Node = node
	while cur != null and cur != from_:
		parts.push_front(cur.name)
		cur = cur.get_parent()
	if cur != from_:
		return ""
	return "/".join(parts)
