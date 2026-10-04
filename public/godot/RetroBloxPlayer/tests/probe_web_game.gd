extends SceneTree

## WEB GAME PROBE — the full multiplayer loop against a LOCAL dev server.
## Run: godot --headless --path . --script res://tests/probe_web_game.gd
## Requires: npm dev server on 127.0.0.1:3005 + scripts/dev_game_seed.ts seeded.
## (Local accounts only — production is never touched by this probe.)

const RetrobloxApiScript := preload("res://scripts/retroblox_api.gd")
const API_URL := "http://127.0.0.1:3000"

var _failures: int = 0


func check(cond: bool, label: String) -> void:
        if cond:
                print("  ok    " + label)
        else:
                _failures += 1
                printerr("  FAIL  " + label)


func _initialize() -> void:
        await process_frame
        print("== RetroBlox web game probe ==")

        # ---------- login + me ----------
        var api1 = RetrobloxApiScript.new(API_URL)
        var login: Dictionary = await api1.login("gameprobe1", "probe123")
        check(login.get("ok", false) and not String(login.get("token", "")).is_empty(), "probe1 login")
        var me: Dictionary = await api1.get_me()
        check(me.get("ok", false) and String(me.get("username", "")) == "gameprobe1", "probe1 /platform/me")
        check(me.get("avatar", {}) is Dictionary and not me.get("avatar", {}).is_empty(), "me carries the account avatar")

        # ---------- game list + map ----------
        var places: Dictionary = await api1.get_places()
        check(places.get("ok", false), "GET /api/game/places")
        var found_baseplate := false
        var player_count_at_start: int = -1
        for entry in places.get("places", []):
                var place: Dictionary = entry
                if String(place.get("slug", "")) == "baseplate":
                        found_baseplate = true
                        player_count_at_start = int(place.get("players", -1))
        check(found_baseplate, "places list has baseplate")
        check(player_count_at_start >= 0, "places list carries a live player count")

        var place_res: Dictionary = await api1.get_place("baseplate")
        check(place_res.get("ok", false), "GET /api/game/places/baseplate")
        var data: Dictionary = place_res.get("data", {}) if place_res.get("data", {}) is Dictionary else {}
        var parts: Array = data.get("parts", [])
        var spawns: Array = data.get("spawns", [])
        var ladders: Array = data.get("ladders", [])
        check(parts.size() == 19, "map data has the 19 baseplate parts (got %d)" % parts.size())
        check(spawns.size() == 4, "map data has the 4 spawn pads")
        check(ladders.size() == 1, "map data has the ladder truss")

        # ---------- build the world from the web data (the same nodes) ----------
        var arena := Node3D.new()
        arena.set_script(load("res://scripts/arena.gd"))
        root.add_child(arena)
        await process_frame
        await process_frame
        var err: String = arena.apply_map_data(data)
        check(err.is_empty(), "arena builds the web map (%s)" % err)
        var spawn: Vector3 = arena.spawn_point(0)
        check(absf(spawn.y - 1.15) < 0.05, "web-map spawn sits on a pad (y=%.2f)" % spawn.y)

        # ---------- presence: two players see each other ----------
        var tick1: Dictionary = await api1.post_state({"placeSlug": "baseplate", "x": 1.0, "y": 2.0, "z": 3.0, "yaw": 0.5, "state": "walk", "shiftlock": true})
        check(tick1.get("ok", false), "probe1 state tick (%s)" % String(tick1.get("error", "ok")))
        check((tick1.get("players", []) as Array).is_empty(), "probe1 sees nobody yet")

        var api2 = RetrobloxApiScript.new(API_URL)
        var login2: Dictionary = await api2.login("gameprobe2", "probe123")
        check(login2.get("ok", false), "probe2 login")
        var tick2: Dictionary = await api2.post_state({"placeSlug": "baseplate", "x": 7.0, "y": 8.0, "z": 9.0, "yaw": -1.0, "state": "idle", "shiftlock": false})
        var since2 := String(tick2.get("serverTime", ""))
        var others: Array = tick2.get("players", [])
        check(others.size() == 1, "probe2 sees exactly one player")
        if others.size() == 1:
                var other: Dictionary = others[0]
                check(String(other.get("username", "")) == "gameprobe1", "the other player is probe1")
                check(absf(float(other.get("x", 0.0)) - 1.0) < 0.01 and absf(float(other.get("y", 0.0)) - 2.0) < 0.01, "probe1 position synced through the website")
                check(String(other.get("state", "")) == "walk", "probe1 anim state synced")
                check(bool(other.get("shiftlock", false)), "probe1 shiftlock flag synced")

        var tick1b: Dictionary = await api1.post_state({"placeSlug": "baseplate", "x": 1.0, "y": 2.0, "z": 3.0, "yaw": 0.5, "state": "idle", "shiftlock": true})
        check((tick1b.get("players", []) as Array).size() == 1, "probe1 now sees probe2")

        # ---------- chat round trip ----------
        var sent: Dictionary = await api1.post_state({"placeSlug": "baseplate", "x": 1.0, "y": 2.0, "z": 3.0, "yaw": 0.5, "state": "idle", "shiftlock": true, "chat": "hello retroblox!"})
        check(sent.get("ok", false) and bool(sent.get("chatPosted", false)), "probe1 chat posted")
        var since := String(sent.get("serverTime", ""))
        var got: Dictionary = await api2.post_state({"placeSlug": "baseplate", "x": 7.0, "y": 8.0, "z": 9.0, "yaw": -1.0, "state": "idle", "shiftlock": false, "since": since2})
        var chat_rows: Array = got.get("chat", [])
        check(chat_rows.size() >= 1, "probe2 receives the chat message")
        var text_ok := false
        for row in chat_rows:
                var r: Dictionary = row
                if String(r.get("text", "")) == "hello retroblox!" and String(r.get("username", "")) == "gameprobe1":
                        text_ok = true
        check(text_ok, "chat text + author arrive intact")

        # rate limit: an immediate second chat from the SAME player is dropped
        var spam: Dictionary = await api1.post_state({"placeSlug": "baseplate", "x": 1.0, "y": 2.0, "z": 3.0, "yaw": 0.5, "state": "idle", "shiftlock": true, "chat": "spam!"})
        check(not bool(spam.get("chatPosted", true)), "chat rate limit drops the instant second message")

        # ---------- leave ----------
        var bye1: Dictionary = await api1.post_state({"placeSlug": "baseplate", "leave": true})
        var bye2: Dictionary = await api2.post_state({"placeSlug": "baseplate", "leave": true})
        check(bye1.get("ok", false) and bye2.get("ok", false), "both players leave cleanly")
        var places_after: Dictionary = await api1.get_places()
        var count_after: int = -1
        for entry in places_after.get("places", []):
                var place: Dictionary = entry
                if String(place.get("slug", "")) == "baseplate":
                        count_after = int(place.get("players", -1))
        check(count_after == 0, "player count back to 0 after leaving")

        # ---------- UGC placement math (the site-space mirror fix) ----------
        # site rig faces +Z, game rig faces -Z: R_y(PI) must map site-space
        # onto game-space (a hat placed slightly FRONT on the site lands
        # slightly -Z = the game's face side).
        var site_to_game := Basis(Vector3.UP, PI)
        var p_site := Vector3(0.0, 6.2, 0.1)
        var p_game := site_to_game * p_site
        check(absf(p_game.x) < 0.0001 and absf(p_game.y - 6.2) < 0.0001 and absf(p_game.z + 0.1) < 0.0001,
                "site->game mirror maps front to the face side (got %s)" % p_game)

        # three.js 'XYZ' Euler order — the site applies Rx*Ry*Rz; Godot's
        # rotation_degrees is YXZ, so the kit must build the basis manually.
        # Reference values computed with three.js r180 Matrix4.makeRotationFromEuler.
        var rx := deg_to_rad(30.0)
        var ry := deg_to_rad(45.0)
        var rz := deg_to_rad(60.0)
        var basis := Basis(Vector3.RIGHT, rx) * Basis(Vector3.UP, ry) * Basis(Vector3(0, 0, 1), rz)
        var want_cols := [
                Vector3(0.353553, 0.926777, 0.126826),
                Vector3(-0.612372, 0.126826, 0.780330),
                Vector3(0.707107, -0.353553, 0.612372),
        ]
        var cols_ok := true
        for i in range(3):
                var col := basis[i]
                print("    godot col%d: %.6f, %.6f, %.6f" % [i, col.x, col.y, col.z])
                if (col - want_cols[i]).length() > 0.0005:
                        cols_ok = false
        check(cols_ok, "placement rotation matches three.js XYZ Euler exactly")

        if _failures == 0:
                print("== ALL WEB GAME PROBES PASSED ==")
        else:
                printerr("== %d FAILURES ==" % _failures)
        quit(1 if _failures > 0 else 0)
