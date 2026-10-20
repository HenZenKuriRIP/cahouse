extends RefCounted
## Dynamic Energy Core: shared energy split into WEAPON / SHIELD / ENGINE (barycentric weights),
## overload (exceed cap, core heat), overheat (temporarily disables one module category).
signal preset_applied(name: String)
signal overheated(disabled_category: String, duration: float)
signal overload_changed(active: bool)

var cfg: Dictionary
var target := Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0) # x=weapon y=shield z=engine
var current := target
var overload_active := false
var overload_locked := false
var core_heat := 0.0
var cooling_bonus := 0.0
var disabled_category := ""
var disabled_timer := 0.0
var preset_name := "BALANCED"
var rng := RandomNumberGenerator.new()
var stats := {"presets": 0, "nudges": 0, "overload_time": 0.0, "overheats": 0}

func _init(seed_value: int) -> void:
	cfg = GameManager.load_json("res://data/energy.json")
	rng.seed = seed_value

static func normalize(v: Vector3, min_share: float) -> Vector3:
	v = Vector3(maxf(v.x, min_share), maxf(v.y, min_share), maxf(v.z, min_share))
	return v / (v.x + v.y + v.z)

func set_weights(v: Vector3, immediate := false) -> void:
	target = normalize(v, float(cfg["min_share"]))
	preset_name = "CUSTOM"
	if immediate:
		current = target

func apply_preset(name: String) -> void:
	var p: Array = cfg["presets"][name]
	target = normalize(Vector3(p[0], p[1], p[2]), float(cfg["min_share"]))
	preset_name = name
	stats["presets"] += 1
	preset_applied.emit(name)

func apply_preset_index(i: int) -> void:
	var order: Array = cfg["preset_order"]
	apply_preset(order[clampi(i, 0, order.size() - 1)])

func nudge(axis: int) -> void:
	var step := float(cfg["nudge_step"])
	var v := target
	v[axis] += step
	target = normalize(v, float(cfg["min_share"]))
	preset_name = "CUSTOM"
	stats["nudges"] += 1

func set_overload(want: bool) -> void:
	var active := want and not overload_locked
	if active != overload_active:
		overload_active = active
		overload_changed.emit(active)

func update(delta: float) -> void:
	current = current.lerp(target, clampf(float(cfg["transition_speed"]) * delta, 0.0, 1.0))
	if overload_active:
		core_heat += float(cfg["core_heat_rise"]) * delta
		stats["overload_time"] += delta
		if core_heat >= float(cfg["overheat_at"]):
			_overheat()
	else:
		core_heat = maxf(0.0, core_heat - (float(cfg["core_heat_cool"]) + cooling_bonus) * delta)
		if overload_locked and core_heat <= float(cfg["overload_unlock_heat"]):
			overload_locked = false
	if disabled_timer > 0.0:
		disabled_timer -= delta
		if disabled_timer <= 0.0:
			disabled_category = ""

func _overheat() -> void:
	var cats := ["weapon_mount", "shield_gen", "side_thruster"]
	disabled_category = cats[rng.randi() % cats.size()]
	disabled_timer = float(cfg["overheat_disable_time"])
	core_heat = float(cfg["overheat_reset_heat"])
	overload_locked = true
	set_overload(false)
	stats["overheats"] += 1
	overheated.emit(disabled_category, disabled_timer)

func total() -> float:
	return float(cfg["overload_cap"]) if overload_active else 1.0

## Effect multiplier: base + slope * share * 3 (share 1/3 == base + slope ~ 1.6 for most). Normalised so BALANCED == 1.0.
func mult(effect: String) -> float:
	var e: Array = cfg["effects"][effect]
	var share: float
	if effect.begins_with("weapon"):
		share = current.x
	elif effect.begins_with("shield"):
		share = current.y
	else:
		share = current.z
	share *= total()
	var raw := float(e[0]) + float(e[1]) * share * 3.0
	var bal := float(e[0]) + float(e[1])
	return maxf(0.1, raw / bal)

func heat_ratio() -> float:
	return core_heat / float(cfg["overheat_at"])

func is_warning() -> bool:
	return core_heat >= float(cfg["warn_heat"])

func is_disabled(category: String) -> bool:
	return disabled_category == category and disabled_timer > 0.0
