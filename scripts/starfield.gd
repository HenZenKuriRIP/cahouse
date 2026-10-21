extends Node2D
## Procedural 3-layer parallax starfield drawn in screen space.
const W := 270.0
const H := 480.0
var stars: Array = [] # [Vector2, layer]
var camera: Camera2D
var drift := Vector2.ZERO # used when there is no camera (title screen)
var drift_speed := Vector2(0, -30)
const FACTORS := [0.1, 0.3, 0.6]
const COLORS := [Color("#2a3558"), Color("#6b7aa8"), Color("#EAF4FF")]

func setup(cam: Camera2D, seed_value: int) -> void:
	camera = cam
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 160:
		stars.append([Vector2(rng.randf() * W, rng.randf() * H), mini(2, i % 7 / 3)])
	stars.append([Vector2(0, 0), 0])

func _process(d: float) -> void:
	drift += drift_speed * d
	queue_redraw()

func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color("#080C18"))
	var cp := camera.get_screen_center_position() if camera else drift
	for s in stars:
		var layer: int = s[1]
		var p: Vector2 = s[0] - cp * FACTORS[layer]
		p = Vector2(fposmod(p.x, W), fposmod(p.y, H)).floor()
		var sz := Vector2.ONE * (2 if layer == 2 and int(p.x) % 5 == 0 else 1)
		# tile the 270x480 star sheet across the (possibly expanded) viewport
		var tx := 0.0
		while tx < vs.x:
			var ty := 0.0
			while ty < vs.y:
				draw_rect(Rect2(p + Vector2(tx, ty), sz), COLORS[layer])
				ty += H
			tx += W
