# res://scripts/apple_worm/level_manager.gd
class_name LevelManager
extends RefCounted

const SAVE_PATH = "user://apple_worm_save.json"

static func get_all_levels() -> Array[String]:
	var levels: Array[String] = []
	var dir = DirAccess.open("res://levels")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				levels.append("res://levels/" + file_name)
			file_name = dir.get_next()

	# Sort naturally by extracting number if present
	levels.sort_custom(func(a: String, b: String) -> bool:
		var num_a = _extract_number(a)
		var num_b = _extract_number(b)
		if num_a != num_b:
			return num_a < num_b
		return a < b
	)
	return levels

static func _extract_number(path: String) -> int:
	var base = path.get_file().get_basename()
	var digits = ""
	for c in base:
		if c >= '0' and c <= '9':
			digits += c
	if digits != "":
		return digits.to_int()
	return 9999

static func load_progress() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"unlocked": 1, "completed": {}}
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return {"unlocked": 1, "completed": {}}
	var json = JSON.new()
	var err = json.parse(f.get_as_text())
	if err == OK and json.data is Dictionary:
		return json.data
	return {"unlocked": 1, "completed": {}}

static func save_progress(level_idx: int, moves: int) -> void:
	var progress = load_progress()
	var current_unlocked = progress.get("unlocked", 1)
	if level_idx + 1 > current_unlocked:
		progress["unlocked"] = level_idx + 1

	if not progress.has("completed"):
		progress["completed"] = {}
	var prev_best = progress["completed"].get(str(level_idx), 9999)
	if moves < prev_best:
		progress["completed"][str(level_idx)] = moves

	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(progress, "  "))

static func get_next_level(current_path: String) -> String:
	var list = get_all_levels()
	var idx = list.find(current_path)
	if idx != -1 and idx + 1 < list.size():
		return list[idx + 1]
	return ""
