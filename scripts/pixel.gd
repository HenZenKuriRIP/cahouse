class_name Pixel
## Helpers to draw original pixel-art sprites procedurally from string masks.
const C_BG := Color("#080C18")
const C_PANEL := Color("#10182B")
const C_CYAN := Color("#49E6D4")
const C_RED := Color("#FF5268")
const C_GOLD := Color("#FFCC66")
const C_VIOLET := Color("#A78BFA")
const C_WHITE := Color("#EAF4FF")

## mask: rows of chars; '.' = empty; other chars mapped through palette dict. Drawn centered.
static func draw_mask(ci: CanvasItem, mask: PackedStringArray, palette: Dictionary, tint: Color = Color.WHITE) -> void:
	var h := mask.size()
	var w := mask[0].length()
	var ox := -w / 2.0
	var oy := -h / 2.0
	for y in h:
		var row := mask[y]
		for x in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			var c: Color = palette.get(ch, C_WHITE)
			ci.draw_rect(Rect2(ox + x, oy + y, 1, 1), c * tint)
