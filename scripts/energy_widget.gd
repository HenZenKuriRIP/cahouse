extends Control
## Energy triangle (WEAPON top / SHIELD bottom-left / ENGINE bottom-right). Drag handle with mouse;
## presets 1-4 (chips), Z/X/C nudges, gamepad D-pad / X B R3. The triangle outline doubles as the CORE HEAT
## gauge (fills from bottom-left over the top to bottom-right); colours shift normal → overload → critical.
const K = preload("res://scripts/ui/ui_kit.gd")
var core: RefCounted
var dragging := false
var _t := 0.0
const SIZE := Vector2(68, 68)
const PRESETS := ["ASSAULT", "DEFENSE", "ESCAPE", "BALANCED"]

func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP

func verts() -> PackedVector2Array:
	return PackedVector2Array([Vector2(34, 13), Vector2(8, 55), Vector2(60, 55)])

func point_for(w: Vector3) -> Vector2:
	var v := verts()
	return v[0] * w.x + v[1] * w.y + v[2] * w.z

func weights_for(p: Vector2) -> Vector3:
	var v := verts()
	var d := (v[1].y - v[2].y) * (v[0].x - v[2].x) + (v[2].x - v[1].x) * (v[0].y - v[2].y)
	var a := ((v[1].y - v[2].y) * (p.x - v[2].x) + (v[2].x - v[1].x) * (p.y - v[2].y)) / d
	var b := ((v[2].y - v[0].y) * (p.x - v[2].x) + (v[0].x - v[2].x) * (p.y - v[2].y)) / d
	var c := 1.0 - a - b
	return Vector3(maxf(a, 0.0), maxf(b, 0.0), maxf(c, 0.0))

func chip_rect(i: int) -> Rect2:
	return Rect2(4 + i * 15, 60, 14, 6)

func _gui_input(event: InputEvent) -> void:
	if core == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for i in 4:
				if chip_rect(i).grow(1).has_point(event.position):
					core.apply_preset(PRESETS[i])
					accept_event()
					return
		dragging = event.pressed
		if dragging:
			core.set_weights(weights_for(event.position))
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		core.set_weights(weights_for(event.position))
		accept_event()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

## Plot a 1px line pixel by pixel (no AA), returning the points for gauge colouring.
func _line_pts(a: Vector2, b: Vector2) -> Array:
	var pts: Array = []
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for i in n + 1:
		pts.append(a.lerp(b, float(i) / maxf(1, n)).round())
	return pts

func _draw() -> void:
	if core == null:
		return
	var v := verts()
	var hot: bool = core.overload_active
	var crit: bool = core.is_warning()
	var heat: float = core.heat_ratio()
	# backdrop plate
	K.chamfer_fill(self, Rect2(0, 0, 68, 68), 4, Color(K.BG, 0.82))
	K.chamfer_line(self, Rect2(0, 0, 68, 68), 4, Color(K.ACCENT, 0.25))
	# gradient fill (weapon=danger, shield=accent, engine=energy)
	draw_polygon(v, PackedColorArray([Color(K.DANGER, 0.30), Color(K.ACCENT, 0.30), Color(K.ENERGY, 0.30)]))
	K.scanlines(self, Rect2(8, 13, 53, 43), Color(K.BG, 0.25))
	# outline = heat gauge: BL -> top -> BR (lit portion), base edge always dim
	var path: Array = _line_pts(v[1], v[0]) + _line_pts(v[0], v[2])
	var lit := int(heat * path.size())
	var hcol := K.ACCENT
	if crit:
		hcol = K.DANGER if (K.reduce_flash() or int(_t * 6) % 2 == 0) else Color(K.DANGER, 0.5)
	elif hot:
		hcol = K.ENERGY
	for i in path.size():
		draw_rect(Rect2(path[i], Vector2.ONE), hcol if i < lit else Color(K.TEXT, 0.25))
	for p in _line_pts(v[1], v[2]):
		draw_rect(Rect2(p, Vector2.ONE), Color(K.TEXT, 0.25))
	# vertex glyph labels
	K.text(self, Vector2(40, 22), tr("EN_W"), K.DANGER)
	K.text(self, Vector2(0, 56), tr("EN_S"), K.ACCENT)
	K.text(self, Vector2(56, 56), tr("EN_E"), K.ENERGY)
	# target ghost + live handle with glow
	var tp := point_for(core.target).round()
	var cp := point_for(core.current).round()
	draw_rect(Rect2(tp - Vector2(1, 1), Vector2(3, 3)), Color(K.TEXT, 0.35))
	var hc := K.ENERGY if hot else K.TEXT
	draw_rect(Rect2(cp - Vector2(4, 4), Vector2(9, 9)), Color(hc, 0.10))
	draw_rect(Rect2(cp - Vector2(3, 3), Vector2(7, 7)), Color(hc, 0.20))
	draw_rect(Rect2(cp - Vector2(2, 2), Vector2(5, 5)), K.BG)
	draw_rect(Rect2(cp - Vector2(1, 1), Vector2(3, 3)), hc)
	# preset chips
	for i in 4:
		var r := chip_rect(i)
		var active: bool = core.preset_name == PRESETS[i]
		var cols := [K.DANGER, K.ACCENT, K.ENERGY, K.TEXT]
		draw_rect(r, Color(cols[i], 0.85 if active else 0.18))
		if active:
			draw_rect(Rect2(r.position + Vector2(0, -2), Vector2(r.size.x, 1)), cols[i])
	# preset name above
	K.text(self, Vector2(0, 9), tr("PRESET_" + core.preset_name), K.TEXT if not hot else K.ENERGY, K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, 68)
