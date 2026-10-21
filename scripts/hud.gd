extends Control
## Portrait tactical HUD (270x480). Information hierarchy:
##  L1 (always, high contrast): hull/shield segments, weapon heat/cooldown, energy triangle.
##  L2 (glanceable): distance progress + milestones, timer, kills/scrap.
##  L3 (event, transient): synergy toast, wave/preset banner, overheat warning, damage arcs, low-hull vignette.
const K = preload("res://scripts/ui/ui_kit.gd")
const EnergyWidget = preload("res://scripts/energy_widget.gd")
const DASH_COOLDOWN := 1.2
var W := 270.0
var H := 480.0
var oy := 0.0 # bottom group offset (expanded viewport + safe area)
var rx := 0.0 # right-anchored offset
var st := 0.0 # safe-area top
const MILESTONES := 6
var battle: Node
var indicators: Array = [] # [angle, life]
var banner := ""
var banner_col := K.ACCENT
var banner_life := 0.0
var toasts: Array = [] # [synergy_id, age]
var warn_cat := ""
var warn_life := 0.0
var widget: Control
var hull_trail := 1.0
var shield_trail := 1.0
var _trail_hold := 0.0
var _t := 0.0
var _last_hull := 1.0
var _hurt_flash := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	widget = EnergyWidget.new()
	widget.position = Vector2(101, 408)
	add_child(widget)
	EventBus.player_damaged.connect(_on_damaged)
	EventBus.wave_started.connect(func(i: int) -> void: _banner(tr("BANNER_WAVE") % (i + 1), K.ACCENT))
	EventBus.synergy_triggered.connect(_on_synergy)
	EventBus.core_overheated.connect(func(cat: String, dur: float) -> void:
		warn_cat = cat
		warn_life = dur)
	EventBus.preset_changed.connect(func(n: String) -> void: _banner(tr("BANNER_PRESET") % tr("PRESET_" + n), K.ENERGY))
	Loc.language_changed.connect(func(_l: String) -> void: _banner(tr("BANNER_LANGUAGE") % tr("LANG_NAME"), K.ACCENT))

func bind(b: Node) -> void:
	battle = b
	widget.core = b.player.energy

func _banner(t: String, c: Color) -> void:
	banner = t
	banner_col = c
	banner_life = 1.8

func _on_synergy(id: String, _p: Vector2) -> void:
	for t in toasts:
		if t[0] == id and t[1] < 1.2:
			t[1] = 0.25 # refresh, no re-slide
			return
	toasts.append([id, 0.0])
	if toasts.size() > 2:
		toasts.pop_front()

func _on_damaged(_a: float, from_pos: Vector2) -> void:
	if battle and battle.player:
		indicators.append([(from_pos - battle.player.global_position).angle(), 0.9])
		_trail_hold = 0.45
		_hurt_flash = 0.15

func _process(delta: float) -> void:
	_t += delta
	for ind in indicators:
		ind[1] -= delta
	indicators = indicators.filter(func(i: Array) -> bool: return i[1] > 0.0)
	for t in toasts:
		t[1] += delta
	toasts = toasts.filter(func(t: Array) -> bool: return t[1] < 2.0)
	banner_life -= delta
	warn_life -= delta
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	if battle and battle.player:
		var p: Node2D = battle.player
		var hf: float = p.hull / maxf(1.0, p.max_hull)
		var sf: float = p.shield / maxf(1.0, p.max_shield)
		_trail_hold -= delta
		if _trail_hold <= 0.0:
			hull_trail = move_toward(hull_trail, hf, delta * 0.8)
			shield_trail = move_toward(shield_trail, sf, delta * 1.2)
		hull_trail = maxf(hull_trail, hf)
		shield_trail = maxf(shield_trail, sf)
	queue_redraw()

func _draw() -> void:
	if battle == null or battle.player == null:
		return
	var p: Node2D = battle.player
	var e: RefCounted = p.energy
	var vs := K.vsize(self)
	var ins := K.safe_insets(self)
	W = vs.x
	H = vs.y
	st = ins.y
	oy = floorf(H - 480.0 - ins.w)
	rx = floorf(W - 270.0)
	if widget:
		widget.position = Vector2(101 + floorf(rx / 2.0), 408 + oy)
	_draw_vignette(p)
	_draw_damage_arcs(p)
	draw_set_transform(Vector2(0, st))
	_draw_top()
	_draw_toasts()
	draw_set_transform(Vector2(0, oy))
	_draw_left(p, e)
	draw_set_transform(Vector2(rx, oy))
	_draw_right(p)
	draw_set_transform(Vector2(floorf(rx / 2.0), oy))
	var w0 := W
	W = 270.0
	_draw_center_states(e)
	W = w0
	draw_set_transform(Vector2.ZERO)

func _draw_vignette(p: Node2D) -> void:
	var hf: float = p.hull / maxf(1.0, p.max_hull)
	var k := clampf((0.4 - hf) / 0.4, 0.0, 1.0)
	if _hurt_flash > 0.0 and not K.reduce_flash():
		k = maxf(k, _hurt_flash * 2.0)
	if k <= 0.0:
		return
	var pulse := 1.0 if K.reduce_flash() else 0.75 + 0.25 * sin(_t * 6.0)
	for i in 6:
		var a := 0.16 * k * pulse * (1.0 - i / 6.0)
		var d := i * 3
		var c := Color(K.DANGER, a)
		draw_rect(Rect2(0, d, W, 3), c)
		draw_rect(Rect2(0, H - d - 3, W, 3), c)
		draw_rect(Rect2(d, 0, 3, H), c)
		draw_rect(Rect2(W - d - 3, 0, 3, H), c)

func _draw_top() -> void:
	var r := Rect2(4, 3, W - 8, 34)
	K.panel(self, r, K.ACCENT, 0.78, 3, false)
	K.brackets(self, r, 4, Color(K.ACCENT, 0.7), 1)
	K.text(self, Vector2(10, 15), tr("HUD_SECTOR"), K.RARE)
	var rt := int(GameManager.run_time)
	K.icon(self, "time", Vector2(W - 50, 6), K.DIM)
	K.text(self, Vector2(0, 15), "%d:%02d" % [rt / 60, rt % 60], K.TEXT, K.FS_BODY, HORIZONTAL_ALIGNMENT_RIGHT, W - 11)
	# progress strip with milestone ticks
	var bx := 10.0
	var bw := W - 20.0
	var prog := clampf(battle.distance() / battle.distance_goal, 0.0, 1.0) if not battle.endless else fmod(battle.distance(), 1200.0) / 1200.0
	draw_rect(Rect2(bx, 19, bw, 3), Color(K.BG, 0.9))
	draw_rect(Rect2(bx, 20, floorf(bw * prog), 1), K.ACCENT)
	for i in range(1, MILESTONES):
		var tx := floorf(bx + bw * i / MILESTONES)
		var passed := prog >= float(i) / MILESTONES
		draw_rect(Rect2(tx, 18, 1, 5), K.ACCENT if passed else Color(K.TEXT, 0.25))
	var mx := floorf(bx + bw * prog)
	draw_rect(Rect2(mx - 1, 17, 3, 7), K.TEXT)
	var dist_txt: String = tr("HUD_DISTANCE") % [int(battle.distance()), int(battle.distance_goal)] if not battle.endless else "%d · %s" % [int(battle.distance()), tr("HUD_ENDLESS")]
	K.icon(self, "distance", Vector2(10, 25), K.ACCENT)
	K.text(self, Vector2(20, 33), dist_txt, K.ACCENT)
	var kills := str(GameManager.kills)
	var scrap := str(GameManager.scrap)
	var sw := K.text_width(scrap)
	var kw := K.text_width(kills)
	var x := W - 11 - sw
	K.text(self, Vector2(x, 33), scrap, K.ENERGY)
	K.icon(self, "scrap", Vector2(x - 10, 25), K.ENERGY)
	x -= 18 + kw
	K.text(self, Vector2(x, 33), kills, K.TEXT)
	K.icon(self, "kills", Vector2(x - 10, 25), K.DANGER)
	K.text(self, Vector2(8, 50), tr("HUD_ENV_ASTEROID"), Color(K.TEXT, 0.35))

func _draw_damage_arcs(p: Node2D) -> void:
	var sp: Vector2 = p.get_global_transform_with_canvas().origin
	for ind in indicators:
		var a: float = ind[0]
		var k: float = clampf(ind[1] / 0.9, 0.0, 1.0)
		var col := Color(K.DANGER, k)
		for i in range(-5, 6):
			var aa := a + i * 0.07
			var w := 2 if absi(i) < 4 else 1
			for rr in w:
				var pp := (sp + Vector2.from_angle(aa) * (24 + rr)).floor()
				draw_rect(Rect2(pp, Vector2.ONE), col)
		var tip := (sp + Vector2.from_angle(a) * 28).floor()
		draw_rect(Rect2(tip - Vector2(1, 1), Vector2(2, 2)), col)

func _draw_left(p: Node2D, e: RefCounted) -> void:
	var r := Rect2(4, 406, 94, 70)
	K.panel(self, r, K.ACCENT, 0.82, 3, false)
	K.brackets(self, r, 4, Color(K.ACCENT, 0.6), 1)
	var hf: float = p.hull / maxf(1.0, p.max_hull)
	var low := hf < 0.35
	var hcol := K.DANGER
	K.icon(self, "hull", Vector2(9, 412), K.DANGER if (low and (K.reduce_flash() or int(_t * 4) % 2 == 0)) else K.TEXT)
	K.seg_bar(self, Vector2(19, 413), 12, 5, 5, hf, hcol, hull_trail)
	var shield_off: bool = e.is_disabled("shield_gen")
	K.icon(self, "shield", Vector2(9, 424), K.DANGER if shield_off else K.TEXT)
	K.seg_bar(self, Vector2(19, 425), 12, 5, 5, p.shield / maxf(1.0, p.max_shield), K.ACCENT, shield_trail)
	K.icon(self, "dash", Vector2(9, 436), K.TEXT)
	var dash_frac: float = 1.0 - p.dash_cd / DASH_COOLDOWN
	K.gauge(self, Rect2(20, 438, 70, 3), dash_frac, K.RARE if dash_frac < 1.0 else K.TEXT)
	# numeric readouts
	K.text(self, Vector2(9, 460), "%d" % ceili(p.hull), K.DANGER if low else K.TEXT)
	K.text(self, Vector2(9, 472), "%d" % ceili(p.shield), K.ACCENT)
	# module map (nose up)
	var ship: RefCounted = p.ship
	var ox := 54.0
	var oy := 470.0
	draw_rect(Rect2(ox - 2, oy - 24, 26, 26), Color(K.BG, 0.6))
	for c in ship.cells:
		var cell: Dictionary = ship.cells[c]
		var k: float = cell["hp"] / cell["max_hp"]
		var col: Color = Color(ship.defs[cell["id"]]["color"]) if ship.connected.has(c) else Color(K.TEXT, 0.15)
		if e.is_disabled(cell["id"]) and (K.reduce_flash() or int(_t * 6) % 2 == 0):
			col = K.DANGER
		draw_rect(Rect2(Vector2(ox + c.y * 3, oy - 3 - c.x * 3), Vector2(2, 2)), col.darkened(0.6 * (1.0 - k)))

func _draw_right(p: Node2D) -> void:
	var r := Rect2(172, 406, 94, 70)
	K.panel(self, r, K.ACCENT, 0.82, 3, false)
	K.brackets(self, r, 4, Color(K.ACCENT, 0.6), 1)
	var ship: RefCounted = p.ship
	var mounts_off: bool = p.energy.is_disabled("weapon_mount")
	# primaries row
	var x := 178.0
	var seen := {}
	for c in p.weapons:
		var w: RefCounted = p.weapons[c]
		if w.slot != "primary" or seen.has(w.id) or not ship.connected.has(c):
			continue
		seen[w.id] = true
		var col: Color = K.DANGER if (w.overheated or mounts_off) else K.ACCENT
		K.icon(self, w.id, Vector2(x, 411), col)
		K.gauge(self, Rect2(x + 10, 415, 30, 2), w.heat_ratio(), K.DANGER if w.overheated or w.heat_ratio() > 0.75 else K.ENERGY)
		x += 44
	draw_rect(Rect2(178, 422, 82, 1), Color(K.ACCENT, 0.2))
	# selected secondary: icon inside cooldown ring
	var sec: RefCounted = p.selected_secondary()
	if sec:
		var cc := Vector2(189, 441)
		var ready: float = clampf(sec.ready_ratio(), 0.0, 1.0)
		K.ring(self, cc, 10, ready, K.RARE if ready < 1.0 else K.ACCENT, Color(K.TEXT, 0.12))
		K.icon(self, sec.id, cc - Vector2(3, 3), K.DANGER if sec.overheated else K.TEXT)
		K.text(self, Vector2(203, 440), tr("WPN_" + sec.id.to_upper()), K.TEXT)
		K.gauge(self, Rect2(204, 446, 56, 2), sec.heat_ratio(), K.DANGER if sec.overheated else K.ENERGY)
		# secondary slots + key hint
		var cells: Array = p.secondary_cells()
		var sx := 204.0
		for i in cells.size():
			var wid: String = p.weapons[cells[i]].id
			var sel: bool = p.weapons[cells[i]] == sec
			draw_rect(Rect2(sx - 1, 455, 11, 11), Color(K.ACCENT, 0.25) if sel else Color(K.BG, 0.6))
			K.icon(self, wid, Vector2(sx + 1, 457), K.TEXT if sel else K.DIM)
			sx += 14
		K.chamfer_line(self, Rect2(244, 455, 16, 11), 1, K.DIM)
		K.text(self, Vector2(244, 465), "Q", K.DIM, K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, 16)
	if mounts_off:
		K.text(self, Vector2(178, 472), tr("MOD_WEAPON_MOUNT"), K.DANGER)

func _draw_center_states(e: RefCounted) -> void:
	var y := 398.0
	if e.overload_active:
		_chip(tr("HUD_OVERLOAD") % roundi(e.total() * 100), K.ENERGY, y, "core")
	elif e.overload_locked:
		_chip(tr("HUD_OVERLOAD_LOCKED"), K.DANGER, y, "warning")
	if e.is_warning() and e.overload_active:
		_chip(tr("HUD_HEAT_CRITICAL"), K.DANGER, y - 16, "warning")
	if warn_life > 0.0:
		var blink := K.reduce_flash() or int(warn_life * 4) % 2 == 0
		var txt: String = tr("HUD_OVERHEAT_WARN") % [tr("MOD_" + warn_cat.to_upper()), ceili(warn_life)]
		var tw := K.text_width(txt) + 26
		var rr := Rect2(floorf((W - tw) / 2.0), 92, tw, 18)
		K.chamfer_fill(self, rr, 3, Color(K.DANGER, 0.22))
		K.chamfer_line(self, rr, 3, K.DANGER if blink else Color(K.DANGER, 0.5))
		K.icon(self, "warning", rr.position + Vector2(6, 5), K.DANGER)
		K.text(self, rr.position + Vector2(18, 13), txt, K.TEXT)
	if banner_life > 0.0:
		var a := clampf(banner_life / 0.4, 0.0, 1.0) * K.ease_out_cubic((1.8 - banner_life) / 0.2)
		var bw := K.text_width(banner)
		var bx := floorf((W - bw) / 2.0)
		draw_rect(Rect2(bx - 18, 70, 12, 1), Color(banner_col, a))
		draw_rect(Rect2(bx + bw + 6, 70, 12, 1), Color(banner_col, a))
		K.text(self, Vector2(0, 75), banner, Color(banner_col, a), K.FS_BODY, HORIZONTAL_ALIGNMENT_CENTER, W)

func _chip(txt: String, col: Color, y: float, glyph: String) -> void:
	var tw := K.text_width(txt) + 22
	var r := Rect2(floorf((W - tw) / 2.0), y - 12, tw, 15)
	K.chamfer_fill(self, r, 3, Color(K.BG, 0.85))
	K.chamfer_line(self, r, 3, col)
	K.icon(self, glyph, r.position + Vector2(5, 4), col)
	K.text(self, r.position + Vector2(16, 12), txt, col)

## Synergy toast: holographic card slides in from the right, holds, slides out.
func _draw_toasts() -> void:
	var y := 64.0 if (battle and battle.touch and battle.touch.enabled) else 58.0
	for t in toasts:
		var id: String = t[0]
		var age: float = t[1]
		var k_in := K.ease_out_back(age / 0.22)
		var k_out := K.ease_out_cubic((age - 1.6) / 0.4)
		var off := (1.0 - k_in) * 200.0 + k_out * 200.0
		var col := K.RARE if id == "ion_vortex" else K.ACCENT
		var tw := maxf(K.text_width(tr("HUD_SYNERGY_TAG")), K.text_width(tr("SYN_" + id.to_upper())))
		var r := Rect2(floorf(W - tw - 48 + off), y, tw + 42, 34)
		K.panel(self, r, col, 0.9, 4, false)
		draw_rect(Rect2(r.position + Vector2(1, 4), Vector2(2, r.size.y - 8)), col)
		var sweep := fmod(age * 1.4, 1.0)
		if not K.reduce_flash():
			draw_rect(Rect2(r.position.x + floorf(sweep * r.size.x), r.position.y + 1, 2, r.size.y - 2), Color(K.TEXT, 0.12))
		draw_rect(Rect2(r.position + Vector2(8, 8), Vector2(17, 17)), Color(col, 0.15))
		K.icon(self, "synergy", r.position + Vector2(13, 13), col)
		K.text(self, r.position + Vector2(32, 13), tr("HUD_SYNERGY_TAG"), Color(K.TEXT, 0.55))
		K.text(self, r.position + Vector2(32, 28), tr("SYN_" + id.to_upper()), col)
		y += 40
