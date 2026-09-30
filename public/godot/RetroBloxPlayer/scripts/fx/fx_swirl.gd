# [swirl]spinning wobble[/swirl] — mirrors the web's fx-swirl ("Whirly").
class_name FxSwirl
extends RichTextEffect

var bbcode = "swirl"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var phase := sin(char_fx.elapsed_time * 4.487)  # 1.4s ease cycle
	var angle := phase * 7.0 * 0.01745
	char_fx.transform = Transform2D(angle, Vector2(0.0, -phase)) * char_fx.transform
	return true
