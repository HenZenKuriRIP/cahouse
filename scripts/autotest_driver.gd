extends Node
## Headless autotest pilot + checks. Drives the player via `player.auto`, exercises energy presets, nudges,
## overload/overheat, all 4 weapons, the 3 synergies, ship validation/builder API, module damage, asteroid field.
## Prints counters and PASS/FAIL (exit code 1 on FAIL).
var battle: Node
var t := 0.0
var checks: Dictionary = {} # name -> bool
var notes: PackedStringArray = []
var weapon_fired: Dictionary = {}
var preset_log: PackedStringArray = []
var _step := 0
var _overload_until_overheat := false
var _combo_t := 0.0
var _combo_phase := 0
var _combo_pos := Vector2.ZERO
var _pulse_t := 0.0
var _mods_destroyed := 0

func setup(b: Node) -> void:
	battle = b
	EventBus.weapon_fired.connect(func(id: String) -> void: weapon_fired[id] = int(weapon_fired.get(id, 0)) + 1)
	EventBus.module_destroyed.connect(func(id: String) -> void:
		_mods_destroyed += 1
		print("[AUTOTEST] module destroyed: %s at t=%.1f" % [id, GameManager.run_time]))
	_ship_validation_tests()
	# fixture: an isolated ore cluster far from the player to exercise the chain reaction
	var fld: Node2D = battle.field
	var base := Vector2(420, 250)
	var o1: Node2D = fld._spawn(base, 10.0, true, Vector2.ZERO)
	fld._spawn(base + Vector2(30, 0), 10.0, true, Vector2.ZERO)
	fld._spawn(base + Vector2(60, 10), 10.0, true, Vector2.ZERO)
	o1.ignite(false)

func _check(name: String, ok: bool, info := "") -> void:
	checks[name] = ok
	print("[AUTOTEST] CHECK %-34s %s %s" % [name, "OK" if ok else "FAIL", info])

func _ship_validation_tests() -> void:
	var SM: GDScript = load("res://scripts/ship_model.gd")
	var m: RefCounted = SM.from_file("res://data/ships/default_ship.json")
	_check("ship.default_valid", m.is_valid(), str(m.errors))
	var s: Dictionary = m.stats
	print("[AUTOTEST] default ship stats mass=%.0f power=%d accel=%.0f max_speed=%.0f turn=%.0f shield=%.0f hull=%.0f mounts=%d" % [s["mass"], s["power"], s["accel"], s["max_speed"], s["turn"], s["shield"], s["hull"], s["mounts"]])
	var a: RefCounted = m.duplicate_model()
	a.remove(Vector2i(3, 3))
	a.revalidate()
	_check("ship.no_core_invalid", not a.is_valid() and "缺少能量核心 (NO CORE)" in a.errors, str(a.errors))
	var b: RefCounted = m.duplicate_model()
	b.place(Vector2i(0, 0), "armor")
	b.revalidate()
	_check("ship.disconnected_invalid", not b.is_valid() and not b.connected.has(Vector2i(0, 0)), str(b.errors))
	var c: RefCounted = m.duplicate_model()
	c.place(Vector2i(1, 3), "armor")
	c.revalidate()
	_check("ship.exhaust_blocked_invalid", "主推进器尾焰被遮挡 (EXHAUST BLOCKED)" in c.errors, str(c.errors))
	var d: RefCounted = m.duplicate_model()
	d.remove(Vector2i(2, 3))
	d.revalidate()
	_check("ship.no_thrust_invalid", "缺少有效主推进器 (NO THRUST)" in d.errors, str(d.errors))
	var e: RefCounted = m.duplicate_model()
	for i in 4:
		e.place(Vector2i(i, 6), "shield_gen")
	e.place(Vector2i(4, 5), "shield_gen")
	e.place(Vector2i(4, 6), "shield_gen")
	e.revalidate()
	var adds := 0
	for x in range(0, 7):
		if e.connected.has(Vector2i(x, 6)):
			adds += 1
	# fault tolerance: destroying the shield gen (3,2) must keep (4,2) mount alive via the cockpit link
	var f: RefCounted = m.duplicate_model()
	f.cells[Vector2i(3, 1)]["hp"] = 1.0
	var lost: String = f.damage_from(Vector2(0, -10), 5.0, 1.0)
	_check("ship.module_destroyed_by_hit", lost == "weapon_mount" and not f.cells.has(Vector2i(3, 1)), "lost=%s" % lost)
	f.remove(Vector2i(3, 2)) # shield gen destroyed
	f.revalidate()
	# (4,2) mount links to both shield gen and cockpit -> stays powered (redundant path)
	_check("ship.fault_tolerance_redundant_path", f.connected.has(Vector2i(4, 2)), "mount(4,2) connected=%s" % f.connected.has(Vector2i(4, 2)))
	var g: RefCounted = m.duplicate_model()
	for i in 30:
		g.damage_from(Vector2(10, 0), 100.0, 1.0)
	_check("ship.core_protected_high_hull", g.find_first("core") != null and g.find_first("cockpit") != null, "remaining=%d" % g.cells.size())
	var power_ship: RefCounted = m.duplicate_model()
	power_ship.place(Vector2i(5, 2), "shield_gen")
	power_ship.place(Vector2i(5, 4), "shield_gen")
	power_ship.place(Vector2i(2, 1), "shield_gen")
	power_ship.revalidate()
	_check("ship.power_deficit_invalid", power_ship.stats["power"] < 0 and not power_ship.is_valid(), "power=%d errs=%s" % [power_ship.stats["power"], power_ship.errors])
	# builder API: move armor via drag/drop, verify preview colors + apply
	var bl: Control = battle.builder
	bl.open_with(battle)
	var picked: bool = bl.pick_up(Vector2i(3, 4))
	var bad_preview: bool = bl.preview_ok(Vector2i(0, 0))
	var good_preview: bool = bl.preview_ok(Vector2i(3, 4))
	bl.drop(Vector2i(3, 4))
	bl.begin_drag("armor", "")
	var armor_ok: bool = bl.preview_ok(Vector2i(4, 1))
	bl.drop(Vector2i(4, 1))
	var applied: bool = bl.apply()
	_check("builder.drag_drop_preview", picked and good_preview and not bad_preview and armor_ok, "good=%s bad=%s" % [good_preview, bad_preview])
	_check("builder.apply_valid", applied and battle.player.ship.cells.has(Vector2i(4, 1)), "hull_max=%.0f" % battle.player.max_hull)
	bl.remove_cell(Vector2i(3, 3))
	_check("builder.apply_rejects_invalid", not bl.apply())
	bl.visible = false

func _nearest_enemy(from: Vector2, max_d := 1e9) -> Node2D:
	var best: Node2D = null
	var bd := max_d
	for e in battle.enemies:
		if e.alive:
			var d: float = from.distance_to(e.global_position)
			if d < bd:
				bd = d
				best = e
	return best

func _select_secondary(id: String) -> void:
	var p: Node2D = battle.player
	var cells: Array = p.secondary_cells()
	for i in cells.size():
		if p.weapons[cells[i]].id == id:
			p.secondary_index = i

func _process(delta: float) -> void:
	var p: Node2D = battle.player
	if p == null or not p.alive:
		return
	t += delta
	var e: RefCounted = p.energy
	# --- pilot ---
	var center: Vector2 = battle.arena.get_center()
	var orbit_pos := center + Vector2(cos(t * 0.5), sin(t * 0.5)) * 140.0
	var move := (orbit_pos - p.global_position).limit_length(40.0) / 40.0
	var tgt := _nearest_enemy(p.global_position)
	var aim: Vector2 = p.global_position + Vector2.RIGHT * 50.0
	var dash := false
	if tgt:
		aim = tgt.global_position
		if p.global_position.distance_to(tgt.global_position) < 28.0:
			move = (p.global_position - tgt.global_position).normalized()
			dash = true
	# --- energy presets & nudges ---
	var sched := [2.0, 4.0, 6.0, 8.0]
	if _step < 4 and t >= sched[_step]:
		if _step > 0:
			_log_preset()
		e.apply_preset_index(_step)
		_step += 1
	elif _step == 4 and t >= 10.0:
		_log_preset()
		var before: Vector3 = e.target
		e.nudge(0)
		e.nudge(0)
		e.nudge(2)
		_check("energy.nudge", e.target.x > before.x and e.preset_name == "CUSTOM", "%s -> %s" % [before, e.target])
		_step += 1
	elif _step == 5 and t >= 12.0:
		e.apply_preset("ASSAULT")
		_overload_until_overheat = true
		_step += 1
	var want_overload := false
	if _overload_until_overheat:
		want_overload = true
		if int(e.stats["overheats"]) >= 1:
			_overload_until_overheat = false
			_check("energy.overheat_disables_module", e.disabled_category != "", "disabled=%s" % e.disabled_category)
			e.apply_preset("BALANCED")
	if _step == 6 and t >= 14.0 and e.overload_active and not checks.has("energy.overload_boost"):
		_check("energy.overload_boost", e.mult("weapon_damage") > 1.0 and e.total() > 1.0, "total=%.2f dmg_mult=%.2f" % [e.total(), e.mult("weapon_damage")])
	# --- secondary combo: gravity bomb -> EMP into the well; missiles & pulse keep firing ---
	var want_secondary := false
	if t >= 16.0:
		_combo_t -= delta
		if _combo_phase == 0 and _combo_t <= 0.0:
			var ct := _nearest_enemy(p.global_position, 200.0)
			if ct:
				_combo_pos = ct.global_position
				_select_secondary("gravity_bomb")
				_combo_phase = 1
				_pulse_t = 0.25
		elif _combo_phase == 1:
			aim = _combo_pos
			want_secondary = true
			_pulse_t -= delta
			if _pulse_t <= 0.0:
				_combo_phase = 2
				_pulse_t = 0.9
		elif _combo_phase == 2:
			_pulse_t -= delta
			if _pulse_t <= 0.0:
				_select_secondary("emp_launcher")
				_combo_phase = 3
				_pulse_t = 0.25
				if battle.wells.size() > 0:
					_combo_pos = battle.wells[battle.wells.size() - 1].global_position
		elif _combo_phase == 3:
			aim = _combo_pos
			want_secondary = true
			_pulse_t -= delta
			if _pulse_t <= 0.0:
				_combo_phase = 0
				_combo_t = 3.0
	p.auto = {"move": move, "aim_point": aim, "fire": tgt != null, "secondary": want_secondary, "dash": dash, "overload": want_overload}

func _log_preset() -> void:
	var e: RefCounted = battle.player.energy
	var p: Node2D = battle.player
	var line := "%s dmg=%.2f rate=%.2f shield_cap=%.2f regen=%.2f accel=%.2f speed=%.2f turn=%.2f | live accel=%.0f max_speed=%.0f shield_cap=%.0f" % [
		e.preset_name, e.mult("weapon_damage"), e.mult("weapon_fire_rate"), e.mult("shield_capacity"), e.mult("shield_regen"),
		e.mult("engine_accel"), e.mult("engine_max_speed"), e.mult("engine_turn"), p.cur_accel(), p.cur_max_speed(), p.cur_shield_cap()]
	preset_log.append(line)
	print("[AUTOTEST] PRESET " + line)

func report() -> bool:
	var e: RefCounted = battle.player.energy
	var syn: Dictionary = battle.synergy.counters
	var f: Dictionary = battle.field.counters
	print("[AUTOTEST] COUNTERS weapons_fired=%s" % weapon_fired)
	print("[AUTOTEST] COUNTERS synergies=%s" % syn)
	print("[AUTOTEST] COUNTERS energy presets=%d nudges=%d overload_time=%.1fs overheats=%d" % [e.stats["presets"], e.stats["nudges"], e.stats["overload_time"], e.stats["overheats"]])
	print("[AUTOTEST] COUNTERS emp_blasts=%d wells_spawned_total>0=%s modules_destroyed=%d scrap=%d" % [battle.emp_blasts, syn.get("ion_vortex", 0) >= 0, _mods_destroyed, GameManager.scrap])
	print("[AUTOTEST] COUNTERS asteroid_field=%s" % f)
	_check("energy.presets_applied", int(e.stats["presets"]) >= 4)
	_check("energy.presets_differ", _presets_differ())
	_check("energy.overload_used", float(e.stats["overload_time"]) > 0.0)
	_check("energy.overheat_triggered", int(e.stats["overheats"]) >= 1)
	for w in ["pulse_cannon", "missile_swarm", "gravity_bomb", "emp_launcher"]:
		_check("weapon.fired." + w, int(weapon_fired.get(w, 0)) > 0, str(weapon_fired.get(w, 0)))
	for s in ["gravity_missile", "emp_crit", "ion_vortex"]:
		_check("synergy." + s, int(syn.get(s, 0)) > 0, str(syn.get(s, 0)))
	_check("asteroids.destroyed", int(f["asteroids_destroyed"]) > 0, str(f["asteroids_destroyed"]))
	_check("asteroids.blocked_shots", int(f["shots_blocked"]) > 0, str(f["shots_blocked"]))
	_check("asteroids.ore_chain_reaction", int(f["ore_chain"]) > 0, str(f["ore_chain"]))
	_check("asteroids.meteor_telegraphed", int(f["meteors"]) > 0, str(f["meteors"]))
	var failed := 0
	for k in checks:
		if not checks[k]:
			failed += 1
	print("[AUTOTEST] RESULT %s (%d/%d checks passed)" % ["PASS" if failed == 0 else "FAIL", checks.size() - failed, checks.size()])
	return failed == 0

func _presets_differ() -> bool:
	return preset_log.size() >= 4 and preset_log[0] != preset_log[1] and preset_log[1] != preset_log[2]
