extends Node
# Developer guide for customizing worlds, animations, and UI in the RetroBlox SDK.

# ============================================================================
# 1. BUILDING YOUR 3D GAME / WORLD (scenes/retroblox.tscn)
# ============================================================================
# - Open `res://scenes/retroblox.tscn` in Godot's 3D tab to build your map
#   under the `World` node. Everything you see under `World` in `retroblox.tscn`
#   is the exact map played in the game!
# - 1 stud = 1 meter in Godot. Characters can step up 0.1–2.0 stud blocks
#   automatically, and use a Roblox-style CapsuleShape3D collision body.
# - Select any special brick or pad (`DamageBrick`, `KillBrick`, `HealBrick`,
#   `InstaHealBrick`, `SpeedCoilPad`, `GravityCoilPad`, `Trampoline`, `ClimbLadder`,
#   `MovingPlatformAlways`, `MovingPlatformOnStand`) in `retroblox.tscn` and look
#   at the Inspector panel on the right to edit its `@export` variables (`pad_type`,
#   `damage_amount`, `heal_amount`, `speed_multiplier`, `gravity_multiplier`,
#   `bounce_power`, `climb_speed`, `move_on_stand`, etc.).
# - Add any StaticBody3D to group:
#     * `"spawn"`       -> Spawn pad
#     * `"ladder"`      -> Climbable part (climbs while the player's Torso touches it, and smoothly steps onto the platform at the top)
#     * `"damage"`      -> Damage brick (hurts player by `metadata/damage`, default 20 HP per tick)
#     * `"kill"`        -> Kill brick (instant 100% death on touch)
#     * `"heal"`        -> Heal brick (heals player by `metadata/heal`, default 15 HP per tick)
#     * `"insta_heal"`  -> Insta-Heal brick (restores 100% full health immediately)
#     * `"bounce"`      -> Trampoline pad
#     * `"speed_pad"`   -> Speed Coil boost pad
#     * `"gravity_pad"` -> Gravity Coil low-gravity pad
# - For Moveable Platforms (`res://scripts/world/moving_platform.gd`):
#     * Add an `AnimatableBody3D` with `moving_platform.gd` attached.
#     * Set `point_a` and `point_b` in the Inspector.
#     * Set `move_mode` to `0` ("Always Move") or `1` ("Move When Player Stands On It") / toggle `move_on_player_stand`.
#     * Pick `easing` (`"Linear"`, `"SineInOut"`, `"QuadInOut"`, `"CubicInOut"`, `"ExpoInOut"`, `"BounceOut"`, `"ElasticOut"`, `"BackInOut"`).
#
# ============================================================================
# 2. EDITING ANIMATIONS (Walk, Jump, Climb, Idle, Sit)
# ============================================================================
# - Select `LocalPlayer` in `res://scenes/retroblox.tscn` and look at the
#   Inspector panel on the right under "Editable Animations", OR open
#   `res://scripts/player/avatar_rig.gd`.
# - You can adjust `walk_arm_swing`, `walk_leg_swing`, `walk_cycle_speed`,
#   `jump_arm_angle`, `jump_leg_spread`, and `climb_swing` directly.
# - If you want full keyframe animation control in Godot's Animation editor,
#   toggle `use_animation_player = true` on `AvatarRig` and edit the tracks on
#   its `AnimationPlayer` node (`Idle`, `Walk`, `Jump`, `Climb`, `Sit`).
#
# ============================================================================
# 3. EDITING THE UI & USING IN-GAME UI STUDIO
# ============================================================================
# - You can edit the HUD nodes directly inside `res://scenes/retroblox.tscn`
#   under the `HUD` CanvasLayer (`Topbar`, `ChatBox`, `FpsChip`, `MobileControls`).
# - While playing, click the UI Studio button in the topbar (or open Settings
#   -> "Open UI Studio") to drag/move any UI element, resize it (great for small
#   or Nokia-sized screens), rotate it, change its opacity, hide it, or add
#   your own custom images on screen.
#
# ============================================================================
# 4. LOGIN SCENE WARNING (scenes/login.tscn & scripts/ui/login.gd)
# ============================================================================
# - Do NOT modify `res://scenes/login.tscn` or `res://scripts/ui/login.gd`
#   unless you are only restyling the visual UI nodes OR you are a pro who
#   knows how the session/authentication handshake works.
