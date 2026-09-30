# [spin]twirling letters[/spin] — mirrors the web's fx-spin: every letter
# twirls on its own axis, staggered down the line.
class_name FxSpin
extends RichTextEffect

var bbcode = "spin"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := char_fx.elapsed_time * 3.696  # 1.7s cycle
	var rot := t + float(char_fx.relative_index) * 0.68  # -0.11s stagger
	char_fx.transform = Transform2D(fmod(rot, TAU), Vector2())
	return true
