extends Node
## Seeded wave spawner driven by data/waves.json over the run duration.
var battle: Node
var rng := RandomNumberGenerator.new()
var waves: Array = []
var enemy_defs: Dictionary = {}
var run_duration := 180.0
var spawn_radius := 290.0
var max_enemies := 60
var wave_index := -1
var spawn_timer := 0.0
var spawned_total := 0

func setup(b: Node, seed_value: int) -> void:
	battle = b
	rng.seed = seed_value
	var w: Dictionary = GameManager.load_json("res://data/waves.json")
	waves = w["waves"]
	run_duration = float(w["run_duration"])
	spawn_radius = float(w["spawn_radius"])
	max_enemies = int(w["max_enemies"])
	enemy_defs = GameManager.load_json("res://data/enemies/enemies.json")

var culled_total := 0

func tick(t: float, delta: float) -> void:
	# despawn enemies left far behind the scrolling view (not a kill)
	var cull_y: float = battle.view_rect().end.y + 120.0
	for e in battle.enemies.duplicate():
		if e.global_position.y > cull_y:
			culled_total += 1
			battle.remove_enemy(e)
	var idx := 0
	for i in waves.size():
		if t >= float(waves[i]["start"]):
			idx = i
	if idx != wave_index:
		wave_index = idx
		spawn_timer = 0.0
		EventBus.wave_started.emit(idx)
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		var wave: Dictionary = waves[wave_index]
		spawn_timer = float(wave["interval"])
		for i in int(wave["count"]):
			if battle.enemies.size() >= max_enemies:
				break
			_spawn(_pick(wave["weights"]))

func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys()[0]

func _spawn(type_id: String) -> void:
	# spawn ahead (top edge) 70%, flanks (upper half, outside the band) 30%
	var v: Rect2 = battle.view_rect()
	var pos: Vector2
	if rng.randf() < 0.7:
		pos = Vector2(rng.randf_range(v.position.x + 10, v.end.x - 10), v.position.y - 20.0)
	else:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		pos = Vector2(side * (v.size.x / 2.0 + 16.0), rng.randf_range(v.position.y + 20, v.get_center().y))
	spawned_total += 1
	battle.spawn_enemy(type_id, enemy_defs[type_id], pos, rng.randi())
