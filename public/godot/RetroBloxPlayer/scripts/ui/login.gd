extends Control
## Login — THE OLD LOGIN PAGE, BACK FOR REAL: it IS the retro-blox.vercel.app
## sign-in, rebuilt 1:1 inside the player. The same roller-coaster key art,
## the same chunky sprite-letter RETROBLOX wordmark, the same white card with
## the blue frame, the same labels, wells and the big RED Log In key.
## The site is the truth — the game's front door now looks exactly like it.
##
## LOG IN ONLY: the account-creation form is GONE (you asked). An
## account is made on the website, once — the player just signs you in.
## The FIRST login saves a session token on disk; every boot after that
## auto-signs in with zero typing. The server is LOCKED to the official
## RetroBlox platform — a label, not a field.
##
## The server now answers with the site's SPECIFIC errors ("No account named
## X exists here yet" vs "Wrong password for X"), so a wrong password can
## never again read as a mystery.

const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VERSION := "12.2"

## the site's own login palette (AuthPages.tsx, color for color)
const SKY := Color("63b3ec")              # the key-art fallback sky
const CARD_TOP := Color("ffffff")         # card gradient face
const CARD_BOTTOM := Color("f2f7fb")
const CARD_FRAME := Color("1e78c8")       # the 3px blue frame
const INK_HEAD := Color("1c3a52")         # "Login and start having fun"
const LABEL_INK := Color("43505c")        # the uppercase field labels
const WELL_EDGE := Color("b9c6d0")        # the well border
const INK := Color("1c2733")              # typed ink
const RED_TOP := Color("f0392f")          # the Log In key gradient
const RED_MID := Color("d21f16")
const RED_BOT := Color("b81b13")
const WORD_SHADOW := Color("a8231c")      # the wordmark's hard drop shadow

const LETTERS := "RETROBLOX"
const WORD_H := 54.0                      # sprite letter height

var _user: LineEdit
var _pass: LineEdit
var _err: PanelContainer
var _err_label: Label
var _info: Label
var _go: Button
var _offline: Button
var _working := false
var _wm_root: Control                     # the bobbing wordmark
var _wm_base_y := 0.0
var _bob_t := 0.0


func _ready() -> void:
        theme = RetroUI.shared
        RetroUI.apply_cursors()
        _build()
        _try_auto_login()


func _process(delta: float) -> void:
        # the wordmark's gentle bob — the site's rb-auth-bob keyframe
        if _wm_root != null and is_instance_valid(_wm_root):
                _bob_t += delta
                _wm_root.position.y = _wm_base_y + sin(_bob_t * 2.2) * 3.5


func _build() -> void:
        # ---- the stage: the site's roller-coaster key art, full-bleed ----
        var bg := ColorRect.new()
        bg.color = SKY
        bg.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(bg)
        var tex := RetroUI.login_backdrop()
        if tex != null:
                var photo := TextureRect.new()
                photo.texture = tex
                photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
                photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
                photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
                photo.set_anchors_preset(Control.PRESET_FULL_RECT)
                bg.add_child(photo)

        # ---- the column: wordmark on top, the white card under it ----
        var center := CenterContainer.new()
        center.set_anchors_preset(Control.PRESET_FULL_RECT)
        add_child(center)
        var col := VBoxContainer.new()
        col.alignment = BoxContainer.ALIGNMENT_CENTER
        col.add_theme_constant_override("separation", 10)
        center.add_child(col)

        # ---- THE WORDMARK — the site's chunky sprite letters, shadowed ----
        var word := _wordmark_block()
        if word != null:
                col.add_child(word)

        var gap := Control.new()
        gap.custom_minimum_size = Vector2(0, 14)
        gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
        col.add_child(gap)

        # ---- THE CARD — the site's white sheet with the BLUE frame ----
        var card := PanelContainer.new()
        card.custom_minimum_size = Vector2(400, 0)
        card.add_theme_stylebox_override("panel", _card_style())
        col.add_child(card)

        var body := VBoxContainer.new()
        body.add_theme_constant_override("separation", 13)
        card.add_child(body)

        var h1 := Label.new()
        h1.text = "Login and start having fun"
        h1.add_theme_font_override("font", RetroUI.gotham(800))
        h1.add_theme_font_size_override("font_size", 19)
        h1.add_theme_color_override("font_color", INK_HEAD)
        body.add_child(h1)

        # ---- USERNAME — the site's uppercase label + white well ----
        body.add_child(_field_label("USERNAME"))
        _user = LineEdit.new()
        _user.placeholder_text = "e.g. Nexico8225"
        _user.text = Api.saved_username   # remembered from last time
        _user.max_length = 20
        _user.custom_minimum_size = Vector2(0, 40)
        _style_well(_user)
        body.add_child(_user)

        # ---- PASSWORD ----
        body.add_child(_field_label("PASSWORD"))
        _pass = LineEdit.new()
        _pass.placeholder_text = "Password"
        _pass.secret = true
        _pass.custom_minimum_size = Vector2(0, 40)
        _style_well(_pass)
        body.add_child(_pass)

        # ---- THE ERROR BANNER — the site's AuthError, inside the card ----
        _err = PanelContainer.new()
        _err.add_theme_stylebox_override("panel", _error_style())
        _err.visible = false
        body.add_child(_err)
        _err_label = Label.new()
        _err_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _err_label.add_theme_font_override("font", RetroUI.gotham(600))
        _err_label.add_theme_font_size_override("font_size", 12)
        _err_label.add_theme_color_override("font_color", Color("ffd9d6"))
        _err.add_child(_err_label)

        # ---- THE RED LOG IN KEY — the site's exact gradient ----
        _go = Button.new()
        _go.text = "Log In"
        _go.custom_minimum_size = Vector2(0, 46)
        _go.focus_mode = Control.FOCUS_NONE
        _go.add_theme_stylebox_override("normal", _red_key())
        var red_hover := _red_key()
        red_hover.modulate_color = Color(1.06, 1.06, 1.06)
        _go.add_theme_stylebox_override("hover", red_hover)
        _go.add_theme_stylebox_override("pressed", _red_key())
        _go.add_theme_stylebox_override("hover_pressed", _red_key())
        _go.add_theme_font_override("font", RetroUI.gotham(700))
        _go.add_theme_font_size_override("font_size", 15)
        _go.add_theme_color_override("font_color", Color.WHITE)
        _go.add_theme_color_override("font_hover_color", Color.WHITE)
        _go.add_theme_color_override("font_pressed_color", Color.WHITE)
        _go.pressed.connect(_on_action)
        body.add_child(_go)

        # ---- quiet helper lines + the offline escape hatch ----
        _info = Label.new()
        _info.text = ""
        _info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _info.add_theme_font_override("font", RetroUI.gotham(400))
        _info.add_theme_font_size_override("font_size", 12)
        _info.add_theme_color_override("font_color", Color("5a6b7b"))
        body.add_child(_info)

        _offline = Button.new()
        _offline.text = "Can't connect — play offline instead"
        _offline.theme_type_variation = "BtnGhost"
        _offline.custom_minimum_size = Vector2(0, 30)
        _offline.visible = false
        _offline.pressed.connect(_on_offline)
        body.add_child(_offline)

        var footer := Label.new()
        footer.text = "Accounts live on retro-blox.vercel.app  ·  your avatar loads from your account"
        footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        footer.add_theme_font_override("font", RetroUI.gotham(400))
        footer.add_theme_font_size_override("font_size", 11)
        footer.add_theme_color_override("font_color", INK_HEAD)
        body.add_child(footer)

        # ---- under everything: the copyright line ----
        var legal := Label.new()
        legal.text = "RetroBlox Player v%s  ·  ©2006-2013 RetroBlox — not affiliated with Roblox" % VERSION
        legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        legal.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
        legal.grow_vertical = Control.GROW_DIRECTION_BEGIN
        legal.offset_top = -30.0
        legal.offset_bottom = -14.0
        legal.offset_left = -420.0
        legal.offset_right = 420.0
        legal.add_theme_font_override("font", RetroUI.gotham(400))
        legal.add_theme_font_size_override("font_size", 11)
        legal.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
        add_child(legal)

        _user.text_submitted.connect(func(_t: String) -> void: _pass.grab_focus())
        _pass.text_submitted.connect(func(_t: String) -> void: _on_action())


## The wordmark block: the site's sprite-letter RETROBLOX (the font-sheet
## PNGs the website itself uses), rotated -2deg, with the hard #a8231c
## drop-shadow copy and the soft white halo, bobbing on a sine.
func _wordmark_block() -> Control:
        var pair := _wordmark_textures()
        if pair.is_empty():
                return null
        var main: Texture2D = pair[0]
        var shadow: Texture2D = pair[1]
        var w := main.get_width()
        var h := main.get_height()

        var root := Control.new()
        root.custom_minimum_size = Vector2(w + 60, h + 34)
        root.mouse_filter = Control.MOUSE_FILTER_IGNORE

        # the soft white halo (the site's radial glow behind the letters)
        var halo := TextureRect.new()
        halo.texture = _halo_texture()
        halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        halo.stretch_mode = TextureRect.STRETCH_SCALE
        halo.size = Vector2(w + 150, h + 110)
        halo.position = Vector2((w + 60) / 2.0 - halo.size.x / 2.0,
                (h + 34) / 2.0 - halo.size.y / 2.0)
        halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(halo)

        # the shadow copy — the silhouette recolored, hard 5px offset
        var sh := TextureRect.new()
        sh.texture = shadow
        sh.position = Vector2(30, 17 + 5)
        sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(sh)

        # the letters themselves
        var face := TextureRect.new()
        face.texture = main
        face.position = Vector2(30, 17)
        face.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(face)

        root.rotation = deg_to_rad(-2.0)
        root.pivot_offset = root.custom_minimum_size / 2.0
        _wm_root = root
        _wm_base_y = 0.0
        return root


## Composite the sprite letters into one texture (+ the shadow silhouette).
func _wordmark_textures() -> Array:
        var h := int(WORD_H)
        var step := int(WORD_H * 0.07)
        var loaded: Array[Image] = []
        var total := 0
        for i in range(LETTERS.length()):
                var path := "res://assets/ui/font/%s.png" % LETTERS[i]
                if not ResourceLoader.exists(path):
                        continue
                var tex: Texture2D = load(path)
                if tex == null:
                        continue
                var img := tex.get_image()
                if img == null or img.is_empty():
                        continue
                if img.is_compressed():
                        img.decompress()
                var w := int(round(float(h) * float(img.get_width()) / float(img.get_height())))
                img.resize(w, h, Image.INTERPOLATE_LANCZOS)
                loaded.append(img)
                total += w + step
        if loaded.is_empty():
                return []
        total -= step
        var comp := Image.create_empty(total, h, false, Image.FORMAT_RGBA8)
        var x := 0
        for img in loaded:
                comp.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(x, 0))
                x += img.get_width() + step
        # the shadow silhouette — same alpha, flat shadow color
        var sh := Image.create_empty(total, h, false, Image.FORMAT_RGBA8)
        for y in range(h):
                for xx in range(total):
                        var px := comp.get_pixel(xx, y)
                        if px.a > 0.02:
                                sh.set_pixel(xx, y, Color(WORD_SHADOW.r, WORD_SHADOW.g, WORD_SHADOW.b, px.a))
        return [ImageTexture.create_from_image(comp), ImageTexture.create_from_image(sh)]


## The soft white radial halo behind the wordmark (the site's blurred glow).
func _halo_texture() -> ImageTexture:
        var s := 128
        var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
        var c := Vector2(s / 2.0, s / 2.0)
        for y in range(s):
                for x in range(s):
                        var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c) / (s / 2.0)
                        var a := clampf(1.0 - d, 0.0, 1.0)
                        img.set_pixel(x, y, Color(1, 1, 1, a * a * 0.55))
        return ImageTexture.create_from_image(img)


## The card: white sheet, 3px blue frame, rounded 12, one deep shadow —
## the site's exact `border: 3px solid #1e78c8` read.
func _card_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = CARD_TOP
        sb.set_corner_radius_all(12)
        sb.anti_aliasing = true
        sb.set_border_width_all(3)
        sb.border_color = CARD_FRAME
        sb.shadow_color = Color(0.06, 0.2, 0.34, 0.4)
        sb.shadow_size = 24
        sb.shadow_offset = Vector2(0, 10)
        sb.content_margin_left = 30.0
        sb.content_margin_right = 30.0
        sb.content_margin_top = 24.0
        sb.content_margin_bottom = 26.0
        return sb


## The site's field label: tiny, uppercase, bold, quiet steel ink.
func _field_label(txt: String) -> Label:
        var l := Label.new()
        l.text = txt
        l.add_theme_font_override("font", RetroUI.gotham(700))
        l.add_theme_font_size_override("font_size", 11)
        l.add_theme_color_override("font_color", LABEL_INK)
        return l


## The white wells: white face, gray 2px border, ink caret, blue focus ring —
## the site's INPUT style to the pixel.
func _style_well(w: LineEdit) -> void:
        var normal := StyleBoxFlat.new()
        normal.bg_color = Color.WHITE
        normal.set_corner_radius_all(8)
        normal.set_border_width_all(2)
        normal.border_color = WELL_EDGE
        normal.content_margin_left = 12.0
        normal.content_margin_right = 12.0
        normal.content_margin_top = 8.0
        normal.content_margin_bottom = 8.0
        var focus := normal.duplicate() as StyleBoxFlat
        focus.border_color = CARD_FRAME
        focus.set_border_width_all(2)
        w.add_theme_stylebox_override("normal", normal)
        w.add_theme_stylebox_override("focus", focus)
        w.add_theme_color_override("font_color", INK)
        w.add_theme_color_override("font_placeholder_color", Color(LABEL_INK, 0.6))
        w.add_theme_color_override("caret_color", CARD_FRAME)
        w.add_theme_color_override("selection_color", Color(CARD_FRAME, 0.25))
        if RetroUI.gotham(400) != null:
                w.add_theme_font_override("font", RetroUI.gotham(400))
        w.add_theme_font_size_override("font_size", 14)


## The RED Log In key — the site's exact gradient (#f0392f → #b81b13).
func _red_key() -> StyleBoxTexture:
        return RetroUI.gloss(RED_TOP, RED_BOT, RED_BOT.darkened(0.3), 8)


## The error banner — the site's AuthError read, docked inside the card.
func _error_style() -> StyleBoxFlat:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color("2a0f0d")
        sb.set_corner_radius_all(8)
        sb.set_border_width_all(1)
        sb.border_color = Color("ff6259")
        sb.content_margin_left = 12.0
        sb.content_margin_right = 12.0
        sb.content_margin_top = 8.0
        sb.content_margin_bottom = 8.0
        return sb


func _show_error(text: String) -> void:
        _err_label.text = text
        _err.visible = text != ""


func _set_info(text: String) -> void:
        _info.text = text


## Auto sign-in on boot: the saved token (180-day server-side TTL) brings
## the whole account back. The token is ONLY wiped when the server itself
## says it is invalid (401) — a Wi-Fi hiccup never logs you out.
func _try_auto_login() -> void:
        if Api.token == "":
                return
        _working = true
        _set_info("Logging you in…")
        var me: Dictionary = await Api.get_me()
        _working = false
        if me.get("ok", false):
                _finish_login(me)
                return
        if int(me.get("status", 0)) == 401:
                Api.clear_session()
                _set_info("Your session expired — log in one more time.")
        else:
                # offline: KEEP the token, offer offline play, retry works
                _offline.visible = true
                _set_info("Could not reach RetroBlox just now. Your saved session was kept — check your internet and press LOG IN to retry.")


func _on_action() -> void:
        if _working:
                return
        var uname := _user.text.strip_edges()
        var pwd := _pass.text
        if uname == "" or pwd == "":
                _show_error("Write your username and password first!")
                return
        _working = true
        _go.disabled = true
        _offline.visible = false
        _show_error("")
        _set_info("Talking to RetroBlox…")
        var res: Dictionary = await Api.login(uname, pwd)
        _working = false
        _go.disabled = false
        if not res.get("ok", false):
                # the server's OWN words — "No account named X exists here
                # yet" vs "Wrong password for X" — land here verbatim
                _show_error(String(res.get("error", "Could not reach RetroBlox.")))
                _set_info("")
                # network dead? show the offline hatch (401-style answers keep it hidden)
                if not res.has("status"):
                        _offline.visible = true
                return
        Api.token = String(res.get("token", ""))
        Api.save_session(uname)   # log in once — remembered from now on
        _set_info("Welcome back, %s…" % uname)
        var me: Dictionary = await Api.get_me()
        if me.get("ok", false):
                _finish_login(me)
        else:
                _show_error("Signed in, but the avatar fetch failed — try again.")


func _finish_login(me: Dictionary) -> void:
        # Api.txt everywhere: role can arrive as JSON null, and String(null)
        # hard-crashes with "Invalid call 'String' constructor"
        Session.sign_in(me, Api.txt(me.get("userId", "")), Api.txt(me.get("username", ""), "Player"),
                Api.txt(me.get("role", ""), "user"))
        # sign in and you are instantly playing the classic baseplate
        get_tree().change_scene_to_file("res://scenes/game.tscn")


## Last resort when the platform is unreachable: classic noob, offline chat.
func _on_offline() -> void:
        if _working:
                return
        Session.set_guest()
        get_tree().change_scene_to_file("res://scenes/game.tscn")
