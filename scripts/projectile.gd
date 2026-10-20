class_name Projectile
extends Node2D
## Pooled projectile. Movement + collision is pure logic; _draw is visual only.
const POOL_KEY := "projectile"
var velocity := Vector2.ZERO
var damage := 0.0
var life := 0.0
var radius := 2.0
var team := 0 # 0 = player, 1 = enemy
var color := Color.WHITE
var crit := false
var active := false
var battle: Node = null

func setup(b: Node, pos: Vector2, vel: Vector2, dmg: float, lifetime: float, t: int, col: Color, is_crit: bool) -> void:
	battle = b
	global_position = pos
	velocity = vel
	rotation = vel.angle()
	damage = dmg
	life = lifetime
	team = t
	color = col
	crit = is_crit
	radius = 2.0 if t == 0 else 3.0
	active = true
	visible = true
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if not active:
		return
	global_position += velocity * delta
	life -= delta
	if life <= 0.0:
		deactivate()
		return
	if team == 0:
		for e in battle.enemies:
			if e.alive and global_position.distance_squared_to(e.global_position) < (radius + e.radius) * (radius + e.radius):
				e.take_damage(damage, crit)
				deactivate()
				return
	else:
		var p: Node2D = battle.player
		if p and p.alive and global_position.distance_squared_to(p.global_position) < (radius + p.radius) * (radius + p.radius):
			p.take_damage(damage, global_position - velocity.normalized() * 40.0)
			deactivate()

func deactivate() -> void:
	if not active:
		return
	active = false
	visible = false
	set_process(false)
	ObjectPool.release(POOL_KEY, self)

func _draw() -> void:
	if team == 0:
		draw_rect(Rect2(-3, -1, 6, 2), color)
		draw_rect(Rect2(1, -1, 2, 2), Pixel.C_WHITE if not crit else Pixel.C_GOLD)
	else:
		draw_rect(Rect2(-2, -2, 4, 4), color)
		draw_rect(Rect2(-1, -1, 2, 2), Pixel.C_WHITE)
