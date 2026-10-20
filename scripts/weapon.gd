extends RefCounted
## Data-driven weapon (JSON). Fire-rate, heat/overheat, energy multipliers, kinds: bullet/missile/bomb/emp.
var data: Dictionary
var id: String
var kind: String
var slot: String
var cooldown := 0.0
var heat := 0.0
var overheated := false
var shots := 0
var rng := RandomNumberGenerator.new()

func _init(json_path: String, seed_value: int) -> void:
	data = GameManager.load_json(json_path)
	id = data.get("id", "unknown")
	kind = data.get("kind", "bullet")
	slot = data.get("slot", "primary")
	rng.seed = seed_value

func update(delta: float, dissipation_mult := 1.0) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	heat = maxf(0.0, heat - float(data["heat_dissipation"]) * dissipation_mult * delta)
	if overheated and heat <= float(data["overheat_recover"]):
		overheated = false

func heat_ratio() -> float:
	return heat / float(data["overheat_threshold"])

func ready_ratio() -> float:
	return 1.0 - cooldown * float(data["fire_rate"])

func try_fire(battle: Node, origin: Vector2, dir: Vector2, target_pos: Vector2, dmg_mult := 1.0, rate_mult := 1.0) -> bool:
	if cooldown > 0.0 or overheated:
		return false
	cooldown = 1.0 / (float(data["fire_rate"]) * rate_mult)
	heat += float(data["heat_generation"])
	if heat >= float(data["overheat_threshold"]):
		heat = float(data["overheat_threshold"])
		overheated = true
	var speed := float(data["projectile_speed"])
	var lifetime := float(data["projectile_lifetime"])
	if kind == "bullet":
		lifetime = minf(lifetime, float(data["range"]) / speed)
	elif kind == "bomb" or kind == "emp":
		# detonate at the aim point (clamped by range)
		lifetime = clampf(origin.distance_to(target_pos), 30.0, float(data["range"])) / speed
	var count := int(data.get("count", 1))
	var spread := deg_to_rad(float(data["spread_deg"]))
	for i in count:
		var a := rng.randf_range(-spread, spread) if count == 1 else lerpf(-spread, spread, float(i) / maxf(1.0, count - 1.0))
		var d := dir.rotated(a)
		var is_crit := rng.randf() < float(data["critical_chance"])
		var dmg := float(data["damage"]) * dmg_mult * (float(data["critical_multiplier"]) if is_crit else 1.0)
		battle.spawn_projectile(origin, d * speed, dmg, lifetime, 0, Color(data["color"]), is_crit, {"kind": kind, "weapon": id, "data": data})
	shots += 1
	EventBus.weapon_fired.emit(id)
	return true
