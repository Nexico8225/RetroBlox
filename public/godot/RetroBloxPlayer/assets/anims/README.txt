DROP YOUR ANIMATIONS HERE
=========================

Put animation files (.fbx or .glb) in this folder and open the project —
RetroBlox picks them up automatically. No code, no renaming.

Clip names -> what they play:
  Idle / Old_Idle / Stand ......... standing still
  Walk / Old_Walk / Walking ....... moving
  Run / Running / Sprint .......... fast movement (used when no walk clip)
  Jump / Old_Jump / Leap .......... jumping (holds the last frame mid-air)
  Fall / Falling / Freefall ....... falling (falls back to the jump clip)
  Climb / Ladder / Truss .......... on a ladder
  Sit / Sitting ................... reserved for seats

Names are matched loosely: "My_Cool-Walk 2" plays as the walk clip.
User clips always win over the rig's built-in Old_* clips.

IMPORTANT — getting the animations INTO the file
------------------------------------------------
An FBX only carries animations when the export includes them. In Blender:

  File > Export > FBX (.fbx)
    - Bake Animation: ON  (this is the switch that was missed)
    - All Actions / NLA Strips: ON if your clips live in the NLA
    - Object Types: Mesh + Armature (if you use one)
    - Path Mode: Copy + embed textures

Or skip the dialog entirely: File > Export > glTF 2.0 (.glb) — .glb ALWAYS
carries every action, keeps materials, and is the recommended format.

user://anims (advanced, no re-download needed)
----------------------------------------------
You can also put .glb files in
    Windows: %APPDATA%/Godot/app_userdata/RetroBlox Player/anims/
    macOS:   ~/Library/Application Support/Godot/app_userdata/RetroBlox Player/anims/
    Linux:   ~/.local/share/godot/app_userdata/RetroBlox Player/anims/
Runtime loading works with .glb only (FBX needs the editor import step).

Animate in place — the character engine moves the body, the clips should
not walk across the map. Root motion is not used.
