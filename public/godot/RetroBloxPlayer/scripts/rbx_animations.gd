extends RefCounted

## The RetroBlox animation system: SLOTS, not hardcoded clip names.
##
## The player needs an animation for seven situations (the "slots"):
##   idle / walk / run / jump / fall / climb / sit
##
## Clips come from two places, USER clips always win:
##   1. assets/anims/  — any .fbx or .glb you drop in the kit folder
##      (Godot imports it when the project opens; then it just plays)
##   2. user://anims/  — .glb files dropped there play WITHOUT re-downloading
##      the kit (Blender: File > Export > glTF 2.0). FBX cannot load at
##      runtime, which is why this folder asks for .glb.
##   3. the rig's own clips (R6IK.fbx: Old_Idle / Old_Walk / Old_Jump /
##      Climb / Idle / Walk / Run / Sit) as the fallback.
##
## Every imported track is REMAPPED onto the rig's real nodes, so a clip
## exported with part names like "Left Arm" or "Left_Arm" binds correctly
## even though the rig node is called "Left_Arm" (or anything aliased).

const SLOT_IDLE := "idle"
const SLOT_WALK := "walk"
const SLOT_RUN := "run"
const SLOT_JUMP := "jump"
const SLOT_FALL := "fall"
const SLOT_CLIMB := "climb"
const SLOT_SIT := "sit"
const SLOTS: Array[String] = [SLOT_IDLE, SLOT_WALK, SLOT_RUN, SLOT_JUMP, SLOT_FALL, SLOT_CLIMB, SLOT_SIT]

## Slots that cycle forever when played (jump holds its last frame instead).
const LOOP_SLOTS: Array[String] = [SLOT_IDLE, SLOT_WALK, SLOT_RUN, SLOT_CLIMB, SLOT_FALL, SLOT_SIT]

## Clip-name aliases per slot, priority order. The rig's old clips
## ("old idle", "old walk", "old jump") list first so today's classic feel
## is preserved, then the plain names user exports usually have.
const SLOT_ALIASES: Dictionary = {
        SLOT_IDLE: ["old idle", "idle", "stand", "breathing"],
        SLOT_WALK: ["old walk", "walk", "walking", "move"],
        SLOT_RUN: ["run", "running", "sprint", "jog"],
        SLOT_JUMP: ["old jump", "jump", "jumping", "leap"],
        SLOT_FALL: ["fall", "falling", "freefall", "in air"],
        SLOT_CLIMB: ["climb", "climbing", "ladder", "truss"],
        SLOT_SIT: ["sit", "sitting", "seat"],
}

## Where user animation files live.
const KIT_ANIM_DIR := "res://assets/anims"
const USER_ANIM_DIR := "user://anims"

# slot -> clip name (the unique name registered in the AnimationPlayer)
var _slots: Dictionary = {}
# registered clip name -> original clip name in the source file
var _source_names: Dictionary = {}
# every clip we know, name -> Animation (inspection/tests)
var clips: Dictionary = {}
var loaded_from: Array[String] = []   # human-readable list of files that contributed clips


## Scan one AnimationPlayer's built-in clips (the rig) and map slots.
func attach(anim_player: AnimationPlayer) -> void:
        if anim_player == null:
                return
        var rig_clips: Dictionary = {}
        for clip_name in anim_player.get_animation_list():
                rig_clips[String(clip_name)] = anim_player.get_animation(clip_name)
        _apply_candidates(rig_clips, false)


## Load every user animation file that exists and merge its clips into
## `anim_player`'s default library. Returns the number of files loaded.
func load_user_files(anim_player: AnimationPlayer, rig_root: Node) -> int:
        if anim_player == null:
                return 0
        var library := _default_library(anim_player)
        var node_map := _build_node_map(anim_player, rig_root)
        var count := 0
        var running_index := 0
        for dir_path: String in [KIT_ANIM_DIR, USER_ANIM_DIR]:
                for file_name: String in _list_anim_files(dir_path):
                        var full: String = dir_path.path_join(file_name)
                        var animations := _extract_animations(full)
                        if animations.is_empty():
                                print("[RetroBlox] anims: no clips found in ", full)
                                continue
                        count += 1
                        loaded_from.append(full)
                        for source_name in animations:
                                running_index += 1
                                var registered := "user_%d_%s" % [running_index, source_name]
                                var anim: Animation = (animations[source_name] as Animation).duplicate(true)
                                _remap_tracks(anim, node_map)
                                library.add_animation(registered, anim)
                                _source_names[registered] = String(source_name)
                                clips[registered] = anim
                        print("[RetroBlox] anims: loaded %d clips from %s" % [animations.size(), full])
        if count > 0:
                _remap_all_slots(anim_player)
        return count


## Play the clip bound to `slot`. Returns true when a clip is playing.
## `speed` drives speed_scale (play() itself always runs at 1.0 so the two
## never multiply into a surprise).
func play_slot(anim_player: AnimationPlayer, slot: String, blend: float, speed: float) -> bool:
        var clip := resolve(slot)
        if clip.is_empty() or anim_player == null:
                return false
        if anim_player.current_animation != clip:
                anim_player.play(clip, blend)
        anim_player.speed_scale = maxf(speed, 0.01)
        return true


## The clip name that plays for `slot` (may come from a fallback slot).
func resolve(slot: String) -> String:
        if _slots.has(slot):
                return String(_slots[slot])
        # sensible chains: fall falls back to jump, run falls back to walk
        if slot == SLOT_FALL and _slots.has(SLOT_JUMP):
                return String(_slots[SLOT_JUMP])
        if slot == SLOT_RUN and _slots.has(SLOT_WALK):
                return String(_slots[SLOT_WALK])
        return ""


func has_slot(slot: String) -> bool:
        return not resolve(slot).is_empty()


func describe() -> String:
        var parts: Array[String] = []
        for slot in SLOTS:
                var resolved := resolve(slot)
                parts.append("%s=%s" % [slot, resolved if not resolved.is_empty() else "-"])
        return ", ".join(parts)


## ------------------------------------------------------------------ internals

## Rebuild the whole slot map from one candidate set.
func _apply_candidates(clip_set: Dictionary, _unused: bool) -> void:
        _slots.clear()
        for slot in SLOTS:
                var clip := _best_clip(clip_set, slot)
                if not clip.is_empty():
                        _slots[slot] = clip

## After user clips are registered, prefer them: search user_* names first,
## then the rig's own clips, matching aliases per slot.
func _remap_all_slots(anim_player: AnimationPlayer) -> void:
        var user_clips: Dictionary = {}
        var rig_clips: Dictionary = {}
        for clip_name in anim_player.get_animation_list():
                var key := String(clip_name)
                if key.begins_with("user_"):
                        user_clips[key] = anim_player.get_animation(clip_name)
                else:
                        rig_clips[key] = anim_player.get_animation(clip_name)
        _slots.clear()
        for slot in SLOTS:
                var clip := _best_clip(user_clips, slot)
                if clip.is_empty():
                        clip = _best_clip(rig_clips, slot)
                if not clip.is_empty():
                        _slots[slot] = clip

func _best_clip(clip_set: Dictionary, slot: String) -> String:
        for alias in SLOT_ALIASES[slot]:
                for clip_name in clip_set:
                        if _norm(_match_name(String(clip_name))) == alias:
                                return String(clip_name)
        return ""

## The name aliases match against: the original clip name when known,
## otherwise the registered name with its "user_N_" bookkeeping prefix off.
func _match_name(clip_name: String) -> String:
        if _source_names.has(clip_name):
                return String(_source_names[clip_name])
        if clip_name.begins_with("user_"):
                var rest := clip_name.substr(5)
                var i := 0
                while i < rest.length() and rest[i] >= "0" and rest[i] <= "9":
                        i += 1
                if i > 0 and i < rest.length() and rest[i] == "_":
                        return rest.substr(i + 1)
                return rest
        return clip_name

func _default_library(anim_player: AnimationPlayer) -> AnimationLibrary:
        var lib_name := ""
        if not anim_player.has_animation_library(lib_name):
                anim_player.add_animation_library(lib_name, AnimationLibrary.new())
        return anim_player.get_animation_library(lib_name)


## All .fbx / .glb files in a folder ([] when the folder is missing).
func _list_anim_files(dir_path: String) -> Array[String]:
        var out: Array[String] = []
        if not DirAccess.dir_exists_absolute(dir_path):
                return out
        var dir := DirAccess.open(dir_path)
        if dir == null:
                return out
        dir.list_dir_begin()
        var file_name := dir.get_next()
        while file_name != "":
                if not dir.current_is_dir():
                        var lower := file_name.to_lower()
                        if lower.ends_with(".fbx") or lower.ends_with(".glb") or lower.ends_with(".gltf"):
                                out.append(file_name)
                file_name = dir.get_next()
        dir.list_dir_end()
        out.sort()
        return out


## Load an animation file and return {clip_name: Animation}. res:// paths go
## through the importer; user:// glb loads at runtime via GLTFDocument.
func _extract_animations(path: String) -> Dictionary:
        if path.begins_with("user://") and path.to_lower().ends_with(".glb"):
                return _collect_from(_load_glb_runtime(path))
        var packed: PackedScene = load(path)
        if packed == null:
                return {}
        var inst := packed.instantiate()
        if inst == null:
                return {}
        var found := _collect_from(inst)
        inst.free()   # never entered the tree — free() is safe here
        return found


## Runtime .glb loader — no import step needed (user:// support).
func _load_glb_runtime(path: String) -> Node:
        var bytes := FileAccess.get_file_as_bytes(path)
        if bytes.is_empty():
                return null
        var doc := GLTFDocument.new()
        var state := GLTFState.new()
        if doc.append_from_buffer(bytes, path.get_base_dir(), state) != OK:
                return null
        return doc.generate_scene(state)


func _collect_from(root: Node) -> Dictionary:
        var animations: Dictionary = {}
        if root == null:
                return animations
        for node in root.find_children("*", "AnimationPlayer", true, false):
                var player := node as AnimationPlayer
                # get_animation_library_list returns library NAMES
                for lib_name in player.get_animation_library_list():
                        var library := player.get_animation_library(lib_name)
                        for anim_name in library.get_animation_list():
                                animations[String(anim_name)] = library.get_animation(anim_name)
        return animations


## normalized node name -> NodePath from the AnimationPlayer's root_node.
func _build_node_map(anim_player: AnimationPlayer, rig_root: Node) -> Dictionary:
        var map: Dictionary = {}
        var base: Node = null
        if not anim_player.root_node.is_empty():
                base = anim_player.get_node_or_null(anim_player.root_node)
        if base == null:
                base = rig_root if rig_root != null else anim_player.get_parent()
        if base == null:
                return map
        var stack: Array[Node] = [base]
        while not stack.is_empty():
                var node: Node = stack.pop_back()
                for child in node.get_children():
                        stack.append(child)
                var key := _norm(node.name)
                if key.is_empty() or map.has(key):
                        continue
                map[key] = base.get_path_to(node)
        return map


## Rewrite every track so it points at the rig's real nodes. Tracks whose
## target matches nothing are kept — they simply bind to nothing.
func _remap_tracks(anim: Animation, node_map: Dictionary) -> void:
        for t in range(anim.get_track_count()):
                var path := anim.track_get_path(t)
                var sub := ""
                for s in range(path.get_subname_count()):
                        sub += ":" + path.get_subname(s)
                var node_part := String(path.get_concatenated_names())
                if node_part.is_empty():
                        continue
                var segments := node_part.split("/")
                var target := ""
                # walk from the leaf up so "Armature/Left Arm" still finds "left arm"
                for i in range(segments.size() - 1, -1, -1):
                        var key := _norm(segments[i])
                        if node_map.has(key):
                                target = String(node_map[key])
                                break
                if target.is_empty():
                        continue
                anim.track_set_path(t, NodePath(target + sub))


## Clip/node name normalizer — mirrors the site's rig rules:
## lowercase, "$tags" stripped, separators become spaces, digit-only tokens
## (Blender's "Plane.002"-style suffixes) dropped entirely.
func _norm(raw: String) -> String:
        var s := ""
        var i := 0
        while i < raw.length():
                var c := raw[i]
                if c == "$":
                        i += 1
                        while i < raw.length() and raw[i] != " " and raw[i] != "_" and raw[i] != "-" and raw[i] != ".":
                                i += 1
                        continue
                s += c
                i += 1
        s = s.to_lower().replace("_", " ").replace(".", " ").replace("-", " ").replace(":", " ").replace("/", " ")
        var keep: Array[String] = []
        for token in s.split(" ", false):
                var all_digits := true
                for ch in token:
                        if ch < "0" or ch > "9":
                                all_digits = false
                                break
                if not all_digits:
                        keep.append(token)
        return " ".join(keep)
