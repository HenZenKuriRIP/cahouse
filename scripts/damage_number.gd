extends Node2D
## Floating pixel damage number (visual only).
var text := ""
var life := 0.6
var color := Color.WHITE

func _process(delta: float) -> void:
	life -= delta
	position.y -= 20.0 * delta
	modulate.a = clampf(life / 0.3, 0.0, 1.0)
	if life <= 0.0:
		queue_free()

func _draw() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(-6, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)
