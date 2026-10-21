extends Control
## Tactical blueprint ship builder (Tab). Portrait: blueprint grid (nose up) on top, module cards below,
## live stats with +/- deltas vs the applied ship, validation list, action buttons.
## Drag cards onto the grid; drag placed modules to move; right-click / drop outside to remove.
const K = preload("res://scripts/ui/ui_kit.gd")
const GRID_POS := Vector2(72, 36)
const CELL := 18
const PAL_POS := Vector2(6, 176)
const CARD := Vector2(128, 26)
const PAL_ROWS := 6
const BTN_Y := 454.0
const GLYPHS := {"core": "core", "cockpit": "hull", "main_thruster": "dash", "side_thruster": "dash", "shield_gen": "shield",
	"armor": "module", "radiator": "flash", "weapon_mount": "pulse_cannon"}
var battle: Node
var model: RefCounted
var palette: Array = [
	["core", ""], ["cockpit", ""], ["main_thruster", ""], ["side_thruster", ""], ["shield_gen", ""],
	["armor", ""], ["radiator", ""], ["weapon_mount", "pulse_cannon"], ["weapon_mount", "missile_swarm"],
	["weapon_mount", "gravity_bomb"], ["weapon_mount", "emp_launcher"]]
var drag: Array = []
var mouse := Vector2.ZERO
var message := ""
var message_arg := ""
var preview_valid := false
var snap_cell := Vector2i(-1, -1)
var snap_t := 9.0
var _t := 0.0
var _open_t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

func open_with(b: Node) -> void:
	battle = b
	model = b.player.ship.duplicate_model()
	for c in model.cells:
		model.cells[c]["hp"] = model.cells[c]["max_hp"]
	model.revalidate()
	visible = true
	_open_t = 0.0
	message = "BLD_MSG_DRAG"
	message_arg = ""

func cell_screen(c: Vector2i) -> Vector2:
	return GRID_POS + Vector2(c.y, model.grid_size - 1 - c.x) * CELL

func cell_at(p: Vector2) -> Vector2i:
	if model == null:
		return Vector2i(-1, -1)
	var sc := Vector2i(((p - GRID_POS) / CELL).floor())
	if sc.x < 0 or sc.y < 0 or sc.x >= model.grid_size or sc.y >= model.grid_size:
		return Vector2i(-1, -1)
	return Vector2i(model.grid_size - 1 - sc.y, sc.x)

static func dir_to_screen(d: Vector2) -> Vector2:
	return Vector2(d.y, -d.x)

func palette_rect(i: int) -> Rect2:
	return Rect2(PAL_POS + Vector2((i / PAL_ROWS) * (CARD.x + 2), (i % PAL_ROWS) * (CARD.y + 1)), CARD)

func palette_at(p: Vector2) -> int:
	for i in palette.size():
		if palette_rect(i).has_point(p):
			return i
	return -1

func button_rect(i: int) -> Rect2:
	return Rect2(6 + i * 87, BTN_Y, 84, 20)

func palette_label(i: int) -> String:
	if palette[i][1] == "":
		return tr("MOD_" + str(palette[i][0]).to_upper())
	return tr("BLD_MOUNT") % tr("WPN_" + str(palette[i][1]).to_upper())

func glyph_for(id: String, weapon: String) -> String:
	return weapon if weapon != "" else GLYPHS.get(id, "module")

# --- API (mouse handlers + autotest) ---
func begin_drag(id: String, weapon: String) -> void:
	drag = [id, weapon]

func pick_up(c: Vector2i) -> bool:
	if not model.cells.has(c):
		return false
	drag = [model.cells[c]["id"], model.cells[c]["weapon"]]
	model.remove(c)
	model.revalidate()
	return true

func preview_ok(c: Vector2i) -> bool:
	if drag.is_empty() or c.x < 0 or model.cells.has(c):
		return false
	var m: RefCounted = model.duplicate_model()
	m.place(c, drag[0], drag[1])
	m.revalidate()
	return m.connected.has(c)

func drop(c: Vector2i) -> bool:
	if drag.is_empty():
		return false
	var ok: bool = c.x >= 0 and not model.cells.has(c)
	if ok:
		model.place(c, drag[0], drag[1])
		model.revalidate()
		message = "BLD_MSG_PLACED"
		message_arg = "MOD_" + str(drag[0]).to_upper()
		snap_cell = c
		snap_t = 0.0
	else:
		message = "BLD_MSG_REMOVED"
	drag = []
	return ok

func remove_cell(c: Vector2i) -> void:
	model.remove(c)
	model.revalidate()

func apply() -> bool:
	model.revalidate()
	if not model.is_valid():
		message = "BLD_MSG_INVALID"
		return false
	battle.player.set_ship(model.duplicate_model())
	message = "BLD_MSG_APPLIED"
	return true

func reset_default() -> void:
	model = load("res://scripts/ship_model.gd").from_file("res://data/ships/default_ship.json").duplicate_model()

func _gui_input(event: InputEvent) -> void:
	if model == null:
		return
	if event is InputEventMouseMotion:
		mouse = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		mouse = event.position
		var i := palette_at(mouse)
		if i >= 0:
			begin_drag(palette[i][0], palette[i][1])
		elif cell_at(mouse).x >= 0:
			pick_up(cell_at(mouse))
		elif button_rect(0).has_point(mouse):
			apply()
		elif button_rect(1).has_point(mouse):
			reset_default()
		elif button_rect(2).has_point(mouse):
			battle.toggle_builder()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not drag.is_empty():
			drop(cell_at(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var c := cell_at(event.position)
		if c.x >= 0:
			remove_cell(c)
	accept_event()

func _process(delta: float) -> void:
	if visible:
		_t += delta
		_open_t += delta
		snap_t += delta
		queue_redraw()

func _draw_module(r: Rect2, id: String, weapon: String, alpha := 1.0, connected := true) -> void:
	var col := Color(model.defs[id]["color"])
	if not connected:
		col = col.darkened(0.55)
	K.chamfer_fill(self, r, 2, Color(col, 0.28 * alpha))
	K.chamfer_line(self, r, 2, Color(col, 0.95 * alpha))
	K.icon(self, glyph_for(id, weapon), r.get_center() - Vector2(3, 3), Color(K.TEXT if connected else K.DIM, alpha))

func _draw() -> void:
	if model == null:
		return
	var k := K.ease_out_cubic(_open_t / 0.2)
	draw_rect(Rect2(0, 0, 270, 480), Color(K.BG, 0.97 * k))
	K.scanlines(self, Rect2(0, 0, 270, 480), Color(K.ACCENT, 0.02))
	# header
	K.icon(self, "build", Vector2(8, 7), K.ACCENT)
	K.text(self, Vector2(19, 14), tr("BLD_TITLE"), K.ACCENT)
	K.text(self, Vector2(0, 14), tr("BLD_FORWARD"), K.DIM, K.FS_BODY, HORIZONTAL_ALIGNMENT_RIGHT, 264)
	draw_rect(Rect2(6, 20, 258, 1), Color(K.ACCENT, 0.3))
	# blueprint grid
	var g: int = model.grid_size
	var gr := Rect2(GRID_POS - Vector2(6, 6), Vector2(g * CELL + 11, g * CELL + 11))
	K.panel(self, gr, K.ACCENT, 0.7, 4, true)
	for i in g + 1:
		var a := 0.22 if i == 0 or i == g else 0.10
		draw_rect(Rect2(GRID_POS.x + i * CELL - 1, GRID_POS.y, 1, g * CELL - 1), Color(K.ACCENT, a))
		draw_rect(Rect2(GRID_POS.x, GRID_POS.y + i * CELL - 1, g * CELL - 1, 1), Color(K.ACCENT, a))
	for sy in g:
		for sx in g:
			draw_rect(Rect2(GRID_POS + Vector2(sx, sy) * CELL + Vector2(8, 8), Vector2(1, 1)), Color(K.ACCENT, 0.25))
	# modules + connectors + arcs
	for c in model.cells:
		var id: String = model.cells[c]["id"]
		var conn: bool = model.connected.has(c)
		var r := Rect2(cell_screen(c) + Vector2(2, 2), Vector2(CELL - 5, CELL - 5))
		if id == "weapon_mount" and conn:
			var f: float = model.mount_facing(c) - PI / 2.0
			var a: float = model.mount_arc(c)
			for j in 15:
				var aa := f - a / 2.0 + a * j / 14.0
				draw_rect(Rect2((r.get_center() + Vector2.from_angle(aa) * 24).floor(), Vector2.ONE), Color(K.DANGER, 0.45))
		_draw_module(r, id, model.cells[c]["weapon"], 1.0, conn)
		if not conn:
			K.brackets(self, r, 3, K.DANGER, 1)
		for side in model.DIRS:
			if side in model.defs[id]["connectors"]:
				var cp: Vector2 = r.get_center() + dir_to_screen(Vector2(model.DIRS[side])) * (CELL / 2.0 - 1)
				draw_rect(Rect2(cp.floor() - Vector2(1, 1), Vector2(2, 2)), Color(K.TEXT, 0.8) if conn else K.DIM)
	# snap animation
	if snap_t < 0.3 and snap_cell.x >= 0:
		var sk := K.ease_out_cubic(snap_t / 0.3)
		var sr := Rect2(cell_screen(snap_cell), Vector2(CELL - 1, CELL - 1)).grow(floorf(6.0 * (1.0 - sk)))
		K.brackets(self, sr, 4, Color(K.ACCENT, 1.0 - sk * 0.6))
	# placement ghost
	if not drag.is_empty():
		var c := cell_at(mouse)
		preview_valid = preview_ok(c)
		var gcol := K.ACCENT if preview_valid else K.DANGER
		if c.x >= 0:
			var rr := Rect2(cell_screen(c) + Vector2(2, 2), Vector2(CELL - 5, CELL - 5))
			K.chamfer_fill(self, rr, 2, Color(gcol, 0.3))
			K.icon(self, glyph_for(drag[0], drag[1]), rr.get_center() - Vector2(3, 3), gcol)
			K.brackets(self, rr, 4, gcol, 2)
		else:
			_draw_module(Rect2(mouse - Vector2(7, 7), Vector2(15, 15)), drag[0], drag[1], 0.8)
	# module cards (warehouse)
	K.text(self, Vector2(6, PAL_POS.y - 4), tr("BLD_MODULES"), K.ENERGY)
	for i in palette.size():
		var pr := palette_rect(i)
		var hovered := pr.has_point(mouse)
		var id: String = palette[i][0]
		var d: Dictionary = model.defs[id]
		var col := Color(d["color"])
		K.chamfer_fill(self, pr, 2, Color(K.BG2, 0.95) if not hovered else Color(K.ACCENT, 0.14))
		K.chamfer_line(self, pr, 2, Color(K.ACCENT, 0.9) if hovered else Color(K.TEXT, 0.14))
		draw_rect(Rect2(pr.position + Vector2(1, 3), Vector2(2, pr.size.y - 6)), col)
		K.icon(self, glyph_for(id, palette[i][1]), pr.position + Vector2(7, 9), col)
		K.text(self, pr.position + Vector2(18, 12), palette_label(i), K.TEXT)
		K.text(self, pr.position + Vector2(18, 24), tr("CARD_STATS") % [int(d["mass"]), int(d["power"])], K.DIM)
	# live stats with deltas vs applied ship
	var s: Dictionary = model.stats
	var cur: Dictionary = battle.player.ship.stats if battle and battle.player else s
	var defs := [["STAT_MASS", "mass", -1], ["STAT_POWER", "power", 1], ["STAT_ACCEL", "accel", 1], ["STAT_SPEED", "max_speed", 1],
		["STAT_TURN", "turn", 1], ["STAT_HULL", "hull", 1], ["STAT_SHIELD", "shield", 1], ["STAT_ENERGY", "energy", 1],
		["STAT_COOLING", "cooling", 1], ["STAT_MOUNTS", "mounts", 1]]
	var sy0 := 352.0
	draw_rect(Rect2(6, sy0 - 10, 258, 1), Color(K.ACCENT, 0.2))
	for i in defs.size():
		var key: String = defs[i][0]
		var f: String = defs[i][1]
		var label: String
		if key == "STAT_SHIELD":
			label = tr(key) % [s["shield"], s["shield_regen"]]
		elif key == "STAT_POWER" or key == "STAT_MOUNTS":
			label = tr(key) % int(s[f])
		else:
			label = tr(key) % s[f]
		var x := 6.0 + (i % 2) * 131.0
		var y := sy0 + (i / 2) * 12.0
		K.text(self, Vector2(x, y), label, K.TEXT)
		var dv: float = float(s[f]) - float(cur.get(f, s[f]))
		if absf(dv) >= 0.5:
			var good: bool = (dv > 0.0) == (int(defs[i][2]) > 0)
			K.text(self, Vector2(x, y), ("%+d" % roundi(dv)), K.ACCENT if good else K.DANGER, K.FS_BODY, HORIZONTAL_ALIGNMENT_RIGHT, 126)
	# validation
	var ey := 414.0
	if model.is_valid():
		K.icon(self, "play", Vector2(6, ey - 8), K.ACCENT)
		K.text(self, Vector2(17, ey), tr("BLD_VALID"), K.ACCENT)
	else:
		for err in model.errors:
			if ey > 427.0:
				break
			K.icon(self, "warning", Vector2(6, ey - 8), K.DANGER)
			K.text(self, Vector2(17, ey), model.error_text(err), K.DANGER)
			ey += 13
	var msg := tr(message)
	if message_arg != "" and message == "BLD_MSG_PLACED":
		msg = msg % tr(message_arg)
	K.text(self, Vector2(6, 442), msg, K.ENERGY)
	K.text(self, Vector2(0, 442), tr("BLD_HINT"), K.DIM, K.FS_BODY, HORIZONTAL_ALIGNMENT_RIGHT, 264)
	var btns := [["BLD_APPLY", "play", K.ACCENT, model.is_valid()], ["BLD_RESET", "restart", K.ENERGY, true], ["BLD_CLOSE", "quit", K.TEXT, true]]
	for i in 3:
		var r := button_rect(i)
		var en: bool = btns[i][3]
		var hov := r.has_point(mouse) and en
		var col: Color = btns[i][2] if en else K.DIM
		K.chamfer_fill(self, r, 3, Color(col, 0.22) if hov else Color(K.BG2, 0.95))
		K.chamfer_line(self, r, 3, col)
		if hov:
			K.brackets(self, r, 4, K.TEXT, 1)
		var lw := K.text_width(tr(btns[i][0])) + 11
		var lx := floorf(r.position.x + (r.size.x - lw) / 2.0)
		K.icon(self, btns[i][1], Vector2(lx, r.position.y + 7), col)
		K.text(self, Vector2(lx + 11, r.position.y + 14), tr(btns[i][0]), col)
