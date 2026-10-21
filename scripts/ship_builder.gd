extends Control
## Debug ship builder (Tab). Drag modules from palette onto the grid; drag placed modules to move;
## right-click / drop outside to remove. Cyan = valid placement, red = invalid. Live stats + errors.
const PixelLib = preload("res://scripts/pixel.gd")
## Portrait layout (270x480): grid on top (ship nose points UP), module warehouse below, stats, errors, buttons.
const GRID_POS := Vector2(65, 36)
const CELL := 20
const PAL_POS := Vector2(4, 200)
const PAL_ROW := 15
const PAL_COL_W := 133
const PAL_ROWS := 6
const BTN_Y := 452.0
const FS := 12
var battle: Node
var model: RefCounted
var palette: Array = [
	["core", ""], ["cockpit", ""], ["main_thruster", ""], ["side_thruster", ""], ["shield_gen", ""],
	["armor", ""], ["radiator", ""], ["weapon_mount", "pulse_cannon"], ["weapon_mount", "missile_swarm"],
	["weapon_mount", "gravity_bomb"], ["weapon_mount", "emp_launcher"]]
var drag: Array = [] # [id, weapon] while dragging
var mouse := Vector2.ZERO
var font: Font
var message := ""
var message_arg := ""
var preview_valid := false

func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP

func open_with(b: Node) -> void:
	battle = b
	model = b.player.ship.duplicate_model()
	# repaired copy: builder edits a fresh blueprint
	for c in model.cells:
		model.cells[c]["hp"] = model.cells[c]["max_hp"]
	model.revalidate()
	visible = true
	message = "BLD_MSG_DRAG"
	message_arg = ""

## grid (x forward, y right-side) -> screen: column = y, row = G-1-x (nose up)
func cell_screen(c: Vector2i) -> Vector2:
	return GRID_POS + Vector2(c.y, model.grid_size - 1 - c.x) * CELL

func cell_at(p: Vector2) -> Vector2i:
	if model == null:
		return Vector2i(-1, -1)
	var sc := Vector2i(((p - GRID_POS) / CELL).floor())
	var c := Vector2i(model.grid_size - 1 - sc.y, sc.x)
	if sc.x < 0 or sc.y < 0 or sc.x >= model.grid_size or sc.y >= model.grid_size:
		return Vector2i(-1, -1)
	return c

static func dir_to_screen(d: Vector2) -> Vector2:
	return Vector2(d.y, -d.x)

func palette_rect(i: int) -> Rect2:
	return Rect2(PAL_POS + Vector2((i / PAL_ROWS) * PAL_COL_W, (i % PAL_ROWS) * PAL_ROW), Vector2(PAL_COL_W - 2, PAL_ROW - 1))

func palette_at(p: Vector2) -> int:
	for i in palette.size():
		if palette_rect(i).has_point(p):
			return i
	return -1

func button_rect(i: int) -> Rect2:
	return Rect2(8 + i * 87, BTN_Y, 80, 18)

func palette_label(i: int) -> String:
	if palette[i][1] == "":
		return tr("MOD_" + str(palette[i][0]).to_upper())
	return tr("BLD_MOUNT") % tr("WPN_" + str(palette[i][1]).to_upper())

# --- API (used by mouse handlers and autotest) ---
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
		if i >= 0 and i < palette.size():
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

func _process(_d: float) -> void:
	if visible:
		queue_redraw()

func _t(p: Vector2, s: String, c: Color, size := FS, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, p, s, align, w, size, c)

func _draw() -> void:
	if model == null:
		return
	draw_rect(Rect2(0, 0, 270, 480), Color(PixelLib.C_BG, 0.95))
	_t(Vector2(4, 13), tr("BLD_TITLE"), PixelLib.C_CYAN)
	_t(Vector2(0, 13), tr("BLD_FORWARD"), Color(PixelLib.C_WHITE, 0.6), FS, HORIZONTAL_ALIGNMENT_RIGHT, 266)
	for sy in model.grid_size:
		for sx in model.grid_size:
			draw_rect(Rect2(GRID_POS + Vector2(sx, sy) * CELL, Vector2(CELL - 1, CELL - 1)), PixelLib.C_PANEL)
	for c in model.cells:
		var id: String = model.cells[c]["id"]
		var r := Rect2(cell_screen(c) + Vector2(2, 2), Vector2(CELL - 5, CELL - 5))
		var col := Color(model.defs[id]["color"])
		draw_rect(r, col if model.connected.has(c) else col.darkened(0.6))
		if not model.connected.has(c):
			draw_rect(r.grow(1), PixelLib.C_RED, false, 1.0)
		_t(r.position + Vector2(0, 12), _abbr(id, model.cells[c]["weapon"]), PixelLib.C_BG, FS, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		for side in model.DIRS:
			if side in model.defs[id]["connectors"]:
				var cp: Vector2 = r.get_center() + dir_to_screen(Vector2(model.DIRS[side])) * (CELL / 2.0 - 2)
				draw_rect(Rect2(cp.floor() - Vector2(1, 1), Vector2(2, 2)), PixelLib.C_WHITE)
		if id == "weapon_mount" and model.connected.has(c):
			var f: float = model.mount_facing(c) - PI / 2.0
			var a: float = model.mount_arc(c)
			draw_arc(r.get_center(), 26, f - a / 2, f + a / 2, 12, Color(PixelLib.C_RED, 0.5), 1.0)
	if not drag.is_empty():
		var c := cell_at(mouse)
		preview_valid = preview_ok(c)
		if c.x >= 0:
			draw_rect(Rect2(cell_screen(c), Vector2(CELL - 1, CELL - 1)), PixelLib.C_CYAN if preview_valid else PixelLib.C_RED, false, 1.0)
		draw_rect(Rect2(mouse - Vector2(6, 6), Vector2(12, 12)), Color(Color(model.defs[drag[0]]["color"]), 0.7))
	# warehouse
	_t(PAL_POS + Vector2(0, -3), tr("BLD_MODULES"), PixelLib.C_GOLD)
	for i in palette.size():
		var pr := palette_rect(i)
		draw_rect(Rect2(pr.position + Vector2(0, 3), Vector2(8, 8)), Color(model.defs[palette[i][0]]["color"]))
		_t(pr.position + Vector2(11, 12), palette_label(i), PixelLib.C_WHITE)
	# stats (2 columns)
	var s: Dictionary = model.stats
	var lines := [tr("STAT_MASS") % s["mass"], tr("STAT_POWER") % s["power"], tr("STAT_ACCEL") % s["accel"], tr("STAT_SPEED") % s["max_speed"],
		tr("STAT_TURN") % s["turn"], tr("STAT_HULL") % s["hull"], tr("STAT_SHIELD") % [s["shield"], s["shield_regen"]],
		tr("STAT_ENERGY") % s["energy"], tr("STAT_COOLING") % s["cooling"], tr("STAT_MOUNTS") % s["mounts"]]
	for i in lines.size():
		_t(Vector2(4 + (i % 2) * 133, 306 + (i / 2) * 13), lines[i], PixelLib.C_CYAN)
	var ey := 378.0
	if model.is_valid():
		_t(Vector2(4, ey), tr("BLD_VALID"), PixelLib.C_CYAN)
	for err in model.errors:
		if ey > 420.0:
			break
		_t(Vector2(4, ey), model.error_text(err), PixelLib.C_RED)
		ey += 13
	var msg := tr(message)
	if message_arg != "" and message == "BLD_MSG_PLACED":
		msg = msg % tr(message_arg)
	_t(Vector2(4, 434), msg, PixelLib.C_GOLD)
	_t(Vector2(4, 447), tr("BLD_HINT"), Color(PixelLib.C_WHITE, 0.6))
	var btns := [["BLD_APPLY", PixelLib.C_CYAN if model.is_valid() else Color("#444")], ["BLD_RESET", PixelLib.C_GOLD], ["BLD_CLOSE", PixelLib.C_WHITE]]
	for i in 3:
		var r := button_rect(i)
		draw_rect(r, PixelLib.C_PANEL)
		draw_rect(r, btns[i][1], false, 1.0)
		_t(r.position + Vector2(0, 14), tr(btns[i][0]), btns[i][1], FS, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _abbr(id: String, weapon: String) -> String:
	if weapon != "":
		return tr("WPNA_" + weapon.to_upper())
	return tr("ABBR_" + id.to_upper())
