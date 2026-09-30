# [flip]upside down flip[/flip] — mirrors the web's fx-flip: each chunk does a
# full 180-degree turn about the baseline, pauses, then comes back around.
class_name FxFlip
extends RichTextEffect

var bbcode = "flip"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := char_fx.elapsed_time * 2.856  # 2.2s cycle
	var cycle := fmod(t, TAU) / TAU  # 0..1
	# flip window mirrors the CSS keyframes: rest -> spin -> rest
	var sy := 1.0
	if cycle > 0.55 and cycle < 0.95:
		var spin := sin((cycle - 0.55) / 0.4 * PI)  # 0 -> 1 -> 0
		sy = 1.0 - 2.0 * spin  # 1 -> -1 -> 1 (a full turn through squash)
	char_fx.transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.0, sy), Vector2())
	# flipping about the baseline pushes glyphs below it — pull them back up
	if sy < 0.0:
		char_fx.offset.y -= 15.0
	return true
