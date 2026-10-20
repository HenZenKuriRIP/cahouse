extends Control
## HUD: hull/shield + module map (bottom-left), weapons/heat/dash (bottom-right), energy triangle + core heat
## (bottom-centre), timer/sector/kills/scrap (top), damage direction, warnings, synergy banner.
const PixelLib = preload("res://scripts/pixel.gd")
const EnergyWidget = preload("res://scripts/energy_widget.gd")
const DASH_COOLDOWN := 1.2
var battle: Node
var indicators: Array = []
var banner := ""
var banner_col := Color.WHITE
var banner_life := 0.0
var warn := ""
var warn_life := 0.0
var font: Font
var widget: Control

func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	widget = EnergyWidget.new()
	widget.position = Vector2(213, 212)
	add_child(widget)
	EventBus.player_damaged.connect(_on_damaged)
	EventBus.wave_started.connect(func(i: int) -> void: _banner("WAVE %d // SIGNAL INTENSIFIES" % (i + 1), PixelLib.C_CYAN))
	EventBus.synergy_triggered.connect(func(id: String, _p: Vector2) -> void:
		_banner("SYNERGY: " + str(battle.synergy.defs[id]["name"]), PixelLib.C_VIOLET))
	EventBus.core_overheated.connect(func(cat: String, dur: float) -> void:
		warn = "CORE OVERHEAT // %s OFFLINE %.0fs" % [cat.to_upper(), dur]
		warn_life = dur)
	EventBus.preset_changed.connect(func(n: String) -> void: _banner("ENERGY PRESET: " + n, PixelLib.C_GOLD))

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
	draw_string(font, pos, s, align, w, 8, col)

func _draw() -> void:
	if battle == null or battle.player == null:
		return
	var p: Node2D = battle.player
	var e: RefCounted = p.energy
	# bottom-left: hull / shield / module map
	_text(Vector2(8, 244), "HULL", PixelLib.C_WHITE)
	_bar(Vector2(36, 238), 80, p.hull / p.max_hull, PixelLib.C_RED)
	_text(Vector2(8, 256), "SHLD", PixelLib.C_RED if e.is_disabled("shield_gen") else PixelLib.C_WHITE)
	_bar(Vector2(36, 250), 80, p.shield / maxf(1.0, p.max_shield), PixelLib.C_CYAN)
	var ship: RefCounted = p.ship
	for c in ship.cells:
		var cell: Dictionary = ship.cells[c]
		var k: float = cell["hp"] / cell["max_hp"]
		var col: Color = Color(ship.defs[cell["id"]]["color"]) if ship.connected.has(c) else Color("#333a4d")
		# rotate grid so ship nose points up in the HUD map
		draw_rect(Rect2(Vector2(10 + c.y * 4, 228 - (c.x * 4) + 0), Vector2(3, 3)), col.darkened(0.6 * (1.0 - k)))
	# bottom-right: weapons
	var y := 222.0
	var sec: RefCounted = p.selected_secondary()
	var listed := {}
	for c in p.weapons:
		var w: RefCounted = p.weapons[c]
		if listed.has(w.id) or not ship.connected.has(c):
			continue
		listed[w.id] = true
		var name: String = w.data["name"].to_upper()
		var tag := ">" if w == sec else (" " if w.slot == "secondary" else "*")
		_text(Vector2(330, y + 6), tag + name, PixelLib.C_RED if w.overheated else (PixelLib.C_CYAN if w.slot == "primary" else PixelLib.C_VIOLET))
		_bar(Vector2(420, y), 50, w.heat_ratio(), PixelLib.C_RED if w.overheated else PixelLib.C_GOLD)
		y += 9
	var dash_frac: float = 1.0 - p.dash_cd / DASH_COOLDOWN
	_text(Vector2(330, 218), "DASH", PixelLib.C_WHITE)
	_bar(Vector2(360, 212), 40, dash_frac, PixelLib.C_VIOLET)
	# bottom-centre: core heat
	_text(Vector2(180, 266), "CORE", PixelLib.C_RED if e.is_warning() else PixelLib.C_WHITE)
	_bar(Vector2(206, 261), 66, e.heat_ratio(), PixelLib.C_RED if e.is_warning() else PixelLib.C_GOLD)
	if e.overload_active:
		_text(Vector2(0, 200), "OVERLOAD %d%%" % roundi(e.total() * 100), PixelLib.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, 480)
	elif e.overload_locked:
		_text(Vector2(0, 200), "OVERLOAD LOCKED // COOLING", PixelLib.C_RED, HORIZONTAL_ALIGNMENT_CENTER, 480)
	if e.is_warning() and e.overload_active:
		_text(Vector2(0, 190), "!! CORE HEAT CRITICAL !!", PixelLib.C_RED, HORIZONTAL_ALIGNMENT_CENTER, 480)
	if warn_life > 0.0:
		_text(Vector2(0, 54), warn, PixelLib.C_RED, HORIZONTAL_ALIGNMENT_CENTER, 480)
	# top
	var remain := maxf(0.0, battle.run_duration - GameManager.run_time)
	_text(Vector2(0, 14), "%d:%02d" % [int(remain) / 60, int(remain) % 60], PixelLib.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, 480)
	_text(Vector2(8, 14), GameManager.sector_name, PixelLib.C_VIOLET)
	_text(Vector2(0, 14), "KILLS %d  SCRAP %d " % [GameManager.kills, GameManager.scrap], PixelLib.C_WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 472)
	_text(Vector2(8, 24), "ENV: ASTEROID FIELD", Color(PixelLib.C_WHITE, 0.6))
	if banner_life > 0.0:
		_text(Vector2(0, 40), banner, Color(banner_col, clampf(banner_life, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, 480)
	var sp: Vector2 = p.get_global_transform_with_canvas().origin
	for ind in indicators:
		var a: float = ind[0]
		draw_arc(sp, 22, a - 0.35, a + 0.35, 6, Color(PixelLib.C_RED, clampf(ind[1] / 0.8, 0, 1)), 2.0)
