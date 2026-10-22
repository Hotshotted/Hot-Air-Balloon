class_name MapScreen
extends Control
## The world map, Storybook Sky: parchment, the current region drawn as a hillside with a winding dotted route between its six
## numbered Flight tiles (gold = three stars, green = played, blue = next, with a glow; tan = locked), your balloon parked at the
## next Flight, the other regions as cards below (tap an open one to look at it) and a bottom dock of Album, Shop and Daily.
## Built once; refresh() recolours and re-texts everything from the save.

signal flight_chosen(id: int)
signal album_pressed
signal shop_pressed
signal daily_pressed
signal home_pressed

const NODE := 144.0                     # a Flight tile
const NODE_NEXT := 166.0                # the next Flight is a little bigger
const INK := Color("0a1020")
const PAPER := Color("f1e3c4")
const BROWN := Color("7a5a3a")
const COL_LOCKED := Color(0.33, 0.35, 0.42)   # (the legacy colours Ui maps to its tile styles: grey, blue, green, gold)
const COL_OPEN := Color(0.2, 0.55, 0.95)
const COL_PLAYED := Color(0.25, 0.7, 0.4)
const COL_GOLD := Color(0.95, 0.72, 0.1)
## Tile centres of the six Flights on the hillside (from the design canvas).
const TILES := [Vector2(227, 1070), Vector2(282, 870), Vector2(476, 751), Vector2(587, 615), Vector2(820, 583), Vector2(914, 1010)]
const HILL_TOP := 480.0
const HILL_BOTTOM := 1190.0

var nodes: Array[Button] = []
var region_titles: Array[Label] = []
var region_stars: Array[Label] = []
var region_blurbs: Array[Label] = []
var region_locks: Array[Label] = []
var region_cards: Array[Control] = []
var coins_label: Label
var stars_label: Label
var album_btn: Button
var shop_btn: Button
var daily_btn: Button
var kicker: Label
var hero_name: Label
var hero_info: Label
var suggested := 0
var shown_region := 0                       # the region drawn as the hillside
var _chosen := -1                           # a region picked by tapping its card (-1: the one with the next Flight)
# --- the dotted route, the parked balloon and the stars popping in ---
var route := PackedVector2Array()           # the dotted route through the six tiles of the shown region
var _route_dots := PackedVector2Array()
var _balloon_sprite: _RouteBalloon
var _pop_layer: _StarPops
var _draw_stars := PackedInt32Array()       # stars drawn for each Flight (a new star counts once its pop has played)
var _was_open := PackedByteArray()
var _inited := false
var pops: Array = []                        # [flight id, star index, seconds since it began (negative = waiting)]

func _pill(x: float, w: float) -> Control:
	var p := Panel.new()
	p.position = Vector2(x, 56.0)
	p.size = Vector2(w, 108.0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", Style.box(Style.SURFACE_DARK, Color(0, 0, 0, 0), 54, 0, false))
	add_child(p)
	return p

## A chunky dock button: flat colour, ink border, a thick lip.
func _chunk(text: String, fill: Color, text_col: Color, pos: Vector2, area: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = area
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Style.display())
	b.add_theme_font_size_override("font_size", 44)
	for k in ["font_color", "font_pressed_color", "font_hover_color"]:
		b.add_theme_color_override(k, text_col)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = INK
		sb.set_border_width_all(8)
		sb.border_width_bottom = 18
		sb.set_corner_radius_all(54)
		sb.anti_aliasing = true
		b.add_theme_stylebox_override(st, sb)
	Ui.hook_press(b, "")
	return b

func _ready() -> void:
	size = Vector2(Lanes.W, Lanes.H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var home := Ui.ghost_button("home", Vector2(44.0, 44.0), 132.0)
	home.pressed.connect(func(): home_pressed.emit())
	add_child(home)
	_pill(Lanes.W - 44.0 - 300.0 - 24.0 - 270.0, 270.0)
	add_child(Ui.icon("coin", 74, Vector2(Lanes.W - 44.0 - 300.0 - 24.0 - 270.0 + 16.0, 73)))
	coins_label = Ui.label("", 52, HORIZONTAL_ALIGNMENT_LEFT, Vector2(Lanes.W - 44.0 - 300.0 - 24.0 - 270.0 + 100.0, 72), Vector2(160, 76))
	coins_label.add_theme_constant_override("outline_size", 0)
	add_child(coins_label)
	_pill(Lanes.W - 44.0 - 300.0, 300.0)
	add_child(Ui.icon("star", 74, Vector2(Lanes.W - 44.0 - 300.0 + 16.0, 73)))
	stars_label = Ui.label("", 52, HORIZONTAL_ALIGNMENT_LEFT, Vector2(Lanes.W - 44.0 - 300.0 + 100.0, 72), Vector2(190, 76))
	stars_label.add_theme_constant_override("outline_size", 0)
	add_child(stars_label)
	kicker = Ui.label("", 36, HORIZONTAL_ALIGNMENT_LEFT, Vector2(80, 214), Vector2(700, 50))
	kicker.add_theme_color_override("font_color", BROWN)
	kicker.add_theme_constant_override("outline_size", 0)
	add_child(kicker)
	hero_name = Ui.label("", 112, HORIZONTAL_ALIGNMENT_LEFT, Vector2(80, 252), Vector2(900, 140))
	hero_name.add_theme_color_override("font_color", Style.INK)
	hero_name.add_theme_constant_override("outline_size", 0)
	add_child(hero_name)
	hero_info = Ui.label("", 42, HORIZONTAL_ALIGNMENT_LEFT, Vector2(80, 392), Vector2(900, 60))
	hero_info.add_theme_color_override("font_color", Color("5a4630"))
	hero_info.add_theme_constant_override("outline_size", 0)
	add_child(hero_info)
	# the other regions as cards below the hillside (built for every region; the shown one is hidden)
	for r in Regions.COUNT:
		var card := Control.new()
		card.size = Vector2(Lanes.W - 160.0, 140.0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(card)
		region_cards.append(card)
		var bg := Button.new()
		bg.size = card.size
		bg.focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			bg.add_theme_stylebox_override(st, Style.box(Style.SURFACE_DARK, Color(0, 0, 0, 0), 62, 0, false))
		var rr := r
		bg.pressed.connect(func(): _pick(rr))
		card.add_child(bg)
		card.add_child(Ui.icon("region_%d" % r, 80, Vector2(30, 30)))
		var t := Ui.label(Regions.NAMES[r], 52, HORIZONTAL_ALIGNMENT_LEFT, Vector2(140, 14), Vector2(560, 70))
		t.add_theme_constant_override("outline_size", 0)
		card.add_child(t)
		region_titles.append(t)
		var bl := Ui.label(Regions.BLURB[r], 34, HORIZONTAL_ALIGNMENT_LEFT, Vector2(140, 80), Vector2(640, 48))
		bl.add_theme_color_override("font_color", Style.TEXT_SOFT)
		bl.add_theme_constant_override("outline_size", 0)
		card.add_child(bl)
		region_blurbs.append(bl)
		var lk := Ui.label("", 34, HORIZONTAL_ALIGNMENT_LEFT, Vector2(140, 80), Vector2(700, 48))
		lk.add_theme_color_override("font_color", Style.TEXT_SOFT)
		lk.add_theme_constant_override("outline_size", 0)
		card.add_child(lk)
		region_locks.append(lk)
		var rs := Ui.label("", 42, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(card.size.x - 330.0, 44), Vector2(260, 56))
		rs.add_theme_color_override("font_color", Ui.COL_GOLD)
		rs.add_theme_constant_override("outline_size", 0)
		card.add_child(rs)
		region_stars.append(rs)
		card.add_child(Ui.icon("star", 44, Vector2(card.size.x - 64.0, 50)))
	# the six tiles of every Flight (only the shown region's are visible)
	for id in Flights.TOTAL:
		var b := Ui.button(str(Flights.index_of(id) + 1), 64, Vector2.ZERO, Vector2(NODE, NODE), COL_OPEN)
		var fid := id
		b.pressed.connect(func(): flight_chosen.emit(fid))
		add_child(b)
		nodes.append(b)
	album_btn = _chunk("ALBUM", COL_GOLD, Style.TEXT_ON_LIGHT, Vector2(44, 1750), Vector2(300, 130))
	album_btn.pressed.connect(func(): album_pressed.emit())
	add_child(album_btn)
	shop_btn = _chunk("SHOP", Color("a06bff"), Color.WHITE, Vector2(390, 1750), Vector2(300, 130))
	shop_btn.pressed.connect(func(): shop_pressed.emit())
	add_child(shop_btn)
	daily_btn = _chunk("DAILY", Color("35c98a"), Style.TEXT_ON_LIGHT, Vector2(736, 1750), Vector2(300, 130))
	daily_btn.add_theme_font_size_override("font_size", 34)
	daily_btn.pressed.connect(func(): daily_pressed.emit())
	add_child(daily_btn)
	# Make sure every button colour is in the style cache now, not the first time it is needed.
	for kind in ["primary", "accent", "gold", "played", "open", "locked", "ghost", "secondary"]:
		for st in 4:
			Ui.box(kind, st)
	_pop_layer = _StarPops.new()
	_pop_layer.map = self
	_pop_layer.size = size
	_pop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pop_layer)
	_balloon_sprite = _RouteBalloon.new()
	_balloon_sprite.map = self
	_balloon_sprite.size = Vector2(240, 300)
	_balloon_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_balloon_sprite)
	_draw_stars.resize(Flights.TOTAL)
	_was_open.resize(Flights.TOTAL)
	Ui.fit_safe(self)

## Look at another (open) region.
func _pick(r: int) -> void:
	if not Save.region_unlocked(r):
		return
	_chosen = r
	Sfx.ui("tap")
	refresh()

func select_region(r: int) -> void:
	_chosen = r
	refresh()

## Where Flight `id`'s tile sits (the six hillside positions, mirrored for odd regions so each hillside winds its own way).
func tile_center(id: int) -> Vector2:
	var p: Vector2 = TILES[Flights.index_of(id)]
	if Flights.region_of(id) % 2 == 1:
		p.x = Lanes.W - p.x
	return p

## Recolour the tiles and texts from the save.
func refresh() -> void:
	coins_label.text = Tuning.fmt(float(Save.coins))
	stars_label.text = "%d / %d" % [Save.total_stars(), Flights.TOTAL * 3]
	var cards := 0
	for r in Regions.COUNT:
		cards += 1 if Save.postcard_of(r) > 0 else 0
	album_btn.text = "ALBUM %d/%d" % [cards, Regions.COUNT]
	var day := Flights.today()
	var streak := Save.daily_streak_now(day)
	daily_btn.text = ("DAILY  done  x%d" % streak) if Save.daily_done(day) else (("DAILY  streak %d" % streak) if streak > 0 else "DAILY  new!")
	suggested = Save.suggested_flight()
	shown_region = _chosen if (_chosen >= 0 and Save.region_unlocked(_chosen)) else Flights.region_of(suggested)
	kicker.text = "REGION %d OF %d" % [shown_region + 1, Regions.COUNT]
	hero_name.text = Regions.NAMES[shown_region]
	hero_info.text = "%s  ·  %d of %d stars" % [Regions.BLURB[shown_region].substr(0, 1).to_upper() + Regions.BLURB[shown_region].substr(1), Save.region_stars(shown_region), Flights.PER_REGION * 3]
	var slot := 0
	for r in Regions.COUNT:
		var open := Save.region_unlocked(r)
		region_stars[r].text = "%d/%d" % [Save.region_stars(r), Flights.PER_REGION * 3]
		region_locks[r].visible = not open
		region_blurbs[r].visible = open
		if not open:
			region_locks[r].text = "Earn %d stars in %s (%d/%d)" % [Save.REGION_UNLOCK_STARS, Regions.NAMES[r - 1], Save.region_stars(r - 1), Save.REGION_UNLOCK_STARS]
		region_cards[r].visible = r != shown_region
		if r != shown_region:
			region_cards[r].position = Vector2(80.0, 1250.0 + float(slot) * 160.0)
			region_cards[r].modulate.a = 1.0 if open else 0.7
			slot += 1
	_build_route()
	for id in Flights.TOTAL:
		var b := nodes[id]
		var inr := Flights.region_of(id) == shown_region
		b.visible = inr and Save.region_unlocked(shown_region)
		var st := Save.stars_of(id)
		var open := Save.flight_unlocked(id)
		b.disabled = not open
		var big := id == suggested
		var sz := NODE_NEXT if big else NODE
		b.size = Vector2(sz, sz)
		b.pivot_offset = b.size * 0.5
		b.position = tile_center(id) - b.size * 0.5
		var col := COL_LOCKED if not open else (COL_GOLD if st >= 3 else (COL_PLAYED if st >= 1 else COL_OPEN))
		Ui.apply_color(b, col)
	_animate_changes()
	if _balloon_sprite != null:
		_balloon_sprite.queue_redraw()
	queue_redraw()

func _build_route() -> void:
	route.clear()
	for i in Flights.PER_REGION:
		route.append(tile_center(Flights.id_of(shown_region, i)))
	_route_dots.clear()
	# a smooth (Catmull-Rom) curve through the tiles, sampled as evenly spaced dots
	var pts := PackedVector2Array()
	for i in route.size() - 1:
		var p0 := route[maxi(i - 1, 0)]
		var p1 := route[i]
		var p2 := route[i + 1]
		var p3 := route[mini(i + 2, route.size() - 1)]
		for k in 16:
			var u := float(k) / 16.0
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u))
	pts.append(route[route.size() - 1])
	var acc := 0.0
	var last := pts[0]
	_route_dots.append(last)
	for q in range(1, pts.size()):
		acc += pts[q].distance_to(last)
		last = pts[q]
		if acc >= 34.0:
			_route_dots.append(last)
			acc = 0.0

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	for c in [Vector3(60, 700, 80), Vector3(1000, 1100, 110), Vector3(210, 1660, 90)]:   # faded blots on the paper
		draw_circle(Vector2(c.x, c.y), c.z, Color("e6d3ad", 0.7))
	var r := shown_region
	var open := Save.region_unlocked(r)
	_draw_hillside(r)
	if not open:
		draw_rect(Rect2(0, HILL_TOP, Lanes.W, HILL_BOTTOM - HILL_TOP), Color(0.03, 0.04, 0.08, 0.35))
	var reach := suggested
	for k in _route_dots.size():   # the dotted route: dark up to the next Flight, fainter beyond
		var p := _route_dots[k]
		var seg := mini(k * (Flights.PER_REGION - 1) / maxi(_route_dots.size() - 1, 1), Flights.PER_REGION - 1)
		var done := Flights.id_of(r, seg) < reach
		draw_circle(p, 7.0, Color(BROWN, 0.95 if done else 0.55))
	for i in Flights.PER_REGION:
		var id := Flights.id_of(r, i)
		if not open:
			continue
		var c := tile_center(id)
		var tsz := (NODE_NEXT if id == suggested else NODE) * 0.5
		for k in 3:
			Ui.draw_star(self, c + Vector2((float(k) - 1.0) * 40.0, tsz + 36.0), 16.0, Style.ACCENT if k < _draw_stars[id] else Color(BROWN, 0.35))
		if id == suggested:   # the glow around the next Flight
			draw_circle(c, tsz + 38.0, Color(0.24, 0.55, 1.0, 0.22))
		if not Save.flight_unlocked(id):   # a padlock on a Flight that is not open yet
			Icons.draw(self, "lock", c, 30.0, BROWN)

## The region as a hillside: two rolling hills of the region's colours and a few details.
func _draw_hillside(r: int) -> void:
	var c1: Color = Regions.GROUND[r].lightened(0.25)
	var c2: Color = Regions.GROUND2[r].lightened(0.1)
	var top_pts := PackedVector2Array()
	for k in 31:
		var x := 60.0 + float(k) * 32.0
		top_pts.append(Vector2(x, HILL_TOP + 40.0 + sin(x / 330.0 * TAU * 0.5 + 0.6) * 55.0 + 0.0))
	top_pts.append(Vector2(1020, HILL_BOTTOM))
	top_pts.append(Vector2(60, HILL_BOTTOM))
	draw_colored_polygon(top_pts, c1)
	var mid_pts := PackedVector2Array()
	for k in 31:
		var x2 := 60.0 + float(k) * 32.0
		mid_pts.append(Vector2(x2, HILL_TOP + 200.0 + sin(x2 / 280.0 * TAU * 0.5 + 2.0) * 45.0))
	mid_pts.append(Vector2(1020, HILL_BOTTOM))
	mid_pts.append(Vector2(60, HILL_BOTTOM))
	draw_colored_polygon(mid_pts, c2)
	draw_line(Vector2(60, HILL_BOTTOM), Vector2(1020, HILL_BOTTOM), Color(BROWN, 0.8), 5.0, true)
	match r:
		0:   # trees and a little red house
			draw_circle(Vector2(190, 600), 28.0, Color("3e8a48"))
			draw_circle(Vector2(222, 622), 22.0, Color("56a65a"))
			draw_circle(Vector2(912, 760), 30.0, Color("3e8a48"))
			draw_colored_polygon(PackedVector2Array([Vector2(800, 1000), Vector2(880, 1000), Vector2(880, 1056), Vector2(800, 1056)]), Color("e9776a"))
			draw_colored_polygon(PackedVector2Array([Vector2(788, 1000), Vector2(840, 956), Vector2(892, 1000)]), Color("b84a3e"))
		1, 3:   # snowy peaks
			for pk in [Vector2(210, 640), Vector2(870, 700)]:
				draw_colored_polygon(PackedVector2Array([pk + Vector2(-90, 110), pk, pk + Vector2(90, 110)]), Color("c3cfe6"))
				draw_colored_polygon(PackedVector2Array([pk + Vector2(-26, 32), pk, pk + Vector2(26, 32)]), Color.WHITE)
		2:   # dunes and a cactus
			draw_circle(Vector2(900, 560), 52.0, Color("fff1c8"))
			draw_colored_polygon(SvgArt.rrect(180.0, 980.0, 28.0, 90.0, 14.0), Color("4c9a5a"))
			draw_colored_polygon(SvgArt.rrect(196.0, 1000.0, 36.0, 16.0, 8.0), Color("4c9a5a"))

# ---------------------------------------------------------------------------------------------------------
# Stars and unlocks animating in
# ---------------------------------------------------------------------------------------------------------

func _animate_changes() -> void:
	if not _inited:
		_inited = true
		for id in Flights.TOTAL:
			_draw_stars[id] = Save.stars_of(id)
			_was_open[id] = 1 if Save.flight_unlocked(id) else 0
		return
	var delay := 0.0
	for id in Flights.TOTAL:
		var st := Save.stars_of(id)
		if st < _draw_stars[id]:
			_draw_stars[id] = st
		for k in range(_draw_stars[id], st):
			pops.append([id, k, -delay])
			delay += Style.STAGGER * 5.0
			# the star is drawn lit once its pop has played (see _StarPops)
		var open := Save.flight_unlocked(id)
		if open and _was_open[id] == 0 and nodes[id].visible:
			Motion.pop(nodes[id], delay + 0.1)
			delay += Style.STAGGER * 2.0
			Sfx.ui("unlock")
		_was_open[id] = 1 if open else 0
	if not pops.is_empty():
		_pop_layer.set_process(true)

## Draws the stars that are popping in (a big star shrinking to its place with an overshoot, a burst of sparks) and, when a pop
## ends, lights that star in the map's own drawing. Only runs while a pop is playing.
class _StarPops extends Control:
	var map: MapScreen

	func _ready() -> void:
		set_process(false)

	func _process(delta: float) -> void:
		var done := false
		for p in map.pops:
			var before: float = p[2]
			p[2] = before + delta
			if before < 0.0 and p[2] >= 0.0:
				Sfx.ui("star", 0.9 + 0.12 * float(p[1]))
			if p[2] >= 0.55:
				done = true
		if done:
			var keep: Array = []
			for p in map.pops:
				if p[2] >= 0.55:
					map._draw_stars[p[0]] = maxi(map._draw_stars[p[0]], p[1] + 1)
				else:
					keep.append(p)
			map.pops = keep
			map.queue_redraw()
		queue_redraw()
		if map.pops.is_empty():
			set_process(false)

	func _draw() -> void:
		for p in map.pops:
			if p[2] < 0.0:
				continue
			var id: int = p[0]
			if Flights.region_of(id) != map.shown_region:
				continue
			var u := clampf(p[2] / 0.5, 0.0, 1.0)
			var k := 1.0 + (1.0 - Style.ease_out_back(u)) * 2.2
			var tsz := (MapScreen.NODE_NEXT if id == map.suggested else MapScreen.NODE) * 0.5
			var c := map.tile_center(id) + Vector2((float(p[1]) - 1.0) * 40.0, tsz + 36.0)
			Ui.draw_star(self, c, 16.0 * k, Style.ACCENT)
			if u < 0.8:
				for j in 6:
					var a := TAU * float(j) / 6.0 + float(p[1])
					draw_circle(c + Vector2(cos(a), sin(a)) * (14.0 + 60.0 * u), 4.0 * (1.0 - u), Style.ACCENT)

## Your balloon, parked above the next Flight and bobbing a little.
class _RouteBalloon extends Control:
	var map: MapScreen
	var _t := 0.0

	func _draw() -> void:
		draw_set_transform(Vector2(120.0, 130.0), 0.0, Vector2(1.5, 1.5))
		BalloonArt.shared().draw_body(self, Save.equipped(0), Save.equipped(1), Save.equipped(2), 4.0)

	func _process(delta: float) -> void:
		if not visible or map == null or not map.visible or map.route.is_empty():
			return
		_t += delta
		var id := map.suggested
		self.visible = Flights.region_of(id) == map.shown_region and Save.region_unlocked(map.shown_region)
		position = map.tile_center(id) + Vector2(-120.0, -310.0 + sin(_t * 1.7) * 8.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _balloon_sprite != null:
		_balloon_sprite.queue_redraw()
