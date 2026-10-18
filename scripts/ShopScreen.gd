class_name ShopScreen
extends Control
## The Shop: three categories (envelopes, baskets, passengers) bought with coins. Tap an item to try it on in
## the preview (with whatever else you have equipped), then BUY or EQUIP. Purely cosmetic. Built once.

signal back_pressed
signal changed

const COLS := 4
const CARD_W := 236.0
const CARD_H := 206.0
const GRID_X := 48.0
const GRID_Y := 690.0

var category := Cosmetics.ENV
var selected := 0
var coins_label: Label
var info_label: Label
var preview: Control
var tabs: Array[Button] = []
var slots: Array[Button] = []
var slot_names: Array[Label] = []
var slot_prices: Array[Label] = []
var action_btn: Button
var _art: BalloonArt

func _ready() -> void:
	size = Vector2(Lanes.W, Lanes.H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_art = BalloonArt.shared()
	add_child(Ui.label("SHOP", 70, HORIZONTAL_ALIGNMENT_LEFT, Vector2(40, 24), Vector2(400, 90)))
	coins_label = Ui.label("", 44, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(480, 36), Vector2(560, 70))
	coins_label.add_theme_color_override("font_color", Ui.COL_GOLD)
	add_child(coins_label)
	preview = Control.new()
	preview.position = Vector2(230, 130)
	preview.size = Vector2(620, 380)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.draw.connect(_draw_preview)
	add_child(preview)
	info_label = Ui.label("", 42, HORIZONTAL_ALIGNMENT_CENTER, Vector2(40, 520), Vector2(1000, 60))
	add_child(info_label)
	for c in 3:
		var t := Ui.button(Cosmetics.CATEGORIES[c], 36, Vector2(40.0 + 340.0 * float(c), 596), Vector2(320, 80), Color(0.35, 0.4, 0.55))
		t.pressed.connect(func(): _set_category(c))
		add_child(t)
		tabs.append(t)
	for i in 14:
		var col := i % COLS
		var row := i / COLS
		var b := Ui.button("", 20, Vector2(GRID_X + (CARD_W + 12.0) * float(col), GRID_Y + (CARD_H + 10.0) * float(row)), Vector2(CARD_W, CARD_H), Color(0.22, 0.27, 0.38))
		b.clip_contents = true
		b.pressed.connect(func(): _select(i))
		b.draw.connect(func(): _draw_slot(b, i))
		var nl := Ui.label("", 26, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 132), Vector2(CARD_W, 36))
		var pl := Ui.label("", 28, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0, 164), Vector2(CARD_W, 36))
		pl.add_theme_color_override("font_color", Ui.COL_GOLD)
		b.add_child(nl)
		b.add_child(pl)
		add_child(b)
		slots.append(b)
		slot_names.append(nl)
		slot_prices.append(pl)
	action_btn = Ui.button("", 52, Vector2(40, 1680), Vector2(620, 120), Color(0.95, 0.5, 0.15))
	action_btn.pressed.connect(_on_action)
	add_child(action_btn)
	var back := Ui.button("BACK", 52, Vector2(690, 1680), Vector2(350, 120))
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)

## Opening the shop: envelopes first, with what you wear selected.
func open() -> void:
	category = Cosmetics.ENV
	selected = Save.equipped(Cosmetics.ENV)
	refresh()

func _set_category(c: int) -> void:
	category = c
	selected = Save.equipped(c)
	refresh()

func _select(i: int) -> void:
	selected = i
	refresh()

func _on_action() -> void:
	if Save.owns(category, selected):
		Save.equip(category, selected)
	elif not Save.buy(category, selected):
		return
	changed.emit()
	refresh()

## What the preview shows: the selected item of this category, the equipped items of the others.
func preview_ids() -> Array:
	var ids := [Save.equipped(0), Save.equipped(1), Save.equipped(2)]
	ids[category] = selected
	return ids

func refresh() -> void:
	coins_label.text = "coins %s" % Tuning.fmt(float(Save.coins))
	var n := Cosmetics.count(category)
	selected = clampi(selected, 0, n - 1)
	for c in 3:
		tabs[c].disabled = c == category
	for i in slots.size():
		slots[i].visible = i < n
		if i >= n:
			continue
		slot_names[i].text = Cosmetics.item_name(category, i)
		var owned := Save.owns(category, i)
		slot_prices[i].text = ("EQUIPPED" if Save.equipped(category) == i else "owned") if owned else Tuning.fmt(float(Cosmetics.price(category, i)))
		slot_prices[i].add_theme_color_override("font_color", Color(0.5, 1.0, 0.6) if owned else Ui.COL_GOLD)
		slots[i].queue_redraw()
	var price := Cosmetics.price(category, selected)
	info_label.text = "%s" % Cosmetics.item_name(category, selected)
	if Save.owns(category, selected):
		var eq := Save.equipped(category) == selected
		action_btn.text = "EQUIPPED" if eq else "EQUIP"
		action_btn.disabled = eq
	else:
		action_btn.text = "BUY  %s" % Tuning.fmt(float(price))
		action_btn.disabled = Save.coins < price
	preview.queue_redraw()

func _draw_preview() -> void:
	var r := Rect2(Vector2.ZERO, preview.size)
	Regions.draw_backdrop(preview, 0, r, 5.0)
	var ids := preview_ids()
	preview.draw_set_transform(Vector2(preview.size.x * 0.5, 150.0), 0.0, Vector2(2.1, 2.1))
	_art.draw(preview, ids[0], ids[1], ids[2], 0.0, 0.0, 4.0 / 2.1)
	preview.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_slot(b: Button, i: int) -> void:
	if i >= Cosmetics.count(category):
		return
	var env := Save.equipped(0)
	var bk := Save.equipped(1)
	var ps := Save.equipped(2)
	match category:
		0:
			env = i
			bk = 0
			ps = 0
		1:
			bk = i
		2:
			ps = i
	var sc := 0.62   # envelopes: the whole balloon; baskets and passengers: zoomed in on the basket
	var pos := Vector2(CARD_W * 0.5, 62.0)
	if category == 1:
		sc = 1.5
		pos = Vector2(CARD_W * 0.5, 62.0 - 50.0 * sc + 10.0)
	elif category == 2:
		sc = 2.6
		pos = Vector2(CARD_W * 0.5 - 4.0 * sc, 76.0 - 62.0 * sc)
	b.draw_set_transform(pos, 0.0, Vector2(sc, sc))
	_art.draw(b, env, bk, ps, 0.0, 0.0, 4.0 / sc)
	b.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if Save.equipped(category) == i:
		b.draw_rect(Rect2(3, 3, CARD_W - 6, CARD_H - 6), Ui.COL_GOLD, false, 6.0)
	elif i == selected:
		b.draw_rect(Rect2(3, 3, CARD_W - 6, CARD_H - 6), Color.WHITE, false, 5.0)
	if Save.owns(category, i):   # a tick
		b.draw_line(Vector2(CARD_W - 44, 22), Vector2(CARD_W - 34, 32), Color(0.4, 1.0, 0.5), 6.0)
		b.draw_line(Vector2(CARD_W - 34, 32), Vector2(CARD_W - 16, 10), Color(0.4, 1.0, 0.5), 6.0)
	elif i != 0:   # a padlock-ish dot for items not owned yet
		b.draw_circle(Vector2(CARD_W - 28, 24), 8.0, Color(0.1, 0.1, 0.15, 0.8))

## Pre-warm: show item n of the whole catalogue, so every shape is drawn once at boot.
func prewarm_show(n: int) -> void:
	var c := 0
	var k := n
	while k >= Cosmetics.count(c) and c < 2:
		k -= Cosmetics.count(c)
		c += 1
	category = c
	selected = mini(k, Cosmetics.count(c) - 1)
	refresh()
