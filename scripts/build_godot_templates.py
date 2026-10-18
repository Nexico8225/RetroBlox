#!/usr/bin/env python3
"""Build a REAL, runnable Godot 4.5 project for every public/templates/*.retroplace.

Output: public/templates/<slug>-godot-project.zip  (root folder <slug>/ inside)
Each project: project.godot + icon.svg + README.md + scenes/main.tscn (every
brick is a real node you can select/move/recolor in the editor) + scripts
(player.gd movement/kill/bounce/ladder/goal + game.gd spawn/win/paint).

After zipping, every project is VERIFIED with the headless Godot binary:
  godot --headless --path <dir> --import
  godot --headless --path <dir> --quit-after 60
Any SCRIPT ERROR / ERROR line fails the build loudly.
"""
import json, math, os, shutil, subprocess, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL_DIR = os.path.join(ROOT, 'public', 'templates')
BUILD_DIR = os.path.join(ROOT, 'scripts', '_godot_tpl_build')
GODOT = os.path.join(ROOT, 'scripts', 'godot-bin', 'Godot_v4.5.1-stable_linux.x86_64')

def hx(c):
    c = (c or '8f8f8f').ljust(6, '0')
    return (int(c[0:2], 16) / 255.0, int(c[2:4], 16) / 255.0, int(c[4:6], 16) / 255.0)

def fnum(v):
    v = float(v)
    return ('%.6g' % v)

def vec(v):
    return 'Vector3(%s, %s, %s)' % (fnum(v[0]), fnum(v[1]), fnum(v[2]))

def color(c, a=1.0):
    r, g, b = hx(c)
    return 'Color(%s, %s, %s, %s)' % (fnum(r), fnum(g), fnum(b), fnum(a))

def tform(p):
    return 'Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)' % (fnum(p[0]), fnum(p[1]), fnum(p[2]))

SLUG_OK = True

# ---------------------------------------------------------------- scripts ---
PLAYER_GD = '''extends CharacterBody3D
## The player. Classic feel: WalkSpeed 16, JumpPower 50, gravity 196.2 (studs).
## Tune the numbers below in the Inspector or right here, then press F5.

signal won
signal toast(msg: String)

const SPEED := 16.0          # studs / second
const JUMP := 50.0           # jump launch speed
const GRAVITY := 196.2       # studs / second^2
const BOUNCE := 85.0         # bounce pad launch speed
const CLIMB := 12.0          # ladder climb speed
const KILL_Y := -60.0        # falling below this respawns you
const MOUSE_SENS := 0.0035

var topdown := false         # the exporter sets this per template
var yaw := 0.0
var pitch := -0.9            # radians, negative = camera above
var spawn_pos := Vector3.ZERO
var checkpoint := Vector3.ZERO
var won_game := false

@onready var cam: Camera3D = $Camera

func _ready() -> void:
        spawn_pos = global_position
        checkpoint = global_position
        if topdown:
                yaw = 0.0
                pitch = -1.12
        else:
                pitch = -0.62
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not topdown:
                yaw -= event.relative.x * MOUSE_SENS
                pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.4, -0.12)
        elif event.is_action_pressed("ui_cancel"):
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
                Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
        if not is_on_floor():
                velocity.y -= GRAVITY * delta
        var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
        var s := sin(yaw)
        var c := cos(yaw)
        # forward key = away from the camera (screen-up in top-down mode)
        var dir := Vector3(s * inp.y + c * inp.x, 0.0, c * inp.y - s * inp.x)
        velocity.x = dir.x * SPEED
        velocity.z = dir.z * SPEED
        if Input.is_action_just_pressed("jump") and is_on_floor():
                velocity.y = JUMP
        move_and_slide()
        _touch_scan(inp)
        if not topdown:
                var d := 16.0
                var off := Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * d
                cam.global_position = global_position + off + Vector3(0, 2.5, 0)
                cam.look_at(global_position + Vector3(0, 2.0, 0))
        else:
                var d := 42.0
                cam.global_position = global_position + Vector3(0, d * absf(sin(pitch)) + 2.0, d * absf(cos(pitch)))
                cam.look_at(global_position + Vector3(0, 1.5, 0))
        if global_position.y < KILL_Y and not won_game:
                _respawn()

func _touch_scan(inp: Vector2) -> void:
        for i in get_slide_collision_count():
                var col := get_slide_collision(i)
                var other := col.get_collider()
                if other == null:
                        continue
                if other.is_in_group("kill"):
                        if not won_game:
                                _respawn()
                        return
                elif other.is_in_group("goal"):
                        if not won_game:
                                won_game = true
                                won.emit()
                        return
                elif other.is_in_group("checkpoint"):
                        var top: Vector3 = other.global_position + Vector3(0, 2.5, 0)
                        if top.distance_to(checkpoint) > 1.0:
                                checkpoint = top
                                toast.emit("Checkpoint saved.")
                elif other.is_in_group("bounce") and is_on_floor():
                        velocity.y = BOUNCE
                elif other.is_in_group("ladder") and inp.y < -0.1:
                        velocity.y = CLIMB

func _respawn() -> void:
        global_position = checkpoint + Vector3(0, 1.5, 0)
        velocity = Vector3.ZERO
        toast.emit("You died. Back you go.")
'''

GAME_GD = '''extends Node3D
## World logic: spawn placement, the win banner, toasts — and, for paint
## templates, LEFT CLICK paints the brick you aim at. Paint everything to win.

const PLACE_NAME := "__NAME__"
const PAINT_GAME := __PAINT__
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
'''

ICON_SVG = '''<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><rect width="128" height="128" rx="18" fill="#1b2a34"/><rect x="22" y="58" width="38" height="38" rx="4" fill="#c4281c"/><rect x="66" y="58" width="38" height="38" rx="4" fill="#f5cd30"/><rect x="44" y="20" width="38" height="34" rx="4" fill="#4b974b"/><rect x="22" y="58" width="38" height="10" fill="#ffffff" opacity="0.25"/><rect x="44" y="20" width="38" height="9" fill="#ffffff" opacity="0.25"/></svg>'''

README = '''# {NAME}

{DESC}

A RetroBlox game template exported as a **real Godot 4.5 project** — open it in
the Godot editor, press F5, and it runs. Everything is standard Godot: no
plugins, no custom formats.

## Open it

1. Install Godot 4.5+ (free, open source): https://godotengine.org/download
2. Open Godot -> Import -> pick this folder's `project.godot` -> Import & Edit.
3. Press **F5** (or the play button). That is the whole game running.

## What is inside

| Path | What it is |
|------|------------|
| `scenes/main.tscn` | The whole level. Every brick is a real node under `Parts` — select, move, scale, recolor in the editor. |
| `scripts/player.gd` | Movement (WASD + Space), camera, death/respawn, bounce pads, ladders, checkpoints, goal. Classic feel: WalkSpeed 16, JumpPower 50. |
| `scripts/game.gd` | Spawn placement, win banner, toasts, and the paint-to-win mode on paint templates. |
| `project.godot` | Engine settings + the WASD/Space input map. |

## How bricks work

Each part is a `StaticBody3D` with a `MeshInstance3D` (BoxMesh) and a
`CollisionShape3D`. The part's **group** is its gameplay role:

| Group | Meaning |
|-------|---------|
| `spawn` | where players start |
| `kill` | touch it and you die |
| `goal` | touch it to win |
| `checkpoint` | touch it to save your respawn |
| `bounce` | launch pad |
| `ladder` | hold W against it to climb |

To build: duplicate any `Part_*` node (Ctrl+D), move it, resize the BoxMesh +
BoxShape3D together, recolor the material. To change how the player feels,
tune the constants at the top of `scripts/player.gd`.

Top-down templates: the camera parks high above the board (`topdown = true`
in `scripts/player.gd`). Set it to `false` for a third-person chase camera.

## Publish it back

1. Zip this folder (with `project.godot` at the top of the zip).
2. On retro-blox.vercel.app -> Create / your game -> attach it as the game file
   or source. The sibling `{SLUG}.retroplace` file is the same layout for the
   RetroBlox studio player (STUDIO > OPEN GAME FILE).
'''

# ------------------------------------------------------------------ scene ---
def build_scene(place):
    parts = place.get('parts', [])
    props = place.get('props', [])
    topdown = place.get('cam') == 'topdown'
    sky_top = color(place.get('sky_top', '7db7e8'))
    sky_hor = color(place.get('sky_horizon', 'cfe6f5'))
    sky_gnd = color(place.get('sky_ground', '9fb8a4'))

    subs, nodes = [], []
    si = 0

    def sub(kind, idname, body):
        # append one sub_resource with id "<idname>_<running counter>" and
        # return the counter so references always match the defined id
        nonlocal si
        si += 1
        subs.append('[sub_resource type="%s" id="%s_%d"]\n%s' % (kind, idname, si, body))
        return si

    # sky + environment (always the first three subs -> ids _1.._3)
    sub('ProceduralSkyMaterial', 'SkyMat', 'sky_top_color = %s\nsky_horizon_color = %s\nsky_energy_multiplier = 1.0\nground_bottom_color = %s\nground_horizon_color = %s\n' % (sky_top, sky_hor, sky_gnd, sky_hor))
    sub('Sky', 'Sky', 'sky_material = SubResource("SkyMat_1")\n')
    sub('Environment', 'Env', 'background_mode = 2\nsky = SubResource("Sky_2")\nambient_light_source = 3\nambient_light_energy = 1.0\ntonemap_mode = 2\n')
    cap_shape_n = sub('CapsuleShape3D', 'CapShape', 'radius = 1.2\nheight = 4.6\n')
    cap_mesh_n = sub('CapsuleMesh', 'CapMesh', 'radius = 1.2\nheight = 4.6\n')

    part_nodes = []
    for i, p in enumerate(parts):
        s = p.get('s', [4, 1, 4])
        if not isinstance(s, list) or len(s) == 0:
            s = [4, 1, 4]
        while len(s) < 3:
            s = list(s) + [s[-1]]
        c = p.get('c', '8f8f8f')
        g = p.get('g', '')
        m = p.get('m', '')
        mesh_n = sub('BoxMesh', 'Mesh', 'size = %s\n' % vec(s))
        mat_lines = ['albedo_color = %s' % color(c)]
        if m == 'neon':
            mat_lines += ['emission_enabled = true', 'emission = %s' % color(c), 'emission_energy_multiplier = 1.6']
        elif m == 'metal':
            mat_lines += ['metallic = 0.75', 'roughness = 0.3']
        mat_n = sub('StandardMaterial3D', 'Mat', '\n'.join(mat_lines) + '\n')
        shape_n = sub('BoxShape3D', 'Shape', 'size = %s\n' % vec(s))
        grp = ' groups=["%s"]' % g if g else ''
        part_nodes.append('[node name="Part_%d" type="StaticBody3D" parent="Parts"%s]\ntransform = %s\n' % (i + 1, grp, tform(p['p'])))
        part_nodes.append('[node name="Mesh" type="MeshInstance3D" parent="Part_%d"]\nmesh = SubResource("Mesh_%d")\nsurface_material_override/0 = SubResource("Mat_%d")\n' % (i + 1, mesh_n, mat_n))
        part_nodes.append('[node name="Shape" type="CollisionShape3D" parent="Part_%d"]\nshape = SubResource("Shape_%d")\n' % (i + 1, shape_n))

    prop_nodes = []
    for j, pr in enumerate(props):
        t = pr.get('type', 'crate')
        if t == 'sign':
            w, h = float(pr.get('w', 8)), float(pr.get('h', 4))
            base = pr.get('p', [0, 0, 0])
            yaw = float(pr.get('yaw', 0)) * math.pi / 180.0
            board_w, board_h, board_d = w, h * 0.55, 0.35
            post_h = h * 0.5
            post_c = pr.get('c', '7c5c46')
            board_c = 'f2f3f3'
            pid = sub('BoxMesh', 'PMsg', 'size = %s\n' % vec([0.5, post_h, 0.5]))
            bmid = sub('BoxMesh', 'PBrd', 'size = %s\n' % vec([board_w, board_h, board_d]))
            pmat = sub('StandardMaterial3D', 'PMat', 'albedo_color = %s\n' % color(post_c))
            bmat = sub('StandardMaterial3D', 'BMat', 'albedo_color = %s\n' % color(board_c))
            rot = ''
            if abs(yaw) > 0.001:
                rot = '\nrotation = Vector3(0, %s, 0)' % fnum(yaw)
            prop_nodes.append('[node name="Sign_%d" type="Node3D" parent="Props"]\ntransform = %s%s\n' % (j + 1, tform(base), rot))
            prop_nodes.append('[node name="Post" type="MeshInstance3D" parent="Sign_%d"]\nmesh = SubResource("PMsg_%d")\nsurface_material_override/0 = SubResource("PMat_%d")\ntransform = %s\n' % (j + 1, pid, pmat, tform([0, post_h * 0.5, 0])))
            prop_nodes.append('[node name="Board" type="MeshInstance3D" parent="Sign_%d"]\nmesh = SubResource("PBrd_%d")\nsurface_material_override/0 = SubResource("BMat_%d")\ntransform = %s\n' % (j + 1, bmid, bmat, tform([0, post_h + board_h * 0.5, 0])))
            txt = (pr.get('text', '') or '').replace('\n', '\\n').replace('"', '\\"')
            title = (pr.get('title', '') or '').replace('"', '\\"')
            label = title + ('\\n' + txt if txt else '')
            prop_nodes.append('[node name="Text" type="Label3D" parent="Sign_%d/Board"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, %s)\ntext = "%s"\nfont_size = 64\npixel_size = 0.004\noutline_size = 8\nmodulate = %s\n' % (j + 1, fnum(board_d / 2.0 + 0.02), label, color(pr.get('title_c', '1b2a34'))))
        else:
            s = pr.get('s', [2, 2, 2])
            if not isinstance(s, list) or len(s) == 0:
                s = [2, 2, 2]
            while len(s) < 3:
                s = list(s) + [s[-1]]
            mid = sub('BoxMesh', 'PrM', 'size = %s\n' % vec(s))
            mat = sub('StandardMaterial3D', 'PrMat', 'albedo_color = %s\n' % color(pr.get('c', 'a8b0b8')))
            prop_nodes.append('[node name="%s_%d" type="MeshInstance3D" parent="Props"]\nmesh = SubResource("PrM_%d")\nsurface_material_override/0 = SubResource("PrMat_%d")\ntransform = %s\n' % (t.capitalize(), j + 1, mid, mat, tform(pr.get('p', [0, 0, 0]))))

    out = ['[gd_scene load_steps=%d format=3]\n' % (si + 3)]
    out.append('[ext_resource type="Script" path="res://scripts/game.gd" id="1_game"]\n')
    out.append('[ext_resource type="Script" path="res://scripts/player.gd" id="2_player"]\n')
    out.append('\n' + '\n'.join(subs) + '\n')
    out.append('[node name="Main" type="Node3D"]\nscript = ExtResource("1_game")\n')
    out.append('\n[node name="WorldEnvironment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("Env_3")\n')
    out.append('\n[node name="Sun" type="DirectionalLight3D" parent="."]\nrotation = Vector3(-0.95, 0.5, 0)\nshadow_enabled = true\nlight_energy = 1.2\n')
    out.append('\n[node name="Parts" type="Node3D" parent="."]')
    if part_nodes:
        out.append('\n' + '\n'.join(part_nodes))
    out.append('\n[node name="Props" type="Node3D" parent="."]')
    if prop_nodes:
        out.append('\n' + '\n'.join(prop_nodes))
    out.append('\n[node name="Player" type="CharacterBody3D" parent="."]\ntransform = %s\nscript = ExtResource("2_player")\ntopdown = %s\n' % (tform([0, 3, 0]), 'true' if topdown else 'false'))
    out.append('\n[node name="Shape" type="CollisionShape3D" parent="Player"]\nshape = SubResource("CapShape_%d")\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.3, 0)\n' % cap_shape_n)
    out.append('\n[node name="Body" type="MeshInstance3D" parent="Player"]\nmesh = SubResource("CapMesh_%d")\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2.3, 0)\n' % cap_mesh_n)
    out.append('\n[node name="Camera" type="Camera3D" parent="Player"]\nfov = 70.0\n')
    out.append('\n[node name="UI" type="CanvasLayer" parent="."]')
    out.append('\n[node name="Hint" type="Label" parent="UI"]\noffset_left = 12.0\noffset_top = 8.0\noffset_right = 1100.0\noffset_bottom = 30.0\ntext = "RETROBLOX"\ntheme_override_font_sizes/font_size = 14\ntheme_override_colors/font_color = Color(1, 1, 1, 1)\n')
    out.append('\n[node name="Win" type="Label" parent="UI"]\nanchor_right = 1.0\nanchor_bottom = 1.0\ntext = "YOU WIN!"\nhorizontal_alignment = 1\nvertical_alignment = 1\ntheme_override_font_sizes/font_size = 52\ntheme_override_colors/font_color = Color(1, 0.9, 0.3, 1)\nvisible = false\n')
    out.append('\n[node name="Toast" type="Label" parent="UI"]\nanchor_top = 1.0\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_top = -70.0\ntext = ""\nhorizontal_alignment = 1\ntheme_override_font_sizes/font_size = 20\ntheme_override_colors/font_color = Color(1, 1, 1, 1)\nvisible = false\n')
    return ''.join(out)

PROJECT_GODOT = '''; Engine configuration file.
config_version=5

[application]

config/name="{NAME}"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.5", "GL Compatibility")
config/icon="res://icon.svg"

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="disabled"

[input]

move_left={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":97,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194319,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]}
move_right={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":100,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194321,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]}
move_forward={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":119,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194320,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]}
move_back={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":115,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194322,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]}
jump={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":32,"location":0,"echo":false,"script":null)
]}

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'''

def gd_escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

def build_project(slug, place):
    name = place.get('name', slug)
    desc = place.get('desc', '')
    topdown = place.get('cam') == 'topdown'
    paint = bool(place.get('paint'))
    d = os.path.join(BUILD_DIR, slug)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(os.path.join(d, 'scenes'), exist_ok=True)
    os.makedirs(os.path.join(d, 'scripts'), exist_ok=True)

    with open(os.path.join(d, 'project.godot'), 'w') as f:
        f.write(PROJECT_GODOT.replace('{NAME}', gd_escape(name)))
    with open(os.path.join(d, 'icon.svg'), 'w') as f:
        f.write(ICON_SVG)
    with open(os.path.join(d, 'scenes', 'main.tscn'), 'w') as f:
        f.write(build_scene(place))
    with open(os.path.join(d, 'scripts', 'player.gd'), 'w') as f:
        f.write(PLAYER_GD.replace('var topdown := false', 'var topdown := %s' % ('true' if topdown else 'false')))
    with open(os.path.join(d, 'scripts', 'game.gd'), 'w') as f:
        f.write(GAME_GD.replace('__NAME__', gd_escape(name)).replace('__PAINT__', 'true' if paint else 'false'))
    with open(os.path.join(d, 'README.md'), 'w') as f:
        f.write(README.format(NAME=name, DESC=desc, SLUG=slug))

    zip_path = os.path.join(TPL_DIR, '%s-godot-project.zip' % slug)
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
        for dirpath, _, files in os.walk(d):
            for fn in sorted(files):
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, d)
                z.write(full, os.path.join(slug, rel))
    return d, zip_path

def verify(d):
    env = dict(os.environ, HOME=os.path.expanduser('~'))
    r1 = subprocess.run([GODOT, '--headless', '--path', d, '--import'], capture_output=True, text=True, timeout=300, env=env)
    r2 = subprocess.run([GODOT, '--headless', '--path', d, '--quit-after', '60'], capture_output=True, text=True, timeout=300, env=env)
    blob = (r1.stdout + r1.stderr + r2.stdout + r2.stderr)
    errs = [ln.strip() for ln in blob.splitlines() if ('SCRIPT ERROR' in ln or 'Parse Error' in ln or 'ERROR:' in ln or 'Failed' in ln)]
    return errs, blob

def main():
    files = sorted(f for f in os.listdir(TPL_DIR) if f.endswith('.retroplace'))
    os.makedirs(BUILD_DIR, exist_ok=True)
    failures = []
    for fn in files:
        slug = fn.replace('.retroplace', '')
        place = json.load(open(os.path.join(TPL_DIR, fn)))
        d, zip_path = build_project(slug, place)
        errs, blob = verify(d)
        size = os.path.getsize(zip_path)
        status = 'OK' if not errs else 'FAIL'
        print('[%s] %s -> %s (%d bytes) parts=%d props=%d topdown=%s' % (status, slug, os.path.basename(zip_path), size, len(place.get('parts', [])), len(place.get('props', [])), place.get('cam') == 'topdown'))
        if errs:
            failures.append((slug, errs))
            print('\n'.join(errs[:12]))
            print('---- full log tail ----')
            print(blob[-2500:])
    if failures:
        print('VERIFY FAILED: %d project(s)' % len(failures))
        sys.exit(1)
    print('ALL GODOT PROJECTS VERIFIED')

if __name__ == '__main__':
    main()
