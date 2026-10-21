extends Control
## Mobile touch layer: floating left stick (move), floating right stick (aim + auto-fire primary while held),
## DASH / OVERLOAD (hold) / SECONDARY (hold) / SWAP / BUILD / PAUSE buttons, and multi-finger control of the energy
## triangle. Finger 0 is also emulated as a mouse by Godot (input_devices/pointing/emulate_mouse_from_touch), which
## drives menus, the ship builder and the triangle; extra fingers on the triangle are forwarded here.
## All positions are logical viewport coordinates (270x480); the root viewport applies the stretch transform.
const K = preload("res://scripts/ui/ui_kit.gd")
const STICK_R := 22.0
const DEAD := 0.15
const IDLE_L := Vector2(62, 344)
const IDLE_R := Vector2(176, 344)

var battle: Node
var enabled := false
var insets := Vector4.ZERO # left, top, right, bottom (logical px)
var move_vec := Vector2.ZERO
var aim_vec := Vector2.UP
var overload_held := false
var secondary_held := false
var fingers := {} # index -> {"kind": String, "origin": Vector2, "pos": Vector2}
var max_concurrent := 0
var _dash_q := false
var _swap_q := false
var _t := 0.0

static func should_enable() -> bool:
	if GameManager.force_touch:
		return true
	var mode := str(SaveManager.settings.get("touch_controls", "auto"))
	if mode == "on":
		return true
	if mode == "off":
		return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("android") or OS.has_feature("ios")

func setup(b: Node) -> void:
	battle = b
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh()

func refresh() -> void:
	enabled = should_enable()
	visible = enabled
	_update_insets()
	if not enabled:
		release_all()

func _update_insets() -> void:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0:
		insets = Vector4.ZERO
		return
	var inv := get_viewport().get_final_transform().affine_inverse()
	var a: Vector2 = inv * Vector2(safe.position)
	var b: Vector2 = inv * Vector2(safe.end)
	var vs := get_viewport_rect().size
	insets = Vector4(clampf(a.x, 0, 40), clampf(a.y, 0, 60), clampf(vs.x - b.x, 0, 40), clampf(vs.y - b.y, 0, 60))

# ---- layout (kept clear of the top bar 0-40 and bottom HUD cards 404+) ----
func col_x() -> float:
	return 270.0 - insets.z - 32.0

func buttons() -> Dictionary:
	var x := col_x()
	var top := 42.0 + insets.y
	return {
		"pause": Rect2(270.0 - insets.z - 24.0, top, 20, 18),
		"build": Rect2(270.0 - insets.z - 48.0, top, 20, 18),
		"swap": Rect2(x, 256, 28, 22),
		"secondary": Rect2(x, 282, 28, 28),
		"overload": Rect2(x, 314, 28, 28),
		"dash": Rect2(x, 346, 28, 52),
	}

func left_zone() -> Rect2:
	return Rect2(insets.x, 170, 134.0 - insets.x, 232 - insets.w)

func right_zone() -> Rect2:
	return Rect2(136, 170, col_x() - 140.0, 232 - insets.w)

func aim_active() -> bool:
	for f in fingers.values():
		if f["kind"] == "aim":
			return true
	return false

func consume_dash() -> bool:
	var d := _dash_q
	_dash_q = false
	return d

func consume_swap() -> bool:
	var s := _swap_q
	_swap_q = false
	return s

func _input(event: InputEvent) -> void:
	if enabled and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		if handle(event):
			get_viewport().set_input_as_handled()

## Returns true when the touch was consumed by the touch layer.
func handle(event: InputEvent) -> bool:
	if not enabled:
		return false
	var idx: int = event.index
	var p: Vector2 = event.position
	if event is InputEventScreenTouch:
		if event.pressed:
			if get_tree().paused or battle.ended:
				return false
			for n in buttons():
				if buttons()[n].grow(3).has_point(p):
					fingers[idx] = {"kind": n, "origin": p, "pos": p}
					_press(n, true)
					_recount()
					return true
			var w: Control = battle.hud.widget if battle.hud else null
			if w and Rect2(w.global_position, w.size).has_point(p):
				if idx == 0:
					return false # emulated mouse drives the widget
				fingers[idx] = {"kind": "widget", "origin": p, "pos": p}
				_widget(p, true)
				_recount()
				return true
			if left_zone().has_point(p) and not _has_kind("move"):
				fingers[idx] = {"kind": "move", "origin": p, "pos": p}
			elif right_zone().has_point(p) and not _has_kind("aim"):
				fingers[idx] = {"kind": "aim", "origin": p, "pos": p}
			else:
				return false
			_recount()
			_recompute()
			return true
		if fingers.has(idx):
			var kind: String = fingers[idx]["kind"]
			fingers.erase(idx)
			if kind == "widget":
				battle.hud.widget.dragging = false
			elif kind in ["overload", "secondary"]:
				_press(kind, false)
			_recompute()
			return true
		return false
	if event is InputEventScreenDrag and fingers.has(idx):
		var f: Dictionary = fingers[idx]
		f["pos"] = p
		if f["kind"] == "widget":
			_widget(p, false)
		elif f["kind"] in ["move", "aim"]:
			var d: Vector2 = p - f["origin"]
			if d.length() > STICK_R: # floating base follows the thumb
				f["origin"] = p - d.normalized() * STICK_R
		_recompute()
		return true
	return false

func release_all() -> void:
	if battle and battle.hud and battle.hud.widget:
		battle.hud.widget.dragging = false
	fingers.clear()
	overload_held = false
	secondary_held = false
	_recompute()

func _has_kind(k: String) -> bool:
	for f in fingers.values():
		if f["kind"] == k:
			return true
	return false

func _recount() -> void:
	max_concurrent = maxi(max_concurrent, fingers.size())

func _recompute() -> void:
	move_vec = Vector2.ZERO
	for f in fingers.values():
		var v: Vector2 = (f["pos"] - f["origin"]) / STICK_R
		v = v.limit_length(1.0)
		if f["kind"] == "move":
			move_vec = v if v.length() > DEAD else Vector2.ZERO
		elif f["kind"] == "aim" and v.length() > DEAD * 1.5:
			aim_vec = v.normalized()

func _press(n: String, down: bool) -> void:
	match n:
		"dash":
			if down:
				_dash_q = true
		"swap":
			if down:
				_swap_q = true
		"overload":
			overload_held = down
		"secondary":
			secondary_held = down
		"pause":
			if down:
				release_all()
				battle._toggle_pause()
		"build":
			if down:
				release_all()
				battle.toggle_builder()

func _widget(p: Vector2, down: bool) -> void:
	var w: Control = battle.hud.widget
	var local := p - w.global_position
	if down:
		for i in 4:
			if w.chip_rect(i).grow(1).has_point(local):
				w.core.apply_preset(w.PRESETS[i])
				return
	w.dragging = true
	w.core.set_weights(w.weights_for(local))

func _process(delta: float) -> void:
	_t += delta
	if enabled:
		queue_redraw()

func _draw() -> void:
	if not enabled or (battle and (battle.ended or battle.builder.visible)):
		return
	var paused := get_tree().paused
	if paused:
		return
	_draw_stick("move", IDLE_L, K.ACCENT, tr("TOUCH_MOVE"))
	_draw_stick("aim", IDLE_R, K.DANGER, tr("TOUCH_AIM"))
	var held := {}
	for f in fingers.values():
		held[f["kind"]] = true
	var bs := buttons()
	var sec: RefCounted = battle.player.selected_secondary() if battle and battle.player else null
	var spec := {
		"pause": ["", K.TEXT], "build": ["build", K.TEXT], "swap": ["restart", K.TEXT],
		"secondary": [sec.id if sec else "module", K.DANGER], "overload": ["core", K.ENERGY], "dash": ["dash", K.ACCENT]}
	for n in bs:
		var r: Rect2 = bs[n]
		var col: Color = spec[n][1]
		var on: bool = held.has(n) or (n == "overload" and battle.player.energy.overload_active)
		K.chamfer_fill(self, r, 3, Color(col, 0.28) if on else Color(K.BG, 0.55))
		K.chamfer_line(self, r, 3, Color(col, 0.95 if on else 0.45))
		var ic := r.position + Vector2(floorf((r.size.x - 7) / 2.0), floorf((r.size.y - 7) / 2.0))
		if n == "pause":
			draw_rect(Rect2(ic + Vector2(1, 0), Vector2(2, 7)), Color(col, 0.9))
			draw_rect(Rect2(ic + Vector2(4, 0), Vector2(2, 7)), Color(col, 0.9))
		elif n == "dash":
			K.icon(self, "dash", r.position + Vector2(11, 12), col, 1)
			var dl := tr("TOUCH_DASH")
			K.text(self, Vector2(r.position.x, r.position.y + 38), dl, Color(col, 0.9), K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			var cd: float = battle.player.dash_cd
			if cd > 0.0:
				K.gauge(self, Rect2(r.position.x + 4, r.end.y - 6, r.size.x - 8, 2), 1.0 - cd / 1.2, col)
		else:
			K.icon(self, spec[n][0], ic, Color(col, 0.95))
		if n == "overload":
			K.gauge(self, Rect2(r.position.x + 4, r.end.y - 5, r.size.x - 8, 2), battle.player.energy.heat_ratio(), K.ENERGY)

func _draw_stick(kind: String, idle: Vector2, col: Color, label: String) -> void:
	var f: Dictionary = {}
	for x in fingers.values():
		if x["kind"] == kind:
			f = x
	if f.is_empty():
		# idle affordance: dotted ring + caption so players know where to put a thumb
		K.ring(self, idle, STICK_R, 1.0, Color(col, 0.16))
		draw_rect(Rect2(idle - Vector2(1, 1), Vector2(3, 3)), Color(col, 0.25))
		K.text(self, Vector2(idle.x - 40, idle.y + STICK_R + 14), label, Color(K.TEXT, 0.28), K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, 80)
		return
	var o: Vector2 = f["origin"].round()
	var p: Vector2 = (o + (f["pos"] - f["origin"]).limit_length(STICK_R)).round()
	draw_circle(o, STICK_R, Color(K.BG, 0.35))
	K.ring(self, o, STICK_R, 1.0, Color(col, 0.55))
	K.brackets(self, Rect2(o - Vector2(STICK_R + 3, STICK_R + 3), Vector2(STICK_R * 2 + 6, STICK_R * 2 + 6)), 4, Color(col, 0.35))
	draw_line(o, p, Color(col, 0.35), 1.0)
	draw_rect(Rect2(p - Vector2(6, 6), Vector2(13, 13)), Color(col, 0.25))
	draw_rect(Rect2(p - Vector2(4, 4), Vector2(9, 9)), K.BG)
	draw_rect(Rect2(p - Vector2(3, 3), Vector2(7, 7)), col)
	if kind == "aim" and int(_t * 10) % 2 == 0 or (kind == "aim" and K.reduce_flash()):
		K.text(self, Vector2(o.x - 30, o.y - STICK_R - 6), tr("TOUCH_FIRE"), Color(col, 0.8), K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, 60)
