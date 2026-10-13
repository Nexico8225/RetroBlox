extends Node
## UiConfig — YOUR CLIENT, YOUR RULES (v9.0 autoload "UiConfig").
## Everything the player edits in the UI Editor lives here and survives
## forever: element positions/scales/text, custom labels they add, their
## own profile-picture URL, the global UI scale. Saved to
## user://ui_config.json (IndexedDB on the web — it persists per site).
##
## The Editor writes; the game reads. Nothing else touches this file.

signal changed

const SAVE_PATH := "user://ui_config.json"

# ---- the data ------------------------------------------------------------
var ui_scale := 1.0               # global HUD/menu scale (0.6 .. 1.6)
var elements: Dictionary = {}     # id -> {"dx": float, "dy": float, "scale": float, "text": String}
var labels: Array = []            # [{id, text, x, y, size, color}] — the details THEY add


func _ready() -> void:
        load_config()


# ---------------------------------------------------------------- disk

func load_config() -> void:
        if not FileAccess.file_exists(SAVE_PATH):
                return
        var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
        if f == null:
                return
        var parsed: Variant = JSON.parse_string(f.get_as_text())
        if typeof(parsed) != TYPE_DICTIONARY:
                return
        var d: Dictionary = parsed
        ui_scale = clampf(float(d.get("ui_scale", 1.0)), 0.6, 1.6)
        var el: Variant = d.get("elements", {})
        if typeof(el) == TYPE_DICTIONARY:
                elements = el
        var lb: Variant = d.get("labels", [])
        if typeof(lb) == TYPE_ARRAY:
                labels = lb


func save_config() -> void:
        var d := {
                "ui_scale": ui_scale,
                "elements": elements,
                "labels": labels,
                "saved_at": int(Time.get_unix_time_from_system()),
        }
        var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
        if f != null:
                f.store_string(JSON.stringify(d))
                f.close()
        changed.emit()


# ---------------------------------------------------------------- element edits

func has_edit(id: String) -> bool:
        return elements.has(id)


func edit_for(id: String) -> Dictionary:
        return elements.get(id, {}) if typeof(elements.get(id, {})) == TYPE_DICTIONARY else {}


func set_edit(id: String, key: String, value: Variant) -> void:
        var e: Dictionary = edit_for(id)
        e[key] = value
        elements[id] = e
        save_config()


func clear_edit(id: String) -> void:
        elements.erase(id)
        save_config()


func clear_all() -> void:
        elements.clear()
        labels.clear()
        ui_scale = 1.0
        save_config()


# ---------------------------------------------------------------- custom labels

func add_label(text: String, pos: Vector2, size: int, color: String) -> String:
        var id := "label_%d" % (int(Time.get_unix_time_from_system() * 1000) % 100000000)
        labels.append({
                "id": id, "text": text,
                "x": pos.x, "y": pos.y,
                "size": size, "color": color,
        })
        save_config()
        return id


func update_label(id: String, key: String, value: Variant) -> void:
        for i in range(labels.size()):
                if String(labels[i].get("id", "")) == id:
                        labels[i][key] = value
                        save_config()
                        return


func remove_label(id: String) -> void:
        for i in range(labels.size()):
                if String(labels[i].get("id", "")) == id:
                        labels.remove_at(i)
                        save_config()
                        return
