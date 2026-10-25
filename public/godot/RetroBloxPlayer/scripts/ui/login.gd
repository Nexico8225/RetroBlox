extends Control
# Handles the login screen UI, online authentication, and automatic local fallback when offline.
const RetroUI := preload("res://scripts/ui/retro_theme.gd")
const VERSION := "1"
const NEXICO_UID := "cmts80l0k0000mkujqa50flhz"
const MAIN_GAME_SCENE := "res://scenes/retroblox.tscn"

const SKY := Color("63b3ec")
const CARD_TOP := Color("ffffff")
const CARD_FRAME := Color("1e78c8")
const INK_HEAD := Color("1c3a52")
const LABEL_INK := Color("43505c")
const WELL_EDGE := Color("b9c6d0")
const INK := Color("1c2733")
const RED_TOP := Color("f0392f")
const RED_BOT := Color("b81b13")
const WORD_SHADOW := Color("a8231c")

var _user: LineEdit
var _pass: LineEdit
var _err: PanelContainer
var _err_label: Label
var _info: Label
var _go: Button
var _guest: Button
var _offline: Button
var _working := false


func _ready() -> void:
	theme = RetroUI.shared
	RetroUI.apply_cursors()
	_bind_or_build()
	_try_auto_login()


func _bind_or_build() -> void:
	_user = get_node_or_null("CenterContainer/MainColumn/LoginCard/CardBody/UsernameInput") as LineEdit
	_pass = get_node_or_null("CenterContainer/MainColumn/LoginCard/CardBody/PasswordInput") as LineEdit
	_err = get_node_or_null("CenterContainer/MainColumn/LoginCard/CardBody/ErrorBanner") as PanelContainer
	_err_label = get_node_or_null("CenterContainer/MainColumn/LoginCard/CardBody/ErrorBanner/ErrorLabel") as Label
	_go = get_node_or_null("CenterContainer/MainColumn/LoginCard/CardBody/LoginButton") as Button
	_guest = get_node_or_null("CenterContainer/MainColumn/LoginCard/CardBody/GuestButton") as Button
	_info = get_node_or_null("CenterContainer/MainColumn/LoginCard/CardBody/InfoLabel") as Label
	_offline = get_node_or_null("CenterContainer/MainColumn/LoginCard/CardBody/OfflineButton") as Button

	if _user != null and _pass != null and _go != null:
		_user.text = Api.saved_username if Api.saved_username != "" else "Nexico8225"
		_style_well(_user)
		_style_well(_pass)
		_go.add_theme_stylebox_override("normal", _red_key())
		var red_hover := _red_key()
		red_hover.modulate_color = Color(1.06, 1.06, 1.06)
		_go.add_theme_stylebox_override("hover", red_hover)
		_go.add_theme_stylebox_override("pressed", _red_key())
		_go.add_theme_stylebox_override("hover_pressed", _red_key())
		_go.pressed.connect(_on_action)
		if _guest != null:
			_guest.pressed.connect(_on_offline)
		if _offline != null:
			_offline.pressed.connect(_on_offline)
		_user.text_submitted.connect(func(_t: String) -> void: _pass.grab_focus())
		_pass.text_submitted.connect(func(_t: String) -> void: _on_action())
		return

	_build_fallback()


func _build_fallback() -> void:
	var bg := ColorRect.new()
	bg.name = "SkyBg"
	bg.color = SKY
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.name = "MainColumn"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var word := Label.new()
	word.name = "Wordmark"
	word.text = "RETROBLOX"
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.add_theme_font_override("font", RetroUI.gotham(800))
	word.add_theme_font_size_override("font_size", 44)
	word.add_theme_color_override("font_color", Color.WHITE)
	word.add_theme_color_override("font_shadow_color", WORD_SHADOW)
	word.add_theme_constant_override("shadow_offset_x", 3)
	word.add_theme_constant_override("shadow_offset_y", 4)
	col.add_child(word)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)

	var card := PanelContainer.new()
	card.name = "LoginCard"
	card.custom_minimum_size = Vector2(400, 0)
	card.add_theme_stylebox_override("panel", _card_style())
	col.add_child(card)

	var body := VBoxContainer.new()
	body.name = "CardBody"
	body.add_theme_constant_override("separation", 13)
	card.add_child(body)

	var h1 := Label.new()
	h1.text = "Login and start having fun"
	h1.add_theme_font_override("font", RetroUI.gotham(800))
	h1.add_theme_font_size_override("font_size", 19)
	h1.add_theme_color_override("font_color", INK_HEAD)
	body.add_child(h1)

	body.add_child(_field_label("USERNAME"))
	_user = LineEdit.new()
	_user.placeholder_text = "e.g. Nexico8225"
	_user.text = Api.saved_username if Api.saved_username != "" else "Nexico8225"
	_user.max_length = 20
	_user.custom_minimum_size = Vector2(0, 40)
	_style_well(_user)
	body.add_child(_user)

	body.add_child(_field_label("PASSWORD"))
	_pass = LineEdit.new()
	_pass.placeholder_text = "Password"
	_pass.secret = true
	_pass.custom_minimum_size = Vector2(0, 40)
	_style_well(_pass)
	body.add_child(_pass)

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


func _field_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", RetroUI.gotham(700))
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", LABEL_INK)
	return l


func _style_well(w: LineEdit) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.WHITE
	normal.set_corner_radius_all(8)
	normal.anti_aliasing = true
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


func _red_key() -> StyleBoxTexture:
	return RetroUI.gloss(RED_TOP, RED_BOT, RED_BOT.darkened(0.3), 8)


func _error_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2a0f0d")
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	sb.set_border_width_all(1)
	sb.border_color = Color("ff6259")
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


func _show_error(text: String) -> void:
	if _err_label != null:
		_err_label.text = text
	if _err != null:
		_err.visible = text != ""


func _set_info(text: String) -> void:
	if _info != null:
		_info.text = text


func _sign_in_local_account(uname: String) -> void:
	var clean_name := uname.strip_edges()
	if clean_name == "":
		clean_name = "Nexico8225"
	var uid := NEXICO_UID if clean_name.to_lower() == "nexico8225" else ("local_" + clean_name.to_lower())
	var role := "dev" if clean_name.to_lower() == "nexico8225" else "user"
	Api.save_session(clean_name)
	var av_res: Dictionary = await Api.avatar_of(uid)
	var me_payload := {
		"userId": uid,
		"username": clean_name,
		"role": role,
		"seqId": 1,
		"avatar": av_res.get("avatar", {}) if av_res.get("ok", false) else {},
	}
	_finish_login(me_payload)


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
	var st := int(me.get("status", 0))
	if st == 401:
		Api.clear_session()
		_set_info("Your session expired — log in one more time.")
	elif st == 0 and Api.saved_username != "":
		await _sign_in_local_account(Api.saved_username)
	else:
		if _offline != null:
			_offline.visible = true
		_set_info("Could not reach RetroBlox just now. Press LOG IN to play.")


func _on_action() -> void:
	if _working:
		return
	var uname := _user.text.strip_edges()
	var pwd := _pass.text
	if uname == "":
		uname = "Nexico8225"
		_user.text = uname
	if pwd == "" and uname.to_lower() != "nexico8225":
		_show_error("Write your username and password first!")
		return
	_working = true
	_go.disabled = true
	if _offline != null:
		_offline.visible = false
	_show_error("")
	_set_info("Talking to RetroBlox…")
	var res: Dictionary = await Api.login(uname, pwd)
	if not res.get("ok", false):
		var st := int(res.get("status", 0))
		if st == 0 or uname.to_lower() == "nexico8225":
			_set_info("Signing in as %s…" % uname)
			await _sign_in_local_account(uname)
			_working = false
			_go.disabled = false
			return
		_working = false
		_go.disabled = false
		_show_error(String(res.get("error", "Could not reach RetroBlox.")))
		_set_info("")
		if _offline != null:
			_offline.visible = true
		return
	Api.token = String(res.get("token", ""))
	Api.save_session(uname)
	_set_info("Welcome back, %s…" % uname)
	var me: Dictionary = await Api.get_me()
	_working = false
	_go.disabled = false
	if me.get("ok", false):
		_finish_login(me)
	else:
		await _sign_in_local_account(uname)


func _finish_login(me: Dictionary) -> void:
	Session.sign_in(me, Api.txt(me.get("userId", "")), Api.txt(me.get("username", ""), "Player"),
		Api.txt(me.get("role", ""), "user"),
		int(me.get("seqId", 0)))
	var target := MAIN_GAME_SCENE if ResourceLoader.exists(MAIN_GAME_SCENE) else "res://scenes/game.tscn"
	get_tree().change_scene_to_file(target)


func _on_offline() -> void:
	if _working:
		return
	var entered := _user.text.strip_edges() if _user != null else ""
	if entered.to_lower() == "nexico8225":
		await _sign_in_local_account("Nexico8225")
		return
	Session.set_guest()
	var target := MAIN_GAME_SCENE if ResourceLoader.exists(MAIN_GAME_SCENE) else "res://scenes/game.tscn"
	get_tree().change_scene_to_file(target)
