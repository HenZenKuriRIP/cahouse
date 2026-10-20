extends Control
## Screen-edge pixel distortion when the core is hot / overloaded. reduce_flash => static, non-flicker border.
const PixelLib = preload("res://scripts/pixel.gd")
var battle: Node
var rng := RandomNumberGenerator.new()
var _t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	if battle == null or battle.player == null:
		return
	var e: RefCounted = battle.player.energy
	var k: float = clampf((e.heat_ratio() - 0.5) * 2.0, 0.0, 1.0)
	if e.overload_active:
		k = maxf(k, 0.25)
	if k <= 0.0:
		return
	var col := Color(PixelLib.C_RED, 0.25 + 0.5 * k)
	if bool(SaveManager.settings.get("reduce_flash", false)):
		var t := 1.0 + k * 3.0
		draw_rect(Rect2(0, 0, 480, t), col)
		draw_rect(Rect2(0, 270 - t, 480, t), col)
		draw_rect(Rect2(0, 0, t, 270), col)
		draw_rect(Rect2(480 - t, 0, t, 270), col)
		return
	rng.seed = int(_t * 15.0)
	var n := int(40 + 160 * k)
	for i in n:
		var side := rng.randi() % 4
		var depth := rng.randf() * (6.0 + 22.0 * k)
		var along := rng.randf()
		var p: Vector2
		match side:
			0: p = Vector2(along * 480, depth)
			1: p = Vector2(along * 480, 270 - depth)
			2: p = Vector2(depth, along * 270)
			_: p = Vector2(480 - depth, along * 270)
		var s := float(1 + rng.randi() % 3)
		var c := col if rng.randf() < 0.7 else Color(PixelLib.C_GOLD, col.a)
		draw_rect(Rect2(p.floor(), Vector2(s, s)), c)
