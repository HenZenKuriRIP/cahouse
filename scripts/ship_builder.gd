extends Control
## Debug ship builder (Tab). Drag modules from palette onto the grid; drag placed modules to move;
## right-click / drop outside to remove. Cyan = valid placement, red = invalid. Live stats + errors.
const PixelLib = preload("res://scripts/pixel.gd")
const GRID_POS := Vector2(14, 40)
const CELL := 20
const PAL_POS := Vector2(170, 40)
const PAL_ROW := 13
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
	message = "拖拽模块到网格 / DRAG MODULES"

func cell_at(p: Vector2) -> Vector2i:
	var c := Vector2i(((p - GRID_POS) / CELL).floor())
	return c if model and model.in_bounds(c) else Vector2i(-1, -1)

func palette_at(p: Vector2) -> int:
	var r := Rect2(PAL_POS, Vector2(130, PAL_ROW * palette.size()))
	if not r.has_point(p):
		return -1
	return int((p.y - PAL_POS.y) / PAL_ROW)

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
		message = "放置 %s" % drag[0]
	else:
		message = "已移除 / REMOVED"
	drag = []
	return ok

func remove_cell(c: Vector2i) -> void:
	model.remove(c)
	model.revalidate()

func apply() -> bool:
	model.revalidate()
	if not model.is_valid():
		message = "无效设计，无法应用 / INVALID"
		return false
	battle.player.set_ship(model.duplicate_model())
	message = "已应用 / APPLIED"
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
		elif Rect2(330, 236, 44, 14).has_point(mouse):
			apply()
		elif Rect2(378, 236, 44, 14).has_point(mouse):
			reset_default()
		elif Rect2(426, 236, 44, 14).has_point(mouse):
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

func _t(p: Vector2, s: String, c: Color, size := 8) -> void:
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)

func _draw() -> void:
	if model == null:
		return
	draw_rect(Rect2(0, 0, 480, 270), Color(PixelLib.C_BG, 0.94))
	_t(Vector2(14, 22), "SHIP BUILDER // 舰船编辑 (TAB 关闭)", PixelLib.C_CYAN, 10)
	_t(Vector2(14, 33), "前方 → (FORWARD = RIGHT)", Color(PixelLib.C_WHITE, 0.6))
	for y in model.grid_size:
		for x in model.grid_size:
			draw_rect(Rect2(GRID_POS + Vector2(x, y) * CELL, Vector2(CELL - 1, CELL - 1)), PixelLib.C_PANEL)
	for c in model.cells:
		var id: String = model.cells[c]["id"]
		var r := Rect2(GRID_POS + Vector2(c) * CELL + Vector2(2, 2), Vector2(CELL - 5, CELL - 5))
		var col := Color(model.defs[id]["color"])
		draw_rect(r, col if model.connected.has(c) else col.darkened(0.6))
		if not model.connected.has(c):
			draw_rect(r.grow(1), PixelLib.C_RED, false, 1.0)
		_t(r.position + Vector2(1, 9), _abbr(id, model.cells[c]["weapon"]), PixelLib.C_BG)
		for side in model.DIRS:
			if side in model.defs[id]["connectors"]:
				var cp: Vector2 = r.get_center() + Vector2(model.DIRS[side]) * (CELL / 2.0 - 2)
				draw_rect(Rect2(cp.floor() - Vector2(1, 1), Vector2(2, 2)), PixelLib.C_WHITE)
		if id == "weapon_mount" and model.connected.has(c):
			var f: float = model.mount_facing(c)
			var a: float = model.mount_arc(c)
			draw_arc(r.get_center(), 26, f - a / 2, f + a / 2, 12, Color(PixelLib.C_RED, 0.5), 1.0)
	# drag preview
	if not drag.is_empty():
		var c := cell_at(mouse)
		preview_valid = preview_ok(c)
		if c.x >= 0:
			draw_rect(Rect2(GRID_POS + Vector2(c) * CELL, Vector2(CELL - 1, CELL - 1)), PixelLib.C_CYAN if preview_valid else PixelLib.C_RED, false, 1.0)
		draw_rect(Rect2(mouse - Vector2(6, 6), Vector2(12, 12)), Color(Color(model.defs[drag[0]]["color"]), 0.7))
	# palette
	_t(PAL_POS + Vector2(0, -4), "MODULES", PixelLib.C_GOLD)
	for i in palette.size():
		var id: String = palette[i][0]
		var y := PAL_POS.y + i * PAL_ROW
		draw_rect(Rect2(PAL_POS.x, y, 8, 8), Color(model.defs[id]["color"]))
		var label: String = model.defs[id]["name"] if palette[i][1] == "" else "MOUNT:" + palette[i][1].to_upper()
		_t(Vector2(PAL_POS.x + 12, y + 8), label, PixelLib.C_WHITE)
	# stats
	var s: Dictionary = model.stats
	var lines := ["MASS %.0f" % s["mass"], "POWER %+d" % s["power"], "ACCEL %.0f" % s["accel"], "MAX SPD %.0f" % s["max_speed"],
		"TURN %.0f°/s" % s["turn"], "HULL %.0f" % s["hull"], "SHIELD %.0f (+%.0f/s)" % [s["shield"], s["shield_regen"]],
		"ENERGY %.0f" % s["energy"], "COOLING %.0f" % s["cooling"], "MOUNTS %d" % s["mounts"]]
	for i in lines.size():
		_t(Vector2(330, 44 + i * 10), lines[i], PixelLib.C_CYAN)
	var ey := 150.0
	if model.is_valid():
		_t(Vector2(330, ey), "VALID OK", PixelLib.C_CYAN)
	for err in model.errors:
		_t(Vector2(330, ey), err, PixelLib.C_RED)
		ey += 10
	_t(Vector2(14, 200), message, PixelLib.C_GOLD)
	_t(Vector2(14, 212), "左键拖放 / 右键删除 / 拖出网格删除", Color(PixelLib.C_WHITE, 0.6))
	var btns := [["APPLY", PixelLib.C_CYAN if model.is_valid() else Color("#444")], ["RESET", PixelLib.C_GOLD], ["CLOSE", PixelLib.C_WHITE]]
	for i in 3:
		var r := Rect2(330 + i * 48, 236, 44, 14)
		draw_rect(r, PixelLib.C_PANEL)
		draw_rect(r, btns[i][1], false, 1.0)
		_t(r.position + Vector2(6, 10), btns[i][0], btns[i][1])

func _abbr(id: String, weapon: String) -> String:
	if weapon != "":
		return weapon.substr(0, 2).to_upper()
	return {"core": "CO", "cockpit": "CP", "main_thruster": "MT", "side_thruster": "ST", "shield_gen": "SG", "armor": "AR", "radiator": "RD"}.get(id, "?")
