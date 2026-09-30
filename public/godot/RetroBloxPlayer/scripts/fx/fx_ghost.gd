# [ghost]fades away and back[/ghost] — mirrors the web's fx-ghost.
class_name FxGhost
extends RichTextEffect

var bbcode = "ghost"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := char_fx.elapsed_time * 2.417  # 2.6s cycle
	var vis := 0.5 + 0.5 * sin(t)  # 0..1
	char_fx.color.a *= lerpf(0.15, 1.0, vis)
	return true
