extends Node2D
## Battle scene root. Builds world, environment, layers and UI in code; owns entity lists and spawn API.
const PixelLib = preload("res://scripts/pixel.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const EnemyDirectorScript = preload("res://scripts/enemy_director.gd")
const FloatTextScript = preload("res://scripts/float_text.gd")
const MenuPanel = preload("res://scripts/menu_panel.gd")
const GravityWellScript = preload("res://scripts/gravity_well.gd")
const SynergySystemScript = preload("res://scripts/synergy_system.gd")
const AsteroidFieldScript = preload("res://scripts/asteroid_field.gd")
const ShipBuilderScript = preload("res://scripts/ship_builder.gd")
const AutotestDriverScript = preload("res://scripts/autotest_driver.gd")

const VIEW := Vector2(270, 480)
## Vertical endless battlefield: the camera auto-scrolls upward (world -y). Player is kept in a band.
var band_half := 118.0
var scroll_y := 0.0
var base_scroll_speed := 40.0
var push_margin := 100.0
var distance_goal := 7200.0
var endless := false
var run_duration := 180.0
var world: Node2D
var fx_layer: Node2D
var proj_layer: Node2D
var enemy_layer: Node2D
var well_layer: Node2D
var player: Node2D
var camera: Camera2D
var director: Node
var synergy: Node
var field: Node2D
var hud: Control
var perf: Label
var ui_layer: CanvasLayer
var builder: Control
var pause_menu: Control
var end_menu: Control
var driver: Node
var enemies: Array = []
var wells: Array = []
var emp_blasts := 0
var shake_amount := 0.0
var shake_rng := RandomNumberGenerator.new()
var ended := false
var _real_time := 0.0

func _ready() -> void:
	ObjectPool.reset()
	GameManager.start_run()
	get_tree().paused = false
	for a in OS.get_cmdline_user_args():
		if a == "--endless":
			endless = true
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
	well_layer = Node2D.new()
	world.add_child(well_layer)
	field = AsteroidFieldScript.new()
	world.add_child(field)
	enemy_layer = Node2D.new()
	world.add_child(enemy_layer)
	player = PlayerScript.new()
	world.add_child(player)
	player.setup(self)
	field.setup(self, GameManager.run_seed + 101)
	proj_layer = Node2D.new()
	world.add_child(proj_layer)
	fx_layer = Node2D.new()
	world.add_child(fx_layer)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.position_smoothing_enabled = false
	world.add_child(camera)
	stars.setup(camera, GameManager.run_seed)

	synergy = SynergySystemScript.new()
	add_child(synergy)
	synergy.setup(self)
	director = EnemyDirectorScript.new()
	add_child(director)
	director.setup(self, GameManager.run_seed)
	run_duration = director.run_duration

	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	var edge := Control.new()
	edge.set_script(preload("res://scripts/edge_fx.gd"))
	edge.battle = self
	ui_layer.add_child(edge)
	hud = Control.new()
	hud.set_script(preload("res://scripts/hud.gd"))
	ui_layer.add_child(hud)
	hud.bind(self)
	perf = Label.new()
	perf.set_script(preload("res://scripts/perf_overlay.gd"))
	perf.battle = self
	ui_layer.add_child(perf)
	builder = ShipBuilderScript.new()
	builder.visible = false
	ui_layer.add_child(builder)

	EventBus.player_died.connect(_on_player_died)
	if GameManager.autotest_seconds > 0.0:
		driver = AutotestDriverScript.new()
		add_child(driver)
		driver.setup(self)
	print("[VOID SIGNAL] run start seed=%d goal=%.0fm endless=%s lang=%s" % [GameManager.run_seed, distance_goal, endless, Loc.language])

func _process(delta: float) -> void:
	_real_time += delta / maxf(Engine.time_scale, 0.001)
	if not ended and not get_tree().paused:
		GameManager.run_time += delta
		director.tick(GameManager.run_time, delta)
		# the ship moves in the screen frame: auto-scroll carries it; flying above the push line drags the camera ahead
		var dy := base_scroll_speed * delta
		scroll_y -= dy
		if player.alive:
			player.global_position.y -= dy
			var push_line := scroll_y - push_margin
			if player.global_position.y < push_line:
				scroll_y -= push_line - player.global_position.y
		if not endless and distance() >= distance_goal and player.alive:
			_end(true)
	camera.position = Vector2(0, scroll_y)
	wells = wells.filter(func(w: Variant) -> bool: return is_instance_valid(w))
	if shake_amount > 0.0:
		shake_amount = maxf(0.0, shake_amount - 20.0 * delta)
		camera.offset = Vector2(shake_rng.randf_range(-1, 1), shake_rng.randf_range(-1, 1)) * shake_amount
	if GameManager.autotest_seconds > 0.0 and _real_time >= GameManager.autotest_seconds and not ended:
		_autotest_finish("TIMEOUT")

func _autotest_finish(reason: String) -> void:
	print("[AUTOTEST] END reason=%s state=%s run_time=%.1f distance=%.0f kills=%d spawned=%d hull=%.0f" % [reason, GameManager.State.keys()[GameManager.state], GameManager.run_time, distance(), GameManager.kills, director.spawned_total, player.hull])
	var ok: bool = driver.report() if driver else true
	print("[AUTOTEST] PERF\n" + perf.summary())
	get_tree().paused = true
	AudioManager.stop_all()
	set_process(false)
	await get_tree().create_timer(0.3, true, false, true).timeout
	get_tree().quit(0 if ok else 1)

func distance() -> float:
	return -scroll_y

func view_rect() -> Rect2:
	return Rect2(Vector2(-VIEW.x / 2.0, scroll_y - VIEW.y / 2.0), VIEW)

## Soft walls: horizontal band and a vertical window inside the scrolling view (above the HUD).
func constrain_player(p: Node2D, delta: float) -> void:
	var x: float = p.global_position.x
	if absf(x) > band_half:
		p.velocity.x -= signf(x) * (absf(x) - band_half) * 40.0 * delta
	p.global_position.x = clampf(x, -band_half - 12.0, band_half + 12.0)
	var top := scroll_y - 205.0
	var bottom := scroll_y + 140.0
	var y: float = p.global_position.y
	if y > bottom:
		p.velocity.y -= (y - bottom) * 40.0 * delta
	elif y < top:
		p.velocity.y += (top - y) * 40.0 * delta
	p.global_position.y = clampf(p.global_position.y, top - 15.0, bottom + 25.0)

func ui_blocks_fire() -> bool:
	return builder.visible or (hud.widget and hud.widget.dragging) or (hud.widget and Rect2(hud.widget.global_position, hud.widget.size).has_point(get_viewport().get_mouse_position()) and not InputManager.using_gamepad)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not ended:
		if builder.visible:
			toggle_builder()
		else:
			_toggle_pause()
	elif event.is_action_pressed("builder") and not ended and pause_menu == null:
		toggle_builder()

func toggle_builder() -> void:
	if builder.visible:
		builder.visible = false
		get_tree().paused = false
	else:
		builder.open_with(self)
		get_tree().paused = true

func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	GameManager.state = GameManager.State.PAUSED if p else GameManager.State.PLAYING
	if p:
		pause_menu = _make_pause_menu()
	elif pause_menu:
		pause_menu.queue_free()
		pause_menu = null

func _make_pause_menu() -> Control:
	var flash_on := bool(SaveManager.settings.get("reduce_flash", false))
	return _make_menu(tr("MENU_PAUSED"), tr("MENU_PAUSED_SUB"), [
		["MENU_RESUME", tr("MENU_RESUME")], ["MENU_RESTART", tr("MENU_RESTART")],
		["MENU_REDUCE_FLASH", tr("MENU_REDUCE_FLASH") % tr("MENU_ON" if flash_on else "MENU_OFF")],
		["MENU_LANGUAGE", tr("MENU_LANGUAGE") % tr("LANG_NAME")], ["MENU_QUIT", tr("MENU_QUIT")]])

func _make_menu(title: String, sub: String, actions: Array) -> Control:
	var m := Control.new()
	m.set_script(MenuPanel)
	ui_layer.add_child(m)
	m.build(title, sub, actions)
	m.chosen.connect(_on_menu)
	m.focus_first()
	return m

func _on_menu(action: String) -> void:
	if action == "MENU_REDUCE_FLASH" or action == "MENU_LANGUAGE":
		if action == "MENU_REDUCE_FLASH":
			SaveManager.set_setting("reduce_flash", not bool(SaveManager.settings.get("reduce_flash", false)))
		else:
			Loc.toggle_language()
		pause_menu.queue_free()
		pause_menu = _make_pause_menu()
		return
	match action:
		"MENU_RESUME":
			_toggle_pause()
		"MENU_RESTART":
			get_tree().paused = false
			get_tree().reload_current_scene()
		"MENU_QUIT":
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
	print("[VOID SIGNAL] run %s at %.1fs distance=%.0fm kills=%d" % ["WON" if won else "LOST", GameManager.run_time, distance(), GameManager.kills])
	if GameManager.autotest_seconds > 0.0:
		_autotest_finish("WON" if won else "LOST")
		return
	if won:
		for e in enemies.duplicate():
			e.die()
	var title := tr("END_WON_TITLE") if won else tr("END_LOST_TITLE")
	var rt := int(GameManager.run_time)
	var sub: String = tr("END_WON_SUB") % [int(distance()), GameManager.kills] if won else tr("END_LOST_SUB") % [int(distance()), rt / 60, rt % 60, GameManager.kills]
	end_menu = _make_menu(title, sub, [["MENU_RESTART", tr("MENU_RESTART")], ["MENU_QUIT", tr("MENU_QUIT")]])

# ---- spawning API used by systems ----
func spawn_projectile(pos: Vector2, vel: Vector2, dmg: float, life: float, team: int, col: Color, crit: bool, extra: Dictionary = {}) -> void:
	var p: Node2D = ObjectPool.acquire(ProjectileScript.POOL_KEY, func() -> Node:
		var n: Node2D = ProjectileScript.new()
		proj_layer.add_child(n)
		return n)
	p.setup(self, pos, vel, dmg, life, team, col, crit, extra)

func spawn_enemy(type_id: String, data: Dictionary, pos: Vector2, seed_value: int) -> void:
	var e: Node2D = EnemyScript.new()
	enemy_layer.add_child(e)
	e.setup(self, type_id, data, pos, seed_value)
	enemies.append(e)
	EventBus.enemy_spawned.emit(type_id)
	spawn_explosion(pos, Color(PixelLib.C_VIOLET, 0.6), 6)

func remove_enemy(e: Node2D) -> void:
	enemies.erase(e)
	e.queue_free()

func asteroid_at(pos: Vector2, r: float) -> Node2D:
	return field.asteroid_at(pos, r)

func spawn_gravity_well(pos: Vector2, d: Dictionary) -> void:
	var w: Node2D = GravityWellScript.new()
	well_layer.add_child(w)
	w.setup(self, pos, d)
	wells.append(w)
	spawn_explosion(pos, PixelLib.C_VIOLET, 12)

func emp_blast(pos: Vector2, d: Dictionary, dmg: float) -> void:
	emp_blasts += 1
	var r := float(d.get("blast_radius", 60))
	for e in enemies.duplicate():
		if e.alive and e.global_position.distance_to(pos) <= r + e.radius:
			e.apply_emp(float(d.get("stun_time", 1.5)), float(d.get("emp_mark_time", 3.0)))
			e.take_damage(dmg, false, "emp_launcher")
	synergy.on_emp_blast(pos, r)
	spawn_explosion(pos, Color("#7fd1ff"), 24)

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
	grad.set_color(0, PixelLib.C_WHITE)
	grad.set_color(1, Color(col, 0.0))
	grad.add_point(0.3, col)
	p.color_ramp = grad
	p.global_position = pos
	fx_layer.add_child(p)
	p.finished.connect(p.queue_free)
	if amount > 10:
		shake(minf(5.0, amount / 10.0))

func spawn_dash_trail(pos: Vector2, dir: Vector2) -> void:
	spawn_explosion(pos - dir * 6.0, PixelLib.C_CYAN, 8)

func spawn_float_text(pos: Vector2, t: String, col: Color, life := 0.6) -> void:
	if fx_layer.get_child_count() > 150:
		return
	var d: Node2D = FloatTextScript.new()
	d.text = t
	d.color = col
	d.life = life
	d.max_life = life
	d.global_position = pos
	fx_layer.add_child(d)

func spawn_damage_number(pos: Vector2, amount: float, crit: bool) -> void:
	spawn_float_text(pos + Vector2(0, -8), str(int(amount)) + ("!" if crit else ""), PixelLib.C_GOLD if crit else PixelLib.C_WHITE)

func shake(amount: float) -> void:
	if bool(SaveManager.settings.get("screen_shake", true)):
		shake_amount = maxf(shake_amount, amount)
