class_name PlazaPlatform
extends StaticBody3D
# Editable studded platform for map districts (food court, grapple range, arena).
# Drop one under World, set Size and Color in the Inspector — no art resources needed.

@export var size: Vector3 = Vector3(26, 1, 22):
	set(v):
		size = Vector3(maxf(v.x, 0.5), maxf(v.y, 0.25), maxf(v.z, 0.5))
		if is_inside_tree():
			_rebuild_visuals()
@export var color: Color = Color("8f8f8f"):
	set(v):
		color = v
		if is_inside_tree():
			_rebuild_visuals()
@export var use_studs: bool = true

func _ready() -> void:
	if not is_in_group("plaza_platform"):
		add_to_group("plaza_platform")
	_rebuild_visuals()


func _rebuild_visuals() -> void:
	for ch in get_children():
		if bool(ch.get_meta("_plaza_generated", false)):
			ch.queue_free()

	var mat: Material = WorldBuilder._part_material(color, "plastic", WorldBuilder.stud_texture(), not use_studs)

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	mi.set_meta("_plaza_generated", true)
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	if mat != null:
		mi.material_override = mat
	add_child(mi)

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "Collision"
	col.set_meta("_plaza_generated", true)
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = size
	col.shape = bs
	add_child(col)
