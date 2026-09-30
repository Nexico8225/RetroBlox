# [bounce]letters hop in sequence[/bounce] — per-letter stagger like the web.
class_name FxBounce
extends RichTextEffect

var bbcode = "bounce"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := fmod(char_fx.elapsed_time * (TAU / 1.1) + float(char_fx.relative_index) * 0.571, TAU)
	# 0..30% of the cycle: hop up; the rest: rest on the ground
	var phase := t / TAU
	if phase < 0.3:
		char_fx.offset.y -= sin(phase / 0.3 * PI) * 7.0
	return true
