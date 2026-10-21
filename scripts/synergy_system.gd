extends Node
## Data-driven synergies (data/synergies.json). Active when the ship's live loadout contains the required weapons.
## Central damage routing for player projectile hits so synergies can modify them.
const PixelLib = preload("res://scripts/pixel.gd")
var battle: Node
var defs: Dictionary
var counters: Dictionary = {}
var _text_cd: Dictionary = {}

func setup(b: Node) -> void:
	battle = b
	defs = GameManager.load_json("res://data/synergies.json")
	for k in defs:
		counters[k] = 0
		_text_cd[k] = 0.0

func _process(delta: float) -> void:
	for k in _text_cd:
		_text_cd[k] = maxf(0.0, _text_cd[k] - delta)

func is_active(id: String) -> bool:
	if not defs.has(id):
		return false
	var lo: Array = battle.player.loadout_ids()
	for w in defs[id]["weapons"]:
		if not (w in lo):
			return false
	var any_of: Array = defs[id].get("any_of", [])
	if any_of.is_empty():
		return true
	for w in any_of:
		if w in lo:
			return true
	return false

func trigger(id: String, pos: Vector2) -> void:
	counters[id] += 1
	EventBus.synergy_triggered.emit(id, pos)
	if _text_cd[id] <= 0.0:
		_text_cd[id] = 1.2
		battle.spawn_float_text(pos + Vector2(0, -14), tr("SYN_" + id.to_upper()), PixelLib.C_CYAN if id != "ion_vortex" else PixelLib.C_VIOLET, 1.2)
		battle.spawn_explosion(pos, PixelLib.C_CYAN, 10)

func on_player_hit(p: Node2D, e: Node2D) -> void:
	var dmg: float = p.damage
	var crit: bool = p.crit
	# GRAVITY LOCK: missiles vs enemies held in a gravity well
	if p.kind == "missile" and e.in_well_timer > 0.0 and is_active("gravity_missile"):
		dmg *= float(defs["gravity_missile"]["damage_mult"])
		trigger("gravity_missile", e.global_position)
	# OVERCHARGE BREACH: pulse/missile vs EMP-stripped enemy => forced crit
	if (p.weapon_id == "pulse_cannon" or p.weapon_id == "missile_swarm") and e.emp_timer > 0.0 and is_active("emp_crit"):
		var base_dmg: float = p.damage
		if p.crit:
			base_dmg /= float(p.wdata.get("critical_multiplier", 2.0))
		dmg = maxf(dmg, base_dmg * float(defs["emp_crit"]["crit_mult"]))
		crit = true
		trigger("emp_crit", e.global_position)
	e.take_damage(dmg, crit, p.weapon_id)

## EMP blast overlapping a gravity well => ION VORTEX
func on_emp_blast(pos: Vector2, blast_radius: float) -> void:
	if not is_active("ion_vortex"):
		return
	for w in battle.wells:
		if is_instance_valid(w) and not w.ion and w.global_position.distance_to(pos) <= w.radius + blast_radius:
			w.make_ion(float(defs["ion_vortex"]["dps"]), float(defs["ion_vortex"]["extend"]))
			trigger("ion_vortex", w.global_position)

func missile_target(from: Vector2, vel: Vector2) -> Node2D:
	var best: Node2D = null
	var best_score := INF
	var prefer_well: bool = is_active("gravity_missile") and battle.wells.size() > 0
	for e in battle.enemies:
		if not e.alive:
			continue
		var d: float = from.distance_to(e.global_position)
		if d > 450.0:
			continue
		var facing := vel.normalized().dot((e.global_position - from).normalized())
		var score := d - facing * 60.0
		if prefer_well and e.in_well_timer > 0.0:
			score -= 400.0
		if score < best_score:
			best_score = score
			best = e
	return best
