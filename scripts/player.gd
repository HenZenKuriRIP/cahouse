class_name Player
extends Node2D
## Player ship: inertia movement, aim, dash, hull + regenerating shield.
const ACCEL := 520.0
const MAX_SPEED := 170.0
const DRAG := 2.4
const DASH_SPEED := 420.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 1.2
const SHIELD_REGEN := 10.0
const SHIELD_DELAY := 2.0

var MASK := PackedStringArray([
	"....cc......",
	"...cwwc.....",
	"..cpppcc....",
	"cpppppwwwcc.",
	"cpppppwwwcc.",
	"..cpppcc....",
	"...cwwc.....",
	"....cc......",
])
var palette := {"c": Pixel.C_CYAN, "w": Pixel.C_WHITE, "p": Pixel.C_PANEL.lightened(0.25)}

var battle: Node
var velocity := Vector2.ZERO
var radius := 5.0
var max_hull := 100.0
var hull := 100.0
var max_shield := 50.0
var shield := 50.0
var shield_timer := 0.0
var dash_cd := 0.0
var dash_timer := 0.0
var flash := 0.0
var alive := true
var thrusting := false
var flame_phase := 0.0
var weapon: Weapon
var aim_dir := Vector2.RIGHT
var god := false
var bounds := Rect2()

func setup(b: Node, arena: Rect2) -> void:
	battle = b
	bounds = arena
	weapon = Weapon.new("res://data/weapons/pulse_cannon.json", GameManager.run_seed)
	god = GameManager.autotest_god

func _process(delta: float) -> void:
	if not alive:
		return
	var move: Vector2
	var want_fire := false
	var want_dash := false
	if GameManager.autotest_seconds > 0.0:
		var auto := _autopilot()
		move = auto[0]
		want_fire = auto[1]
		want_dash = auto[2]
	else:
		move = InputManager.get_move_vector()
		var stick := InputManager.get_stick_aim()
		if stick != Vector2.ZERO:
			aim_dir = stick
		elif not InputManager.using_gamepad:
			var to_mouse := get_global_mouse_position() - global_position
			if to_mouse.length() > 2.0:
				aim_dir = to_mouse.normalized()
		want_fire = Input.is_action_pressed("fire")
		want_dash = Input.is_action_just_pressed("dash")
	thrusting = move.length() > 0.1
	velocity += move * ACCEL * delta
	velocity -= velocity * DRAG * delta
	dash_cd = maxf(0.0, dash_cd - delta)
	if want_dash and dash_cd <= 0.0:
		var ddir := move.normalized() if thrusting else aim_dir
		velocity = ddir * DASH_SPEED
		dash_timer = DASH_TIME
		dash_cd = DASH_COOLDOWN
		EventBus.dash_used.emit()
		battle.spawn_dash_trail(global_position, ddir)
	if dash_timer > 0.0:
		dash_timer -= delta
	elif velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED
	global_position += velocity * delta
	global_position = global_position.clamp(bounds.position, bounds.end)
	rotation = aim_dir.angle()
	weapon.update(delta)
	if want_fire:
		weapon.try_fire(battle, global_position + aim_dir * 7.0, aim_dir)
	shield_timer -= delta
	if shield_timer <= 0.0:
		shield = minf(max_shield, shield + SHIELD_REGEN * delta)
	flash = maxf(0.0, flash - delta)
	flame_phase += delta * 30.0
	queue_redraw()

func _autopilot() -> Array:
	# Deterministic test pilot: orbit arena centre, aim at nearest enemy, dash away from close threats.
	var t := GameManager.run_time
	var target_pos := bounds.get_center() + Vector2(cos(t * 0.6), sin(t * 0.6)) * 120.0
	var move := (target_pos - global_position).limit_length(40.0) / 40.0
	var nearest: Node2D = null
	var best := INF
	for e in battle.enemies:
		if e.alive:
			var d := global_position.distance_squared_to(e.global_position)
			if d < best:
				best = d
				nearest = e
	var dash := false
	if nearest:
		aim_dir = (nearest.global_position - global_position).normalized()
		if best < 30.0 * 30.0:
			move = -aim_dir
			dash = true
	return [move, nearest != null, dash]

func is_invulnerable() -> bool:
	return dash_timer > 0.0 or god

func take_damage(amount: float, from_pos: Vector2) -> void:
	if not alive or is_invulnerable():
		return
	shield_timer = SHIELD_DELAY
	var absorbed := minf(shield, amount)
	shield -= absorbed
	hull -= amount - absorbed
	flash = 0.12
	EventBus.player_damaged.emit(amount, from_pos)
	battle.shake(2.0 if absorbed >= amount else 4.0)
	if hull <= 0.0:
		hull = 0.0
		alive = false
		visible = false
		battle.spawn_explosion(global_position, Pixel.C_CYAN, 40)
		EventBus.player_died.emit()

func _draw() -> void:
	if thrusting or dash_timer > 0.0:
		var len := 3 + int(flame_phase) % 3 + (4 if dash_timer > 0.0 else 0)
		draw_rect(Rect2(-6 - len, -1, len, 2), Pixel.C_GOLD)
		draw_rect(Rect2(-6 - len / 2, -1, len / 2, 2), Pixel.C_WHITE)
		draw_rect(Rect2(-7 - len, 0, 2, 1), Pixel.C_RED)
	var tint := Color.WHITE
	if flash > 0.0:
		tint = Color(3, 3, 3)
	elif dash_timer > 0.0:
		tint = Color(1, 1, 1, 0.6)
	Pixel.draw_mask(self, MASK, palette, tint)
	if shield > 1.0 and flash > 0.0:
		draw_arc(Vector2.ZERO, 9, 0, TAU, 16, Color(Pixel.C_CYAN, 0.6), 1.0)
