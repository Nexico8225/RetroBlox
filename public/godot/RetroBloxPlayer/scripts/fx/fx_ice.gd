# [ice]frozen shimmer[/ice] — a cold shimmer sliding through the letters.
class_name FxIce
extends RichTextEffect

var bbcode = "ice"

const FROST := Color("dff6ff")
const MID := Color("8fd8ff")
const DEEP := Color("4fa8e0")


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var slide := fmod(char_fx.elapsed_time * 0.714 + float(char_fx.absolute_index) * 0.06, 1.0)
	var c: Color
	if slide < 0.4:
		c = FROST.lerp(MID, slide / 0.4)
	elif slide < 0.7:
		c = MID.lerp(DEEP, (slide - 0.4) / 0.3)
	else:
		c = DEEP.lerp(FROST, (slide - 0.7) / 0.3)
	char_fx.color = c
	return true
