class_name MapScreen
extends Control
## The world map: four regions stacked top to bottom, six Flights each as a row of numbered nodes with the
## stars earned under them. Built once; refresh() recolours and re-texts everything from the save.

signal flight_chosen(id: int)
signal album_pressed
signal shop_pressed
signal daily_pressed
signal home_pressed

const TOP := 124.0
const BLOCK_H := 396.0
const BLOCK_GAP := 14.0
const NODE := 112.0
const COL_LOCKED := Color(0.33, 0.35, 0.42)
const COL_OPEN := Color(0.2, 0.55, 0.95)
const COL_PLAYED := Color(0.25, 0.7, 0.4)
const COL_GOLD := Color(0.95, 0.72, 0.1)

var nodes: Array[Button] = []
var region_titles: Array[Label] = []
var region_stars: Array[Label] = []
var region_blurbs: Array[Label] = []
var region_locks: Array[Label] = []
var coins_label: Label
var stars_label: Label
var album_btn: Button
var shop_btn: Button
var daily_btn: Button
var suggested := 0
# --- the hand-drawn route, the drifting balloon and the stars popping in ---
var route := PackedVector2Array()           # the dotted route through every Flight, in order
var route_node := PackedInt32Array()        # route index of each Flight's node
var _route_len := PackedFloat32Array()      # arc length up to each route point
var _balloon_sprite: _RouteBalloon
var _pop_layer: _StarPops
var _draw_stars := PackedInt32Array()       # stars drawn for each Flight (a new star counts once its pop has played)
var _was_open := PackedByteArray()
var _inited := false
var pops: Array = []                        # [flight id, star index, seconds since it began (negative = waiting)]

func _ready() -> void:
	size = Vector2(Lanes.W, Lanes.H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(Ui.icon("coin", 52, Vector2(30, 26)))
	coins_label = Ui.label("", 40, HORIZONTAL_ALIGNMENT_LEFT, Vector2(92, 28), Vector2(340, 56))
	coins_label.add_theme_color_override("font_color", Ui.COL_GOLD)
	add_child(coins_label)
	add_child(Ui.icon("star", 52, Vector2(440, 26)))
	stars_label = Ui.label("", 40, HORIZONTAL_ALIGNMENT_LEFT, Vector2(502, 28), Vector2(340, 56))
	add_child(stars_label)
	var home := Ui.ghost_button("home", Vector2(Lanes.W - 30.0 - 84.0, 14), 84.0)
	home.pressed.connect(func(): home_pressed.emit())
	add_child(home)
	album_btn = Ui.button("ALBUM", 38, Vector2(30, 1790), Vector2(320, 100), Color(0.6, 0.4, 0.8), "album")
	album_btn.pressed.connect(func(): album_pressed.emit())
	add_child(album_btn)
	shop_btn = Ui.button("SHOP", 44, Vector2(380, 1790), Vector2(320, 100), Color(0.2, 0.6, 0.5), "shop")
	shop_btn.pressed.connect(func(): shop_pressed.emit())
	add_child(shop_btn)
	daily_btn = Ui.button("DAILY", 34, Vector2(730, 1790), Vector2(320, 100), Color(0.9, 0.45, 0.2), "daily")
	daily_btn.pressed.connect(func(): daily_pressed.emit())
	add_child(daily_btn)
	# Make sure every button colour is in the style cache now, not the first time it is needed.
	for kind in ["primary", "accent", "gold", "played", "open", "locked", "ghost", "secondary"]:
		for st in 4:
			Ui.box(kind, st)
	for r in Regions.COUNT:
		var y0 := block_y(r)
		add_child(Ui.icon("region_%d" % r, 60, Vector2(50, y0 + 8)))
		var t := Ui.label("%d  %s" % [r + 1, Regions.NAMES[r].to_upper()], 50, HORIZONTAL_ALIGNMENT_LEFT, Vector2(120, y0 + 8), Vector2(540, 66))
		add_child(t)
		region_titles.append(t)
		add_child(Ui.icon("star", 44, Vector2(Lanes.W - 100.0, y0 + 16)))
		var rs := Ui.label("", 42, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(Lanes.W - 480.0, y0 + 12), Vector2(370, 56))
		rs.add_theme_color_override("font_color", Ui.COL_GOLD)
		add_child(rs)
		region_stars.append(rs)
		var bl := Ui.label(Regions.BLURB[r], 28, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(440, y0 + 66), Vector2(560, 40))
		add_child(bl)
		region_blurbs.append(bl)
		var lk := Ui.label("", 40, HORIZONTAL_ALIGNMENT_CENTER, Vector2(60, y0 + 290), Vector2(960, 90))
		lk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(lk)
		region_locks.append(lk)
		for i in Flights.PER_REGION:
			var id := Flights.id_of(r, i)
			var b := Ui.button(str(i + 1), 54, Vector2(node_x(i), y0 + 132.0), Vector2(NODE, NODE), COL_OPEN)
			b.pressed.connect(func(): flight_chosen.emit(id))
			add_child(b)
			nodes.append(b)
	_build_route()
	_pop_layer = _StarPops.new()
	_pop_layer.map = self
	_pop_layer.size = size
	_pop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pop_layer)
	_balloon_sprite = _RouteBalloon.new()
	_balloon_sprite.map = self
	_balloon_sprite.size = Vector2(160, 200)
	_balloon_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_balloon_sprite)
	_draw_stars.resize(Flights.TOTAL)
	_was_open.resize(Flights.TOTAL)
	Ui.fit_safe(self)

static func block_y(region: int) -> float:
	return TOP + float(region) * (BLOCK_H + BLOCK_GAP)

static func node_x(i: int) -> float:
	return 52.0 + float(i) * 160.0

## Recolour the nodes and texts from the save.
func refresh() -> void:
	coins_label.text = "coins %s" % Tuning.fmt(float(Save.coins))
	stars_label.text = "stars %d/%d" % [Save.total_stars(), Flights.TOTAL * 3]
	var cards := 0
	for r in Regions.COUNT:
		cards += 1 if Save.postcard_of(r) > 0 else 0
	album_btn.text = "ALBUM %d/%d" % [cards, Regions.COUNT]
	var day := Flights.today()
	var streak := Save.daily_streak_now(day)
	daily_btn.text = ("DAILY  done  x%d" % streak) if Save.daily_done(day) else (("DAILY  streak %d" % streak) if streak > 0 else "DAILY  new!")
	suggested = Save.suggested_flight()
	for r in Regions.COUNT:
		var open := Save.region_unlocked(r)
		region_stars[r].text = "%d/%d" % [Save.region_stars(r), Flights.PER_REGION * 3]
		region_locks[r].visible = not open
		if not open:
			region_locks[r].text = "Earn %d stars in %s to open  (%d/%d)" % [Save.REGION_UNLOCK_STARS, Regions.NAMES[r - 1], Save.region_stars(r - 1), Save.REGION_UNLOCK_STARS]
	for id in Flights.TOTAL:
		var b := nodes[id]
		b.visible = Save.region_unlocked(Flights.region_of(id))
		var st := Save.stars_of(id)
		var open := Save.flight_unlocked(id)
		b.disabled = not open
		var col := COL_LOCKED if not open else (COL_GOLD if st >= 3 else (COL_PLAYED if st >= 1 else COL_OPEN))
		Ui.apply_color(b, col)
	_animate_changes()
	if _balloon_sprite != null:
		_balloon_sprite.queue_redraw()
	queue_redraw()

func _draw() -> void:
	_draw_paper()
	for r in Regions.COUNT:
		var y0 := block_y(r)
		var rect := Rect2(30, y0, Lanes.W - 60, BLOCK_H)
		Regions.draw_backdrop(self, r, rect, 5.0)
		_draw_wobbly_frame(rect, r)
		var open := Save.region_unlocked(r)
		if not open:   # a big padlock instead of the nodes
			draw_rect(rect, Color(0.03, 0.04, 0.08, 0.55))
			Icons.draw(self, "lock", Vector2(Lanes.W * 0.5, y0 + 195.0), 62.0)
			continue
		for i in Flights.PER_REGION:
			var id := Flights.id_of(r, i)
			var cx := node_x(i) + NODE * 0.5
			var st := Save.stars_of(id)
			for k in 3:
				Ui.draw_star(self, Vector2(cx + (float(k) - 1.0) * 36.0, y0 + 280.0), 15.0, Style.ACCENT if k < _draw_stars[id] else Color(0.28, 0.3, 0.38))
			if open and id == suggested:   # a ring around where to fly next (the balloon drifts along the route to it)
				draw_arc(Vector2(cx, y0 + 132.0 + NODE * 0.5), NODE * 0.5 + 12.0, 0.0, TAU, 28, Color.WHITE, 6.0)
			if not Save.flight_unlocked(id):   # a padlock on a Flight that is not open yet
				Icons.draw(self, "lock", Vector2(cx, y0 + 132.0 + NODE * 0.5), 26.0)
	_draw_route()

# ---------------------------------------------------------------------------------------------------------
# Hand-drawn look: parchment, wobbly frames, a dotted route
# ---------------------------------------------------------------------------------------------------------

static func node_center(id: int) -> Vector2:
	return Vector2(node_x(Flights.index_of(id)) + NODE * 0.5, block_y(Flights.region_of(id)) + 132.0 + NODE * 0.5)

## The route: through every Flight's node in order. (Between regions the balloon simply flies across; no dots are drawn there.)
func _build_route() -> void:
	route.clear()
	route_node.resize(Flights.TOTAL)
	for id in Flights.TOTAL:
		route_node[id] = route.size()
		route.append(node_center(id))
	_route_len.resize(route.size())
	var acc := 0.0
	for i in route.size():
		if i > 0:
			acc += route[i].distance_to(route[i - 1])
		_route_len[i] = acc

## A point on the route `d` px along it.
func route_at(d: float) -> Vector2:
	d = clampf(d, 0.0, _route_len[_route_len.size() - 1])
	for i in range(1, route.size()):
		if d <= _route_len[i]:
			var seg := _route_len[i] - _route_len[i - 1]
			return route[i - 1].lerp(route[i], (d - _route_len[i - 1]) / maxf(seg, 0.001))
	return route[route.size() - 1]

func route_dist(id: int) -> float:
	return _route_len[route_node[id]]

func _draw_paper() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("e9d9b4"))
	# a soft vignette and a few faint hand-drawn contour lines
	for k in 6:
		draw_rect(Rect2(0, float(k) * 6.0, size.x, 6.0), Color(0.45, 0.3, 0.15, 0.05 * float(6 - k)))
		draw_rect(Rect2(0, size.y - float(k + 1) * 6.0, size.x, 6.0), Color(0.45, 0.3, 0.15, 0.05 * float(6 - k)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 14:
		var pts := PackedVector2Array()
		var y := rng.randf_range(20.0, size.y - 20.0)
		var x := rng.randf_range(-40.0, 40.0)
		for j in 12:
			pts.append(Vector2(x + float(j) * 95.0, y + sin(float(j) * 0.9 + float(i)) * 14.0))
		draw_polyline(pts, Color(0.55, 0.4, 0.2, 0.12), 3.0, true)

## A frame that wobbles a little, as if inked by hand (the same wobble every time: seeded by the region).
func _draw_wobbly_frame(rect: Rect2, r: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + r
	var pts := PackedVector2Array()
	var step := 60.0
	var x := rect.position.x
	while x < rect.end.x:
		pts.append(Vector2(x, rect.position.y + rng.randf_range(-3.5, 3.5)))
		x += step
	var y := rect.position.y
	while y < rect.end.y:
		pts.append(Vector2(rect.end.x + rng.randf_range(-3.5, 3.5), y))
		y += step
	x = rect.end.x
	while x > rect.position.x:
		pts.append(Vector2(x, rect.end.y + rng.randf_range(-3.5, 3.5)))
		x -= step
	y = rect.end.y
	while y > rect.position.y:
		pts.append(Vector2(rect.position.x + rng.randf_range(-3.5, 3.5), y))
		y -= step
	pts.append(pts[0])
	draw_polyline(pts, Color(Style.INK, 0.9), 6.0, true)

## The dotted route inside each region: gold dots up to the Flight you fly next (the way you have come), pale ones beyond.
func _draw_route() -> void:
	var reach := route_dist(suggested)
	for id in range(1, Flights.TOTAL):
		if Flights.region_of(id) != Flights.region_of(id - 1) or not Save.region_unlocked(Flights.region_of(id)):
			continue
		var a := route[route_node[id - 1]]
		var b := route[route_node[id]]
		var n := int(a.distance_to(b) / 26.0)
		for k in range(1, n):
			var p := a.lerp(b, float(k) / float(n))
			var done := route_dist(id - 1) + a.distance_to(b) * float(k) / float(n) <= reach
			draw_circle(p, 6.0 if done else 5.0, Color(Style.INK, 0.8))
			draw_circle(p, 4.0 if done else 3.0, Style.ACCENT if done else Color(1, 1, 1, 0.7))

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
			var u := clampf(p[2] / 0.5, 0.0, 1.0)
			var k := 1.0 + (1.0 - Style.ease_out_back(u)) * 2.2
			var c := Vector2(MapScreen.node_x(Flights.index_of(id)) + MapScreen.NODE * 0.5 + (float(p[1]) - 1.0) * 36.0, MapScreen.block_y(Flights.region_of(id)) + 280.0)
			Ui.draw_star(self, c, 15.0 * k, Style.ACCENT)
			if u < 0.8:
				for j in 6:
					var a := TAU * float(j) / 6.0 + float(p[1])
					draw_circle(c + Vector2(cos(a), sin(a)) * (14.0 + 60.0 * u), 4.0 * (1.0 - u), Style.ACCENT)

## Your balloon, drifting along the dotted route between the Flights you have flown and the next one (and bobbing), drawn once.
class _RouteBalloon extends Control:
	var map: MapScreen
	var _t := 0.0

	func _draw() -> void:
		draw_set_transform(Vector2(80.0, 70.0), 0.0, Vector2(0.42, 0.42))
		BalloonArt.shared().draw(self, Save.equipped(0), Save.equipped(1), Save.equipped(2), 0.0, 0.0, 4.0 / 0.42)

	func _process(delta: float) -> void:
		if not visible or map == null or not map.visible or map.route.is_empty():
			return
		_t += delta
		var to := map.route_dist(map.suggested)
		var from := map.route_dist(maxi(map.suggested - 1, 0)) if map.suggested > 0 else 0.0
		# drift forward along the leg of the route to the next Flight, then ease back and start again
		var u := fposmod(_t * 0.16, 1.0)
		var d := lerpf(from, to, Style.ease_out_cubic(u)) if map.suggested > 0 else 0.0
		var p := map.route_at(d)
		position = p + Vector2(-80.0, -150.0 + sin(_t * 1.7) * 7.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _balloon_sprite != null:
		_balloon_sprite.queue_redraw()
