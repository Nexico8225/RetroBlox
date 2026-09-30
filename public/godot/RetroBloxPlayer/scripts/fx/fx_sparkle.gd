# [sparkle]golden twinkle[/sparkle] — mirrors the web's fx-sparkle:
# brightness pulses and the letters do a tiny star-like wiggle.
class_name FxSparkle
extends RichTextEffect

var bbcode = "sparkle"

const GOLD := Color("ffd54d")
const BRIGHT := Color("fff8dc")


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := char_fx.elapsed_time * 5.46  # 1.15s cycle
	var i := float(char_fx.absolute_index)
	var phase := 0.5 + 0.5 * sin(t + i * 1.31)
	char_fx.color = GOLD.lerp(BRIGHT, phase)
	# a two-step twinkle: nudge the letter up on each bright peak
	if phase > 0.75:
		char_fx.offset.y -= 1.6
	return true
