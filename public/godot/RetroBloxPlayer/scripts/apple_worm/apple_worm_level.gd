# res://scripts/apple_worm/apple_worm_level.gd
@tool
class_name AppleWormLevel
extends Node3D

@export var level_title: String = "Level"
@export var par_moves: int = 15
@export var camera_distance: float = 14.0
@export var camera_center: Vector2 = Vector2.ZERO

var wall_tiles: Dictionary = {} # Vector2i -> WallBlock
var apple_tiles: Dictionary = {} # Vector2i -> AppleItem
var hazard_tiles: Dictionary = {} # Vector2i -> SpikeHazard
var portal_tile: Vector2i = Vector2i(999, 999)
var portal_node: LevelPortal
var start_tile: Vector2i = Vector2i(0, 0)
var start_length: int = 3
var start_direction: Vector2i = Vector2i.RIGHT

func scan_level_nodes() -> void:
	wall_tiles.clear()
	apple_tiles.clear()
	hazard_tiles.clear()
	portal_node = null

	var min_pos = Vector2(9999, 9999)
	var max_pos = Vector2(-9999, -9999)

	for child in get_children():
		if child is WallBlock:
			var cell = Vector2i(round(child.position.x), round(child.position.y))
			wall_tiles[cell] = child
			min_pos.x = min(min_pos.x, cell.x)
			min_pos.y = min(min_pos.y, cell.y)
			max_pos.x = max(max_pos.x, cell.x)
			max_pos.y = max(max_pos.y, cell.y)
		elif child is AppleItem:
			var cell = Vector2i(round(child.position.x), round(child.position.y))
			apple_tiles[cell] = child
			min_pos.x = min(min_pos.x, cell.x)
			min_pos.y = min(min_pos.y, cell.y)
			max_pos.x = max(max_pos.x, cell.x)
			max_pos.y = max(max_pos.y, cell.y)
		elif child is LevelPortal:
			portal_node = child
			portal_tile = Vector2i(round(child.position.x), round(child.position.y))
			min_pos.x = min(min_pos.x, portal_tile.x)
			min_pos.y = min(min_pos.y, portal_tile.y)
			max_pos.x = max(max_pos.x, portal_tile.x)
			max_pos.y = max(max_pos.y, portal_tile.y)
		elif child is WormStart:
			start_tile = Vector2i(round(child.position.x), round(child.position.y))
			start_length = child.initial_length
			start_direction = child.get_direction_vector()
			child.visible = false # hide preview in game
			min_pos.x = min(min_pos.x, start_tile.x)
			min_pos.y = min(min_pos.y, start_tile.y)
			max_pos.x = max(max_pos.x, start_tile.x)
			max_pos.y = max(max_pos.y, start_tile.y)
		elif child is SpikeHazard:
			var cell = Vector2i(round(child.position.x), round(child.position.y))
			hazard_tiles[cell] = child

	# Auto-calculate camera center and distance if not set manually
	if camera_center == Vector2.ZERO and min_pos.x <= max_pos.x:
		camera_center = (min_pos + max_pos) * 0.5
		var span_x = max_pos.x - min_pos.x + 4.0
		var span_y = max_pos.y - min_pos.y + 4.0
		camera_distance = max(10.0, max(span_x * 0.9, span_y * 1.2))
