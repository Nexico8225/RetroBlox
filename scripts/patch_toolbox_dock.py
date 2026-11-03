import os

dock_paths = [
    r"D:\Folders\RetroBlox\RetroBlox_SDK\addons\retroblox_studio\toolbox_dock.gd",
    r"D:\Folders\RetroBlox\RetroBlox\public\godot\RetroBloxPlayer\addons\retroblox_studio\toolbox_dock.gd"
]

for p in dock_paths:
    if not os.path.exists(p):
        print("Skipping non-existent:", p)
        continue
    with open(p, "r", encoding="utf-8") as f:
        content = f.read()

    content_n = content.replace("\r\n", "\n")

    # 1. Fix _build_thumbnail_tile thumbnail container & button
    old_thumb_code = """\tvar thumb_btn: Button = Button.new()
\tthumb_btn.custom_minimum_size = Vector2(92, 92)
\tthumb_btn.clip_contents = true
\tthumb_btn.focus_mode = Control.FOCUS_NONE
\tthumb_btn.tooltip_text = "%s\\nby %s (v%s) — %d Thumbs Up\\n%s\\n\\nClick to Insert into Scene!" % [
\t\tString(captured.get("name", "Asset")),
\t\tString(captured.get("creator", "RetroBlox")),
\t\tString(captured.get("version", "1.0")),
\t\tlikes_count,
\t\tString(captured.get("description", ""))
\t]

\tvar tsb: StyleBoxFlat = StyleBoxFlat.new()
\tif _bg_mode == "White":
\t\ttsb.bg_color = Color(0.95, 0.96, 0.98, 1.0)
\telif _bg_mode == "Black":
\t\ttsb.bg_color = Color(0.05, 0.05, 0.06, 1.0)
\telse:
\t\ttsb.bg_color = Color(0.11, 0.11, 0.11, 1.0)
\ttsb.set_corner_radius_all(4)
\ttsb.set_border_width_all(1)
\ttsb.border_color = Color(0.24, 0.24, 0.24, 1.0)
\tvar thov: StyleBoxFlat = tsb.duplicate() as StyleBoxFlat
\tthov.border_color = Color(0.0, 0.64, 1.0, 1.0)
\tthov.set_border_width_all(2)
\tthumb_btn.add_theme_stylebox_override("normal", tsb)
\tthumb_btn.add_theme_stylebox_override("hover", thov)
\tthumb_btn.add_theme_stylebox_override("pressed", thov)
\tthumb_btn.pressed.connect(func() -> void: _insert_toolbox_item(captured))
\ttile.add_child(thumb_btn)

\tvar tex_rect: TextureRect = TextureRect.new()
\ttex_rect.texture = _get_item_thumbnail(captured)
\ttex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
\ttex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
\ttex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
\ttex_rect.offset_left = 6.0
\ttex_rect.offset_top = 6.0
\ttex_rect.offset_right = -6.0
\ttex_rect.offset_bottom = -6.0
\ttex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
\tthumb_btn.add_child(tex_rect)

\tif bool(captured.get("verified", true)):
\t\tvar shield_rect: TextureRect = TextureRect.new()
\t\tshield_rect.texture = _shield_tex
\t\tshield_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
\t\tshield_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
\t\tshield_rect.custom_minimum_size = Vector2(16, 16)
\t\tshield_rect.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
\t\tshield_rect.offset_left = -20.0
\t\tshield_rect.offset_top = -20.0
\t\tshield_rect.offset_right = -4.0
\t\tshield_rect.offset_bottom = -4.0
\t\tshield_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
\t\tthumb_btn.add_child(shield_rect)"""

    new_thumb_code = """\tvar thumb_container: PanelContainer = PanelContainer.new()
\tthumb_container.custom_minimum_size = Vector2(92, 92)
\tthumb_container.clip_contents = true
\tvar tsb: StyleBoxFlat = StyleBoxFlat.new()
\tif _bg_mode == "White":
\t\ttsb.bg_color = Color(0.95, 0.96, 0.98, 1.0)
\telif _bg_mode == "Black":
\t\ttsb.bg_color = Color(0.05, 0.05, 0.06, 1.0)
\telse:
\t\ttsb.bg_color = Color(0.11, 0.11, 0.11, 1.0)
\ttsb.set_corner_radius_all(4)
\ttsb.set_border_width_all(1)
\ttsb.border_color = Color(0.24, 0.24, 0.24, 1.0)
\tthumb_container.add_theme_stylebox_override("panel", tsb)
\ttile.add_child(thumb_container)

\tvar tex_rect: TextureRect = TextureRect.new()
\ttex_rect.texture = _get_item_thumbnail(captured)
\ttex_rect.custom_minimum_size = Vector2(80, 80)
\ttex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
\ttex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
\ttex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
\ttex_rect.offset_left = 6.0
\ttex_rect.offset_top = 6.0
\ttex_rect.offset_right = -6.0
\ttex_rect.offset_bottom = -6.0
\ttex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
\tthumb_container.add_child(tex_rect)

\tvar thumb_btn: Button = Button.new()
\tthumb_btn.custom_minimum_size = Vector2(92, 92)
\tthumb_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
\tthumb_btn.focus_mode = Control.FOCUS_NONE
\tthumb_btn.flat = true
\tthumb_btn.tooltip_text = "%s\\nby %s (v%s) — %d Thumbs Up\\n%s\\n\\nClick to Insert into Scene!" % [
\t\tString(captured.get("name", "Asset")),
\t\tString(captured.get("creator", "RetroBlox")),
\t\tString(captured.get("version", "1.0")),
\t\tlikes_count,
\t\tString(captured.get("description", ""))
\t]
\tvar thov: StyleBoxFlat = StyleBoxFlat.new()
\tthov.bg_color = Color(0, 0, 0, 0)
\tthov.border_color = Color(0.0, 0.64, 1.0, 1.0)
\tthov.set_border_width_all(2)
\tthov.set_corner_radius_all(4)
\tthumb_btn.add_theme_stylebox_override("hover", thov)
\tthumb_btn.add_theme_stylebox_override("pressed", thov)
\tthumb_btn.pressed.connect(func() -> void: _insert_toolbox_item(captured))
\tthumb_container.add_child(thumb_btn)

\tif bool(captured.get("verified", true)):
\t\tvar shield_rect: TextureRect = TextureRect.new()
\t\tshield_rect.texture = _shield_tex
\t\tshield_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
\t\tshield_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
\t\tshield_rect.custom_minimum_size = Vector2(16, 16)
\t\tshield_rect.size = Vector2(16, 16)
\t\tshield_rect.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
\t\tshield_rect.offset_left = -20.0
\t\tshield_rect.offset_top = -20.0
\t\tshield_rect.offset_right = -4.0
\t\tshield_rect.offset_bottom = -4.0
\t\tshield_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
\t\tthumb_container.add_child(shield_rect)"""

    if old_thumb_code in content_n:
        content_n = content_n.replace(old_thumb_code, new_thumb_code)
        print("Applied thumb container fix to", p)
    else:
        print("Could not find old thumb code in", p)

    # 2. Fix _pub_icon_dialog parenting
    old_pub_dialog_parent = "\t_publish_window.add_child(_pub_icon_dialog)"
    new_pub_dialog_parent = """\t_pub_icon_dialog.transient = true
\t_pub_icon_dialog.exclusive = false
\tadd_child(_pub_icon_dialog)"""
    if old_pub_dialog_parent in content_n:
        content_n = content_n.replace(old_pub_dialog_parent, new_pub_dialog_parent)
        print("Applied _pub_icon_dialog parenting fix to", p)

    # 3. Add 📸 Snapshot View button to Publish Dialog
    old_icon_row = """\tvar pick_icon_btn: Button = Button.new()
\tpick_icon_btn.text = "Choose Icon..."
\tpick_icon_btn.pressed.connect(func() -> void:
\t\t_pub_icon_dialog.popup_centered_ratio(0.65)
\t)
\ticon_row.add_child(pick_icon_btn)"""

    new_icon_row = """\tvar snap_icon_btn: Button = Button.new()
\tsnap_icon_btn.text = "📸 Snapshot View"
\tsnap_icon_btn.tooltip_text = "Capture 3D viewport into 128x128 icon image"
\tsnap_icon_btn.pressed.connect(_on_snapshot_viewport_as_publish_icon)
\ticon_row.add_child(snap_icon_btn)

\tvar pick_icon_btn: Button = Button.new()
\tpick_icon_btn.text = "Choose Icon..."
\tpick_icon_btn.pressed.connect(func() -> void:
\t\t_pub_icon_dialog.popup_centered_ratio(0.65)
\t)
\ticon_row.add_child(pick_icon_btn)"""

    if old_icon_row in content_n:
        content_n = content_n.replace(old_icon_row, new_icon_row)
        print("Applied snapshot icon button to", p)

    # 4. Add _on_snapshot_viewport_as_publish_icon helper function before _on_publish_icon_selected
    old_fn = "func _on_publish_icon_selected(src_path: String) -> void:"
    snap_fn = """func _on_snapshot_viewport_as_publish_icon() -> void:
\tvar vp: SubViewport = null
\tif plugin != null and plugin.get_editor_interface() != null:
\t\tvp = plugin.get_editor_interface().get_editor_viewport_3d(0)
\tif vp == null:
\t\tvp = get_viewport() as SubViewport
\tif vp != null:
\t\tvar tex: ViewportTexture = vp.get_texture()
\t\tif tex != null:
\t\t\tvar img: Image = tex.get_image()
\t\t\tif img != null and not img.is_empty():
\t\t\t\tvar min_dim: int = mini(img.get_width(), img.get_height())
\t\t\t\tvar start_x: int = (img.get_width() - min_dim) / 2
\t\t\t\tvar start_y: int = (img.get_height() - min_dim) / 2
\t\t\t\tvar cropped: Image = img.get_region(Rect2i(start_x, start_y, min_dim, min_dim))
\t\t\t\tcropped.resize(128, 128, Image.INTERPOLATE_LANCZOS)
\t\t\t\t_ensure_dirs()
\t\t\t\tvar snap_path: String = "%s/snapshot_preview_%d.png" % [PROJECT_PUBLISHED_DIR, Time.get_unix_time_from_system()]
\t\t\t\tvar global_snap: String = ProjectSettings.globalize_path(snap_path)
\t\t\t\tvar err: Error = cropped.save_png(global_snap)
\t\t\t\tif err == OK:
\t\t\t\t\t_pub_pending_icon_path = snap_path
\t\t\t\t\t_pub_icon_path_lbl.text = "Viewport Snapshot"
\t\t\t\t\tvar ptex := ImageTexture.create_from_image(cropped)
\t\t\t\t\t_pub_icon_preview.texture = ptex
\t\t\t\t\t_set_status("Snapped 3D Viewport for icon!", Color(0.52, 0.96, 0.64))
\t\t\t\t\treturn
\t_set_status("Could not snapshot viewport. Please click 'Choose Icon...' to pick an image.", Color(1.0, 0.72, 0.40))


""" + old_fn

    if old_fn in content_n and "func _on_snapshot_viewport_as_publish_icon" not in content_n:
        content_n = content_n.replace(old_fn, snap_fn)
        print("Added _on_snapshot_viewport_as_publish_icon to", p)

    with open(p, "w", encoding="utf-8") as f:
        f.write(content_n)
    print("Done writing:", p)
