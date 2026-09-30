extends SceneTree

## Dev probe: what do the R6IK rig animation tracks actually target?
## The body meshes are rigid (not skinned) — if the tracks drive the
## MeshInstance nodes directly, we can play the clips as-is; if they only
## drive skeleton bones, the visible parts never move and we need another way.

func _init() -> void:
        var packed: PackedScene = load("res://assets/models/R6IK_rig.scn")
        if packed == null:
                print("PROBE_FAILED")
                quit(1)
                return
        var root: Node = packed.instantiate()
        for node in root.find_children("*", "AnimationPlayer", true, false):
                var ap := node as AnimationPlayer
                for anim_name in ap.get_animation_list():
                        var anim := ap.get_animation(anim_name)
                        print("ANIM '%s' length=%.3f tracks=%d" % [anim_name, anim.length, anim.get_track_count()])
                        var shown := {}
                        for t in range(anim.get_track_count()):
                                var path := str(anim.track_get_path(t))
                                var kind := anim.track_get_type(t)
                                var key := "%s|%d" % [path.split(":")[0], kind]
                                if shown.has(key):
                                        continue
                                shown[key] = true
                                print("   track %d: %s (type %d)" % [t, path, kind])
        root.free()
        quit(0)
