import os

paths = [
    r"D:\Folders\RetroBlox\RetroBlox_SDK\addons\retroblox_studio\toolbox_dock.gd",
    r"D:\Folders\RetroBlox\RetroBlox\public\godot\RetroBloxPlayer\addons\retroblox_studio\toolbox_dock.gd"
]

for p in paths:
    if not os.path.exists(p):
        print("Skipping non-existent:", p)
        continue
    with open(p, "r", encoding="utf-8") as f:
        src = f.read()

    # 1. Patch _load_texture_from_any_path to strictly resize all loaded icons to 128x128
    old_load = """func _load_texture_from_any_path(icon_p: String) -> Texture2D:
\tif icon_p == "":
\t\treturn null
\tif _thumb_cache.has("file:" + icon_p):
\t\treturn _thumb_cache["file:" + icon_p] as Texture2D
\tif icon_p.begins_with("res://") and ResourceLoader.exists(icon_p):
\t\tvar r: Resource = load(icon_p)
\t\tif r is Texture2D:
\t\t\t_thumb_cache["file:" + icon_p] = r
\t\t\treturn r as Texture2D
\tvar glob_p: String = ProjectSettings.globalize_path(icon_p)
\tif FileAccess.file_exists(icon_p) or FileAccess.file_exists(glob_p):
\t\tvar load_p: String = glob_p if FileAccess.file_exists(glob_p) else icon_p
\t\tvar img: Image = Image.load_from_file(load_p)
\t\tif img != null and not img.is_empty():
\t\t\tvar tex: ImageTexture = ImageTexture.create_from_image(img)
\t\t\t_thumb_cache["file:" + icon_p] = tex
\t\t\treturn tex
\treturn null"""

    new_load = """func _load_texture_from_any_path(icon_p: String) -> Texture2D:
\tif icon_p == "":
\t\treturn null
\tif _thumb_cache.has("file:" + icon_p):
\t\treturn _thumb_cache["file:" + icon_p] as Texture2D
\tvar glob_p: String = ProjectSettings.globalize_path(icon_p)
\tvar load_p: String = glob_p if FileAccess.file_exists(glob_p) else icon_p
\tif FileAccess.file_exists(load_p):
\t\tvar img: Image = Image.load_from_file(load_p)
\t\tif img != null and not img.is_empty():
\t\t\tif img.get_width() != 128 or img.get_height() != 128:
\t\t\t\timg.resize(128, 128, Image.INTERPOLATE_LANCZOS)
\t\t\tvar tex: ImageTexture = ImageTexture.create_from_image(img)
\t\t\t_thumb_cache["file:" + icon_p] = tex
\t\t\treturn tex
\tif icon_p.begins_with("res://") and ResourceLoader.exists(icon_p):
\t\tvar r: Resource = load(icon_p)
\t\tif r is Texture2D:
\t\t\tvar r_img: Image = (r as Texture2D).get_image()
\t\t\tif r_img != null and not r_img.is_empty():
\t\t\t\tif r_img.get_width() != 128 or r_img.get_height() != 128:
\t\t\t\t\tr_img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
\t\t\t\tvar tex: ImageTexture = ImageTexture.create_from_image(r_img)
\t\t\t\t_thumb_cache["file:" + icon_p] = tex
\t\t\t\treturn tex
\t\t\t_thumb_cache["file:" + icon_p] = r
\t\t\treturn r as Texture2D
\treturn null"""

    if old_load in src:
        src = src.replace(old_load, new_load)
        print("Updated _load_texture_from_any_path in", p)
    else:
        print("Could not find exact old _load_texture_from_any_path in", p)

    # 2. Patch _on_custom_icon_file_selected to save resized 128x128 and persist in user catalog
    old_custom_icon = """\t# Copy icon into project published dir & user dir for the target item_id
\t_ensure_dirs()
\tvar ext: String = src_path.get_extension().to_lower()
\tvar slug: String = _slugify(_icon_target_item_id)
\tvar dst_proj: String = "%s/%s_icon.%s" % [PROJECT_PUBLISHED_DIR, slug, ext]
\tvar dst_user: String = "%s/%s_icon.%s" % [USER_SAVED_DIR, slug, ext]

\tvar wf1: FileAccess = FileAccess.open(dst_proj, FileAccess.WRITE)
\tif wf1 != null:
\t\twf1.store_buffer(bytes)
\tvar wf2: FileAccess = FileAccess.open(dst_user, FileAccess.WRITE)
\tif wf2 != null:
\t\twf2.store_buffer(bytes)"""

    new_custom_icon = """\t# Copy icon into project published dir & user dir for the target item_id
\t_ensure_dirs()
\tvar ext: String = src_path.get_extension().to_lower()
\tvar slug: String = _slugify(_icon_target_item_id)
\tvar dst_proj: String = "%s/%s_icon.png" % [PROJECT_PUBLISHED_DIR, slug]
\tvar dst_user: String = "%s/%s_icon.png" % [USER_SAVED_DIR, slug]

\tvar src_load_p: String = global_src if FileAccess.file_exists(global_src) else src_path
\tvar img: Image = Image.load_from_file(src_load_p)
\tif img != null and not img.is_empty():
\t\timg.resize(128, 128, Image.INTERPOLATE_LANCZOS)
\t\timg.save_png(ProjectSettings.globalize_path(dst_proj))
\t\timg.save_png(ProjectSettings.globalize_path(dst_user))
\telse:
\t\tvar wf1: FileAccess = FileAccess.open(dst_proj, FileAccess.WRITE)
\t\tif wf1 != null: wf1.store_buffer(bytes)
\t\tvar wf2: FileAccess = FileAccess.open(dst_user, FileAccess.WRITE)
\t\tif wf2 != null: wf2.store_buffer(bytes)"""

    if old_custom_icon in src:
        src = src.replace(old_custom_icon, new_custom_icon)
        print("Updated _on_custom_icon_file_selected in", p)
    else:
        print("Could not find exact old _on_custom_icon_file_selected in", p)

    # 3. Patch _on_files_uploaded so uploading 1 file opens publish dialog with icon picker
    old_files_uploaded = """func _on_files_uploaded(paths: PackedStringArray) -> void:
\t_ensure_dirs()
\tvar imported_count: int = 0
\tfor src_path in paths:"""

    new_files_uploaded = """func _on_files_uploaded(paths: PackedStringArray) -> void:
\tif paths.size() == 1:
\t\tvar single_p: String = paths[0]
\t\tvar fname: String = single_p.get_file()
\t\topen_publish_dialog_for_selection()
\t\t_pub_title_input.text = fname.get_basename().replace("_", " ").capitalize()
\t\tvar ext: String = fname.get_extension().to_lower()
\t\tif ext == "gd":
\t\t\t_pub_cat_option.selected = 1 # Scripts
\t\t\t_pub_mode_option.selected = 1 # Script only
\t\telif ext in ["mp3", "wav", "ogg", "png", "jpg", "jpeg"]:
\t\t\t_pub_cat_option.selected = 3 # Audio & Decals
\t\t_set_status("Selected '%s' for publishing. Snapshot or choose an icon, then click OK!" % fname, Color(0.45, 0.88, 1.0))
\t\treturn
\t_ensure_dirs()
\tvar imported_count: int = 0
\tfor src_path in paths:"""

    if old_files_uploaded in src:
        src = src.replace(old_files_uploaded, new_files_uploaded)
        print("Updated _on_files_uploaded in", p)
    else:
        print("Could not find exact old _on_files_uploaded in", p)

    with open(p, "w", encoding="utf-8") as f:
        f.write(src)
    print("Saved", p)
