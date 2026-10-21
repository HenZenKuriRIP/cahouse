extends Control
## WEAPON / SHIELD / ENGINE triangle. Drag the point (mouse) or use hotkeys 1-4 / Z X C, gamepad D-pad / X B R3.
const PixelLib = preload("res://scripts/pixel.gd")
var core: RefCounted # EnergyCore
var dragging := false
var font: Font
const SIZE := Vector2(54, 48)

func _ready() -> void:
	font = ThemeDB.fallback_font
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP

func verts() -> PackedVector2Array:
	# weapon (top), shield (bottom-left), engine (bottom-right)
	return PackedVector2Array([Vector2(27, 8), Vector2(5, 42), Vector2(49, 42)])

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

func _gui_input(event: InputEvent) -> void:
	if core == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging:
			core.set_weights(weights_for(event.position))
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		core.set_weights(weights_for(event.position))
		accept_event()

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	if core == null:
		return
	var v := verts()
	draw_colored_polygon(v, Color(PixelLib.C_PANEL, 0.85))
	var hot: bool = core.overload_active
	var edge := PixelLib.C_RED if hot else PixelLib.C_CYAN
	draw_polyline(v + PackedVector2Array([v[0]]), edge, 1.0)
	draw_string(font, v[0] + Vector2(-6, 0), tr("EN_W"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelLib.C_RED)
	draw_string(font, v[1] + Vector2(-10, 4), tr("EN_S"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelLib.C_CYAN)
	draw_string(font, v[2] + Vector2(1, 4), tr("EN_E"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelLib.C_GOLD)
	var tp := point_for(core.target).floor()
	var cp := point_for(core.current).floor()
	draw_rect(Rect2(tp - Vector2(1, 1), Vector2(3, 3)), Color(PixelLib.C_WHITE, 0.4))
	draw_rect(Rect2(cp - Vector2(2, 2), Vector2(4, 4)), PixelLib.C_GOLD if hot else PixelLib.C_WHITE)
	draw_string(font, Vector2(-20, -1), tr("PRESET_" + core.preset_name), HORIZONTAL_ALIGNMENT_CENTER, 94, 12, PixelLib.C_WHITE)
