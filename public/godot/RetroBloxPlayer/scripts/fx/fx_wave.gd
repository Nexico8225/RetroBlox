# [wave]letters ride a sine wave[/wave] — per-letter stagger like the web.
class_name FxWave
extends RichTextEffect

var bbcode = "wave"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
        var t := char_fx.elapsed_time * 4.18879  # 1.5s cycle
        var i := float(char_fx.relative_index) * 0.545  # -0.13s stagger (2pi/1.5s)
        char_fx.offset.y += sin(t + i) * 3.0  # -3..3 px ride
        return true
