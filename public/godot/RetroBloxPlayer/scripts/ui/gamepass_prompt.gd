class_name GamePassPrompt
extends CanvasLayer
## 1:1 Roblox-style "Buy Item" GamePass Purchase Popup
## Matches the classic dark Roblox Buy Item modal and spends real Tix from retro-blox.vercel.app!
## Usage from any script:
##   if body is LocalPlayer:
##       GamePassPrompt.popup("VIP")

signal pass_purchased(pass_name: String, cost_tix: int)
signal pass_canceled(pass_name: String)

@export var gamepass_name: String = "VIP"
@export var title: String = "VIP"
@export_multiline var description: String = ""
@export var cost_tix: int = 75
@export var icon: Texture2D
@export var recipient_username: String = ""

static var _instance: GamePassPrompt = null

var _backdrop: ColorRect
var _modal: PanelContainer
var _header_lbl: Label
var _icon_rect: TextureRect
var _question_lbl: Label
var _desc_lbl: Label
var _cancel_btn: Button
var _buy_btn: Button
var _footer_lbl: Label
var _hex_icon_tex: Texture2D
var _default_vip_tex: Texture2D
var _busy: bool = false
var _last_open_msec: int = 0


static func popup(
	pass_file_or_name: String = "VIP",
	override_title: String = "",
	override_desc: String = "",
	override_cost: int = -1,
	override_icon: Texture2D = null,
	override_recipient: String = ""
) -> GamePassPrompt:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	if _instance == null or not is_instance_valid(_instance):
		_instance = GamePassPrompt.new()
		_instance.name = "GamePassPromptLayer"
		tree.root.add_child(_instance)
	_instance.open_pass(pass_file_or_name, override_title, override_desc, override_cost, override_icon, override_recipient)
	return _instance


func _ready() -> void:
	layer = 110
	_instance = self
	_hex_icon_tex = _build_currency_hex_icon()
	if ResourceLoader.exists("res://assets/icons/gamepasses/vip_pass.png"):
		_default_vip_tex = load("res://assets/icons/gamepasses/vip_pass.png") as Texture2D
	_build_ui()
	_backdrop.visible = false


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.45)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_child(center)

	_modal = PanelContainer.new()
	_modal.custom_minimum_size = Vector2(440, 296)
	var msb: StyleBoxFlat = StyleBoxFlat.new()
	msb.bg_color = Color(0.204, 0.212, 0.227, 0.98) # Exact Roblox #34363a modal dark grey
	msb.set_corner_radius_all(8)
	msb.set_border_width_all(1)
	msb.border_color = Color(0.32, 0.34, 0.37, 1.0)
	msb.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	msb.shadow_size = 16
	msb.content_margin_left = 22.0
	msb.content_margin_right = 22.0
	msb.content_margin_top = 16.0
	msb.content_margin_bottom = 16.0
	_modal.add_theme_stylebox_override("panel", msb)
	center.add_child(_modal)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_modal.add_child(col)

	# 1. Top "Buy Item" Header
	_header_lbl = Label.new()
	_header_lbl.text = "Buy Item"
	_header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_lbl.add_theme_color_override("font_color", Color.WHITE)
	_header_lbl.add_theme_font_size_override("font_size", 20)
	col.add_child(_header_lbl)

	# Thin horizontal divider line just like image_eac379.png
	var div: ColorRect = ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(0.33, 0.35, 0.38, 0.95)
	col.add_child(div)

	# 2. Center Icon
	var icon_center: CenterContainer = CenterContainer.new()
	icon_center.custom_minimum_size = Vector2(0, 82)
	col.add_child(icon_center)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(72, 72)
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.texture = _default_vip_tex
	icon_center.add_child(_icon_rect)

	# 3. Question Label ("Would you like to buy "VIP"?") + optional Description
	_question_lbl = Label.new()
	_question_lbl.text = "Would you like to buy \"VIP\"?"
	_question_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question_lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	_question_lbl.add_theme_font_size_override("font_size", 16)
	col.add_child(_question_lbl)

	_desc_lbl = Label.new()
	_desc_lbl.text = ""
	_desc_lbl.visible = false
	_desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.add_theme_color_override("font_color", Color(0.72, 0.75, 0.80))
	_desc_lbl.add_theme_font_size_override("font_size", 12)
	col.add_child(_desc_lbl)

	# 4. Cancel & Buy Buttons Row (matching image_eac379.png)
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	col.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.custom_minimum_size = Vector2(186, 40)
	_cancel_btn.focus_mode = Control.FOCUS_NONE
	var csb: StyleBoxFlat = StyleBoxFlat.new()
	csb.bg_color = Color(0.204, 0.212, 0.227, 1.0)
	csb.border_color = Color(0.68, 0.70, 0.74, 1.0)
	csb.set_border_width_all(1)
	csb.set_corner_radius_all(6)
	var chov: StyleBoxFlat = csb.duplicate() as StyleBoxFlat
	chov.bg_color = Color(0.26, 0.27, 0.29, 1.0)
	_cancel_btn.add_theme_stylebox_override("normal", csb)
	_cancel_btn.add_theme_stylebox_override("hover", chov)
	_cancel_btn.add_theme_stylebox_override("pressed", csb)
	_cancel_btn.add_theme_color_override("font_color", Color(0.88, 0.90, 0.93))
	_cancel_btn.add_theme_font_size_override("font_size", 16)
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	btn_row.add_child(_cancel_btn)

	_buy_btn = Button.new()
	_buy_btn.text = "  75"
	_buy_btn.icon = _hex_icon_tex
	_buy_btn.custom_minimum_size = Vector2(186, 40)
	_buy_btn.focus_mode = Control.FOCUS_NONE
	var bsb: StyleBoxFlat = StyleBoxFlat.new()
	bsb.bg_color = Color(0.98, 0.98, 0.99, 1.0)
	bsb.border_color = Color(0.98, 0.98, 0.99, 1.0)
	bsb.set_border_width_all(1)
	bsb.set_corner_radius_all(6)
	var bhov: StyleBoxFlat = bsb.duplicate() as StyleBoxFlat
	bhov.bg_color = Color(0.88, 0.90, 0.94, 1.0)
	_buy_btn.add_theme_stylebox_override("normal", bsb)
	_buy_btn.add_theme_stylebox_override("hover", bhov)
	_buy_btn.add_theme_stylebox_override("pressed", bsb)
	_buy_btn.add_theme_color_override("font_color", Color(0.14, 0.15, 0.17))
	_buy_btn.add_theme_color_override("font_hover_color", Color(0.08, 0.09, 0.10))
	_buy_btn.add_theme_color_override("font_pressed_color", Color(0.08, 0.09, 0.10))
	_buy_btn.add_theme_font_size_override("font_size", 16)
	_buy_btn.pressed.connect(_on_buy_pressed)
	btn_row.add_child(_buy_btn)

	# 5. Footer Note
	_footer_lbl = Label.new()
	_footer_lbl.text = "Your RetroBlox Tix account will be charged."
	_footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_lbl.add_theme_color_override("font_color", Color(0.75, 0.77, 0.80))
	_footer_lbl.add_theme_font_size_override("font_size", 12)
	col.add_child(_footer_lbl)


func open_pass(
	pass_file_or_name: String = "VIP",
	override_title: String = "",
	override_desc: String = "",
	override_cost: int = -1,
	override_icon: Texture2D = null,
	override_recipient: String = ""
) -> void:
	var now: int = Time.get_ticks_msec()
	if _backdrop.visible and (now - _last_open_msec) < 800:
		return
	_last_open_msec = now
	_busy = false

	gamepass_name = pass_file_or_name.strip_edges()
	if gamepass_name == "":
		gamepass_name = "VIP"

	# Load .tres from res://gamepasses/<name>.tres if it exists
	var clean_name: String = gamepass_name.replace(".tres", "")
	var candidates: Array[String] = [
		gamepass_name,
		"res://gamepasses/%s.tres" % clean_name,
		"res://gamepasses/%s.tres" % clean_name.to_lower(),
		"res://gamepasses/%s.tres" % clean_name.to_upper(),
	]
	var loaded_res: Resource = null
	for p in candidates:
		if p.begins_with("res://") and ResourceLoader.exists(p):
			loaded_res = load(p)
			break

	if loaded_res != null:
		title = String(loaded_res.get("title")) if loaded_res.get("title") != null else clean_name
		description = String(loaded_res.get("description")) if loaded_res.get("description") != null else ""
		cost_tix = int(loaded_res.get("cost_tix")) if loaded_res.get("cost_tix") != null else 75
		icon = loaded_res.get("icon") as Texture2D
		recipient_username = String(loaded_res.get("creator_username")) if loaded_res.get("creator_username") != null else ""
	else:
		title = clean_name
		description = ""
		cost_tix = 75
		icon = _default_vip_tex

	# Apply any public Inspector overrides passed by the caller
	if override_title.strip_edges() != "":
		title = override_title.strip_edges()
	if override_desc.strip_edges() != "":
		description = override_desc.strip_edges()
	if override_cost >= 0:
		cost_tix = override_cost
	if override_icon != null:
		icon = override_icon
	if override_recipient.strip_edges() != "":
		recipient_username = override_recipient.strip_edges()

	_icon_rect.texture = icon if icon != null else _default_vip_tex
	_question_lbl.text = "Would you like to buy \"%s\"?" % title
	_desc_lbl.text = description
	_desc_lbl.visible = (description.strip_edges() != "")
	_buy_btn.disabled = false
	_buy_btn.text = "  %d" % cost_tix

	# Release mouse capture so the player can click Cancel or Buy!
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_backdrop.visible = true
	_refresh_wallet_footer()


func _refresh_wallet_footer() -> void:
	if Api == null or String(Api.token) == "":
		_footer_lbl.text = "This is a test purchase. Sign in to spend real Tix."
		return
	_footer_lbl.text = "Checking your RetroBlox Tix balance..."
	var bal_res: Dictionary = await Api.get_tix_balance_info()
	if not _backdrop.visible:
		return
	if bool(bal_res.get("ok", false)):
		var bal: int = int(bal_res.get("balance", 0))
		_footer_lbl.text = "Your balance: %d Tix. Buying \"%s\" costs %d Tix." % [bal, title, cost_tix]
	else:
		_footer_lbl.text = "Your account will be charged %d Tix." % cost_tix


func _on_cancel_pressed() -> void:
	if _busy:
		return
	_backdrop.visible = false
	pass_canceled.emit(gamepass_name)


func _on_buy_pressed() -> void:
	if _busy:
		return
	_busy = true
	_buy_btn.disabled = true
	_footer_lbl.text = "Processing Tix purchase on RetroBlox..."

	if Api != null and String(Api.token) != "":
		var res: Dictionary = await Api.spend_tix(
			cost_tix,
			recipient_username,
			"Bought GamePass: %s" % title,
			String(Session.place_id) if Session != null else "default"
		)
		if not bool(res.get("ok", false)):
			_busy = false
			_buy_btn.disabled = false
			_footer_lbl.text = String(res.get("error", "Not enough Tix!"))
			return
		var bal_after: int = int(res.get("balanceAfter", 0))
		_footer_lbl.text = "Purchased \"%s\"! Remaining balance: %d Tix." % [title, bal_after]
	else:
		_footer_lbl.text = "Test purchase complete for \"%s\" (%d Tix)!" % [title, cost_tix]

	if Sfx != null and Sfx.has_method("play_click"):
		Sfx.play_click()

	pass_purchased.emit(gamepass_name, cost_tix)
	await get_tree().create_timer(0.85).timeout
	_busy = false
	_backdrop.visible = false


func _build_currency_hex_icon() -> Texture2D:
	var img: Image = Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark: Color = Color(0.14, 0.15, 0.17, 1.0)
	for y in range(2, 18):
		for x in range(2, 18):
			var d: float = Vector2(x - 9.5, y - 9.5).length()
			if d <= 7.8 and d >= 5.6:
				img.set_pixel(x, y, dark)
			elif absf(x - 9.5) <= 2.4 and absf(y - 9.5) <= 2.4:
				img.set_pixel(x, y, dark)
	return ImageTexture.create_from_image(img)
