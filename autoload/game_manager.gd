extends Node
## Run state, seeds, data loading, command line flags.
enum State { PLAYING, PAUSED, WON, LOST }
var state: State = State.PLAYING
var run_seed: int = 0
var kills: int = 0
var run_time: float = 0.0
var sector_name: String = "SECTOR 01 // OUTER RIM"
var autotest_seconds: float = 0.0
var autotest_god: bool = false
var _seed_from_cli: bool = false
var _json_cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			autotest_seconds = float(a.split("=")[1])
		elif a == "--god":
			autotest_god = true
		elif a.begins_with("--seed="):
			run_seed = int(a.split("=")[1])
			_seed_from_cli = true
	EventBus.run_won.connect(func() -> void: state = State.WON)
	EventBus.run_lost.connect(func() -> void: state = State.LOST)
	EventBus.enemy_killed.connect(func(_t: String, _p: Vector2) -> void: kills += 1)

func start_run() -> void:
	state = State.PLAYING
	kills = 0
	run_time = 0.0
	if not _seed_from_cli:
		run_seed = 3287 if autotest_seconds > 0.0 else randi()

func load_json(path: String) -> Variant:
	if _json_cache.has(path):
		return _json_cache[path]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open data file: " + path)
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null:
		push_error("Invalid JSON: " + path)
		return {}
	_json_cache[path] = data
	return data
