extends Label
const PixelLib = preload("res://scripts/pixel.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
## F3 performance overlay.
var battle: Node
var _acc := 0.0

func _ready() -> void:
	position = Vector2(4, 44)
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", PixelLib.C_CYAN)
	visible = bool(SaveManager.settings.get("show_perf", false))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_perf"):
		visible = not visible
		SaveManager.set_setting("show_perf", visible)

func _process(delta: float) -> void:
	_acc += delta
	if not visible or _acc < 0.25:
		return
	_acc = 0.0
	text = summary()

func summary() -> String:
	return tr("PERF_TEXT") % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		battle.enemies.size() if battle else 0,
		ObjectPool.active(ProjectileScript.POOL_KEY), ObjectPool.created_total,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		battle.field.chunks.size() if battle else 0]
