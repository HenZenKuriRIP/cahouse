extends Node2D
## Environment: ASTEROID FIELD. Seeded asteroids that block shots, drop scrap, explosive ore chains,
## and telegraphed meteor crossings (2s warning line + marker).
const PixelLib = preload("res://scripts/pixel.gd")
const AsteroidScript = preload("res://scripts/asteroid.gd")
var battle: Node
var cfg: Dictionary
var rng := RandomNumberGenerator.new()
var asteroids: Array = []
var pickups: Array = [] # [pos: Vector2, value: int, vel: Vector2]
var warnings: Array = [] # [start: Vector2, dir: Vector2, time_left: float]
var meteor_timer := 0.0
var counters := {"asteroids_destroyed": 0, "ore_explosions": 0, "ore_chain": 0, "scrap_collected": 0, "meteors": 0, "shots_blocked": 0, "chunks_generated": 0, "chunks_freed": 0, "asteroids_culled": 0}
## Endless vertical field: chunk k covers world y in [-(k+1)*H, -k*H]. Each chunk is generated from its own
## seeded RNG (run seed + k), so the same seed always yields the same field. Chunks far below the view are freed.
var chunks: Dictionary = {} # k -> Array of asteroids
var next_chunk := 0
var base_seed := 0
var chunk_h := 480.0

func setup(b: Node, seed_value: int) -> void:
	battle = b
	cfg = GameManager.load_json("res://data/environments/asteroid_field.json")
	base_seed = seed_value
	rng.seed = seed_value
	chunk_h = float(cfg["chunk_height"])
	meteor_timer = float(cfg["meteor_interval"]) * 0.5
	_update_chunks()

func _chunk_seed(k: int) -> int:
	return hash([base_seed, k])

func _generate_chunk(k: int) -> void:
	var crng := RandomNumberGenerator.new()
	crng.seed = _chunk_seed(k)
	var list: Array = []
	var half: float = battle.band_half
	for i in int(cfg["per_chunk"]):
		var pos := Vector2(crng.randf_range(-half, half), -k * chunk_h - crng.randf() * chunk_h)
		if k == 0 and pos.length() < float(cfg["safe_radius"]):
			continue
		var r := crng.randf_range(float(cfg["min_radius"]), float(cfg["max_radius"]))
		var v := Vector2.from_angle(crng.randf() * TAU) * crng.randf_range(0.0, float(cfg["drift"]))
		var a := _spawn(pos, r, crng.randf() < float(cfg["ore_chance"]), v, crng.randi())
		list.append(a)
	chunks[k] = list
	counters["chunks_generated"] += 1

func _update_chunks() -> void:
	var top_needed := int(floor(battle.distance() / chunk_h)) + int(cfg["chunks_ahead"])
	while next_chunk <= top_needed:
		_generate_chunk(next_chunk)
		next_chunk += 1
	var cull_y: float = battle.view_rect().end.y + float(cfg["cull_below"])
	for k in chunks.keys():
		var chunk_top: float = -(k + 1) * chunk_h
		if chunk_top > cull_y:
			for a in chunks[k]:
				if is_instance_valid(a) and a.alive:
					a.alive = false
					asteroids.erase(a)
					a.queue_free()
			chunks.erase(k)
			counters["chunks_freed"] += 1

func _spawn(pos: Vector2, r: float, is_ore: bool, v: Vector2, shape_seed := -1) -> Node2D:
	var a: Node2D = AsteroidScript.new()
	add_child(a)
	a.setup(self, pos, r, is_ore, v, shape_seed if shape_seed >= 0 else rng.randi(), float(cfg["hp_per_radius"]))
	asteroids.append(a)
	return a

func asteroid_at(pos: Vector2, r: float) -> Node2D:
	for a in asteroids:
		if a.alive and pos.distance_squared_to(a.global_position) < (a.radius + r) * (a.radius + r):
			counters["shots_blocked"] += 1
			return a
	return null

func destroy_asteroid(a: Node2D) -> void:
	if not a.alive:
		return
	a.alive = false
	asteroids.erase(a)
	counters["asteroids_destroyed"] += 1
	battle.spawn_explosion(a.global_position, Color("#6b7aa8"), int(a.radius))
	var n := maxi(1, int(a.radius * float(cfg["scrap_per_radius"])))
	for i in n:
		pickups.append([a.global_position, 1, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20, 60)])
	if a.radius >= 12.0 and not a.is_meteor:
		for i in 2:
			_spawn(a.global_position + Vector2.from_angle(rng.randf() * TAU) * 4.0, a.radius * 0.55, false, a.velocity + Vector2.from_angle(rng.randf() * TAU) * 25.0)
	a.queue_free()

func explode_ore(a: Node2D) -> void:
	if not a.alive:
		return
	a.alive = false
	asteroids.erase(a)
	counters["asteroids_destroyed"] += 1
	counters["ore_explosions"] += 1
	if a.chained:
		counters["ore_chain"] += 1
	var br := float(cfg["ore_blast_radius"])
	var dmg := float(cfg["ore_blast_damage"])
	var pos: Vector2 = a.global_position
	battle.spawn_explosion(pos, PixelLib.C_GOLD, 40)
	battle.shake(4.0)
	for e in battle.enemies.duplicate():
		if e.alive and e.global_position.distance_to(pos) < br:
			e.take_damage(dmg, false, "ore")
	if battle.player.alive and battle.player.global_position.distance_to(pos) < br:
		battle.player.take_damage(dmg * 0.5, pos)
	for o in asteroids.duplicate():
		if o.alive and o.global_position.distance_to(pos) < br + o.radius:
			if o.ore:
				o.ignite(true)
			else:
				o.take_damage(dmg)
	for i in 3:
		pickups.append([pos, 2, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(30, 80)])
	a.queue_free()

func _process(delta: float) -> void:
	_update_chunks()
	var view: Rect2 = battle.view_rect()
	var cull_y: float = view.end.y + float(cfg["cull_below"])
	var half: float = battle.band_half + 20.0
	var pl: Node2D = battle.player
	for a in asteroids.duplicate():
		if not a.alive:
			continue
		if a.global_position.y > cull_y or absf(a.global_position.x) > half + 200.0:
			a.alive = false
			asteroids.erase(a)
			counters["asteroids_culled"] += 1
			a.queue_free()
			continue
		if not a.is_meteor and absf(a.global_position.x) > half:
			a.velocity.x = -signf(a.global_position.x) * absf(a.velocity.x)
		if pl.alive:
			var off: Vector2 = pl.global_position - a.global_position
			var min_d: float = a.radius + pl.radius
			if off.length() < min_d:
				var n := off.normalized() if off.length() > 0.01 else Vector2.DOWN
				pl.global_position = a.global_position + n * min_d
				var rel: float = (pl.velocity - a.velocity).dot(-n)
				if rel > 0.0:
					pl.velocity += n * rel * 1.4
				if rel > 90.0 or a.is_meteor:
					pl.take_damage(8.0 if not a.is_meteor else 20.0, a.global_position)
					if a.is_meteor:
						destroy_asteroid(a)
	# pickups: magnet to player
	for p in pickups:
		p[2] = p[2] * (1.0 - 2.5 * delta)
		if pl.alive:
			var d: float = p[0].distance_to(pl.global_position)
			if d < 60.0:
				p[2] += (pl.global_position - p[0]).normalized() * 600.0 * delta
			if d < pl.radius + 4.0:
				p[1] = -p[1]
				counters["scrap_collected"] += -p[1]
				GameManager.scrap += -p[1]
		p[0] += p[2] * delta
	pickups = pickups.filter(func(p: Array) -> bool: return p[1] > 0 and p[0].y < cull_y)
	# telegraphed meteors
	meteor_timer -= delta
	if meteor_timer <= 0.0:
		meteor_timer = float(cfg["meteor_interval"])
		# meteors come from ahead (top of the view), aimed near the player
		var target: Vector2 = pl.global_position + Vector2(rng.randf_range(-50, 50), rng.randf_range(-20, 40))
		var start := Vector2(rng.randf_range(-battle.band_half, battle.band_half), view.position.y - 30.0)
		warnings.append([start, (target - start).normalized(), float(cfg["meteor_warning"])])
	for w in warnings:
		w[2] -= delta
		if w[2] <= 0.0:
			var m := _spawn(w[0], float(cfg["meteor_radius"]), false, w[1] * float(cfg["meteor_speed"]))
			m.is_meteor = true
			counters["meteors"] += 1
	warnings = warnings.filter(func(w: Array) -> bool: return w[2] > 0.0)
	queue_redraw()

func _draw() -> void:
	# band walls (soft limits), dashed, following the view
	var v: Rect2 = battle.view_rect()
	var wx: float = battle.band_half + 12.0
	var y0 := floorf(v.position.y / 16.0) * 16.0
	var y := y0
	while y < v.end.y:
		draw_line(Vector2(-wx, y), Vector2(-wx, y + 8), Color(PixelLib.C_VIOLET, 0.4), 1.0)
		draw_line(Vector2(wx, y), Vector2(wx, y + 8), Color(PixelLib.C_VIOLET, 0.4), 1.0)
		y += 16.0
	for p in pickups:
		draw_rect(Rect2(p[0].floor() - Vector2(1, 1), Vector2(3, 3)), PixelLib.C_GOLD if p[1] > 1 else PixelLib.C_CYAN)
	for w in warnings:
		var blink := int(w[2] * 8.0) % 2 == 0
		var col := Color(PixelLib.C_RED, 0.8 if blink else 0.3)
		var s: Vector2 = w[0]
		var d: Vector2 = w[1]
		for i in 50:
			if i % 2 == 0:
				draw_line(s + d * i * 12.0, s + d * (i * 12.0 + 6.0), col, 1.0)
		var mark: Vector2 = s + d * 120.0
		draw_rect(Rect2(mark - Vector2(1, 5), Vector2(2, 6)), col)
		draw_rect(Rect2(mark + Vector2(-1, 3), Vector2(2, 2)), col)
