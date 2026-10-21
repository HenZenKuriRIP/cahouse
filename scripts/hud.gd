extends Control
## Portrait HUD (270x480). Top: sector, distance/goal, timer, kills/scrap. Bottom-left: hull/shield/dash +
## module map. Bottom-right: weapons/heat. Bottom-centre: compact energy triangle + core heat.
## All text via tr() keys (data/i18n/strings.csv).
const PixelLib = preload("res://scripts/pixel.gd")
const EnergyWidget = preload("res://scripts/energy_widget.gd")
const DASH_COOLDOWN := 1.2
const W := 270.0
const H := 480.0
const FS := 12
var battle: Node
var indicators: Array = []
var banner := ""
var banner_col := Color.WHITE
var banner_life := 0.0
var warn_cat := ""
var warn_life := 0.0
var font: Font
var widget: Control

func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	widget = EnergyWidget.new()
	widget.position = Vector2(108, 430)
	add_child(widget)
	EventBus.player_damaged.connect(_on_damaged)
	EventBus.wave_started.connect(func(i: int) -> void: _banner(tr("BANNER_WAVE") % (i + 1), PixelLib.C_CYAN))
	EventBus.synergy_triggered.connect(func(id: String, _p: Vector2) -> void:
		_banner(tr("BANNER_SYNERGY") % tr("SYN_" + id.to_upper()), PixelLib.C_VIOLET))
	EventBus.core_overheated.connect(func(cat: String, dur: float) -> void:
		warn_cat = cat
		warn_life = dur)
	EventBus.preset_changed.connect(func(n: String) -> void: _banner(tr("BANNER_PRESET") % tr("PRESET_" + n), PixelLib.C_GOLD))
	Loc.language_changed.connect(func(_l: String) -> void: _banner(tr("BANNER_LANGUAGE") % tr("LANG_NAME"), PixelLib.C_CYAN))

func bind(b: Node) -> void:
	battle = b
	widget.core = b.player.energy

func _banner(t: String, c: Color) -> void:
	banner = t
	banner_col = c
	banner_life = 1.6

func _on_damaged(_a: float, from_pos: Vector2) -> void:
	if battle and battle.player:
		indicators.append([(from_pos - battle.player.global_position).angle(), 0.8])

func _process(delta: float) -> void:
	for ind in indicators:
		ind[1] -= delta
	indicators = indicators.filter(func(i: Array) -> bool: return i[1] > 0.0)
	banner_life -= delta
	warn_life -= delta
	queue_redraw()

func _bar(pos: Vector2, w: float, frac: float, col: Color) -> void:
	draw_rect(Rect2(pos, Vector2(w + 2, 6)), PixelLib.C_PANEL)
	draw_rect(Rect2(pos + Vector2(1, 1), Vector2(floorf(w * clampf(frac, 0, 1)), 4)), col)

func _text(pos: Vector2, s: String, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos, s, align, w, FS, col)

func _draw() -> void:
	if battle == null or battle.player == null:
		return
	var p: Node2D = battle.player
	var e: RefCounted = p.energy
	# panel backdrop for the bottom HUD strip
	draw_rect(Rect2(0, 404, W, 76), Color(PixelLib.C_BG, 0.55))
	# --- top ---
	draw_rect(Rect2(0, 0, W, 30), Color(PixelLib.C_BG, 0.55))
	_text(Vector2(4, 12), tr("HUD_SECTOR"), PixelLib.C_VIOLET)
	var rt := int(GameManager.run_time)
	_text(Vector2(0, 12), "%d:%02d " % [rt / 60, rt % 60], PixelLib.C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT, W - 2)
	var dist_txt: String = tr("HUD_DISTANCE") % [int(battle.distance()), int(battle.distance_goal)] if not battle.endless else "%dm %s" % [int(battle.distance()), tr("HUD_ENDLESS")]
	_text(Vector2(4, 26), dist_txt, PixelLib.C_CYAN)
	_text(Vector2(0, 26), tr("HUD_KILLS") % GameManager.kills + " " + tr("HUD_SCRAP") % GameManager.scrap + " ", PixelLib.C_WHITE, HORIZONTAL_ALIGNMENT_RIGHT, W - 2)
	if not battle.endless:
		var prog := clampf(battle.distance() / battle.distance_goal, 0.0, 1.0)
		draw_rect(Rect2(0, 29, W, 1), PixelLib.C_PANEL)
		draw_rect(Rect2(0, 29, floorf(W * prog), 1), PixelLib.C_CYAN)
	_text(Vector2(4, 42), tr("HUD_ENV_ASTEROID"), Color(PixelLib.C_WHITE, 0.5))
	# --- bottom-left ---
	_text(Vector2(4, 440), tr("HUD_HULL"), PixelLib.C_WHITE)
	_bar(Vector2(34, 433), 66, p.hull / p.max_hull, PixelLib.C_RED)
	_text(Vector2(4, 454), tr("HUD_SHIELD"), PixelLib.C_RED if e.is_disabled("shield_gen") else PixelLib.C_WHITE)
	_bar(Vector2(34, 447), 66, p.shield / maxf(1.0, p.max_shield), PixelLib.C_CYAN)
	_text(Vector2(4, 468), tr("HUD_DASH"), PixelLib.C_WHITE)
	_bar(Vector2(34, 461), 66, 1.0 - p.dash_cd / DASH_COOLDOWN, PixelLib.C_VIOLET)
	var ship: RefCounted = p.ship
	for c in ship.cells:
		var cell: Dictionary = ship.cells[c]
		var k: float = cell["hp"] / cell["max_hp"]
		var col: Color = Color(ship.defs[cell["id"]]["color"]) if ship.connected.has(c) else Color("#333a4d")
		draw_rect(Rect2(Vector2(6 + c.y * 3, 428 - c.x * 3), Vector2(2, 2)), col.darkened(0.6 * (1.0 - k)))
	# --- bottom-right: weapons ---
	var y := 418.0
	var sec: RefCounted = p.selected_secondary()
	var listed := {}
	for c in p.weapons:
		var w: RefCounted = p.weapons[c]
		if listed.has(w.id) or not ship.connected.has(c):
			continue
		listed[w.id] = true
		var tag := ">" if w == sec else ""
		var col: Color = PixelLib.C_RED if w.overheated else (PixelLib.C_CYAN if w.slot == "primary" else PixelLib.C_VIOLET)
		_text(Vector2(166, y + 6), tag + tr("WPN_" + w.id.to_upper()), col)
		_bar(Vector2(234, y), 32, w.heat_ratio(), PixelLib.C_RED if w.overheated else PixelLib.C_GOLD)
		y += 14
	# --- bottom-centre: core heat above the triangle ---
	_text(Vector2(80, 416), tr("HUD_CORE"), PixelLib.C_RED if e.is_warning() else PixelLib.C_WHITE)
	_bar(Vector2(110, 407), 50, e.heat_ratio(), PixelLib.C_RED if e.is_warning() else PixelLib.C_GOLD)
	if e.overload_active:
		_text(Vector2(0, 396), tr("HUD_OVERLOAD") % roundi(e.total() * 100), PixelLib.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, W)
	elif e.overload_locked:
		_text(Vector2(0, 396), tr("HUD_OVERLOAD_LOCKED"), PixelLib.C_RED, HORIZONTAL_ALIGNMENT_CENTER, W)
	if e.is_warning() and e.overload_active:
		_text(Vector2(0, 382), tr("HUD_HEAT_CRITICAL"), PixelLib.C_RED, HORIZONTAL_ALIGNMENT_CENTER, W)
	if warn_life > 0.0:
		_text(Vector2(0, 70), tr("HUD_OVERHEAT_WARN") % [tr("MOD_" + warn_cat.to_upper()), ceili(warn_life)], PixelLib.C_RED, HORIZONTAL_ALIGNMENT_CENTER, W)
	if banner_life > 0.0:
		_text(Vector2(0, 58), banner, Color(banner_col, clampf(banner_life, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, W)
	var sp: Vector2 = p.get_global_transform_with_canvas().origin
	for ind in indicators:
		var a: float = ind[0]
		draw_arc(sp, 22, a - 0.35, a + 0.35, 6, Color(PixelLib.C_RED, clampf(ind[1] / 0.8, 0, 1)), 2.0)
