extends Control
## Holographic modal panel (pause / victory / game over). Animated reveal, icon buttons, styled switches,
## optional results breakdown with tick-up counters and a rank grade. Works while the tree is paused.
const K = preload("res://scripts/ui/ui_kit.gd")
const PixelButton = preload("res://scripts/ui/pixel_button.gd")
signal chosen(action: String)
## actions: Array of [key, label, glyph, is_switch(bool), on(bool)]
var title := ""
var sub := ""
var accent := K.ACCENT
var results: Array = [] # [glyph, label, value(float), format(String)]
var grade := ""
var box: VBoxContainer
var panel_rect := Rect2()
var _t := 0.0
var _buttons: Array = []
const OPEN_TIME := 0.24
const TICK_TIME := 1.1

func build(t: String, s: String, actions: Array, res: Array = [], col: Color = K.ACCENT, grade_text := "") -> void:
	title = t
	sub = s
	results = res
	accent = col
	grade = grade_text
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var h := 64 + actions.size() * 24 + (results.size() * 16 + 18 if results.size() > 0 else 0)
	var vs := get_viewport_rect().size
	panel_rect = Rect2(floorf((vs.x - 222.0) / 2.0), floorf((vs.y - h) / 2.0), 222, h)
	theme = Loc.ui_theme # CanvasLayer breaks theme propagation from the root window
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.position = Vector2(panel_rect.position.x + 14, panel_rect.end.y - 14 - actions.size() * 24 + 4)
	box.size = Vector2(panel_rect.size.x - 28, actions.size() * 24)
	add_child(box)
	for a in actions:
		var b: Button = PixelButton.new()
		box.add_child(b)
		b.setup(a[1], a[2], a.size() > 3 and a[3], a.size() > 4 and a[4])
		var key: String = a[0]
		b.pressed.connect(func() -> void: chosen.emit(key))
		b.modulate.a = 0.0
		_buttons.append(b)

func focus_first() -> void:
	if _buttons.size() > 0:
		_buttons[0].grab_focus()

func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.001)
	for i in _buttons.size():
		var k := K.ease_out_cubic((_t - OPEN_TIME - i * 0.05) / 0.15)
		_buttons[i].modulate.a = k
		_buttons[i].position.x = floorf((1.0 - k) * 8.0)
	queue_redraw()

func _draw() -> void:
	var k := K.ease_out_cubic(_t / OPEN_TIME)
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(K.BG, 0.72 * k))
	K.scanlines(self, Rect2(Vector2.ZERO, get_viewport_rect().size), Color(K.BG, 0.25 * k), 2)
	# reveal: panel grows from a horizontal line
	var c := panel_rect.get_center()
	var hh := maxf(2.0, floorf(panel_rect.size.y * k / 2.0))
	var r := Rect2(panel_rect.position.x, c.y - hh, panel_rect.size.x, hh * 2.0)
	K.panel(self, r, accent, 0.94)
	if k < 0.98:
		draw_rect(Rect2(r.position.x, c.y, r.size.x, 1), Color(K.TEXT, 0.8 * (1.0 - k)))
		return
	var x0 := panel_rect.position.x
	var y := panel_rect.position.y
	# header strip
	draw_rect(Rect2(x0 + 6, y + 6, panel_rect.size.x - 12, 1), Color(accent, 0.35))
	K.text(self, Vector2(x0, y + 30), title, accent, K.FS_TITLE, HORIZONTAL_ALIGNMENT_CENTER, panel_rect.size.x)
	K.text(self, Vector2(x0, y + 46), sub, K.DIM, K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, panel_rect.size.x)
	draw_rect(Rect2(x0 + 14, y + 53, panel_rect.size.x - 28, 1), Color(accent, 0.25))
	if results.size() > 0:
		var tick := K.ease_out_cubic((_t - OPEN_TIME) / TICK_TIME)
		var ry := y + 62
		for i in results.size():
			var row: Array = results[i]
			var rk := clampf(tick * results.size() - i * 0.6, 0.0, 1.0)
			var val: float = float(row[2]) * rk
			K.icon(self, row[0], Vector2(x0 + 16, ry + 3), Color(accent, 0.9))
			K.text(self, Vector2(x0 + 28, ry + 10), row[1], K.TEXT)
			var vs: String = str(row[3]) % val if str(row[3]).find("%") >= 0 else str(row[3])
			K.text(self, Vector2(x0, ry + 10), vs, K.ENERGY if rk < 1.0 else K.TEXT, K.FS_BODY, HORIZONTAL_ALIGNMENT_RIGHT, panel_rect.size.x - 16)
			draw_rect(Rect2(x0 + 16, ry + 13, panel_rect.size.x - 32, 1), Color(K.TEXT, 0.06))
			ry += 16
		if grade != "" and tick >= 1.0:
			var gx := x0 + panel_rect.size.x - 40
			K.text_outline(self, Vector2(gx, y + 30), grade, K.ENERGY, K.BG, K.FS_TITLE)
