extends Button
## Chamfered pixel button with glyph icon; optional switch (toggle) drawn as a pixel slider on the right.
## Focus (gamepad/keyboard) shows corner brackets + a moving caret.
const K = preload("res://scripts/ui/ui_kit.gd")
var glyph := ""
var is_switch := false
var switch_on := false
var _hover_t := 0.0

func setup(label: String, glyph_name: String, switch := false, on := false) -> void:
	text = label
	glyph = glyph_name
	is_switch = switch
	switch_on = on
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(0, 20)
	focus_mode = Control.FOCUS_ALL
	add_theme_constant_override("h_separation", 0)
	mouse_entered.connect(func() -> void: grab_focus())
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var sb: StyleBox = get_theme_stylebox(st).duplicate()
		sb.content_margin_left = 20
		sb.content_margin_right = 32 if is_switch else 10
		add_theme_stylebox_override(st, sb)

func _process(delta: float) -> void:
	var target := 1.0 if (has_focus() or is_hovered()) else 0.0
	_hover_t = move_toward(_hover_t, target, delta * 8.0)
	queue_redraw()

func _draw() -> void:
	var active := has_focus() or is_hovered()
	var col := K.ACCENT if active else K.TEXT
	if disabled:
		col = K.DIM
	# glyph slot
	var gy := floorf((size.y - 7) / 2.0)
	draw_rect(Rect2(4, gy - 2, 11, 11), Color(K.BG, 0.6))
	K.icon(self, glyph, Vector2(6, gy), col)
	if active:
		var off := floorf(_hover_t * 2.0)
		K.brackets(self, Rect2(Vector2.ZERO, size), 4, K.TEXT, 1)
		draw_rect(Rect2(size.x - 6 - (24 if is_switch else 0) - off, gy + 2, 2, 3), K.ACCENT)
	if is_switch:
		var sw := Rect2(size.x - 26, floorf(size.y / 2.0) - 4, 20, 8)
		draw_rect(sw, Color(K.BG, 0.9))
		draw_rect(sw.grow(-1), Color(K.ACCENT, 0.35) if switch_on else Color(K.TEXT, 0.12))
		var knob_x := sw.position.x + (12.0 if switch_on else 1.0)
		draw_rect(Rect2(knob_x, sw.position.y + 1, 7, 6), K.ACCENT if switch_on else K.DIM)
