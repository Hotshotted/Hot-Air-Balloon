class_name AlbumScreen
extends Control
## The Postcard Album: one slot per region (a grey silhouette until earned, a postcard, or a gold postcard).
## Tap a postcard to see it large. Built once; refresh() re-reads the save.

signal back_pressed

var views: Array[PostcardView] = []
var captions: Array[Label] = []
var zoom_p: Control
var zoom_view: PostcardView
var count_label: Label

func _ready() -> void:
	size = Vector2(Lanes.W, Lanes.H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(Ui.label("POSTCARD ALBUM", 70, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 40), Vector2(1000, 100)))
	add_child(Ui.icon("album", 80, Vector2(110, 48)))
	count_label = Ui.label("", 38, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 140), Vector2(1000, 56))
	add_child(count_label)
	for r in Regions.COUNT:
		var col := r % 2
		var row := r / 2
		var v := PostcardView.new()
		v.position = Vector2(40.0 + 510.0 * float(col), 230.0 + 640.0 * float(row))
		v.size = Vector2(480, 330)
		add_child(v)
		v.tapped.connect(func(): _zoom(r))
		views.append(v)
		var cap := Ui.label("", 30, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40.0 + 510.0 * float(col), 570.0 + 640.0 * float(row)), Vector2(480, 90))
		cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(cap)
		captions.append(cap)
	var back := Ui.button("BACK", 56, Vector2(190, 1640), Vector2(700, 120), Ui.COL_BTN, "back")
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	zoom_p = Control.new()
	zoom_p.size = size
	zoom_p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.9)
	dim.size = size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	zoom_p.add_child(dim)
	zoom_view = PostcardView.new()
	zoom_view.position = Vector2(30, 420)
	zoom_view.size = Vector2(1020, 700)
	zoom_p.add_child(zoom_view)
	var close := Ui.button("CLOSE", 56, Vector2(190, 1260), Vector2(700, 120), Ui.COL_BTN, "close")
	close.pressed.connect(func(): zoom_p.visible = false)
	zoom_p.add_child(close)
	zoom_p.visible = false
	add_child(zoom_p)
	Ui.fit_safe(self)

func _zoom(r: int) -> void:
	var st := Save.postcard_of(r)
	if st == 0:
		return
	zoom_view.set_card(r, st)
	zoom_p.visible = true

func requirement(r: int) -> String:
	return "Complete the last Flight of the %s" % Regions.NAMES[r]

func refresh() -> void:
	zoom_p.visible = false
	var n := 0
	var gold := 0
	for r in Regions.COUNT:
		var st := Save.postcard_of(r)
		n += 1 if st > 0 else 0
		gold += 1 if st == 2 else 0
		views[r].set_card(r, st, requirement(r))
		if st == 0:
			captions[r].text = "Not yet earned"
		elif st == 1:
			captions[r].text = "3 stars on all %d Flights for the gold card  (%d/%d)" % [Flights.PER_REGION, Save.region_three_stars(r), Flights.PER_REGION]
		else:
			captions[r].text = "GOLD postcard"
	count_label.text = "%d / %d postcards    %d gold" % [n, Regions.COUNT, gold]
