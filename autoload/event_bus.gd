extends Node
## Global signal hub. Systems communicate through these signals only.
signal player_damaged(amount: float, from_pos: Vector2)
signal player_died
signal enemy_killed(enemy_type: String, pos: Vector2)
signal enemy_spawned(enemy_type: String)
signal wave_started(index: int)
signal run_won
signal run_lost
signal heat_changed(heat: float, overheated: bool)
signal dash_used
signal weapon_fired(weapon_id: String)
signal synergy_triggered(id: String, pos: Vector2)
signal module_destroyed(module_id: String)
signal core_overheated(category: String, duration: float)
signal preset_changed(name: String)
signal ship_rebuilt
