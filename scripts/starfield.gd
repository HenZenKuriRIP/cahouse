extends Node2D
## Procedural 3-layer parallax starfield drawn in screen space.
const W := 480.0
const H := 270.0
var stars: Array = [] # [Vector2, layer]
var camera: Camera2D
const FACTORS := [0.1, 0.3, 0.6]
const COLORS := [Color("#2a3558"), Color("#6b7aa8"), Color("#EAF4FF")]

func setup(cam: Camera2D, seed_value: int) -> void:
	camera = cam
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 160:
		stars.append([Vector2(rng.randf() * W, rng.randf() * H), mini(2, i % 7 / 3)])
	stars.append([Vector2(0, 0), 0])

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("#080C18"))
	var cp := camera.get_screen_center_position() if camera else Vector2.ZERO
	for s in stars:
		var layer: int = s[1]
		var p: Vector2 = s[0] - cp * FACTORS[layer]
		p = Vector2(fposmod(p.x, W), fposmod(p.y, H)).floor()
		draw_rect(Rect2(p, Vector2.ONE * (2 if layer == 2 and int(p.x) % 5 == 0 else 1)), COLORS[layer])
