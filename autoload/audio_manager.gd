extends Node
## Minimal procedural SFX: square/noise blips synthesized into AudioStreamWAV at startup.
const MIX_RATE := 22050
var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var sfx_volume_db: float = -10.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sounds["shoot"] = _make_tone(880.0, 0.05, false, -400.0)
	_sounds["hit"] = _make_tone(220.0, 0.06, true, 0.0)
	_sounds["explode"] = _make_tone(90.0, 0.3, true, -60.0)
	_sounds["dash"] = _make_tone(300.0, 0.12, false, 900.0)
	_sounds["hurt"] = _make_tone(140.0, 0.15, true, -100.0)
	_sounds["enemy_shoot"] = _make_tone(440.0, 0.06, false, -600.0)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	EventBus.weapon_fired.connect(func(_id: String) -> void: play("shoot"))
	EventBus.enemy_killed.connect(func(_t: String, _p: Vector2) -> void: play("explode"))
	EventBus.dash_used.connect(func() -> void: play("dash"))
	EventBus.player_damaged.connect(func(_a: float, _p: Vector2) -> void: play("hurt"))

func play(name: String) -> void:
	if not _sounds.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[name]
	p.volume_db = sfx_volume_db
	p.play()

func _make_tone(freq: float, dur: float, noise: bool, sweep: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq)
	for i in n:
		var t := float(i) / n
		var f := maxf(20.0, freq + sweep * t)
		phase += f / MIX_RATE
		var s: float = rng.randf_range(-1.0, 1.0) if noise else (1.0 if fmod(phase, 1.0) < 0.5 else -1.0)
		var env := (1.0 - t) * 0.5
		data[i] = int(clampf(s * env, -1.0, 1.0) * 127.0) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_8_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w

func stop_all() -> void:
	for p in _players:
		p.stop()
		p.stream = null

func _exit_tree() -> void:
	# Stop playbacks so no AudioStreamPlayback is alive at engine shutdown (avoids leak warnings).
	for p in _players:
		p.stop()
		p.stream = null
	_sounds.clear()
