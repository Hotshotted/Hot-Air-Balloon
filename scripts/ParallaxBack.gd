class_name ParallaxBack
extends Node2D
## Three ridge layers behind the scenery (far, middle, near) per region: Countryside fields and rolling hills, Alpine peaks
## with snow, Sahara dunes, Himalayan ridges in violet haze. Each layer is one polygon, drawn ONCE per leg (redraw()), and
## drifts sideways at a small fraction of the wind of the balloon's layer (opposite to it, like the ground slipping by):
## per frame only three node positions change.

const FACTORS := [0.05, 0.11, 0.2]
const HEIGHTS := [330.0, 215.0, 125.0]          # ridge height above the ground, per layer
const STEP := 36.0                              # sampling step of a smooth ridge

var lanes: Lanes
var draws := 0
var _layers: Array[_Layer] = []
var _off := PackedFloat32Array([0.0, 0.0, 0.0])

class _Layer extends Node2D:
	var owner_back: ParallaxBack
	var idx := 0
	func _draw() -> void:
		owner_back.draw_layer(self, idx)

func _ready() -> void:
	for i in 3:
		var l := _Layer.new()
		l.owner_back = self
		l.idx = i
		add_child(l)
		_layers.append(l)

func redraw() -> void:
	for l in _layers:
		l.queue_redraw()

## Drift: `wind` is the balloon's layer wind (px/s).
func tick(dt: float, wind: float) -> void:
	for i in 3:
		_off[i] += (-wind * FACTORS[i] - 6.0 * (1.0 + float(i))) * dt
		_layers[i].position.x = fposmod(_off[i], Lanes.W) - Lanes.W

static func _hash(n: int) -> float:
	var x := sin(float(n) * 127.1 + 311.7) * 43758.5453
	return x - floorf(x)

## Height factor (0..1) of the ridge at x for a region and layer; periodic in Lanes.W so two copies tile seamlessly.
func _ridge(region: int, layer: int, x: float) -> float:
	var u := x / Lanes.W
	match region:
		0:   # rolling hills
			var ph := float(layer) * 1.7
			return clampf(0.5 + 0.3 * sin(TAU * (u * 1.0) + ph) + 0.2 * sin(TAU * (u * 2.0) + ph * 2.3) + 0.1 * sin(TAU * (u * 3.0) + ph), 0.05, 1.0)
		2:   # dunes: round, a little lopsided
			var a := TAU * (u * float(1 + layer)) + float(layer) * 2.1
			return clampf(0.5 + 0.32 * sin(a) + 0.12 * sin(2.0 * a + 1.0), 0.05, 1.0)
		_:   # jagged ridges: peaks at hashed positions, linear between
			var n := (3 + layer * 2) if region == 1 else (3 + layer)
			var pos := u * float(n)
			var k := int(floorf(pos))
			var f := pos - float(k)
			# peak at the middle of each slot, valley at the slot edges
			var seed_i := (k % n) * 7 + layer * 31 + region * 101
			var peak := 0.62 + 0.38 * _hash(seed_i)
			var valley := 0.22 + 0.1 * _hash(seed_i + 5)
			return lerpf(valley, peak, 1.0 - absf(f - 0.5) * 2.0)

func draw_layer(ci: CanvasItem, layer: int) -> void:
	draws += 1
	if lanes == null:
		return
	var r := lanes.region
	var gy := Lanes.GROUND_Y
	var hmax: float = HEIGHTS[layer] * (1.25 if r == 3 else (0.95 if r == 2 else (0.8 if r == 0 else 1.0)))
	var sky: Color = Regions.SKY_LOW[r]
	var far_col: Color = Regions.PEAK_B[r]
	var near_col: Color = Regions.PEAK_A[r]
	var base: Color
	match layer:
		0:
			base = sky.lerp(far_col, 0.55 if r == 2 else 0.38)
		1:
			base = sky.lerp(far_col, 0.9 if r == 2 else 0.7)
		_:
			base = near_col
	var step := STEP if (r == 0 or r == 2) else Lanes.W / float(((3 + layer * 2) if r == 1 else (3 + layer)) * 8)
	var total := int(Lanes.W * 2.0 / step)
	var poly := PackedVector2Array()
	var line := PackedVector2Array()
	for i in total + 1:
		var x := float(i) * step
		var y := gy - _ridge(r, layer, x) * hmax
		poly.append(Vector2(x, y))
		line.append(Vector2(x, y))
	poly.append(Vector2(Lanes.W * 2.0, gy + 2.0))
	poly.append(Vector2(0.0, gy + 2.0))
	ci.draw_colored_polygon(poly, lanes.tinted(base, gy - hmax * 0.5))
	var edge := Color(0, 0, 0, [0.3, 0.5, 1.0][layer])
	ci.draw_polyline(line, edge, [3.0, 3.5, 4.0][layer])
	# per-region details
	if r == 1 or r == 3:   # snow caps on the peaks of the far and middle layers
		if layer < 2 or r == 3:
			var snow: Color = Regions.SNOW[r]
			snow.a = [0.75, 0.9, 1.0][layer]
			var cap := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
			for i in range(1, total):
				var y0: float = line[i].y
				if y0 < line[i - 1].y and y0 < line[i + 1].y and gy - y0 > hmax * 0.62:
					var drop := (gy - y0) * 0.26
					cap[0] = line[i]
					cap[1] = Vector2(line[i].x + drop * 0.7, y0 + drop)
					cap[2] = Vector2(line[i].x + drop * 0.15, y0 + drop * 0.62)
					cap[3] = Vector2(line[i].x - drop * 0.7, y0 + drop)
					ci.draw_colored_polygon(cap, snow)
	elif r == 0 and layer == 2:   # field furrows fanning down the near hills
		for i in range(0, total, 2):
			var x2: float = line[i].x
			ci.draw_line(Vector2(x2, line[i].y + 14.0), Vector2(x2 + (x2 - Lanes.W) * 0.03, gy), Color(0.1, 0.35, 0.15, 0.28), 3.0)
	elif r == 2:   # a lighter crest along each dune
		var crest := Color(1, 0.95, 0.75, 0.5)
		ci.draw_polyline(line, crest, 2.0 + float(layer))
