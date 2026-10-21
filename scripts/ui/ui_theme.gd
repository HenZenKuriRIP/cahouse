extends RefCounted
## Builds the global Theme in code: procedurally generated 9-slice pixel frames (StyleBoxTexture),
## chamfered corners, 1px inner highlight, corner brackets on focus (gamepad), pixel font defaults.
const K = preload("res://scripts/ui/ui_kit.gd")

## 16x16 frame image, 5px chamfer-safe 9-slice margins.
static func frame_image(fill: Color, border: Color, highlight: Color, focus := false) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cut := 3
	for y in 16:
		for x in 16:
			var dx := mini(x, 15 - x)
			var dy := mini(y, 15 - y)
			if dx + dy < cut:
				continue
			var edge := dx == 0 or dy == 0 or dx + dy == cut
			img.set_pixel(x, y, border if edge else fill)
	for x in range(cut + 1, 16 - cut - 1):
		img.set_pixel(x, 1, highlight)
	if focus:
		# outer brackets drawn inside the slice corners
		for i in 3:
			img.set_pixel(i + 1, 0, K.TEXT)
			img.set_pixel(0, i + 1, K.TEXT)
			img.set_pixel(14 - i, 15, K.TEXT)
			img.set_pixel(15, 14 - i, K.TEXT)
	return img

static func stylebox(fill: Color, border: Color, highlight: Color, focus := false, shift := 0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(frame_image(fill, border, highlight, focus))
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_texture_margin(side, 5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3 + shift
	sb.content_margin_bottom = 3 - shift
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb

static func icon_texture(name: String, col: Color) -> ImageTexture:
	var m: Array = K.ICONS.get(name, K.ICONS["module"])
	var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 7:
		for x in 7:
			if m[y][x] == "#":
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

static func build(font: Font) -> Theme:
	var t := Theme.new()
	if font:
		t.default_font = font
	t.default_font_size = K.FS_BODY
	var normal := stylebox(Color(K.BG2, 0.92), Color(K.ACCENT, 0.45), Color(K.TEXT, 0.08))
	var hover := stylebox(Color(K.ACCENT, 0.16), Color(K.ACCENT, 0.9), Color(K.TEXT, 0.18))
	var pressed := stylebox(Color(K.ACCENT, 0.30), K.ACCENT, Color(K.BG, 0.4), false, 1)
	var disabled := stylebox(Color(K.BG2, 0.6), Color(K.TEXT, 0.15), Color(0, 0, 0, 0))
	var focus := stylebox(Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), true)
	for c in ["Button"]:
		t.set_stylebox("normal", c, normal)
		t.set_stylebox("hover", c, hover)
		t.set_stylebox("pressed", c, pressed)
		t.set_stylebox("hover_pressed", c, pressed)
		t.set_stylebox("disabled", c, disabled)
		t.set_stylebox("focus", c, focus)
		t.set_color("font_color", c, K.TEXT)
		t.set_color("font_hover_color", c, K.ACCENT)
		t.set_color("font_pressed_color", c, K.TEXT)
		t.set_color("font_hover_pressed_color", c, K.TEXT)
		t.set_color("font_focus_color", c, K.ACCENT)
		t.set_color("font_disabled_color", c, K.DIM)
		t.set_color("icon_normal_color", c, K.TEXT)
		t.set_color("icon_hover_color", c, K.ACCENT)
		t.set_color("icon_focus_color", c, K.ACCENT)
		t.set_constant("h_separation", c, 6)
	t.set_stylebox("panel", "Panel", stylebox(Color(K.BG2, 0.9), Color(K.ACCENT, 0.5), Color(K.TEXT, 0.08)))
	t.set_color("font_color", "Label", K.TEXT)
	t.set_color("font_shadow_color", "Label", Color(K.BG, 0.85))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	return t
