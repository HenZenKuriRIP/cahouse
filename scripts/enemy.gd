extends Node2D
const PixelLib = preload("res://scripts/pixel.gd")
## Data-driven enemy. Behaviour chosen by data["behavior"]: chase / strafe / bomber.
const MASKS := {
	"chase": ["..xx..", ".xwwx.", "xxwwxx", "xx..xx", "x....x"],
	"strafe": ["x......x", "xx.ww.xx", "xxxwwxxx", "xx.ww.xx", "x......x"],
	"bomber": ["..xxxxxx..", ".xxddddxx.", "xxdwwwwdxx", "xxdwwwwdxx", ".xxddddxx.", "..xxxxxx..", "..x....x.."],
}
var battle: Node
var type_id := ""
var data: Dictionary
var behavior := ""
var hp := 1.0
var radius := 6.0
var speed := 50.0
var accel := 100.0
var velocity := Vector2.ZERO
var alive := true
var flash := 0.0
var fire_timer := 0.0
var orbit_sign := 1.0
var rng := RandomNumberGenerator.new()
var shield := 0.0
var max_shield := 0.0
var emp_timer := 0.0
var stun_timer := 0.0
var in_well_timer := 0.0
var last_hit_source := ""
var mask: PackedStringArray
var palette: Dictionary

func setup(b: Node, t: String, d: Dictionary, pos: Vector2, seed_value: int) -> void:
	battle = b
	type_id = t
	data = d
	behavior = d["behavior"]
	hp = float(d["hp"])
	max_shield = float(d.get("shield", 0))
	shield = max_shield
	radius = float(d["radius"])
	speed = float(d["speed"])
	accel = float(d["accel"])
	global_position = pos
	rng.seed = seed_value
	orbit_sign = 1.0 if rng.randf() < 0.5 else -1.0
	fire_timer = rng.randf_range(0.5, float(d.get("fire_interval", 2.0)))
	mask = PackedStringArray(MASKS[behavior])
	var col := Color(d["color"])
	palette = {"x": col, "d": col.darkened(0.4), "w": PixelLib.C_WHITE}

func _process(delta: float) -> void:
	if not alive:
		return
	emp_timer = maxf(0.0, emp_timer - delta)
	in_well_timer = maxf(0.0, in_well_timer - delta)
	flash = maxf(0.0, flash - delta)
	var p: Node2D = battle.player
	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = velocity.move_toward(Vector2.ZERO, 120.0 * delta)
		global_position += velocity * delta
		queue_redraw()
		return
	var to_p: Vector2 = p.global_position - global_position
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var desired := Vector2.ZERO
	match behavior:
		"chase":
			desired = dir * speed
		"strafe":
			var od := float(data["orbit_distance"])
			var radial := dir * clampf((dist - od) / 40.0, -1.0, 1.0)
			desired = (radial + dir.orthogonal() * orbit_sign).normalized() * speed
		"bomber":
			var kd := float(data["keep_distance"])
			desired = dir * clampf((dist - kd) / 60.0, -1.0, 1.0) * speed + dir.orthogonal() * orbit_sign * speed * 0.4
	velocity = velocity.move_toward(desired, accel * (0.25 if in_well_timer > 0.0 else 1.0) * delta)
	global_position += velocity * delta
	rotation = dir.angle() if behavior != "strafe" else velocity.angle()
	if data.has("fire_interval") and p.alive:
		fire_timer -= delta
		if fire_timer <= 0.0 and dist < 260.0:
			fire_timer = float(data["fire_interval"])
			_fire(dir)
	if p.alive and dist < radius + p.radius:
		p.take_damage(float(data["contact_damage"]), global_position)
		take_damage(float(data["contact_damage"]), false)
	queue_redraw()

func _fire(dir: Vector2) -> void:
	var bs := float(data["bullet_speed"])
	var dmg := float(data["bullet_damage"])
	var col := Color(data["color"])
	if behavior == "bomber":
		var n := int(data.get("burst", 5))
		for i in n:
			var a := (float(i) - (n - 1) / 2.0) * 0.22
			battle.spawn_projectile(global_position, dir.rotated(a) * bs, dmg, 2.5, 1, col, false)
	else:
		battle.spawn_projectile(global_position, dir * bs, dmg, 2.0, 1, col, false)
	AudioManager.play("enemy_shoot")

func take_damage(amount: float, crit: bool, source := "", silent := false) -> void:
	if not alive:
		return
	last_hit_source = source
	var rest := amount
	if shield > 0.0:
		var absorbed := minf(shield, rest)
		shield -= absorbed
		rest -= absorbed
	hp -= rest
	if not silent:
		flash = 0.08
		battle.spawn_damage_number(global_position, amount, crit)
	if hp <= 0.0:
		die()

## EMP: strip shields, stun, mark (for OVERCHARGE BREACH synergy).
func apply_emp(stun: float, mark: float) -> void:
	shield = 0.0
	stun_timer = maxf(stun_timer, stun)
	emp_timer = maxf(emp_timer, mark)
	flash = 0.15

func die() -> void:
	alive = false
	battle.spawn_explosion(global_position, Color(data["color"]), int(radius * 3))
	EventBus.enemy_killed.emit(type_id, global_position)
	battle.remove_enemy(self)

func _draw() -> void:
	var tint := Color(4, 4, 4) if flash > 0.0 else Color.WHITE
	if stun_timer > 0.0 and flash <= 0.0:
		tint = Color(0.6, 0.9, 1.4)
	draw_set_transform(Vector2.ZERO, PI / 2.0, Vector2.ONE)
	PixelLib.draw_mask(self, mask, palette, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if shield > 0.0:
		draw_arc(Vector2.ZERO, radius + 3, 0, TAU, 16, Color(PixelLib.C_CYAN, 0.35 + 0.4 * shield / max_shield), 1.0)
	if emp_timer > 0.0:
		draw_rect(Rect2(-1, -radius - 6, 2, 2), PixelLib.C_WHITE if int(emp_timer * 10) % 2 == 0 else Color("#7fd1ff"))
