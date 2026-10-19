extends Node3D
## World logic: spawn placement, the win banner, toasts — and, for paint
## templates, LEFT CLICK paints the brick you aim at. Paint everything to win.

const PLACE_NAME := "Classic Obby"
const PAINT_GAME := false
const PALETTE := [Color(0.949,0.953,0.953), Color(0.106,0.165,0.204), Color(0.769,0.157,0.11), Color(0.910,0.459,0.165), Color(0.961,0.804,0.188), Color(0.294,0.592,0.294), Color(0.0,0.6,0.6), Color(0.051,0.412,0.675), Color(0.42,0.196,0.486), Color(0.910,0.729,0.784), Color(0.486,0.361,0.275), Color(0.388,0.373,0.384)]

var paint_total := 0
var paint_done := {}
var won_game := false
var cam: Camera3D

@onready var player: CharacterBody3D = $Player
@onready var win_label: Label = $UI/Win
@onready var toast_label: Label = $UI/Toast
@onready var hint_label: Label = $UI/Hint

func _ready() -> void:
        cam = player.get_node("Camera")
        var spawns := get_tree().get_nodes_in_group("spawn")
        if spawns.size() > 0:
                player.global_position = spawns[0].global_position + Vector3(0, 2.0, 0)
        player.won.connect(_on_won)
        player.toast.connect(_toast)
        win_label.visible = false
        toast_label.visible = false
        var controls := "WASD move  |  SPACE jump  |  ESC mouse"
        if PAINT_GAME:
                controls = "LEFT CLICK paint  |  WASD move  |  SPACE jump"
                _count_paintables($Parts)
                _build_palette()
        hint_label.text = "%s   —   %s" % [PLACE_NAME, controls]

func _unhandled_input(event: InputEvent) -> void:
        if PAINT_GAME and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
                _paint_click()

func _count_paintables(root: Node) -> void:
        for child in root.get_children():
                if child is MeshInstance3D and child.get_parent() is StaticBody3D:
                        paint_total += 1
                _count_paintables(child)

func _paint_click() -> void:
        if won_game:
                return
        var from := cam.global_position
        var to := from - cam.global_transform.basis.z * 400.0
        var q := PhysicsRayQueryParameters3D.create(from, to)
        q.exclude = [player.get_rid()]
        var hit := get_world_3d().direct_space_state.intersect_ray(q)
        if hit.is_empty():
                return
        var node: Object = hit.get("collider")
        if node == null or not node is StaticBody3D:
                return
        var mesh_node: Node = node.get_child(0) if node.get_child_count() > 0 else null
        if mesh_node == null or not mesh_node is MeshInstance3D:
                return
        var key: String = str(node.get_path())
        var idx := int(paint_done.size()) % PALETTE.size()
        var mi := mesh_node as MeshInstance3D
        var mat := mi.get_surface_override_material(0)
        if mat == null and mi.mesh != null:
                mat = mi.mesh.surface_get_material(0)
        if mat is StandardMaterial3D:
                mat.albedo_color = PALETTE[idx]
                paint_done[key] = true
                hint_label.text = "PAINTED %d / %d" % [paint_done.size(), paint_total]
                if paint_done.size() >= paint_total and paint_total > 0:
                        _on_won()

func _on_won() -> void:
        won_game = true
        win_label.text = "YOU WIN!"
        win_label.visible = true
        _toast("Goal reached!")

func _toast(msg: String) -> void:
        toast_label.text = msg
        toast_label.visible = true
        await get_tree().create_timer(2.0).timeout
        toast_label.visible = false

func _build_palette() -> void:
        var strip := HBoxContainer.new()
        strip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        strip.position = Vector2(240, 500)
        strip.add_theme_constant_override("separation", 4)
        for col in PALETTE:
                var r := ColorRect.new()
                r.custom_minimum_size = Vector2(26, 26)
                r.color = col
                strip.add_child(r)
        $UI.add_child(strip)
