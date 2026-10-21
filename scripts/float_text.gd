extends Node2D
## Floating world-space text. Styles: "normal" (white, small rise), "crit" (energy, pop + bounce),
## "synergy" (rare/accent label), "alert" (danger). Pixel outline for legibility.
const K = preload("res://scripts/ui/ui_kit.gd")
var text := ""
var life := 0.6
var max_life := 0.6
var color := Color.WHITE
var style := "normal"
var size := 12
var _age := 0.0

func _process(delta: float) -> void:
	life -= delta
	_age += delta
	var rise := 22.0 if style == "normal" else 14.0
	position.y -= rise * delta * (1.0 - clampf(_age / max_life, 0.0, 0.8))
	modulate.a = clampf(life / (max_life * 0.4), 0.0, 1.0)
	if life <= 0.0:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var w := K.text_width(text, size)
	var pop := 0.0
	if style == "crit":
		pop = -floorf(3.0 * (1.0 - K.ease_out_back(_age / 0.18)))
	var pos := Vector2(-w / 2.0, pop).floor()
	if style == "synergy" or style == "alert":
		var r := Rect2(pos + Vector2(-5, -11), Vector2(w + 10, 15))
		K.chamfer_fill(self, r, 2, Color(K.BG, 0.8))
		K.chamfer_line(self, r, 2, Color(color, 0.8))
	K.text_outline(self, pos, text, color, Color(K.BG, 0.9), size)
