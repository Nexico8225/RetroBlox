# [glow]warm pulsing halo[/glow] — the color pulses like the web's text-shadow.
class_name FxGlow
extends RichTextEffect

var bbcode = "glow"

const WARM := Color("ffb300")


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var pulse := 0.5 + 0.5 * sin(char_fx.elapsed_time * 3.927)  # 1.6s cycle
	char_fx.color = WARM.lerp(Color("ffe08a"), pulse)
	char_fx.color.a = char_fx.color.a
	return true
