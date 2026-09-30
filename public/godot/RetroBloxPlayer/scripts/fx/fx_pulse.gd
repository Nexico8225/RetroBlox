# [pulse]breathing size[/pulse] — mirrors the web's fx-pulse: the whole word
# spreads apart and squeezes together around its own center.
class_name FxPulse
extends RichTextEffect

var bbcode = "pulse"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := char_fx.elapsed_time * 5.98  # 1.05s cycle
	var spread := sin(t)  # -1..1
	# distance from the chunk center -> chars drift outward on the inhale
	var drift := (float(char_fx.relative_index) - 4.0) * spread * 0.22
	char_fx.offset.x += drift
	char_fx.offset.y -= maxf(0.0, spread) * 1.2
	return true
