extends SceneTree
## validate_scenes.gd — instantiate every UI/world scene the way the game
## does and verify the unique-name (%Node) wiring survives _ready.
## Catches the "%MenuButton not found" class of bug that --check-only
## cannot see (script parses fine; the SCENE wiring is broken).
## Run: godot --headless --path . --script res://tests/validate_scenes.gd

var _failures: int = 0


func check(cond: bool, label: String) -> void:
        if cond:
                print("  ok    " + label)
        else:
                _failures += 1
                printerr("  FAIL  " + label)


func _initialize() -> void:
        await process_frame
        print("== RetroBlox scene wiring validation ==")

        # ---- HUD: buttons must resolve via % even AFTER the toolbar moves them
        var hud: Node = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
        root.add_child(hud)
        await process_frame
        await process_frame
        for n in ["MenuButton", "ChatButton", "PeopleButton", "ChatPanel", "RosterPanel", "Menu"]:
                check(hud.get_node_or_null("%" + n) != null, "HUD %%-lookup %s resolves after _ready" % n)
        var mb: Node = hud.get_node_or_null("%MenuButton")
        if mb != null:
                check(mb.owner == hud, "moved buttons keep the scene owner")
                check(mb.get_parent().get_parent().name == "Toolbar", "MenuButton lives in the toolbar")
        hud.queue_free()

        # ---- auth screen instantiates
        var auth: Node = (load("res://scenes/auth_screen.tscn") as PackedScene).instantiate()
        root.add_child(auth)
        await process_frame
        for n in ["ServerEdit", "UserEdit", "PassEdit", "SubmitBtn", "Status"]:
                check(auth.get_node_or_null("%" + n) != null, "Auth %%-lookup %s resolves" % n)
        auth.queue_free()

        # ---- world pieces instantiate (no _ready errors = wiring OK)
        for path in ["res://scenes/part.tscn", "res://scenes/spawn_location.tscn",
                        "res://scenes/ladder.tscn", "res://scenes/avatar.tscn",
                        "res://scenes/player.tscn"]:
                var node: Node = (load(path) as PackedScene).instantiate()
                root.add_child(node)
                await process_frame
                check(is_instance_valid(node), "%s instantiates cleanly" % path.get_file())
                # the script must have PARSED and attached — a missing base
                # class (stale class cache) otherwise fails silently here
                check(node.get_script() != null, "%s has its script attached" % path.get_file())
                node.queue_free()

        # ---- the map's spawn pads prove spawn_location.gd actually ran
        await process_frame
        var map: Node = (load("res://scenes/maps/classic_baseplate.tscn") as PackedScene).instantiate()
        root.add_child(map)
        await process_frame
        check(get_nodes_in_group("spawn").size() == 4, "map registers 4 spawn pads (spawn_location.gd ran)")

        if _failures == 0:
                print("== ALL SCENE VALIDATION PASSED ==")
        else:
                printerr("== %d FAILURES ==" % _failures)
        quit(1 if _failures > 0 else 0)
