# [orbit]letters circle their spot[/orbit] — mirrors the web's fx-orbit:
# each letter runs a small circular orbit, staggered down the line.
class_name FxOrbit
extends RichTextEffect

var bbcode = "orbit"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := char_fx.elapsed_time * 2.992  # 2.1s cycle
	var ang := t + float(char_fx.relative_index) * 1.02  # -0.17s stagger
	char_fx.offset += Vector2(cos(ang) * 2.0, sin(ang) * 2.0)
	return true
