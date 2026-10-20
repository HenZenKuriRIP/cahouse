extends Control
const PixelLib = preload("res://scripts/pixel.gd")
const PlayerScript = preload("res://scripts/player.gd")
## HUD drawn procedurally: hull/shield (bottom-left), weapon/heat/dash (bottom-right),
## timer/sector/kills (top), damage direction indicators around the ship.
var battle: Node
var heat := 0.0
var overheated := false
var indicators: Array = [] # [angle, life]
var banner := ""
var banner_life := 0.0
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.heat_changed.connect(func(h: float, o: bool) -> void:
		heat = h
		overheated = o)
	EventBus.player_damaged.connect(_on_damaged)
	EventBus.wave_started.connect(func(i: int) -> void:
		banner = "WAVE %d // SIGNAL INTENSIFIES" % (i + 1)
		banner_life = 2.0)

func _on_damaged(_a: float, from_pos: Vector2) -> void:
	if battle and battle.player:
		indicators.append([(from_pos - battle.player.global_position).angle(), 0.8])

func _process(delta: float) -> void:
	for ind in indicators:
		ind[1] -= delta
	indicators = indicators.filter(func(i: Array) -> bool: return i[1] > 0.0)
	banner_life -= delta
	queue_redraw()

func _bar(pos: Vector2, w: float, frac: float, col: Color) -> void:
	draw_rect(Rect2(pos, Vector2(w + 2, 6)), PixelLib.C_PANEL)
	draw_rect(Rect2(pos + Vector2(1, 1), Vector2(floorf(w * clampf(frac, 0, 1)), 4)), col)

func _text(pos: Vector2, s: String, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos, s, align, w, 8, col)

func _draw() -> void:
	if battle == null or battle.player == null:
		return
	var p: PlayerScript = battle.player
	# bottom-left
	_text(Vector2(8, 244), "HULL", PixelLib.C_WHITE)
	_bar(Vector2(36, 238), 80, p.hull / p.max_hull, PixelLib.C_RED)
	_text(Vector2(8, 256), "SHLD", PixelLib.C_WHITE)
	_bar(Vector2(36, 250), 80, p.shield / p.max_shield, PixelLib.C_CYAN)
	# bottom-right
	_text(Vector2(352, 244), "PULSE CANNON", PixelLib.C_CYAN)
	_text(Vector2(352, 256), "HEAT" if not overheated else "OVERHEAT!", PixelLib.C_RED if overheated else PixelLib.C_WHITE)
	_bar(Vector2(400, 250), 70, heat, PixelLib.C_RED if overheated or heat > 0.75 else PixelLib.C_GOLD)
	var dash_frac := 1.0 - p.dash_cd / PlayerScript.DASH_COOLDOWN
	_text(Vector2(352, 232), "DASH", PixelLib.C_WHITE)
	_bar(Vector2(400, 226), 70, dash_frac, PixelLib.C_VIOLET)
	# top
	var remain := maxf(0.0, battle.run_duration - GameManager.run_time)
	_text(Vector2(0, 14), "%d:%02d" % [int(remain) / 60, int(remain) % 60], PixelLib.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, 480)
	_text(Vector2(8, 14), GameManager.sector_name, PixelLib.C_VIOLET)
	_text(Vector2(0, 14), "KILLS %d " % GameManager.kills, PixelLib.C_WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 472)
	if banner_life > 0.0:
		_text(Vector2(0, 40), banner, Color(PixelLib.C_CYAN, clampf(banner_life, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, 480)
	# damage direction
	var sp: Vector2 = p.get_global_transform_with_canvas().origin
	for ind in indicators:
		var a: float = ind[0]
		draw_arc(sp, 22, a - 0.35, a + 0.35, 6, Color(PixelLib.C_RED, clampf(ind[1] / 0.8, 0, 1)), 2.0)
