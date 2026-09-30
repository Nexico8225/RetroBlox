# [neon]flickering neon tube[/neon] — cyan with a faulty starter, like the web.
class_name FxNeon
extends RichTextEffect

var bbcode = "neon"

const TUBE := Color("6afff2")


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := fmod(char_fx.elapsed_time, 2.6)
	var on := true
	# the flicker windows from the web keyframes (20%,24%,55%)
	for w in [[0.20, 0.22], [0.24, 0.25], [0.55, 0.57]]:
		if t / 2.6 >= w[0] and t / 2.6 <= w[1]:
			on = false
			break
	if on:
		char_fx.color = TUBE
	else:
		char_fx.color = Color(TUBE.r, TUBE.g, TUBE.b, 0.5 * char_fx.color.a)
	return true
