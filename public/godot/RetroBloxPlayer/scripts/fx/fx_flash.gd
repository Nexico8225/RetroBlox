# [flash]blinks on and off[/flash] — mirrors the web's fx-flash: a sharp
# on/off blink like a broken sign (60% on, 40% off, 0.9s cycle).
class_name FxFlash
extends RichTextEffect

var bbcode = "flash"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := fmod(char_fx.elapsed_time, 0.9)
	char_fx.visible = t < 0.54
	return true
