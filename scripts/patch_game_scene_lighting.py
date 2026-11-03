import os

game_paths = [
    r"D:\Apps\GameEngines\MyGames\ColorWorld\scripts\game\game.gd",
    r"D:\Folders\RetroBlox\RetroBlox_SDK\scripts\game\game.gd",
    r"D:\Folders\RetroBlox\RetroBlox\public\godot\RetroBloxPlayer\scripts\game\game.gd"
]

strip_func = """func _strip_game_controller_from_node(n: Node) -> void:
\tif n == null:
\t\treturn
\t# 1. Remove any game controller script attached to the imported scene root
\tvar s: Variant = n.get_script()
\tif s != null and (s is Script):
\t\tvar sp: String = (s as Script).resource_path
\t\tif sp.ends_with("game.gd") or sp.ends_with("main.gd") or sp.ends_with("client.gd"):
\t\t\tn.set_script(null)

\t# 2. Scan descendants: strip child game scripts and remove duplicate CanvasLayer/HUD/Camera/Player
\tvar to_remove: Array[Node] = []
\tvar stack: Array[Node] = [n]
\twhile not stack.is_empty():
\t\tvar cur: Node = stack.pop_back()
\t\tfor c in cur.get_children():
\t\t\tstack.append(c)

\t\tvar cur_name: String = cur.name.to_lower()
\t\tvar cs: Variant = cur.get_script()
\t\tif cs != null and (cs is Script):
\t\t\tvar csp: String = (cs as Script).resource_path
\t\t\tif csp.ends_with("game.gd") or csp.ends_with("chat_box.gd") or csp.ends_with("color_world_ui.gd"):
\t\t\t\tcur.set_script(null)

\t\tif cur is CanvasLayer or cur.name == "HUD" or cur_name == "hud" or cur_name == "chatbox" or cur_name == "topbar":
\t\t\tto_remove.append(cur)
\t\telif cur is Camera3D:
\t\t\t(cur as Camera3D).current = false
\t\t\tcur.process_mode = Node.PROCESS_MODE_DISABLED
\t\t\tto_remove.append(cur)
\t\telif cur != player and (cur.name == "LocalPlayer" or cur.name == "Player" or cur.name == "CameraRig"):
\t\t\tto_remove.append(cur)

\tfor rem in to_remove:
\t\tif is_instance_valid(rem):
\t\t\trem.process_mode = Node.PROCESS_MODE_DISABLED
\t\t\tif rem is CanvasItem:
\t\t\t\t(rem as CanvasItem).visible = false
\t\t\trem.queue_free()


"""

for gp in game_paths:
    if not os.path.exists(gp):
        print("Skipping non-existent:", gp)
        continue
    with open(gp, "r", encoding="utf-8") as f:
        content = f.read()

    content_n = content.replace("\r\n", "\n")

    # Add _strip_game_controller_from_node if not present
    if "func _strip_game_controller_from_node" not in content_n:
        target = "func _setup_scene_map_node(root_node: Node, map_id: String) -> void:"
        if target in content_n:
            content_n = content_n.replace(target, strip_func + target)
            print("Added _strip_game_controller_from_node to", gp)
        else:
            print("Could not find _setup_scene_map_node target in", gp)

    # Wrap CommunityMapManager.instantiate_map_model
    old_call1 = """\t\t\tvar inst := CommunityMapManager.instantiate_map_model(file_path)
\t\t\tif inst != null:
\t\t\t\tm_node = Node3D.new()
\t\t\t\tm_node.name = scene_node_name
\t\t\t\tmaps_root.add_child(m_node)
\t\t\t\tm_node.add_child(inst)
\t\t\t\t_setup_scene_map_node(inst, map_id)"""

    new_call1 = """\t\t\tvar inst := CommunityMapManager.instantiate_map_model(file_path)
\t\t\tif inst != null:
\t\t\t\t_strip_game_controller_from_node(inst)
\t\t\t\tm_node = Node3D.new()
\t\t\t\tm_node.name = scene_node_name
\t\t\t\tmaps_root.add_child(m_node)
\t\t\t\tm_node.add_child(inst)
\t\t\t\t_setup_scene_map_node(inst, map_id)"""

    if old_call1 in content_n:
        content_n = content_n.replace(old_call1, new_call1)
        print("Updated CommunityMapManager instantiation in", gp)

    # Wrap packed_sc.instantiate()
    old_call2 = """\t\t\t\tif packed_sc != null:
\t\t\t\t\tm_node = Node3D.new()
\t\t\t\t\tm_node.name = scene_node_name
\t\t\t\t\tmaps_root.add_child(m_node)
\t\t\t\t\tvar inst: Node = packed_sc.instantiate()
\t\t\t\t\tm_node.add_child(inst)
\t\t\t\t\t_setup_scene_map_node(inst, map_id)"""

    new_call2 = """\t\t\t\tif packed_sc != null:
\t\t\t\t\tm_node = Node3D.new()
\t\t\t\t\tm_node.name = scene_node_name
\t\t\t\t\tmaps_root.add_child(m_node)
\t\t\t\t\tvar inst: Node = packed_sc.instantiate()
\t\t\t\t\t_strip_game_controller_from_node(inst)
\t\t\t\t\tm_node.add_child(inst)
\t\t\t\t\t_setup_scene_map_node(inst, map_id)"""

    if old_call2 in content_n:
        content_n = content_n.replace(old_call2, new_call2)
        print("Updated packed_sc instantiation in", gp)

    with open(gp, "w", encoding="utf-8") as f:
        f.write(content_n)
    print("Done writing:", gp)
