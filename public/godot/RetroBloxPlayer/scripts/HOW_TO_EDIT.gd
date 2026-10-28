extends Node
# ============================================================================
# RETROBLOX BUILDER & GEAR SDK - QUICK GUIDE
# ============================================================================
# 1. UNLINK DATA & DUPLICATING PARTS:
#    - Duplicating any part (Ctrl+D) automatically unlinks its Mesh, Material,
#      and CollisionShape so changing one part color/size NEVER changes the other.
#    - You can also click "Unlink Data" on the 3D toolbar anytime.
#
# 2. SURFACE STUDS CONFIGURATION (TOP, BOTTOM, LEFT, RIGHT, FULL):
#    - Select any part and use the "Surface Studs" dropdown on the 3D toolbar,
#      or toggle checkboxes in Inspector -> Material Override -> Shader Parameters:
#        * stud_full:   Check to display studs on ALL faces (Full studs!)
#        * stud_top:    Uncheck if you do not want studs on top
#        * stud_bottom: Check to display studs on bottom / underside
#        * stud_left:   Check to display studs on the left face
#        * stud_right:  Check to display studs on the right face
#        * stud_front / stud_back: Check for front and back faces
#
# 3. SPAWN INSIDE SELECTED NODE & AT CAMERA LOOK POINT:
#    - Select any Node3D / Folder in the Scene Tree and click "+ Part" or
#      "+ Item Spawner": the new object is placed as a child INSIDE that node
#      and spawns in 3D right where your editor camera is looking!
#    - Collapsed nodes in the Scene Tree stay collapsed when inserting parts.
#
# 4. SNAP CONTROLS (MOVE SNAP & SCALE SNAP):
#    - Use "Snap: ON/OFF", "Move: 0.25..4 studs", and "Scale: 0.1..1 stud"
#      directly on the top 3D toolbar.
#
# 5. HIDE NODE & HIDER/UNHIDER NODE PANEL:
#    - Click "Hide Node" to hide the selected node from the Workspace (Scene)
#      panel, or open "Hider/Unhider Node" to Hide All, Unhide All, or toggle
#      specific nodes.
#
# 6. 21 EDITABLE ITEMS, ITEM SPAWNERS & INFINITE BACKPACK INVENTORY:
#    - Select any ItemSpawner under World/ItemSpawners (or insert one via
#      "+ Item Spawner") to edit all item variables in the Inspector:
#      Speed/Gravity/Fusion/Heal Coils, Linked/Flame/Slow/Super Sword (with
#      double-click Lunge!), Healing Potion, Big Head Potion, Flying Carpet,
#      Laser Gun, Rocket Launcher, Subspace Tripmine, Grappler, Spicy Sauce
#      (3x speed for health), Ghost Burger (invisibility), Hamburger, Sandwich
#      and Bloxy Cola.
#    - Every gear also exists as an editable resource in res://gears/*.tres —
#      open one and change damage, lunge speed, duration, heal amounts, etc.
#    - Lunge is now a FLAT dash: same height the whole way (even over a hole),
#      and you fall normally once the dash ends. Super Sword dashes faster and
#      pops slightly upward.
#7. MAP DISTRICTS & WORLD CONFIG:
#    - World/SafeZone is the big spawn safe zone (no damage, slow heal).
#    - World/FoodCourt, World/GrappleRange, World/CombatArena, World/ObbyCourse
#      and World/BuildingYard are ordinary nodes: move them anywhere.
#    - Select World/WorldConfig to change safe-zone radius/heal, item respawn
#      timers and plaza distances without touching a script.
#    - Toggle "lose_item_when_dead" (default: On) on LocalPlayer, in Player
#      Settings, or per ItemSpawner.
#    - Press "," (Comma) or click the Backpack icon in the top-left Topbar
#      to open your infinite-storage Inventory and drag items to/from the Hotbar.
# ============================================================================
