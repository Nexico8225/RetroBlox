# [fire]burning gradient[/fire] — embers climb the letters, heat flicker on top.
class_name FxFire
extends RichTextEffect

var bbcode = "fire"

const CORE := Color("ffdd55")
const MID := Color("ff9500")
const TIP := Color("e2231a")


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	# vertical position inside the line drives the gradient (hot at the bottom)
	var heat := clampf(1.0 - char_fx.offset.y / 16.0, 0.0, 1.0)
	var flicker := 0.5 + 0.5 * sin(char_fx.elapsed_time * 9.66 + float(char_fx.absolute_index) * 0.4)
	var c: Color
	if heat > 0.5:
		c = MID.lerp(CORE, (heat - 0.5) * 2.0)
	else:
		c = TIP.lerp(MID, heat * 2.0)
	char_fx.color = c.lerp(Color.WHITE, flicker * 0.18)
	return true
