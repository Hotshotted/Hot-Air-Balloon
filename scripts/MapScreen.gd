class_name MapScreen
extends Control
## The world map: four regions stacked top to bottom, six Flights each as a row of numbered nodes with the
## stars earned under them. Built once; refresh() recolours and re-texts everything from the save.

signal flight_chosen(id: int)
signal album_pressed
signal shop_pressed
signal daily_pressed

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
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Style.INK)
	for r in Regions.COUNT:
		var y0 := block_y(r)
		var rect := Rect2(30, y0, Lanes.W - 60, BLOCK_H)
		Regions.draw_backdrop(self, r, rect, 5.0)
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
				Ui.draw_star(self, Vector2(cx + (float(k) - 1.0) * 36.0, y0 + 280.0), 15.0, Ui.COL_GOLD if k < st else Color(0.28, 0.3, 0.38))
			if open and id == suggested:   # a ring around where to fly next, with your balloon on it
				draw_arc(Vector2(cx, y0 + 132.0 + NODE * 0.5), NODE * 0.5 + 12.0, 0.0, TAU, 28, Color.WHITE, 6.0)
				draw_set_transform(Vector2(cx, y0 + 98.0), 0.0, Vector2(0.5, 0.5))
				BalloonArt.shared().draw(self, Save.equipped(0), Save.equipped(1), Save.equipped(2), 0.0, 0.0, 4.0 / 0.5)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if not Save.flight_unlocked(id):   # a padlock on a Flight that is not open yet
				Icons.draw(self, "lock", Vector2(cx, y0 + 132.0 + NODE * 0.5), 26.0)
