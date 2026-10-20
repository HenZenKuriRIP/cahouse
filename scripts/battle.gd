extends Node2D
## Phase 1 battle scene root. Builds world, layers and UI in code; owns entity lists.
const ProjectileScript := preload("res://scripts/projectile.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const DamageNumberScript := preload("res://scripts/damage_number.gd")
const MenuPanel := preload("res://scripts/menu_panel.gd")

var arena := Rect2(-600, -340, 1200, 680)
var run_duration := 180.0
var world: Node2D
var fx_layer: Node2D
var proj_layer: Node2D
var enemy_layer: Node2D
var player: Player
var camera: Camera2D
var director: EnemyDirector
var hud: Control
var perf: Label
var ui_layer: CanvasLayer
var pause_menu: Control
var end_menu: Control
var enemies: Array = []
var shake_amount := 0.0
var shake_rng := RandomNumberGenerator.new()
var ended := false
var _real_time := 0.0
var _log_timer := 0.0

func _ready() -> void:
	ObjectPool.reset()
	GameManager.start_run()
	get_tree().paused = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--timescale="):
			Engine.time_scale = float(a.split("=")[1])
	var bg := CanvasLayer.new()
	bg.layer = -10
	add_child(bg)
	var stars := Node2D.new()
	stars.set_script(preload("res://scripts/starfield.gd"))
	bg.add_child(stars)

	world = Node2D.new()
	add_child(world)
	var border := Line2D.new()
	border.points = PackedVector2Array([arena.position, Vector2(arena.end.x, arena.position.y), arena.end, Vector2(arena.position.x, arena.end.y), arena.position])
	border.width = 1.0
	border.default_color = Color(Pixel.C_VIOLET, 0.35)
	world.add_child(border)
	enemy_layer = Node2D.new()
	world.add_child(enemy_layer)
	player = Player.new()
	world.add_child(player)
	player.setup(self, arena)
	proj_layer = Node2D.new()
	world.add_child(proj_layer)
	fx_layer = Node2D.new()
	world.add_child(fx_layer)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = int(arena.position.x) - 60
	camera.limit_top = int(arena.position.y) - 60
	camera.limit_right = int(arena.end.x) + 60
	camera.limit_bottom = int(arena.end.y) + 60
	player.add_child(camera)
	stars.setup(camera, GameManager.run_seed)

	director = EnemyDirector.new()
	add_child(director)
	director.setup(self, GameManager.run_seed)
	run_duration = director.run_duration

	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	hud = Control.new()
	hud.set_script(preload("res://scripts/hud.gd"))
	hud.battle = self
	ui_layer.add_child(hud)
	perf = Label.new()
	perf.set_script(preload("res://scripts/perf_overlay.gd"))
	perf.battle = self
	ui_layer.add_child(perf)

	EventBus.player_died.connect(_on_player_died)
	print("[VOID SIGNAL] run start seed=%d duration=%.0fs" % [GameManager.run_seed, run_duration])

func _process(delta: float) -> void:
	_real_time += delta / maxf(Engine.time_scale, 0.001)
	if not ended and not get_tree().paused:
		GameManager.run_time += delta
		director.tick(GameManager.run_time, delta)
		if GameManager.run_time >= run_duration and player.alive:
			_end(true)
	if shake_amount > 0.0:
		shake_amount = maxf(0.0, shake_amount - 20.0 * delta)
		camera.offset = Vector2(shake_rng.randf_range(-1, 1), shake_rng.randf_range(-1, 1)) * shake_amount
	if GameManager.autotest_seconds > 0.0:
		_log_timer += delta
		if _log_timer >= 15.0:
			_log_timer = 0.0
			print("[AUTOTEST] t=%.1fs hull=%.0f shield=%.0f kills=%d enemies=%d proj_active=%d pool_created=%d fps=%d" % [GameManager.run_time, player.hull, player.shield, GameManager.kills, enemies.size(), ObjectPool.active(Projectile.POOL_KEY), ObjectPool.created_total, Engine.get_frames_per_second()])
		if _real_time >= GameManager.autotest_seconds:
			_autotest_finish("TIMEOUT")

func _autotest_finish(reason: String) -> void:
	print("[AUTOTEST] END reason=%s state=%s run_time=%.1f kills=%d spawned=%d hull=%.0f" % [reason, GameManager.State.keys()[GameManager.state], GameManager.run_time, GameManager.kills, director.spawned_total, player.hull])
	print("[AUTOTEST] PERF\n" + perf.summary())
	get_tree().quit(0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not ended:
		_toggle_pause()

func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	GameManager.state = GameManager.State.PAUSED if p else GameManager.State.PLAYING
	if p:
		pause_menu = _make_menu("PAUSED", "SIGNAL ON HOLD", ["RESUME", "RESTART", "QUIT"])
	elif pause_menu:
		pause_menu.queue_free()
		pause_menu = null

func _make_menu(title: String, sub: String, actions: Array) -> Control:
	var m := Control.new()
	m.set_script(MenuPanel)
	ui_layer.add_child(m)
	m.build(title, sub, actions)
	m.chosen.connect(_on_menu)
	m.focus_first()
	return m

func _on_menu(action: String) -> void:
	match action:
		"RESUME":
			_toggle_pause()
		"RESTART":
			get_tree().paused = false
			get_tree().reload_current_scene()
		"QUIT":
			get_tree().quit()

func _on_player_died() -> void:
	_end(false)

func _end(won: bool) -> void:
	if ended:
		return
	ended = true
	if won:
		EventBus.run_won.emit()
	else:
		EventBus.run_lost.emit()
	print("[VOID SIGNAL] run %s at %.1fs kills=%d" % ["WON" if won else "LOST", GameManager.run_time, GameManager.kills])
	if GameManager.autotest_seconds > 0.0:
		_autotest_finish("WON" if won else "LOST")
		return
	if won:
		for e in enemies.duplicate():
			e.die()
	var title := "SIGNAL HELD" if won else "SIGNAL LOST"
	var sub := "SURVIVED 3:00  KILLS %d" % GameManager.kills if won else "TIME %d:%02d  KILLS %d" % [int(GameManager.run_time) / 60, int(GameManager.run_time) % 60, GameManager.kills]
	end_menu = _make_menu(title, sub, ["RESTART", "QUIT"])

# ---- spawning API used by systems ----
func spawn_projectile(pos: Vector2, vel: Vector2, dmg: float, life: float, team: int, col: Color, crit: bool) -> void:
	var p: Projectile = ObjectPool.acquire(Projectile.POOL_KEY, func() -> Node:
		var n := ProjectileScript.new()
		proj_layer.add_child(n)
		return n)
	p.setup(self, pos, vel, dmg, life, team, col, crit)

func spawn_enemy(type_id: String, data: Dictionary, pos: Vector2, seed_value: int) -> void:
	var e: Enemy = EnemyScript.new()
	enemy_layer.add_child(e)
	e.setup(self, type_id, data, pos, seed_value)
	enemies.append(e)
	EventBus.enemy_spawned.emit(type_id)
	spawn_explosion(pos, Color(Pixel.C_VIOLET, 0.6), 6)

func remove_enemy(e: Enemy) -> void:
	enemies.erase(e)
	e.queue_free()

func spawn_explosion(pos: Vector2, col: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = maxi(4, amount)
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 90.0
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	var grad := Gradient.new()
	grad.set_color(0, Pixel.C_WHITE)
	grad.set_color(1, Color(col, 0.0))
	grad.add_point(0.3, col)
	p.color_ramp = grad
	p.global_position = pos
	fx_layer.add_child(p)
	p.finished.connect(p.queue_free)
	if amount > 10:
		shake(minf(5.0, amount / 10.0))

func spawn_dash_trail(pos: Vector2, dir: Vector2) -> void:
	spawn_explosion(pos - dir * 6.0, Pixel.C_CYAN, 8)

func spawn_damage_number(pos: Vector2, amount: float, crit: bool) -> void:
	if fx_layer.get_child_count() > 120:
		return
	var d := Node2D.new()
	d.set_script(DamageNumberScript)
	d.text = str(int(amount)) + ("!" if crit else "")
	d.color = Pixel.C_GOLD if crit else Pixel.C_WHITE
	d.global_position = pos + Vector2(0, -8)
	fx_layer.add_child(d)

func shake(amount: float) -> void:
	if bool(SaveManager.settings.get("screen_shake", true)):
		shake_amount = maxf(shake_amount, amount)
