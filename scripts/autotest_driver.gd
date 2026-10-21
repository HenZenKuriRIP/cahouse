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
var _push_time := 0.0
var _node_samples: Array = [] # [run_time, nodes, chunks, asteroids]
var _sample_t := 0.0

func setup(b: Node) -> void:
	battle = b
	EventBus.weapon_fired.connect(func(id: String) -> void: weapon_fired[id] = int(weapon_fired.get(id, 0)) + 1)
	EventBus.module_destroyed.connect(func(id: String) -> void:
		_mods_destroyed += 1
		print("[AUTOTEST] module destroyed: %s at t=%.1f" % [id, GameManager.run_time]))
	_ship_validation_tests()
	_i18n_tests()
	# fixture: an isolated ore cluster far from the player to exercise the chain reaction
	var fld: Node2D = battle.field
	var base := Vector2(-70, -330)
	var o1: Node2D = fld._spawn(base, 10.0, true, Vector2.ZERO)
	fld._spawn(base + Vector2(30, 0), 10.0, true, Vector2.ZERO)
	fld._spawn(base + Vector2(60, 10), 10.0, true, Vector2.ZERO)
	o1.ignite(false)

var _touch_phase := 0
var _touch_t0 := 0.0
var _touch_fired0 := 0
var _touch_was := false

func _st(idx: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.pressed = pressed
	ev.position = pos
	return ev

func _sd(idx: int, pos: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	return ev

## Simulated multi-touch: left stick (move) and right stick (aim + fire) held at the same time by two fingers,
## then buttons and a third/fourth finger on the energy triangle. Events go through TouchControls.handle(), the
## same function its _input() calls, using logical viewport coordinates.
func _touch_tests(p: Node2D) -> void:
	var tc: Control = battle.touch
	p.auto = {}
	if _touch_phase == 0:
		_touch_was = tc.enabled
		tc.enabled = true
		var n := 0
		for k in weapon_fired:
			n += int(weapon_fired[k])
		_touch_fired0 = n
		var a: bool = tc.handle(_st(0, true, Vector2(60, 330)))
		var b: bool = tc.handle(_st(1, true, Vector2(190, 330)))
		tc.handle(_sd(0, Vector2(60, 300)))
		tc.handle(_sd(1, Vector2(215, 330)))
		_check("touch.both_sticks_claimed", a and b and tc.fingers.size() == 2, "fingers=%d" % tc.fingers.size())
		_touch_t0 = t
		_touch_phase = 1
		return
	if t - _touch_t0 < 0.4:
		return
	var n2 := 0
	for k in weapon_fired:
		n2 += int(weapon_fired[k])
	_check("touch.multitouch_move_and_aim", tc.move_vec.y < -0.9 and tc.aim_vec.x > 0.9 and tc.aim_active(),
		"move=%s aim=%s" % [tc.move_vec, tc.aim_vec])
	_check("touch.player_moves_aims_fires", p.velocity.y < -20.0 and p.aim_dir.x > 0.9 and n2 > _touch_fired0,
		"vel=%s aim_dir=%s shots=%d" % [p.velocity, p.aim_dir, n2 - _touch_fired0])
	# floating base follows the thumb when dragged past the radius
	tc.handle(_sd(0, Vector2(60, 230)))
	var o: Vector2 = tc.fingers[0]["origin"]
	_check("touch.floating_stick_follows", absf(o.y - (230.0 + tc.STICK_R)) < 0.5, "origin=%s" % o)
	# buttons with a third finger while both sticks stay held
	var bs: Dictionary = tc.buttons()
	tc.handle(_st(2, true, bs["overload"].get_center()))
	var ov: bool = tc.overload_held
	tc.handle(_st(2, false, bs["overload"].get_center()))
	tc.handle(_st(2, true, bs["dash"].get_center()))
	tc.handle(_st(2, false, bs["dash"].get_center()))
	var sec0: int = p.secondary_index
	tc.handle(_st(2, true, bs["swap"].get_center()))
	tc.handle(_st(2, false, bs["swap"].get_center()))
	_check("touch.buttons", ov and not tc.overload_held and tc._dash_q and tc._swap_q and tc.max_concurrent >= 3,
		"overload=%s dash_q=%s swap_q=%s max_fingers=%d" % [ov, tc._dash_q, tc._swap_q, tc.max_concurrent])
	tc.consume_dash()
	tc.consume_swap()
	# energy triangle: finger 3 drags toward the weapon vertex, finger 4 taps the DEFENSE chip
	var w: Control = battle.hud.widget
	var top: Vector2 = w.global_position + w.verts()[0] + Vector2(0, 3)
	tc.handle(_st(3, true, w.global_position + w.verts()[2]))
	tc.handle(_sd(3, top))
	var wt: float = p.energy.target.x
	tc.handle(_st(3, false, top))
	tc.handle(_st(4, true, w.global_position + w.chip_rect(1).get_center()))
	tc.handle(_st(4, false, w.global_position + w.chip_rect(1).get_center()))
	_check("touch.energy_triangle", wt > 0.6 and p.energy.preset_name == "DEFENSE", "weapon_w=%.2f preset=%s" % [wt, p.energy.preset_name])
	tc.handle(_st(0, false, Vector2.ZERO))
	tc.handle(_st(1, false, Vector2.ZERO))
	_check("touch.release_clears", tc.fingers.is_empty() and tc.move_vec == Vector2.ZERO and not tc.aim_active(), "fingers=%d" % tc.fingers.size())
	tc.enabled = _touch_was
	p.energy.apply_preset("BALANCED")
	_touch_phase = 2

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
	_check("ship.no_core_invalid", not a.is_valid() and "ERR_NO_CORE" in a.errors, str(a.errors))
	var b: RefCounted = m.duplicate_model()
	b.place(Vector2i(0, 0), "armor")
	b.revalidate()
	_check("ship.disconnected_invalid", not b.is_valid() and not b.connected.has(Vector2i(0, 0)), str(b.errors))
	var c: RefCounted = m.duplicate_model()
	c.place(Vector2i(1, 3), "armor")
	c.revalidate()
	_check("ship.exhaust_blocked_invalid", "ERR_EXHAUST" in c.errors, str(c.errors))
	var d: RefCounted = m.duplicate_model()
	d.remove(Vector2i(2, 3))
	d.revalidate()
	_check("ship.no_thrust_invalid", "ERR_NO_THRUST" in d.errors, str(d.errors))
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

func _i18n_tests() -> void:
	var prev: String = Loc.language
	Loc.set_language("en", false)
	var en_hull := tr("HUD_HULL")
	var en_menu := tr("MENU_RESUME")
	Loc.set_language("zh", false)
	var zh_hull := tr("HUD_HULL")
	var zh_menu := tr("MENU_RESUME")
	_check("i18n.en_loaded", en_hull == "HULL" and en_menu == "RESUME", "%s/%s" % [en_hull, en_menu])
	_check("i18n.zh_loaded", zh_hull == "船体" and zh_menu == "继续", "%s/%s" % [zh_hull, zh_menu])
	_check("i18n.switch_changes_text", en_hull != zh_hull and en_menu != zh_menu)
	# every key used in code (tr-literal keys) + data-driven dynamic keys must exist in both languages
	var used := {}
	var re := RegEx.new()
	re.compile("tr\\(\"([A-Z][A-Z0-9_]+)\"\\)")
	for dir in ["res://scripts", "res://autoload"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir + "/" + f)
			for m in re.search_all(src):
				used[m.get_string(1)] = true
	var mods: Dictionary = GameManager.load_json("res://data/modules.json")
	for id in mods:
		used["MOD_" + str(id).to_upper()] = true
		used["ABBR_" + str(id).to_upper()] = true
	for w in ["pulse_cannon", "missile_swarm", "gravity_bomb", "emp_launcher"]:
		used["WPN_" + w.to_upper()] = true
		used["WPNA_" + w.to_upper()] = true
	for sid in GameManager.load_json("res://data/synergies.json"):
		used["SYN_" + str(sid).to_upper()] = true
	for pn in GameManager.load_json("res://data/energy.json")["preset_order"]:
		used["PRESET_" + str(pn)] = true
	used["PRESET_CUSTOM"] = true
	for k in battle.player.ship.errors:
		used[k] = true
	for k in ["ERR_NO_CORE", "ERR_MULTI_CORE", "ERR_NO_COCKPIT", "ERR_DISCONNECTED", "ERR_EXHAUST", "ERR_NO_THRUST", "ERR_POWER",
			"BLD_MSG_DRAG", "BLD_MSG_PLACED", "BLD_MSG_REMOVED", "BLD_MSG_APPLIED", "BLD_MSG_INVALID", "BLD_APPLY", "BLD_RESET", "BLD_CLOSE",
			"MENU_RESUME", "MENU_RESTART", "MENU_QUIT", "MENU_REDUCE_FLASH", "MENU_LANGUAGE", "MENU_ON", "MENU_OFF"]:
		used[k] = true
	var missing: PackedStringArray = []
	for k in used:
		for lang in ["en", "zh"]:
			if not Loc.has_key(k, lang):
				missing.append("%s[%s]" % [k, lang])
	var unused := 0
	for k in Loc.keys:
		if not used.has(k):
			unused += 1
	_check("i18n.no_missing_keys", missing.is_empty(), "used=%d csv=%d unused_in_code=%d missing=%s" % [used.size(), Loc.keys.size(), unused, missing])
	_check("i18n.font_loaded", Loc.font != null and ThemeDB.fallback_font == Loc.font, "glyph 信 supported=%s" % (Loc.font.has_char("信".unicode_at(0)) if Loc.font else false))
	Loc.set_language(prev, false)

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
	_sample_t += delta
	if _sample_t >= 10.0:
		_sample_t = 0.0
		var sample := [GameManager.run_time, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), battle.field.chunks.size(), battle.field.asteroids.size()]
		_node_samples.append(sample)
		print("[AUTOTEST] t=%.0fs dist=%.0fm nodes=%d chunks=%d asteroids=%d enemies=%d" % [sample[0], battle.distance(), sample[1], sample[2], sample[3], battle.enemies.size()])
	if t >= 0.5 and _touch_phase < 2:
		_touch_tests(p)
		return
	var e: RefCounted = p.energy
	# --- pilot ---
	# weave across the band in the lower half; every 20s push ahead for 4s to test push-scrolling
	var orbit_pos := Vector2(sin(t * 0.7) * 90.0, battle.scroll_y + 70.0 + sin(t * 0.4) * 40.0)
	if fmod(t, 20.0) > 16.0:
		orbit_pos.y = battle.scroll_y - 200.0
		_push_time += delta
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
				_combo_phase = 4
				_pulse_t = 0.8
		elif _combo_phase == 4:
			# follow up with primaries on EMP-marked targets
			var marked: Node2D = null
			for en in battle.enemies:
				if en.alive and en.emp_timer > 0.0:
					marked = en
					break
			if marked:
				aim = marked.global_position
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
	var f2: Dictionary = battle.field.counters
	_check("chunks.generated_and_freed", int(f2["chunks_generated"]) > 3 and int(f2["chunks_freed"]) > 0, "generated=%d freed=%d active=%d" % [f2["chunks_generated"], f2["chunks_freed"], battle.field.chunks.size()])
	_check("chunks.active_bounded", battle.field.chunks.size() <= 5, str(battle.field.chunks.size()))
	var max_nodes := 0
	var late_max := 0
	for smp in _node_samples:
		max_nodes = maxi(max_nodes, smp[1])
		if smp[0] > GameManager.run_time * 0.5:
			late_max = maxi(late_max, smp[1])
	_check("nodes.bounded", _node_samples.size() >= 3 and max_nodes < 900, "max=%d late_max=%d samples=%d" % [max_nodes, late_max, _node_samples.size()])
	var min_expected: float = battle.base_scroll_speed * GameManager.run_time * 0.98
	_check("scroll.progresses", battle.distance() >= min_expected, "distance=%.0f >= %.0f (base speed x time)" % [battle.distance(), min_expected])
	_check("scroll.push_ahead", _push_time <= 0.0 or battle.distance() > battle.base_scroll_speed * GameManager.run_time + 5.0, "distance=%.0f base_only=%.0f push_time=%.1fs" % [battle.distance(), battle.base_scroll_speed * GameManager.run_time, _push_time])
	_check("asteroids.meteor_telegraphed", int(f["meteors"]) > 0, str(f["meteors"]))
	var failed := 0
	for k in checks:
		if not checks[k]:
			failed += 1
	print("[AUTOTEST] RESULT %s (%d/%d checks passed)" % ["PASS" if failed == 0 else "FAIL", checks.size() - failed, checks.size()])
	return failed == 0

func _presets_differ() -> bool:
	return preset_log.size() >= 4 and preset_log[0] != preset_log[1] and preset_log[1] != preset_log[2]
