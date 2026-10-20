extends Control
## Reusable centered panel with title + buttons. Used for pause / game over / victory.
signal chosen(action: String)
var title_label: Label
var sub_label: Label
var box: VBoxContainer

func build(title: String, sub: String, actions: Array) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(Pixel.C_BG, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	box = VBoxContainer.new()
	box.position = Vector2(170, 80)
	box.size = Vector2(140, 110)
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	title_label = _label(title, 16, Pixel.C_CYAN)
	sub_label = _label(sub, 8, Pixel.C_WHITE)
	for a in actions:
		var b := Button.new()
		b.text = a
		b.add_theme_font_size_override("font_size", 8)
		b.pressed.connect(func() -> void: chosen.emit(a))
		box.add_child(b)

func _label(t: String, s: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", s)
	l.add_theme_color_override("font_color", c)
	box.add_child(l)
	return l

func focus_first() -> void:
	for c in box.get_children():
		if c is Button:
			c.grab_focus()
			return
