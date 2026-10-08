extends Area3D
## TixCoin — one collectible Tix. Spins and bobs above the ground; touch it
## and it chimes, pops in a little sparkle burst, and counts toward the
## place's Tix total on the HUD. Coins are placed via the "coin" prop in a
## place definition.

signal collected(coin: Area3D)

const SPIN_SPEED := 2.6          # radians / second
## 1 stud = 0.28 units — the coin is a ~2-stud disc, pickup range in studs
const STUD := 0.28
const BOB_HEIGHT := 0.35 * STUD
const BOB_RATE := 2.2

var _phase := 0.0
var _base_y := 0.0
var _taken := false


func _init() -> void:
        name = "TixCoin"
        add_to_group("tix_coin")
        collision_layer = 0
        collision_mask = 4          # the local player capsule (Players layer)
        monitoring = true

        # the disc: gold cylinder standing upright like a coin
        var mesh_node := MeshInstance3D.new()
        mesh_node.name = "Disc"
        var cyl := CylinderMesh.new()
        cyl.top_radius = 0.95 * STUD
        cyl.bottom_radius = 0.95 * STUD
        cyl.height = 0.22 * STUD
        cyl.radial_segments = 24
        mesh_node.mesh = cyl
        mesh_node.rotation_degrees = Vector3(90.0, 0.0, 0.0)  # stand upright
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color("ffd23f")
        mat.metallic = 0.85
        mat.metallic_specular = 0.9
        mat.roughness = 0.25
        mat.emission_enabled = true
        mat.emission = Color("8a6a00")
        mat.emission_energy_multiplier = 0.35
        mesh_node.material_override = mat
        add_child(mesh_node)

        # inner ring detail — slightly darker second disc for depth
        var inner := MeshInstance3D.new()
        inner.name = "Inner"
        var inner_cyl := CylinderMesh.new()
        inner_cyl.top_radius = 0.6 * STUD
        inner_cyl.bottom_radius = 0.6 * STUD
        inner_cyl.height = 0.26 * STUD
        inner_cyl.radial_segments = 20
        inner.mesh = inner_cyl
        inner.rotation_degrees = Vector3(90.0, 0.0, 0.0)
        var imat := StandardMaterial3D.new()
        imat.albedo_color = Color("e8a80f")
        imat.metallic = 0.7
        imat.roughness = 0.35
        inner.material_override = imat
        mesh_node.add_child(inner)

        # pickup range (studs)
        var shape_node := CollisionShape3D.new()
        var shape := SphereShape3D.new()
        shape.radius = 1.7 * STUD
        shape_node.shape = shape
        shape_node.position = Vector3(0.0, 1.5 * STUD, 0.0)
        add_child(shape_node)


func _ready() -> void:
        _base_y = position.y
        _phase = fposmod(global_position.x * 0.37 + global_position.z * 0.61, TAU)
        body_entered.connect(_on_body)


func _process(delta: float) -> void:
        if _taken:
                return
        _phase += delta
        rotate_y(SPIN_SPEED * delta)
        position.y = _base_y + sin(_phase * BOB_RATE) * BOB_HEIGHT


func _on_body(_body: Node3D) -> void:
        if _taken:
                return
        _taken = true
        set_deferred("monitoring", false)
        # chime at the coin, sparkle burst, tell the game, then vanish
        var sfx: Node = get_node_or_null("/root/Sfx")
        if sfx != null:
                sfx.call("play_tix_3d", self)
        _sparkle()
        collected.emit(self)
        visible = false
        var timer := get_tree().create_timer(1.4)
        timer.timeout.connect(queue_free)


## A tiny one-shot golden burst where the coin stood.
func _sparkle() -> void:
        var burst := CPUParticles3D.new()
        burst.name = "CoinBurst"
        burst.one_shot = true
        burst.emitting = true
        burst.amount = 16
        burst.lifetime = 0.6
        burst.explosiveness = 0.95
        burst.direction = Vector3.UP
        burst.spread = 180.0
        burst.initial_velocity_min = 3.0 * STUD
        burst.initial_velocity_max = 6.5 * STUD
        burst.gravity = Vector3(0.0, -9.0 * STUD, 0.0)
        burst.scale_amount_min = 0.12 * STUD
        burst.scale_amount_max = 0.3 * STUD
        burst.mesh = BoxMesh.new()
        (burst.mesh as BoxMesh).size = Vector3.ONE
        burst.color = Color("ffd23f")
        # particles live at the coin's spot, parented to the world above us
        var parent := get_parent()
        if parent != null:
                var xf := global_transform
                parent.add_child(burst)
                burst.global_transform = xf
        var timer := get_tree().create_timer(1.2)
        timer.timeout.connect(burst.queue_free)
