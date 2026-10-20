extends Node2D
## Pooled projectile. kinds: bullet, missile (homing), bomb (spawns gravity well), emp (blast).
## Logic only touches state; _draw renders. Asteroids block all projectiles.
const PixelLib = preload("res://scripts/pixel.gd")
const POOL_KEY := "projectile"
var velocity := Vector2.ZERO
var damage := 0.0
var life := 0.0
var radius := 2.0
var team := 0 # 0 = player, 1 = enemy
var color := Color.WHITE
var crit := false
var active := false
var kind := "bullet"
var weapon_id := ""
var wdata: Dictionary = {}
var target: Node2D = null
var battle: Node = null
var _retarget_t := 0.0

func setup(b: Node, pos: Vector2, vel: Vector2, dmg: float, lifetime: float, t: int, col: Color, is_crit: bool, extra: Dictionary = {}) -> void:
	battle = b
	global_position = pos
	velocity = vel
	rotation = vel.angle()
	damage = dmg
	life = lifetime
	team = t
	color = col
	crit = is_crit
	kind = extra.get("kind", "bullet")
	weapon_id = extra.get("weapon", "")
	wdata = extra.get("data", {})
	target = null
	_retarget_t = 0.0
	radius = 2.0 if t == 0 else 3.0
	if kind == "bomb" or kind == "emp":
		radius = 3.0
	active = true
	visible = true
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if not active:
		return
	if kind == "missile":
		_home(delta)
	global_position += velocity * delta
	rotation = velocity.angle()
	life -= delta
	if life <= 0.0:
		_expire()
		return
	var ast: Node2D = battle.asteroid_at(global_position, radius)
	if ast:
		ast.take_damage(damage, self)
		_impact()
		return
	if team == 0:
		for e in battle.enemies:
			if e.alive and global_position.distance_squared_to(e.global_position) < (radius + e.radius) * (radius + e.radius):
				battle.synergy.on_player_hit(self, e)
				_impact()
				return
	else:
		var p: Node2D = battle.player
		if p and p.alive and global_position.distance_squared_to(p.global_position) < (radius + p.radius) * (radius + p.radius):
			p.take_damage(damage, global_position - velocity.normalized() * 40.0)
			deactivate()

func _home(delta: float) -> void:
	_retarget_t -= delta
	if target == null or not is_instance_valid(target) or not target.alive or _retarget_t <= 0.0:
		_retarget_t = 0.25
		target = battle.synergy.missile_target(global_position, velocity)
	if target:
		var want := (target.global_position - global_position).angle()
		var turn := float(wdata.get("turn_rate", 4.0)) * delta
		var ang := rotate_toward(velocity.angle(), want, turn)
		velocity = Vector2.from_angle(ang) * velocity.length()

func _impact() -> void:
	if kind == "bomb":
		battle.spawn_gravity_well(global_position, wdata)
	elif kind == "emp":
		battle.emp_blast(global_position, wdata, damage)
	deactivate()

func _expire() -> void:
	if kind == "bomb" or kind == "emp":
		_impact()
	else:
		deactivate()

func deactivate() -> void:
	if not active:
		return
	active = false
	visible = false
	target = null
	set_process(false)
	ObjectPool.release(POOL_KEY, self)

func _draw() -> void:
	match kind:
		"missile":
			draw_rect(Rect2(-3, -1, 4, 2), PixelLib.C_WHITE)
			draw_rect(Rect2(1, -1, 2, 2), color)
			draw_rect(Rect2(-5, -1, 2, 2), PixelLib.C_RED)
		"bomb":
			draw_rect(Rect2(-3, -3, 6, 6), color)
			draw_rect(Rect2(-1, -1, 2, 2), PixelLib.C_BG)
		"emp":
			draw_rect(Rect2(-3, -2, 6, 4), color)
			draw_rect(Rect2(-1, -3, 2, 6), PixelLib.C_WHITE)
		_:
			if team == 0:
				draw_rect(Rect2(-3, -1, 6, 2), color)
				draw_rect(Rect2(1, -1, 2, 2), PixelLib.C_WHITE if not crit else PixelLib.C_GOLD)
			else:
				draw_rect(Rect2(-2, -2, 4, 4), color)
				draw_rect(Rect2(-1, -1, 2, 2), PixelLib.C_WHITE)
