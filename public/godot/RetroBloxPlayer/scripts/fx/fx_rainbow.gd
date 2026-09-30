# [rainbow]animated rainbow[/rainbow] — a sliding spectrum through the letters.
class_name FxRainbow
extends RichTextEffect

var bbcode = "rainbow"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var hue := fmod(char_fx.elapsed_time * 0.33 + float(char_fx.absolute_index) * 0.055, 1.0)
	char_fx.color = Color.from_hsv(hue, 0.85, 1.0, char_fx.color.a)
	return true
