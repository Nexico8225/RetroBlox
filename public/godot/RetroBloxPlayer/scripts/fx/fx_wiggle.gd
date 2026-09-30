# [wiggle]nervous rotations[/wiggle] — mirrors the web's fx-wiggle.
class_name FxWiggle
extends RichTextEffect

var bbcode = "wiggle"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := fmod(char_fx.elapsed_time * 2.0, 2.0)
	if t > 1.0:
		t = 2.0 - t  # alternate, like the web's ease-in-out
	var angle := lerpf(-2.5, 2.5, t) * 0.01745
	char_fx.transform = Transform2D(angle, Vector2.ZERO) * char_fx.transform
	return true
