extends Node2D
## Player ship built from a modular ShipModel, driven by the Dynamic Energy Core.
## Input comes from InputManager, or from `auto` (autotest driver) when set.
const PixelLib = preload("res://scripts/pixel.gd")
const WeaponScript = preload("res://scripts/weapon.gd")
const ShipModel = preload("res://scripts/ship_model.gd")
const EnergyCore = preload("res://scripts/energy_core.gd")
const DRAG := 2.4
const DASH_SPEED := 420.0
const DASH_TIME := 0.18
const DASH_COOLDOWN := 1.2
const MIN_ACCEL := 60.0

var battle: Node
var ship: RefCounted
var energy: RefCounted
var weapons: Dictionary = {} # Vector2i -> Weapon
var secondary_index := 0
var velocity := Vector2.ZERO
var radius := 7.0
var max_hull := 100.0
var hull := 100.0
var max_shield := 50.0
var shield := 50.0
var shield_timer := 0.0
var dash_cd := 0.0
var dash_timer := 0.0
var flash := 0.0
var alive := true
var thrusting := false
var flame_phase := 0.0
var aim_dir := Vector2.RIGHT
var aim_point := Vector2.ZERO
var god := false
var auto: Dictionary = {} # autotest input override
var modules_lost: Array = []

func setup(b: Node) -> void:
	battle = b
	god = GameManager.autotest_god
	energy = EnergyCore.new(GameManager.run_seed + 7)
	energy.overheated.connect(func(cat: String, dur: float) -> void:
		EventBus.core_overheated.emit(cat, dur))
	energy.preset_applied.connect(func(n: String) -> void: EventBus.preset_changed.emit(n))
	set_ship(ShipModel.from_file("res://data/ships/default_ship.json"), true)

func set_ship(model: RefCounted, full_heal := false) -> void:
	var hull_ratio := 1.0 if full_heal else hull / maxf(1.0, max_hull)
	ship = model
	weapons.clear()
	var i := 0
	for c in ship.cells:
		var w: String = ship.cells[c]["weapon"]
		if w != "":
			weapons[c] = WeaponScript.new("res://data/weapons/%s.json" % w, GameManager.run_seed + i)
			i += 1
	_refresh_stats()
	hull = max_hull * hull_ratio
	if full_heal:
		shield = max_shield
	EventBus.ship_rebuilt.emit()

func _refresh_stats() -> void:
	max_hull = float(ship.stats["hull"])
	hull = minf(hull, max_hull)
	radius = ship.extent_radius()
	energy.cooling_bonus = float(ship.stats["cooling"])

func loadout_ids() -> Array:
	var out: Array = []
	for c in weapons:
		if ship.connected.has(c):
			out.append(weapons[c].id)
	return out

func secondary_cells() -> Array:
	var out: Array = []
	for c in weapons:
		if ship.connected.has(c) and weapons[c].slot == "secondary":
			out.append(c)
	out.sort()
	return out

func selected_secondary() -> RefCounted:
	var s := secondary_cells()
	if s.is_empty():
		return null
	return weapons[s[secondary_index % s.size()]]

func cycle_secondary() -> void:
	secondary_index += 1

# --- derived live stats (modules x energy) ---
func cur_accel() -> float:
	return maxf(MIN_ACCEL, float(ship.stats["accel"])) * energy.mult("engine_accel")
func cur_max_speed() -> float:
	return float(ship.stats["max_speed"]) * energy.mult("engine_max_speed")
func cur_turn() -> float:
	var t: float = deg_to_rad(float(ship.stats["turn"])) * energy.mult("engine_turn")
	return t * (0.5 if energy.is_disabled("side_thruster") else 1.0)
func cur_shield_cap() -> float:
	return float(ship.stats["shield"]) * energy.mult("shield_capacity")
func cur_shield_regen() -> float:
	return 0.0 if energy.is_disabled("shield_gen") else float(ship.stats["shield_regen"]) * energy.mult("shield_regen")

func _process(delta: float) -> void:
	if not alive:
		return
	var move: Vector2
	var want_fire := false
	var want_secondary := false
	var want_dash := false
	var want_overload := false
	if not auto.is_empty():
		move = auto.get("move", Vector2.ZERO)
		aim_point = auto.get("aim_point", global_position + aim_dir * 50.0)
		want_fire = auto.get("fire", false)
		want_secondary = auto.get("secondary", false)
		want_dash = auto.get("dash", false)
		want_overload = auto.get("overload", false)
		auto["dash"] = false
	else:
		move = InputManager.get_move_vector()
		var stick := InputManager.get_stick_aim()
		if stick != Vector2.ZERO:
			aim_point = global_position + stick * 120.0
		elif not InputManager.using_gamepad:
			aim_point = get_global_mouse_position()
		var blocked: bool = battle.ui_blocks_fire()
		want_fire = Input.is_action_pressed("fire") and not blocked
		want_secondary = Input.is_action_pressed("fire_secondary") and not blocked
		want_dash = Input.is_action_just_pressed("dash")
		want_overload = Input.is_action_pressed("overload")
		if Input.is_action_just_pressed("cycle_secondary"):
			cycle_secondary()
		for i in 4:
			if Input.is_action_just_pressed("preset_%d" % (i + 1)):
				energy.apply_preset_index(i)
		if Input.is_action_just_pressed("nudge_weapon"):
			energy.nudge(0)
		if Input.is_action_just_pressed("nudge_shield"):
			energy.nudge(1)
		if Input.is_action_just_pressed("nudge_engine"):
			energy.nudge(2)
	var to_aim := aim_point - global_position
	if to_aim.length() > 2.0:
		aim_dir = to_aim.normalized()
	energy.set_overload(want_overload)
	energy.update(delta)
	max_shield = cur_shield_cap()
	shield = minf(shield, max_shield)
	# movement with inertia
	thrusting = move.length() > 0.1
	velocity += move.limit_length(1.0) * cur_accel() * delta
	velocity -= velocity * DRAG * delta
	dash_cd = maxf(0.0, dash_cd - delta)
	if want_dash and dash_cd <= 0.0:
		var ddir := move.normalized() if thrusting else aim_dir
		velocity = ddir * DASH_SPEED
		dash_timer = DASH_TIME
		dash_cd = DASH_COOLDOWN * energy.mult("engine_dash_cooldown")
		EventBus.dash_used.emit()
		battle.spawn_dash_trail(global_position, ddir)
	if dash_timer > 0.0:
		dash_timer -= delta
	elif velocity.length() > cur_max_speed():
		velocity = velocity.normalized() * cur_max_speed()
	global_position += velocity * delta
	battle.constrain_player(self, delta)
	rotation = rotate_toward(rotation, aim_dir.angle(), cur_turn() * delta)
	# weapons
	var dmg_m: float = energy.mult("weapon_damage")
	var rate_m: float = energy.mult("weapon_fire_rate")
	var diss_m: float = energy.mult("weapon_heat_dissipation")
	var sec := selected_secondary()
	var mounts_off: bool = energy.is_disabled("weapon_mount")
	for c in weapons:
		var w: RefCounted = weapons[c]
		w.update(delta, diss_m)
		if not ship.connected.has(c) or mounts_off:
			continue
		var fire_it: bool = (w.slot == "primary" and want_fire) or (w == sec and want_secondary)
		if fire_it:
			_fire_mount(c, w, dmg_m, rate_m)
	shield_timer -= delta
	if shield_timer <= 0.0:
		shield = minf(max_shield, shield + cur_shield_regen() * delta)
	flash = maxf(0.0, flash - delta)
	flame_phase += delta * 30.0
	queue_redraw()

## Fire a mount only if the aim direction lies inside the mount's firing arc.
func mount_world_facing(c: Vector2i) -> float:
	return rotation + ship.mount_facing(c)

func in_arc(c: Vector2i, dir: Vector2) -> bool:
	return absf(angle_difference(mount_world_facing(c), dir.angle())) <= ship.mount_arc(c) * 0.5

func _fire_mount(c: Vector2i, w: RefCounted, dmg_m: float, rate_m: float) -> void:
	var origin: Vector2 = global_position + ship.local_pos(c).rotated(rotation)
	var dir: Vector2 = (aim_point - origin).normalized()
	if dir == Vector2.ZERO or not in_arc(c, dir):
		return
	w.try_fire(battle, origin + dir * 3.0, dir, aim_point, dmg_m, rate_m)

func is_invulnerable() -> bool:
	return dash_timer > 0.0 or god

func take_damage(amount: float, from_pos: Vector2) -> void:
	if not alive or is_invulnerable():
		return
	shield_timer = float(ship.base.get("shield_regen_delay", 2.0))
	var absorbed := minf(shield, amount)
	shield -= absorbed
	var rest := amount - absorbed
	hull -= rest
	flash = 0.12
	EventBus.player_damaged.emit(amount, from_pos)
	battle.shake(2.0 if rest <= 0.0 else 4.0)
	if rest > 0.0:
		var local_dir := (from_pos - global_position).rotated(-rotation)
		var lost: String = ship.damage_from(local_dir, rest * 0.6, hull / maxf(1.0, max_hull))
		if lost != "":
			modules_lost.append(lost)
			battle.spawn_explosion(global_position + local_dir.normalized() * radius, PixelLib.C_GOLD, 14)
			battle.spawn_float_text(global_position + Vector2(0, -16), tr("FT_MODULE_LOST") % tr("MOD_" + lost.to_upper()), PixelLib.C_RED, 1.4, "alert")
			EventBus.module_destroyed.emit(lost)
			if lost == "core" or lost == "cockpit":
				hull = 0.0
			_refresh_stats()
	if hull <= 0.0:
		hull = 0.0
		alive = false
		visible = false
		battle.spawn_explosion(global_position, PixelLib.C_CYAN, 40)
		EventBus.player_died.emit()

func _draw() -> void:
	var tint := Color.WHITE
	if flash > 0.0:
		tint = Color(3, 3, 3)
	elif dash_timer > 0.0:
		tint = Color(1, 1, 1, 0.6)
	var cs: int = ShipModel.CELL_PX
	for c in ship.cells:
		var id: String = ship.cells[c]["id"]
		var d: Dictionary = ship.defs[id]
		var p: Vector2 = ship.local_pos(c) - Vector2(cs, cs) * 0.5
		var col := Color(d["color"])
		if not ship.connected.has(c):
			col = col.darkened(0.7)
		elif energy.is_disabled(id) and int(flame_phase) % 4 < 2:
			col = PixelLib.C_RED
		var dmg_k: float = ship.cells[c]["hp"] / ship.cells[c]["max_hp"]
		draw_rect(Rect2(p, Vector2(cs, cs)), (col * tint).darkened(0.5 * (1.0 - dmg_k)))
		draw_rect(Rect2(p, Vector2(1, 1)), Color(PixelLib.C_WHITE, 0.5))
		if id == "main_thruster" and (thrusting or dash_timer > 0.0):
			var flen := 2 + int(flame_phase) % 3 + (4 if dash_timer > 0.0 else 0)
			draw_rect(Rect2(p + Vector2(-flen, 1), Vector2(flen, 1)), PixelLib.C_GOLD)
			draw_rect(Rect2(p + Vector2(-flen - 1, 1), Vector2(1, 1)), PixelLib.C_RED)
	if shield > 1.0 and flash > 0.0:
		draw_arc(Vector2.ZERO, radius + 3, 0, TAU, 16, Color(PixelLib.C_CYAN, 0.6), 1.0)
