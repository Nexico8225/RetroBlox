extends SceneTree
## Parse-check every .gd in the project — prints PARSE_OK or the errors.

func _init() -> void:
        var res := {"bad": 0, "total": 0}
        for d in ["res://scripts", "res://tests"]:
                _scan(d, res)
        if res["bad"] == 0:
                print("PARSE_OK (%d scripts)" % int(res["total"]))
        else:
                print("PARSE_FAIL (%d bad of %d)" % [int(res["bad"]), int(res["total"])])
        quit(1 if int(res["bad"]) > 0 else 0)


func _scan(path: String, res: Dictionary) -> void:
        var dir := DirAccess.open(path)
        if dir == null:
                return
        dir.list_dir_begin()
        var f := dir.get_next()
        while f != "":
                var full := path + "/" + f
                if dir.current_is_dir() and not f.begins_with("."):
                        _scan(full, res)
                elif f.ends_with(".gd"):
                        res["total"] = int(res["total"]) + 1
                        var s: Variant = load(full)
                        if s == null:
                                res["bad"] = int(res["bad"]) + 1
                                print("BAD: ", full)
                f = dir.get_next()
        dir.list_dir_end()
