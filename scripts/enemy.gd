class_name Enemy
extends Node2D
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
var mask: PackedStringArray
var palette: Dictionary

func setup(b: Node, t: String, d: Dictionary, pos: Vector2, seed_value: int) -> void:
	battle = b
	type_id = t
	data = d
	behavior = d["behavior"]
	hp = float(d["hp"])
	radius = float(d["radius"])
	speed = float(d["speed"])
	accel = float(d["accel"])
	global_position = pos
	rng.seed = seed_value
	orbit_sign = 1.0 if rng.randf() < 0.5 else -1.0
	fire_timer = rng.randf_range(0.5, float(d.get("fire_interval", 2.0)))
	mask = PackedStringArray(MASKS[behavior])
	var col := Color(d["color"])
	palette = {"x": col, "d": col.darkened(0.4), "w": Pixel.C_WHITE}

func _process(delta: float) -> void:
	if not alive:
		return
	var p: Node2D = battle.player
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
	velocity = velocity.move_toward(desired, accel * delta)
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
	flash = maxf(0.0, flash - delta)
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

func take_damage(amount: float, crit: bool) -> void:
	if not alive:
		return
	hp -= amount
	flash = 0.08
	battle.spawn_damage_number(global_position, amount, crit)
	if hp <= 0.0:
		die()

func die() -> void:
	alive = false
	battle.spawn_explosion(global_position, Color(data["color"]), int(radius * 3))
	EventBus.enemy_killed.emit(type_id, global_position)
	battle.remove_enemy(self)

func _draw() -> void:
	var tint := Color(4, 4, 4) if flash > 0.0 else Color.WHITE
	draw_set_transform(Vector2.ZERO, PI / 2.0, Vector2.ONE)
	Pixel.draw_mask(self, mask, palette, tint)
