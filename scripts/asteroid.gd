extends Node2D
## Destructible asteroid. Blocks shots. Explosive ore: telegraphed fuse ring, then blast (chain reactions).
const PixelLib = preload("res://scripts/pixel.gd")
var field: Node
var radius := 10.0
var hp := 50.0
var max_hp := 50.0
var ore := false
var velocity := Vector2.ZERO
var fuse := -1.0
var chained := false
var alive := true
var is_meteor := false
var flash := 0.0
var shape: PackedVector2Array

func setup(f: Node, pos: Vector2, r: float, is_ore: bool, vel: Vector2, seed_value: int, hp_per_r: float) -> void:
	field = f
	global_position = pos
	radius = r
	ore = is_ore
	velocity = vel
	max_hp = r * hp_per_r
	hp = max_hp
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	shape = PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		shape.append((Vector2.from_angle(a) * r * rng.randf_range(0.75, 1.05)).floor())

func take_damage(amount: float, _src: Variant = null) -> void:
	if not alive:
		return
	hp -= amount
	flash = 0.06
	if ore and fuse < 0.0 and hp <= max_hp * 0.5:
		ignite(false)
	if hp <= 0.0:
		if ore and fuse < 0.0:
			ignite(false)
		elif not ore:
			field.destroy_asteroid(self)

func ignite(by_chain: bool) -> void:
	if fuse >= 0.0:
		return
	chained = by_chain
	fuse = float(field.cfg["ore_fuse"]) * (0.5 if by_chain else 1.0)

func _process(delta: float) -> void:
	if not alive:
		return
	global_position += velocity * delta
	flash = maxf(0.0, flash - delta)
	if fuse >= 0.0:
		fuse -= delta
		if fuse <= 0.0:
			field.explode_ore(self)
			return
	queue_redraw()

func _draw() -> void:
	var base := Color("#3b4566") if not ore else Color("#6b5a3a")
	if flash > 0.0:
		base = PixelLib.C_WHITE
	draw_colored_polygon(shape, base)
	draw_polyline(shape + PackedVector2Array([shape[0]]), base.lightened(0.3), 1.0)
	if ore:
		for i in 3:
			var p := (shape[i * 3] * 0.45).floor()
			draw_rect(Rect2(p, Vector2(2, 2)), PixelLib.C_GOLD)
	if fuse >= 0.0:
		# telegraph: blast radius ring + blinking core
		var br := float(field.cfg["ore_blast_radius"])
		var blink := int(fuse * 12.0) % 2 == 0
		draw_arc(Vector2.ZERO, br, 0, TAU, 32, Color(PixelLib.C_RED, 0.8 if blink else 0.35), 1.0)
		draw_rect(Rect2(-2, -2, 4, 4), PixelLib.C_RED if blink else PixelLib.C_GOLD)
