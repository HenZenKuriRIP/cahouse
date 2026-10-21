extends Node
## Screenshot director (--shots=title|battle|gameover). Drives the game into each UI state and saves PNGs of
## the real rendered viewport to res://docs/screenshots/. Requires a non-headless run (e.g. xvfb-run).
var battle: Node
var title_node: Node
var _rt := 0.0
var _busy := false
var done := {}
var _syn_seen := -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func setup_title(t: Node) -> void:
	title_node = t

func setup_battle(b: Node) -> void:
	battle = b
	EventBus.synergy_triggered.connect(func(_id: String, _p: Vector2) -> void:
		if _syn_seen < 0.0 and GameManager.run_time > 16.0:
			_syn_seen = _rt)

func _real(delta: float) -> float:
	return delta / maxf(Engine.time_scale, 0.001)

func shot(name: String, crop := Rect2(), upscale := 1) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var sc := img.get_width() / 270.0
	if crop.size.x > 0.0:
		img = img.get_region(Rect2i(Vector2i((crop.position * sc).floor()), Vector2i((crop.size * sc).floor())))
	if upscale > 1:
		img.resize(img.get_width() * upscale, img.get_height() * upscale, Image.INTERPOLATE_NEAREST)
	var path := ProjectSettings.globalize_path("res://docs/screenshots/%s.png" % name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("[SHOT] %s %dx%d -> %s" % [name, img.get_width(), img.get_height(), path])
	done[name] = true

func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += _real(get_process_delta_time())

func _process(delta: float) -> void:
	_rt += _real(delta)
	if _busy:
		return
	if title_node:
		if _rt > 1.8 and not done.has("title"):
			_busy = true
			await shot("title")
			get_tree().quit()
		return
	if battle == null:
		return
	if GameManager.shots_set == "touch":
		if GameManager.run_time > 7.0 and not done.has("touch_hud"):
			_busy = true
			await _touch_shot()
			get_tree().quit()
		return
	if GameManager.shots_set == "gameover":
		if GameManager.run_time > 9.0 and battle.player.alive:
			battle.player.god = false
			battle.player.dash_timer = 0.0
			battle.player.take_damage(9999.0, battle.player.global_position + Vector2(0, -30))
		if battle.ended and not done.has("gameover"):
			_busy = true
			await _wait(2.4)
			await shot("gameover")
			get_tree().quit()
		return
	var e: RefCounted = battle.player.energy
	if not done.has("overload") and e.overload_active and e.heat_ratio() > 0.72:
		_busy = true
		await shot("overload")
		_busy = false
		return
	if not done.has("synergy_toast") and _syn_seen >= 0.0 and _rt - _syn_seen > 0.3:
		_busy = true
		await shot("synergy_toast")
		_busy = false
		return
	if not done.has("hud_combat") and GameManager.run_time > 44.0 and battle.enemies.size() >= 4:
		_busy = true
		await shot("hud_combat")
		await shot("energy_triangle", Rect2(99, 404, 72, 74), 4)
		_busy = false
		return
	if not done.has("pause_en") and done.has("hud_combat") and GameManager.run_time > 50.0:
		_busy = true
		Loc.set_language("zh", false)
		battle._toggle_pause()
		await _wait(0.8)
		await shot("pause_zh")
		battle._on_menu("MENU_LANGUAGE")
		await _wait(0.8)
		await shot("pause_en")
		Loc.set_language("zh", false)
		battle._toggle_pause()
		await _wait(0.2)
		# ship builder with a cyan placement ghost
		battle.toggle_builder()
		var bl: Control = battle.builder
		bl.begin_drag("armor", "")
		bl.drop(Vector2i(5, 4))
		await _wait(0.1)
		bl.begin_drag("weapon_mount", "missile_swarm")
		bl.mouse = bl.cell_screen(Vector2i(2, 1)) + Vector2(10, 10)
		await _wait(0.5)
		await shot("builder")
		bl.drag = []
		battle.toggle_builder()
		_busy = false
		return
	if battle.ended and not done.has("victory"):
		_busy = true
		await _wait(2.4)
		await shot("victory")
		get_tree().quit()

## Real input path: events are injected in window pixels through Input.parse_input_event, so the stretch
## transform (window 540x960 -> logical 270x480) is exercised exactly as on a device.
func _touch_shot() -> void:
	var tc: Control = battle.touch
	var sc := Vector2(DisplayServer.window_get_size()) / Vector2(270, 480)
	var evs := [[0, true, Vector2(58, 330)], [1, true, Vector2(184, 318)]]
	for e in evs:
		var ev := InputEventScreenTouch.new()
		ev.index = e[0]
		ev.pressed = e[1]
		ev.position = e[2] * sc
		Input.parse_input_event(ev)
	await get_tree().process_frame
	for e in [[0, Vector2(70, 314)], [1, Vector2(204, 308)]]:
		var d := InputEventScreenDrag.new()
		d.index = e[0]
		d.position = e[1] * sc
		Input.parse_input_event(d)
	var ov := InputEventScreenTouch.new()
	ov.index = 2
	ov.pressed = true
	ov.position = tc.buttons()["overload"].get_center() * sc
	Input.parse_input_event(ov)
	await _wait(0.5)
	print("[SHOT] touch state: fingers=%d move=%s aim=%s aim_active=%s overload=%s insets=%s" % [tc.fingers.size(), tc.move_vec, tc.aim_vec, tc.aim_active(), tc.overload_held, tc.insets])
	await shot("touch_hud")
