extends Node2D
## Floating world-space text (damage numbers, synergy names, module loss). Visual only.
var text := ""
var life := 0.6
var max_life := 0.6
var color := Color.WHITE
var size := 8

func _process(delta: float) -> void:
	life -= delta
	position.y -= 18.0 * delta
	modulate.a = clampf(life / (max_life * 0.5), 0.0, 1.0)
	if life <= 0.0:
		queue_free()

func _draw() -> void:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(ThemeDB.fallback_font, Vector2(-w / 2.0, 0).floor(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
