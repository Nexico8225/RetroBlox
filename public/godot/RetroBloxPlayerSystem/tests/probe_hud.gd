extends SceneTree

## Guards the classic top-left toolbar: after scenes/hud.tscn _ready(),
## %MenuButton must still resolve, all three buttons must sit inside the
## toolbar row with their icons loaded, and the menu signal must be wired.
## Run with:
##   godot --headless --path . --script res://tests/probe_hud.gd

func _initialize() -> void:
        await process_frame
        var scene: PackedScene = load("res://scenes/hud.tscn")
        if scene == null:
                print("FAIL: cannot load res://scenes/hud.tscn")
                quit(1)
                return
        var hud: Node = scene.instantiate()
        root.add_child(hud)
        await process_frame
        await process_frame

        var failures: Array = []

        # 1. the reference hud.gd uses — the @onready var must survive the
        # toolbar reparent (%Name lookups do NOT: reparenting into a
        # code-created container breaks Godot's unique-name registry)
        var menu_btn: Button = hud.get("menu_button") as Button
        if menu_btn == null:
                failures.append("hud.menu_button reference is null after _build_toolbar()")
        else:
                print("ok: menu_button wired at ", menu_btn.get_path())

        # 2. the toolbar row exists and holds all three classic buttons
        var row: Node = hud.get_node_or_null("Root/Toolbar/Buttons")
        if row == null:
                failures.append("Root/Toolbar/Buttons missing (toolbar not built)")
        else:
                var names: Array = []
                for child in row.get_children():
                        names.append(String(child.name))
                print("toolbar buttons: ", names)
                for wanted in ["MenuButton", "ChatButton", "PeopleButton"]:
                        if not names.has(wanted):
                                failures.append("toolbar row is missing " + wanted)

        # 3. every toolbar button carries its icon
        if row != null:
                for pair in [["MenuButton", "res://assets/icons/menu.png"],
                                ["ChatButton", "res://assets/icons/chat.png"],
                                ["PeopleButton", "res://assets/icons/people.png"]]:
                        var btn: Button = row.get_node_or_null(pair[0]) as Button
                        if btn != null and btn.icon == null:
                                failures.append(pair[0] + " has no icon (" + pair[1] + ")")

        # 4. the menu signal survived the reparent
        if menu_btn != null and menu_btn.pressed.get_connections().is_empty():
                failures.append("MenuButton.pressed is not connected to the menu")

        if failures.is_empty():
                print("HUD TOOLBAR OK")
                quit(0)
        else:
                for failure in failures:
                        print("FAIL: ", failure)
                quit(1)
