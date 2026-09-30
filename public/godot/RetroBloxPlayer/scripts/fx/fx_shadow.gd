# [shadow]3D block shadow[/shadow] — mirrors the web's fx-shadow: the text
# lifts off the page on a hard diagonal, breathing like retro wordart.
class_name FxShadow
extends RichTextEffect

var bbcode = "shadow"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := char_fx.elapsed_time * 3.491  # 1.8s cycle
	var depth := 2.0 + sin(t) * 1.0  # 1..3 studs of extrusion
	char_fx.offset += Vector2(depth * 0.7, depth)
	return true
