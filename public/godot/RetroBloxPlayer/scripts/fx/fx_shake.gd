# [shake]angry shaking[/shake] — mirrors the web's fx-shake keyframes.
class_name FxShake
extends RichTextEffect

var bbcode = "shake"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := char_fx.elapsed_time * 26.0
	var i := float(char_fx.absolute_index)
	char_fx.offset += Vector2(
		sin(t * 1.31 + i * 0.83) * 0.9 + sin(t * 2.7 + i) * 0.35,
		sin(t * 1.73 + i * 1.37) * 0.7
	)
	return true
