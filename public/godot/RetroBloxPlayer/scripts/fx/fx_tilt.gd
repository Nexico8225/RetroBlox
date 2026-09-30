# [tilt]tips side to side[/tilt] — mirrors the web's fx-tilt: each letter
# rocks about its baseline like a loose picture frame.
class_name FxTilt
extends RichTextEffect

var bbcode = "tilt"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := char_fx.elapsed_time * 3.927  # 1.6s cycle
	var rot := sin(t) * 0.105  # about +/- 6 degrees
	char_fx.transform = Transform2D(rot, Vector2())
	return true
