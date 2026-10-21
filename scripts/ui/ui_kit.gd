extends RefCounted
## VOID SIGNAL UI kit — RETRO-FUTURISTIC PIXEL INTERFACE.
## Pure drawing helpers on any CanvasItem, all coordinates snapped to the pixel grid.
## Palette is strict: BG, BG2, ACCENT, DANGER, ENERGY, RARE, TEXT (+ alpha variants only).
const BG := Color("#080C18")
const BG2 := Color("#10182B")
const ACCENT := Color("#49E6D4")
const DANGER := Color("#FF5268")
const ENERGY := Color("#FFCC66")
const RARE := Color("#A78BFA")
const TEXT := Color("#EAF4FF")
const DIM := Color(0.918, 0.957, 1.0, 0.45) # TEXT @45%
const LINE := Color(0.286, 0.902, 0.831, 0.35) # ACCENT @35%

## Typography scale (Fusion Pixel 12px is the native grid; 24 = 2x for display titles)
const FS_BODY := 12
const FS_TITLE := 24

## 7x7 pixel glyph icons. '#' = pixel.
const ICONS := {
	"hull": [".#####.", "#.....#", "#.###.#", "#.###.#", "#..#..#", ".#...#.", "..###.."],
	"shield": ["..###..", ".#...#.", "#..#..#", "#.###.#", "#..#..#", ".#...#.", "..###.."],
	"dash": ["#..#...", ".#..#..", "..#..#.", "...#..#", "..#..#.", ".#..#..", "#..#..."],
	"core": ["...#...", "..###..", ".##.##.", "###.###", ".##.##.", "..###..", "...#..."],
	"pulse_cannon": [".......", "##.....", "#######", "#######", "##.....", ".......", "......."],
	"missile_swarm": ["....#..", "...###.", "...###.", "...###.", "..#####", "...#.#.", "..#...#"],
	"gravity_bomb": ["..###..", ".#...#.", "#..#..#", "#.#.#.#", "#..#..#", ".#...#.", "..###.."],
	"emp_launcher": ["...##..", "..##...", ".####..", "..###..", "...##..", "..##...", ".##...."],
	"play": [".#.....", ".##....", ".###...", ".####..", ".###...", ".##....", ".#....."],
	"restart": ["..###..", ".#...#.", "#.....#", "#...###", "#....#.", ".#...#.", "..###.."],
	"quit": ["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", ".#...#.", "#.....#"],
	"lang": ["..###..", ".#.#.#.", "#######", "#..#..#", "#######", ".#.#.#.", "..###.."],
	"flash": ["...##..", "..##...", ".####..", "...##..", "..##...", ".##....", "#......"],
	"kills": ["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", ".#...#.", "#.....#"],
	"scrap": ["..#....", ".###...", "#####..", ".###.#.", "..#.###", "....#..", "......."],
	"distance": ["...#...", "..###..", ".#####.", "...#...", "...#...", "...#...", "...#..."],
	"time": ["..###..", ".#.#.#.", "#..#..#", "#..##.#", "#.....#", ".#...#.", "..###.."],
	"warning": ["...#...", "..#.#..", "..#.#..", ".#.#.#.", ".#...#.", "#..#..#", "#######"],
	"build": ["#.#.#.#", ".......", "#.###.#", "..#.#..", "#.###.#", ".......", "#.#.#.#"],
	"synergy": ["#.....#", ".#...#.", "..###..", "..#.#..", "..###..", ".#...#.", "#.....#"],
	"module": ["#######", "#.....#", "#.###.#", "#.#.#.#", "#.###.#", "#.....#", "#######"],
}

static func px(v: Vector2) -> Vector2:
	return v.floor()

static func icon(ci: CanvasItem, name: String, pos: Vector2, col: Color, scale := 1) -> void:
	var m: Array = ICONS.get(name, ICONS["module"])
	for y in m.size():
		var row: String = m[y]
		for x in row.length():
			if row[x] == "#":
				ci.draw_rect(Rect2(px(pos) + Vector2(x, y) * scale, Vector2(scale, scale)), col)

## Chamfered polygon (cut = corner cut in px). Fill only.
static func chamfer_poly(r: Rect2, cut: float) -> PackedVector2Array:
	r = Rect2(px(r.position), r.size.floor())
	var a := r.position
	var b := r.end
	return PackedVector2Array([a + Vector2(cut, 0), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut), Vector2(b.x, b.y - cut),
		Vector2(b.x - cut, b.y), Vector2(a.x + cut, b.y), Vector2(a.x, b.y - cut), Vector2(a.x, a.y + cut)])

static func chamfer_fill(ci: CanvasItem, r: Rect2, cut: float, col: Color) -> void:
	if r.size.x <= cut * 2.0 + 1.0 or r.size.y <= cut * 2.0 + 1.0:
		ci.draw_rect(Rect2(px(r.position), r.size.floor()), col)
		return
	ci.draw_colored_polygon(chamfer_poly(r, cut), col)

## 1px chamfered outline drawn with rects (pixel exact, no AA).
static func chamfer_line(ci: CanvasItem, r: Rect2, cut: int, col: Color) -> void:
	var x0 := int(r.position.x)
	var y0 := int(r.position.y)
	var x1 := int(r.end.x) - 1
	var y1 := int(r.end.y) - 1
	ci.draw_rect(Rect2(x0 + cut, y0, x1 - x0 - 2 * cut + 1, 1), col)
	ci.draw_rect(Rect2(x0 + cut, y1, x1 - x0 - 2 * cut + 1, 1), col)
	ci.draw_rect(Rect2(x0, y0 + cut, 1, y1 - y0 - 2 * cut + 1), col)
	ci.draw_rect(Rect2(x1, y0 + cut, 1, y1 - y0 - 2 * cut + 1), col)
	for i in cut:
		ci.draw_rect(Rect2(x0 + cut - 1 - i, y0 + 1 + i, 1, 1), col)
		ci.draw_rect(Rect2(x1 - cut + 1 + i, y0 + 1 + i, 1, 1), col)
		ci.draw_rect(Rect2(x0 + cut - 1 - i, y1 - 1 - i, 1, 1), col)
		ci.draw_rect(Rect2(x1 - cut + 1 + i, y1 - 1 - i, 1, 1), col)

## Corner brackets (tactical framing).
static func brackets(ci: CanvasItem, r: Rect2, l: int, col: Color, gap := 0) -> void:
	var a := px(r.position) - Vector2(gap, gap)
	var b := px(r.end) + Vector2(gap - 1, gap - 1)
	for c in [[a, Vector2(1, 1)], [Vector2(b.x, a.y), Vector2(-1, 1)], [Vector2(a.x, b.y), Vector2(1, -1)], [b, Vector2(-1, -1)]]:
		var p: Vector2 = c[0]
		var d: Vector2 = c[1]
		ci.draw_rect(Rect2(Vector2(minf(p.x, p.x + d.x * (l - 1)), p.y), Vector2(l, 1)), col)
		ci.draw_rect(Rect2(Vector2(p.x, minf(p.y, p.y + d.y * (l - 1))), Vector2(1, l)), col)

static func scanlines(ci: CanvasItem, r: Rect2, col: Color, step := 2) -> void:
	var y := int(r.position.y)
	while y < int(r.end.y):
		ci.draw_rect(Rect2(r.position.x, y, r.size.x, 1), col)
		y += step

## Standard holographic panel: chamfer fill + scanlines + 1px inner highlight + accent frame + brackets.
static func panel(ci: CanvasItem, r: Rect2, accent: Color = ACCENT, alpha := 0.88, cut := 4, with_brackets := true) -> void:
	chamfer_fill(ci, r, cut, Color(BG2, alpha))
	scanlines(ci, r.grow(-2), Color(accent, 0.035))
	ci.draw_rect(Rect2(px(r.position) + Vector2(cut, 1), Vector2(r.size.x - cut * 2, 1)), Color(TEXT, 0.10)) # inner highlight
	chamfer_line(ci, r, cut, Color(accent, 0.55))
	if with_brackets:
		brackets(ci, r, 5, accent, 2)

## Segmented bar with chip-damage trail. Returns nothing; trail >= frac shows recent loss.
static func seg_bar(ci: CanvasItem, pos: Vector2, segs: int, seg_w: int, h: int, frac: float, col: Color, trail := -1.0, gap := 1) -> void:
	pos = px(pos)
	var total := segs * seg_w + (segs - 1) * gap
	ci.draw_rect(Rect2(pos - Vector2(1, 1), Vector2(total + 2, h + 2)), Color(BG, 0.9))
	var fill_px := clampf(frac, 0.0, 1.0) * segs
	var trail_px := clampf(trail, 0.0, 1.0) * segs
	for i in segs:
		var r := Rect2(pos + Vector2(i * (seg_w + gap), 0), Vector2(seg_w, h))
		if i < int(fill_px):
			ci.draw_rect(r, col)
			ci.draw_rect(Rect2(r.position, Vector2(seg_w, 1)), col.lightened(0.35))
		elif i < fill_px:
			var part := floorf((fill_px - i) * seg_w)
			ci.draw_rect(Rect2(r.position, Vector2(part, h)), col)
			ci.draw_rect(Rect2(r.position + Vector2(part, 0), Vector2(seg_w - part, h)), Color(col, 0.18))
		elif trail >= 0.0 and i < trail_px:
			ci.draw_rect(r, Color(TEXT, 0.75))
		else:
			ci.draw_rect(r, Color(col, 0.14))

## Thin continuous gauge (heat etc.)
static func gauge(ci: CanvasItem, r: Rect2, frac: float, col: Color) -> void:
	r = Rect2(px(r.position), r.size.floor())
	ci.draw_rect(r.grow(1), Color(BG, 0.9))
	ci.draw_rect(r, Color(col, 0.15))
	ci.draw_rect(Rect2(r.position, Vector2(floorf(r.size.x * clampf(frac, 0, 1)), r.size.y)), col)

## Pixel ring: plots square pixels along a circle for `frac` of the circumference (starting at top, clockwise).
static func ring(ci: CanvasItem, c: Vector2, radius: float, frac: float, col: Color, back: Color = Color(0, 0, 0, 0)) -> void:
	var n := maxi(12, int(TAU * radius))
	for i in n:
		var t := float(i) / n
		var a := -PI / 2.0 + t * TAU
		var p := px(c + Vector2(cos(a), sin(a)) * radius)
		if t <= frac:
			ci.draw_rect(Rect2(p, Vector2.ONE), col)
		elif back.a > 0.0:
			ci.draw_rect(Rect2(p, Vector2.ONE), back)

## Text with 1px drop shadow (pixel legibility on busy backgrounds).
static func text(ci: CanvasItem, pos: Vector2, s: String, col: Color, size := FS_BODY, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	var f := ThemeDB.fallback_font
	ci.draw_string(f, px(pos) + Vector2(1, 1), s, align, w, size, Color(BG, 0.85 * col.a))
	ci.draw_string(f, px(pos), s, align, w, size, col)

## Text with full 1px outline (float numbers / logo).
static func text_outline(ci: CanvasItem, pos: Vector2, s: String, col: Color, outline: Color, size := FS_BODY, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	var f := ThemeDB.fallback_font
	pos = px(pos)
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]:
		ci.draw_string(f, pos + o, s, align, w, size, outline)
	ci.draw_string(f, pos, s, align, w, size, col)

static func text_width(s: String, size := FS_BODY) -> float:
	return ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Motion helpers
static func ease_out_cubic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)

static func ease_out_back(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

static func reduce_flash() -> bool:
	return bool(SaveManager.settings.get("reduce_flash", false))
