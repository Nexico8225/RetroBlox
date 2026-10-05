extends ToolBase
## Trowel — place bricks with 1-stud snap and a legacy palette, like the classic.
## Bricks are created on the SERVER (rpc _place_brick) so every player sees them.

const REACH := 9.0
const BRICK := 1.0

var palette: Array[Color] = [
        Color("a4a4a4"), Color("d9b44a"), Color("4a7bd9"), Color("4ad96e"),
        Color("d94a4a"), Color("9a4ad9"), Color("e8e8e8"), Color("3a3a3a"),
]
var color_index := 2
var my_bricks: int = 0
const MAX_BRICKS := 60

func _init() -> void:
        cooldown = 0.22
        var blade := MeshInstance3D.new()
        var box := BoxMesh.new()
        box.size = Vector3(0.5, 0.06, 0.5)
        blade.mesh = box
        blade.position = Vector3(0.28, 0.12, -0.4)
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color(0.75, 0.77, 0.8)
        blade.material_override = mat
        add_child(blade)

func _unhandled_input(event: InputEvent) -> void:
        if not visible or player == null or not player.is_multiplayer_authority():
                return
        if event is InputEventKey and event.pressed and not event.echo:
                var idx := int(event.keycode) - int(KEY_0)  # not used; palette via scroll below
                if event.keycode == KEY_Q:
                        color_index = (color_index - 1 + palette.size()) % palette.size()
                        Sfx.ui("ui_hover", -8.0)
                elif event.keycode == KEY_E:
                        color_index = (color_index + 1) % palette.size()
                        Sfx.ui("ui_hover", -8.0)

func use_primary() -> bool:
        if not ready_to_use() or main == null:
                return false
        start_cooldown(cooldown)
        var hit := aim_ray(REACH)
        if not hit.has("position"):
                return false
        # 1-stud grid snap happens on the SERVER (main._do_place_brick) so every
        # player agrees on placement — send the raw hit point + face normal
        var n: Vector3 = hit.get("normal", Vector3.UP)
        if my_bricks >= MAX_BRICKS:
                Sfx.ui("ui_error", -6.0)
                return false
        if main.has_method("request_place_brick"):
                main.request_place_brick(hit["position"] + n * 0.5, palette[color_index])
        return true

func use_secondary() -> bool:
        if not ready_to_use() or main == null:
                return false
        start_cooldown(0.35)
        var hit := aim_ray(REACH)
        if hit.has("collider") and main.has_method("request_pop_brick"):
                main.request_pop_brick(hit["collider"])
        return true
