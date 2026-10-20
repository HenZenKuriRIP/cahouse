class_name EnemyDirector
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

func tick(t: float, delta: float) -> void:
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
	var a := rng.randf() * TAU
	var pos: Vector2 = battle.player.global_position + Vector2(cos(a), sin(a)) * spawn_radius
	pos = pos.clamp(battle.arena.position, battle.arena.end)
	spawned_total += 1
	battle.spawn_enemy(type_id, enemy_defs[type_id], pos, rng.randi())
