extends SceneTree

## Guards the NODE-BASED editability contract: the UI is SCENE, not script.
## Everything devs touch in the editor must exist as real nodes inside the
## .tscn files — the HUD toolbar, health bar, animations and sound players;
## the auth card's animation and sounds; the player's 3D sound nodes; the
## map as RetroPart/SpawnLocation/RetroLadder node instances.
## Run with:
##   godot --headless --path . --script res://tests/probe_nodes.gd

var failures: Array = []


func _ok(condition: bool, label: String) -> void:
        if condition:
                print("ok: ", label)
        else:
                failures.append(label)
                print("FAIL: ", label)


func _initialize() -> void:
        await process_frame

        # ===== HUD: the whole interface lives in scenes/hud.tscn =====
        var hud: Node = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
        root.add_child(hud)
        await process_frame
        await process_frame

        # toolbar is a SCENE node — no code-built reparenting anymore
        var toolbar: Node = hud.get_node_or_null("Root/Toolbar")
        _ok(toolbar is PanelContainer, "toolbar is a scene node (Root/Toolbar)")
        var row: Node = hud.get_node_or_null("Root/Toolbar/Buttons")
        _ok(row != null, "toolbar row is a scene node (Root/Toolbar/Buttons)")
        if row != null:
                for wanted in ["MenuButton", "ChatButton", "PeopleButton"]:
                        var btn: Button = row.get_node_or_null(NodePath(wanted)) as Button
                        _ok(btn != null, "toolbar button is a scene node: " + wanted)
                        if btn != null:
                                _ok(btn.icon != null, wanted + " icon set in the scene")

        # health bar is a SCENE node (used to be built in code)
        var track: Node = hud.get_node_or_null("Root/HealthBar/HealthBox/HealthTrack")
        _ok(track is ColorRect, "health bar track is a scene node")
        var fill: ColorRect = hud.get_node_or_null("%HealthFill")
        _ok(fill != null and fill.get_parent() == track, "health fill lives inside the scene track")
        var hval: Label = hud.get_node_or_null("%HealthValue")
        _ok(hval != null, "health value label is a scene node")

        # UI animations are real AnimationPlayer resources
        var anim: AnimationPlayer = hud.get_node_or_null("UIAnim")
        _ok(anim is AnimationPlayer, "HUD has a UIAnim AnimationPlayer node")
        if anim != null:
                _ok(anim.has_animation("menu_open"), "menu_open animation exists (editable in the editor)")
                _ok(anim.has_animation("menu_close"), "menu_close animation exists")

        # UI sounds are scene nodes with streams — no code-loaded audio
        for sound_name in ["ClickSound", "HoverSound", "OpenSound", "CloseSound"]:
                var sfx: Node = hud.get_node_or_null("UISounds/" + sound_name)
                _ok(sfx is AudioStreamPlayer and (sfx as AudioStreamPlayer).stream != null,
                        "HUD sound node with stream: UISounds/" + sound_name)

        # the ESC menu exposes the logout + account widgets
        _ok(hud.get_node_or_null("%LogoutBtn") is Button, "menu has a Log Out button")
        _ok(hud.get_node_or_null("%AccountLabel") is Label, "menu has an account label")

        # behavior still works: menu rides the animation, chat/roster toggle
        (hud as CanvasLayer).call("set_menu", true)
        await process_frame
        _ok((hud.get_node_or_null("%Menu") as Control).visible, "menu opens")
        (hud as CanvasLayer).call("set_menu", false)
        await process_frame
        hud.queue_free()

        # ===== auth card: animation + sounds are scene resources =====
        var auth: Node = (load("res://scenes/auth_screen.tscn") as PackedScene).instantiate()
        root.add_child(auth)
        await process_frame
        var auth_anim: AnimationPlayer = auth.get_node_or_null("UIAnim")
        _ok(auth_anim is AnimationPlayer and auth_anim.has_animation("card_in"),
                "auth card has a card_in animation")
        _ok(auth.get_node_or_null("UISounds/SuccessSound") is AudioStreamPlayer
                and (auth.get_node_or_null("UISounds/SuccessSound") as AudioStreamPlayer).stream != null,
                "auth card has a success sound")
        _ok(auth.get_node_or_null("UISounds/DenySound") is AudioStreamPlayer,
                "auth card has a deny sound")
        auth.queue_free()

        # ===== player: 3D sound nodes live in scenes/player.tscn =====
        var player: Node = (load("res://scenes/player.tscn") as PackedScene).instantiate()
        root.add_child(player)
        await process_frame
        for sound_name in ["JumpSound", "LandSound", "StepSound"]:
                var sfx3d: Node = player.get_node_or_null(NodePath(sound_name))
                _ok(sfx3d is AudioStreamPlayer3D and (sfx3d as AudioStreamPlayer3D).stream != null,
                        "player 3D sound node with stream: " + sound_name)
        player.queue_free()

        # ===== sound assets exist on disk =====
        for sound_path in ["jump", "land", "step", "click", "hover", "success", "deny", "open", "close"]:
                _ok(ResourceLoader.exists("res://assets/sounds/%s.wav" % sound_path),
                        "sound asset exists: assets/sounds/%s.wav" % sound_path)

        # ===== the map is a NODE scene (parts, spawns, ladder as instances) =====
        var map: Node = (load("res://scenes/maps/classic_baseplate.tscn") as PackedScene).instantiate()
        _ok(map != null, "map loads as a scene")
        if map != null:
                var parts: Array = map.find_children("*", "RetroPart", true, false)
                var spawns: Array = map.find_children("*", "SpawnLocation", true, false)
                _ok(parts.size() >= 15, "map parts are editable RetroPart nodes (%d)" % parts.size())
                _ok(spawns.size() == 4, "map spawns are editable nodes (%d)" % spawns.size())
                map.free()

        if failures.is_empty():
                print("NODES PROBE OK")
                quit(0)
        else:
                for failure in failures:
                        print("FAIL: ", failure)
                quit(1)
