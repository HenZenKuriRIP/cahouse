extends Node2D
## Gravity well field from Gravity Bomb. Pulls enemies (and pickups); may become an ION VORTEX (synergy).
const PixelLib = preload("res://scripts/pixel.gd")
var battle: Node
var radius := 80.0
var life := 3.0
var max_life := 3.0
var pull := 250.0
var dps := 4.0
var ion := false
var ion_dps := 0.0
var _t := 0.0
var _arc_rng := RandomNumberGenerator.new()

func setup(b: Node, pos: Vector2, d: Dictionary) -> void:
	battle = b
	global_position = pos
	radius = float(d.get("well_radius", 80))
	life = float(d.get("well_duration", 3))
	max_life = life
	pull = float(d.get("well_pull", 250))
	dps = float(d.get("well_dps", 4))
	_arc_rng.seed = int(pos.x * 31 + pos.y)

func make_ion(extra_dps: float, extend: float) -> void:
	if ion:
		return
	ion = true
	ion_dps = extra_dps
	life += extend

func contains(p: Vector2) -> bool:
	return global_position.distance_to(p) <= radius

func _process(delta: float) -> void:
	_t += delta
	life -= delta
	for e in battle.enemies:
		if not e.alive:
			continue
		var off: Vector2 = global_position - e.global_position
		var d := off.length()
		if d < radius:
			e.in_well_timer = 0.2
			var strength := pull * (1.0 - d / radius * 0.6)
			e.velocity += off.normalized() * strength * delta
			e.take_damage((dps + ion_dps) * delta, false, "ion_vortex" if ion else "gravity", true)
			if ion:
				e.stun_timer = maxf(e.stun_timer, 0.15)
	if life <= 0.0:
		battle.spawn_explosion(global_position, PixelLib.C_VIOLET, 18)
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var col := PixelLib.C_CYAN if ion else PixelLib.C_VIOLET
	var k := clampf(life / max_life, 0.0, 1.0)
	for i in 3:
		var r := fmod(radius - _t * 60.0 - i * radius / 3.0, radius)
		if r < 0:
			r += radius
		draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color(col, 0.25 + 0.3 * k), 1.0)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(col, 0.5), 1.0)
	draw_rect(Rect2(-3, -3, 6, 6), PixelLib.C_BG)
	draw_rect(Rect2(-2, -2, 4, 4), col)
	if ion:
		for i in 4:
			var a := _arc_rng.randf() * TAU
			var p1 := Vector2.from_angle(a) * _arc_rng.randf_range(5, radius)
			var p2 := p1 + Vector2.from_angle(a + 1.6) * 10.0
			draw_line(p1.floor(), p2.floor(), PixelLib.C_WHITE, 1.0)
