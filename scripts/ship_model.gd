extends RefCounted
## Data-driven modular ship: grid of modules, connection validation, derived stats,
## weapon mounts with firing arcs, per-module HP with fault tolerance.
const DIRS := {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
const OPP := {"N": "S", "E": "W", "S": "N", "W": "E"}
const CELL_PX := 3

var defs: Dictionary
var base: Dictionary
var grid_size := 7
var cells: Dictionary = {} # Vector2i -> {"id":String, "weapon":String, "hp":float, "max_hp":float}
var errors: PackedStringArray = [] # translation keys (ERR_*)
var loose_count := 0
var connected: Dictionary = {} # Vector2i -> true
var stats: Dictionary = {}
var destroyed_count := 0

func _init() -> void:
	defs = GameManager.load_json("res://data/modules.json")

static func from_file(path: String) -> RefCounted:
	var d: Dictionary = GameManager.load_json(path)
	var m: RefCounted = load("res://scripts/ship_model.gd").new()
	m.load_dict(d)
	return m

func load_dict(d: Dictionary) -> void:
	base = d["base"]
	grid_size = int(d["grid_size"])
	cells.clear()
	for e in d["modules"]:
		place(Vector2i(int(e["x"]), int(e["y"])), e["id"], e.get("weapon", ""))
	revalidate()

func to_dict() -> Dictionary:
	var mods: Array = []
	for c in cells:
		var m: Dictionary = {"x": c.x, "y": c.y, "id": cells[c]["id"]}
		if cells[c]["weapon"] != "":
			m["weapon"] = cells[c]["weapon"]
		mods.append(m)
	return {"name": "CUSTOM", "grid_size": grid_size, "base": base, "modules": mods}

func duplicate_model() -> RefCounted:
	var m: RefCounted = load("res://scripts/ship_model.gd").new()
	m.load_dict(to_dict())
	return m

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < grid_size and c.y < grid_size

func place(c: Vector2i, id: String, weapon := "") -> bool:
	if not in_bounds(c) or not defs.has(id):
		return false
	var hp := float(defs[id]["hp"])
	cells[c] = {"id": id, "weapon": weapon, "hp": hp, "max_hp": hp}
	return true

func remove(c: Vector2i) -> void:
	cells.erase(c)

func find_first(id: String) -> Variant:
	for c in cells:
		if cells[c]["id"] == id:
			return c
	return null

func core_cell() -> Vector2i:
	var c: Variant = find_first("core")
	return c if c != null else Vector2i(grid_size / 2, grid_size / 2)

func links(a: Vector2i, b: Vector2i) -> bool:
	# true if a and b are adjacent and both expose a connector on the shared side
	for side in DIRS:
		if a + DIRS[side] == b:
			return side in defs[cells[a]["id"]]["connectors"] and OPP[side] in defs[cells[b]["id"]]["connectors"]
	return false

func revalidate() -> void:
	errors = PackedStringArray()
	connected.clear()
	var cores := 0
	var cockpits := 0
	for c in cells:
		if cells[c]["id"] == "core":
			cores += 1
		elif cells[c]["id"] == "cockpit":
			cockpits += 1
	if cores == 0:
		errors.append("ERR_NO_CORE")
	elif cores > 1:
		errors.append("ERR_MULTI_CORE")
	if cockpits == 0:
		errors.append("ERR_NO_COCKPIT")
	if cores >= 1:
		var start := core_cell()
		var queue: Array = [start]
		connected[start] = true
		while queue.size() > 0:
			var cur: Vector2i = queue.pop_front()
			for side in DIRS:
				var n: Vector2i = cur + DIRS[side]
				if cells.has(n) and not connected.has(n) and links(cur, n):
					connected[n] = true
					queue.append(n)
		var loose := cells.size() - connected.size()
		if loose > 0:
			errors.append("ERR_DISCONNECTED")
			loose_count = loose
	var thrusters := 0
	for c in connected:
		var d: Dictionary = defs[cells[c]["id"]]
		if cells[c]["id"] == "main_thruster":
			if cells.has(c + DIRS[d["exhaust"]]):
				errors.append("ERR_EXHAUST")
			else:
				thrusters += 1
	if thrusters == 0:
		errors.append("ERR_NO_THRUST")
	_compute_stats()
	if stats["power"] < 0:
		errors.append("ERR_POWER")

## Localized, formatted error line for a key in `errors`.
func error_text(key: String) -> String:
	var t := TranslationServer.translate(key)
	if key == "ERR_DISCONNECTED":
		return t % loose_count
	if key == "ERR_POWER":
		return t % int(stats["power"])
	return t

func is_valid() -> bool:
	return errors.is_empty()

func _compute_stats() -> void:
	var s := {"mass": 0.0, "power": 0, "thrust": 0.0, "turn": float(base.get("turn", 100)), "shield": 0.0,
		"shield_regen": 0.0, "energy": 0.0, "cooling": 0.0, "hull": float(base.get("hull", 50)), "mounts": 0}
	for c in connected:
		var d: Dictionary = defs[cells[c]["id"]]
		s["mass"] += float(d["mass"])
		s["power"] += int(d["power"])
		if cells[c]["id"] == "main_thruster" and cells.has(c + DIRS[d["exhaust"]]):
			continue
		for k in d["stats"]:
			s[k] += float(d["stats"][k])
		if cells[c]["id"] == "weapon_mount":
			s["mounts"] += 1
	var mass := maxf(1.0, s["mass"])
	s["accel"] = s["thrust"] / mass * float(base.get("accel_per_thrust", 0.6)) * 4.0
	s["max_speed"] = 60.0 + s["thrust"] / mass * float(base.get("max_speed_per_thrust", 0.17)) * 4.0
	s["turn"] = s["turn"] * 6.0 / (mass * 0.5 + 3.0)
	stats = s

## Recompute after damage without overwriting module hp.
func active_cells(category: String) -> Array:
	var out: Array = []
	for c in connected:
		if cells[c]["id"] == category:
			out.append(c)
	return out

func local_pos(c: Vector2i) -> Vector2:
	return Vector2(c - core_cell()) * CELL_PX

func mount_facing(c: Vector2i) -> float:
	var off := Vector2(c - core_cell())
	if off.length() < 0.01:
		return 0.0
	return lerp_angle(off.angle(), 0.0, 0.5)

func mount_arc(c: Vector2i) -> float:
	return deg_to_rad(float(defs[cells[c]["id"]].get("arc", 360)))

## Damage a module chosen by the hit direction (ship-local). Cockpit/core are protected unless hull_ratio < 0.3.
## Returns the destroyed module id or "".
func damage_from(local_dir: Vector2, amount: float, hull_ratio: float) -> String:
	var best: Variant = null
	var best_score := -INF
	for c in connected:
		var d: Dictionary = defs[cells[c]["id"]]
		if d.get("protected", false) and hull_ratio >= 0.3:
			continue
		var score := local_pos(c).dot(local_dir.normalized()) + local_pos(c).length() * 0.2
		if score > best_score:
			best_score = score
			best = c
	if best == null:
		return ""
	var cell: Dictionary = cells[best]
	cell["hp"] -= amount
	if cell["hp"] <= 0.0:
		var id: String = cell["id"]
		cells.erase(best)
		destroyed_count += 1
		revalidate()
		return id
	return ""

func extent_radius() -> float:
	var r := 3.0
	for c in connected:
		r = maxf(r, local_pos(c).length() + 2.0)
	return r
