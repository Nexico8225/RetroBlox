extends Node3D

## Screenshot rig: builds a place + HUD + player, positions the camera like
## the reference video, saves PNGs to user://shots/ (headless-with-X run).

const PlacesScript := preload("res://scripts/world/places.gd")
const WorldBuilderScript := preload("res://scripts/world/world_builder.gd")
const LocalPlayerScript := preload("res://scripts/player/local_player.gd")
const CameraRigScript := preload("res://scripts/game/camera_rig.gd")
const ChatBoxScript := preload("res://scripts/game/chat_box.gd")

var place: Dictionary
var player: CharacterBody3D
var camera_rig: Node3D
var hud: CanvasLayer
var chat: Control
var _shots := 0
var _moved := false


func _ready() -> void:
        place = PlacesScript.by_id("cloudkingdom")
        var built: Dictionary = WorldBuilderScript.build(place)
        add_child(built["root"])

        player = LocalPlayerScript.new()
        add_child(player)
        player.global_position = Vector3(0, 2.2, 6)
        player.spawn_point = Transform3D(Basis(), Vector3(0, 2.2, 6))
        player.setup("Nexico8225")
        player.avatar.call("paint_noob")

        camera_rig = CameraRigScript.new()
        add_child(camera_rig)
        camera_rig.setup(player)
        camera_rig.set_ui_blocked(true)   # keep the OS cursor during shots
        camera_rig.yaw = 0.35
        camera_rig.pitch = -0.22
        camera_rig.distance = 14.0

        _build_hud()
        chat.call("add_system", "Welcome to Cloud Kingdom!")
        chat.call("add_chat", "Nexico8225", 1, "Good game")
        var settings: Node = get_node("/root/Settings")
        settings.set_key("fov", 70.0)


func _build_hud() -> void:
        # reuse game.gd's HUD by constructing the same layout inline (visual
        # parity check): topbar pill, health, hotbar, toasts, chat
        hud = CanvasLayer.new()
        add_child(hud)
        var game_script := load("res://scripts/game/game.gd")
        # instead of instantiating game.gd (needs Session), rebuild the pieces:
        var pill := PanelContainer.new()
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.055, 0.06, 0.07, 0.86)
        sb.set_corner_radius_all(22)
        sb.content_margin_left = 8
        sb.content_margin_right = 8
        sb.content_margin_top = 5
        sb.content_margin_bottom = 5
        pill.add_theme_stylebox_override("panel", sb)
        pill.position = Vector2(12, 12)
        hud.add_child(pill)
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 6)
        pill.add_child(row)
        for icon in ["logo", "menu", "chat", "people"]:
                var b := Button.new()
                b.custom_minimum_size = Vector2(40, 34)
                b.icon = load("res://assets/icons/%s.png" % icon)
                b.expand_icon = true
                b.focus_mode = Control.FOCUS_NONE
                row.add_child(b)

        chat = ChatBoxScript.new()
        hud.add_child(chat)

        # hotbar
        var slot := PanelContainer.new()
        var ss := StyleBoxFlat.new()
        ss.bg_color = Color(0.05, 0.07, 0.09, 0.55)
        ss.set_corner_radius_all(4)
        ss.border_color = Color(1, 1, 1, 0.22)
        ss.set_border_width_all(1)
        slot.add_theme_stylebox_override("panel", ss)
        slot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        slot.offset_left = -44
        slot.offset_right = 44
        slot.offset_top = -96
        slot.offset_bottom = -8
        hud.add_child(slot)
        var v := VBoxContainer.new()
        slot.add_child(v)
        var num := Label.new()
        num.text = "1"
        num.add_theme_font_size_override("font_size", 11)
        num.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
        v.add_child(num)
        var nm := Label.new()
        nm.text = "Tix Bag"
        nm.add_theme_font_size_override("font_size", 12)
        nm.add_theme_color_override("font_color", Color.WHITE)
        nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        v.add_child(nm)

        # toast
        var toast := PanelContainer.new()
        toast.add_theme_stylebox_override("panel", sb)
        toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
        toast.offset_top = 14
        toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
        hud.add_child(toast)
        var tl := Label.new()
        tl.text = "eh_raiderbomber joined you"
        tl.add_theme_font_size_override("font_size", 14)
        tl.add_theme_color_override("font_color", Color.WHITE)
        toast.add_child(tl)
        (tl as Control).custom_minimum_size = Vector2(260, 0)
        tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        # health bar right
        var holder := VBoxContainer.new()
        holder.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
        holder.offset_left = -74
        holder.offset_right = -14
        holder.offset_top = -120
        holder.offset_bottom = 120
        holder.alignment = BoxContainer.ALIGNMENT_CENTER
        holder.add_theme_constant_override("separation", 4)
        hud.add_child(holder)
        var track_holder := Control.new()
        track_holder.custom_minimum_size = Vector2(10, 150)
        track_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        holder.add_child(track_holder)
        var track := ColorRect.new()
        track.color = Color(1, 1, 1, 0.85)
        track.set_anchors_preset(Control.PRESET_FULL_RECT)
        track_holder.add_child(track)
        var fill := ColorRect.new()
        fill.color = Color("3fd432")
        fill.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
        fill.offset_top = -150
        track_holder.add_child(fill)
        var lbl := Label.new()
        lbl.text = "Health"
        lbl.add_theme_font_size_override("font_size", 17)
        lbl.add_theme_color_override("font_color", Color("1b3fbf"))
        lbl.add_theme_color_override("font_outline_color", Color.WHITE)
        lbl.add_theme_constant_override("outline_size", 6)
        lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        holder.add_child(lbl)
        var chip := PanelContainer.new()
        var cs := StyleBoxFlat.new()
        cs.bg_color = Color("3fd432")
        cs.set_corner_radius_all(8)
        cs.content_margin_left = 10
        cs.content_margin_right = 10
        chip.add_theme_stylebox_override("panel", cs)
        chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        holder.add_child(chip)
        var cv := Label.new()
        cv.text = "100"
        cv.add_theme_font_size_override("font_size", 14)
        cv.add_theme_color_override("font_color", Color.WHITE)
        chip.add_child(cv)


func _process(_d: float) -> void:
        _shots += 1
        if _shots == 5 and not _moved:
                _moved = true
                # walk forward a bit so the walk clip plays for shot 2
                player.call("drive", 0.016, Vector2(0, -1), 0.35, false, false)
                var img := get_viewport().get_texture().get_image()
                img.save_png("user://shots/shot1_overview.png")
        elif _shots == 40:
                var img := get_viewport().get_texture().get_image()
                img.save_png("user://shots/shot2_walking.png")
                camera_rig.distance = 20.0
                camera_rig.pitch = -0.5
                camera_rig.yaw = 2.4
        elif _shots == 80:
                var img := get_viewport().get_texture().get_image()
                img.save_png("user://shots/shot3_leaderboard.png")
                camera_rig.yaw = 3.6
                camera_rig.distance = 16
        elif _shots == 120:
                var img := get_viewport().get_texture().get_image()
                img.save_png("user://shots/shot4_portal.png")
                var hb := hud.get_node_or_null("HealthBar") as Control
                if hb != null:
                        print("HEALTH rect=", hb.get_global_rect(), " visible=", hb.visible, " children=", hb.get_child_count())
                else:
                        print("HEALTH MISSING")
                get_tree().quit(0)
