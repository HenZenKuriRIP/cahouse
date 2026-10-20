extends RefCounted
## Data-driven weapon (loaded from JSON). Handles fire-rate, heat and overheat.
var data: Dictionary
var id: String
var cooldown := 0.0
var heat := 0.0
var overheated := false
var rng := RandomNumberGenerator.new()

func _init(json_path: String, seed_value: int) -> void:
	data = GameManager.load_json(json_path)
	id = data.get("id", "unknown")
	rng.seed = seed_value

func update(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	var prev_heat := heat
	heat = maxf(0.0, heat - float(data["heat_dissipation"]) * delta)
	if overheated and heat <= float(data["overheat_recover"]):
		overheated = false
	if prev_heat != heat:
		EventBus.heat_changed.emit(heat / float(data["overheat_threshold"]), overheated)

func try_fire(battle: Node, origin: Vector2, dir: Vector2) -> bool:
	if cooldown > 0.0 or overheated:
		return false
	cooldown = 1.0 / float(data["fire_rate"])
	heat += float(data["heat_generation"])
	if heat >= float(data["overheat_threshold"]):
		heat = float(data["overheat_threshold"])
		overheated = true
	var spread := deg_to_rad(float(data["spread_deg"]))
	var d := dir.rotated(rng.randf_range(-spread, spread))
	var is_crit := rng.randf() < float(data["critical_chance"])
	var dmg := float(data["damage"]) * (float(data["critical_multiplier"]) if is_crit else 1.0)
	var speed := float(data["projectile_speed"])
	var lifetime := minf(float(data["projectile_lifetime"]), float(data["range"]) / speed)
	battle.spawn_projectile(origin, d * speed, dmg, lifetime, 0, Color(data["color"]), is_crit)
	EventBus.weapon_fired.emit(id)
	EventBus.heat_changed.emit(heat / float(data["overheat_threshold"]), overheated)
	return true
