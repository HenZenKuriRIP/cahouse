extends Control
## Title / start splash: pixel logo VOID SIGNAL / 虚空信号 with chromatic split, drifting starfield,
## blueprint ship, press-to-start prompt. L toggles language. Autotest/screenshot runs skip straight to battle.
const K = preload("res://scripts/ui/ui_kit.gd")
const ShipModel = preload("res://scripts/ship_model.gd")
var ship: RefCounted
var _t := 0.0
var _leaving := -1.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("[TITLE] ready viewport=%s window=%s touchscreen=%s" % [get_viewport_rect().size, DisplayServer.window_get_size(), DisplayServer.is_touchscreen_available()])
	if GameManager.autotest_seconds > 0.0 and not (GameManager.shots_set in ["title", "flow"]):
		get_tree().change_scene_to_file.call_deferred("res://scenes/battle.tscn")
		return
	var bg := CanvasLayer.new()
	bg.layer = -10
	add_child(bg)
	var stars := Node2D.new()
	stars.set_script(preload("res://scripts/starfield.gd"))
	bg.add_child(stars)
	stars.setup(null, 3287)
	var holo := ColorRect.new()
	holo.set_script(preload("res://scripts/ui/holo_overlay.gd"))
	add_child(holo)
	ship = ShipModel.from_file("res://data/ships/default_ship.json")
	if GameManager.shots_mode:
		var sd: Node = preload("res://scripts/ui/shot_director.gd").new()
		add_child(sd)
		sd.setup_title(self)

## ROOT-CAUSE FIX (Android "touch does nothing"): this Control used to keep the default MOUSE_FILTER_STOP and
## listen in _unhandled_input. Touches arrive as InputEventScreenTouch (never handled) plus an emulated mouse click
## that the GUI hands to this STOP control and marks handled, so _unhandled_input never ran. Now: mouse_filter
## IGNORE + _input, which sees touch, mouse, keys and pads before the GUI; emulated mouse clicks are skipped so a
## single tap is not counted twice.
func _input(event: InputEvent) -> void:
	if _leaving >= 0.0 or ship == null:
		return
	var tap_pos := Vector2(-1, -1)
	var go := false
	if event is InputEventScreenTouch and event.pressed:
		tap_pos = event.position
		go = true
	elif event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		tap_pos = event.position
		go = true
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_L:
			Loc.toggle_language()
			print("[TITLE] key L -> language %s" % Loc.language)
			get_viewport().set_input_as_handled()
			return
		go = true
	elif event is InputEventJoypadButton and event.pressed:
		go = true
	if not go:
		return
	get_viewport().set_input_as_handled()
	var ly := _oy() + 440.0
	if tap_pos.y > ly - 16.0 and tap_pos.y < ly + 10.0:
		Loc.toggle_language()
		print("[TITLE] tap %s on language line -> %s" % [tap_pos, Loc.language])
		return
	print("[TITLE] start via %s at %s" % [event.get_class(), tap_pos])
	_leaving = 0.0
	AudioManager.play("dash")

## Vertical offset that centres the 270x480 title layout in the (expanded) viewport, inside the safe area.
func _oy() -> float:
	var vs := K.vsize(self)
	var ins := K.safe_insets(self)
	return floorf(clampf((vs.y - 480.0) / 2.0, ins.y, maxf(ins.y, vs.y - 480.0 - ins.w)))

func _process(delta: float) -> void:
	_t += delta
	if _leaving >= 0.0:
		_leaving += delta
		if _leaving > 0.35:
			_leaving = -100.0
			print("[TITLE] change scene -> battle")
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
	queue_redraw()

func _draw() -> void:
	if ship == null:
		return
	var vs := K.vsize(self)
	var ins := K.safe_insets(self)
	var k := K.ease_out_cubic(_t / 0.8)
	# frame corners + micro telemetry hug the real screen edges (inside the safe area)
	var fr := Rect2(6 + ins.x, 6 + ins.y, vs.x - 12 - ins.x - ins.z, vs.y - 12 - ins.y - ins.w)
	K.brackets(self, fr, 10, Color(K.ACCENT, 0.5))
	K.text(self, fr.position + Vector2(6, 14), "SIG//0x0CB3", Color(K.ACCENT, 0.5))
	K.text(self, Vector2(fr.position.x, fr.position.y + 14), "%06.2f" % fmod(_t * 13.7 + 120.0, 1000.0), Color(K.ACCENT, 0.5), K.FS_BODY, HORIZONTAL_ALIGNMENT_RIGHT, fr.size.x - 6)
	K.text(self, Vector2(0, fr.end.y - 6), "v0.4.1 · © VOID SIGNAL", Color(K.TEXT, 0.3), K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	# the rest is a 270x480 composition centred in the expanded viewport
	draw_set_transform(Vector2(floorf((vs.x - 270.0) / 2.0), _oy()))
	var W := 270.0
	K.text(self, Vector2(0, 100), tr("TITLE_YEAR"), Color(K.TEXT, 0.6 * k), K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, W)
	# logo
	var ly := 152.0 + floorf((1.0 - k) * 12.0)
	var glitch := 0.0
	if not K.reduce_flash() and fmod(_t, 3.7) < 0.08:
		glitch = 2.0
	for line in [["VOID", ly], ["SIGNAL", ly + 44]]:
		var txt: String = line[0]
		var y: float = line[1]
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(-1 - glitch, y), txt, HORIZONTAL_ALIGNMENT_CENTER, W, 48, Color(K.RARE, 0.55 * k))
		draw_string(f, Vector2(1 + glitch, y), txt, HORIZONTAL_ALIGNMENT_CENTER, W, 48, Color(K.ACCENT, 0.55 * k))
		draw_string(f, Vector2(0, y), txt, HORIZONTAL_ALIGNMENT_CENTER, W, 48, Color(K.TEXT, k))
	K.scanlines(self, Rect2(30, ly - 40, 210, 92), Color(K.BG, 0.35))
	# divider + chinese title
	var dy := ly + 62
	draw_rect(Rect2(40, dy, 60, 1), Color(K.ACCENT, 0.6 * k))
	draw_rect(Rect2(170, dy, 60, 1), Color(K.ACCENT, 0.6 * k))
	draw_rect(Rect2(133, dy - 1, 4, 3), Color(K.ENERGY, k))
	K.text(self, Vector2(0, dy + 30), "虚空信号", Color(K.ACCENT, k), K.FS_TITLE, HORIZONTAL_ALIGNMENT_CENTER, W)
	K.text(self, Vector2(0, dy + 48), tr("TITLE_SUB"), Color(K.TEXT, 0.55 * k), K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, W)
	# blueprint ship (nose up), 5px cells
	var cx := 135.0
	var cy := 330.0
	var core: Vector2i = ship.core_cell()
	for c in ship.cells:
		var off := Vector2(c.y - core.y, -(c.x - core.x)) * 6
		var col := Color(ship.defs[ship.cells[c]["id"]]["color"])
		var r := Rect2(Vector2(cx, cy) + off - Vector2(2, 2), Vector2(5, 5))
		draw_rect(r, Color(col, 0.9 * k))
		draw_rect(Rect2(r.position, Vector2(5, 1)), Color(K.TEXT, 0.3 * k))
		if ship.cells[c]["id"] == "main_thruster":
			var fl := 3 + int(_t * 20) % 3
			draw_rect(Rect2(r.position + Vector2(1, 5), Vector2(3, fl)), Color(K.ENERGY, k))
			draw_rect(Rect2(r.position + Vector2(2, 5 + fl), Vector2(1, 2)), Color(K.DANGER, k))
	K.brackets(self, Rect2(cx - 26, cy - 26, 52, 56), 5, Color(K.ACCENT, 0.4 * k), 0)
	# press to start
	var pa := 1.0 if K.reduce_flash() else (0.55 + 0.45 * absf(sin(_t * 2.4)))
	if _leaving >= 0.0:
		pa = 1.0 if int(_leaving * 20) % 2 == 0 else 0.3
	var touch: bool = preload("res://scripts/ui/touch_controls.gd").should_enable()
	var ptxt := tr("TITLE_TAP" if touch else "TITLE_PRESS")
	var pw := K.text_width(ptxt) + 24
	var pr := Rect2(floorf((W - pw) / 2.0), 384, pw, 20)
	K.chamfer_fill(self, pr, 3, Color(K.ACCENT, 0.12 * pa))
	K.chamfer_line(self, pr, 3, Color(K.ACCENT, pa))
	K.icon(self, "play", pr.position + Vector2(7, 7), Color(K.ACCENT, pa))
	K.text(self, pr.position + Vector2(17, 14), ptxt, Color(K.TEXT, pa))
	K.text(self, Vector2(0, 440), tr("TITLE_LANG_TAP" if touch else "TITLE_LANG_HINT"), K.DIM, K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, W)
