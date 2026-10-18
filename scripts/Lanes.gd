class_name Lanes
extends Node2D
## The sky: horizontal wind layers stacked between the ground (bottom) and the goal (top). Each layer blows
## left or right at its own speed (shown by drifting particles, streamers and chevrons) and carries hazards
## that travel with it: birds, kites, other balloons and drones. Hazards loop around the screen, so a layer
## never runs dry and its gaps never change. Everything is stored in fixed-size arrays that are filled in
## place when a level starts: nothing is created or freed while playing.

const W := 1080.0
const H := 1920.0
const GROUND_Y := 1700.0
const BAND_TOP := 330.0          # top of the highest layer
const BAND_BOTTOM := 1640.0      # bottom of the lowest layer
const GOAL_Y := 310.0            # the balloon's centre above this line clears the level
const MARGIN := 160.0            # hazards live on a ring this far past each screen edge
const RING := W + 2.0 * MARGIN
const MAX_LANES := 9
const MAX_PER_LANE := 6
const MAX_HAZ := MAX_LANES * MAX_PER_LANE
const PARTS_PER_LANE := 14
const STREAMERS_PER_LANE := 2
const STREAM_PTS := 7
const FX_MAX := 48

enum { BIRD, KITE, BALLOON, DRONE }
const KIND_NAME := ["a bird", "a kite", "another balloon", "a drone"]
## Hit ellipse half sizes, speed relative to the wind of the layer, how much of the free layer height the
## hazard bobs through, and bob rate.
const KIND_HX := [34.0, 30.0, 48.0, 50.0]
const KIND_HY := [22.0, 44.0, 60.0, 20.0]
const KIND_SPEED := [1.55, 0.75, 0.45, 2.1]
const KIND_BOB := [0.35, 1.0, 0.5, 0.6]
const KIND_RATE := [2.2, 1.5, 0.8, 2.6]

const C_BIRD := Color(0.88, 0.27, 0.23)
const C_BIRD_WING := Color(0.7, 0.16, 0.2)
const C_KITE_A := Color(1.0, 0.8, 0.2)
const C_KITE_B := Color(0.95, 0.35, 0.55)
const C_BALLOON := Color(0.55, 0.36, 0.9)
const C_BALLOON_B := Color(0.35, 0.85, 0.8)
const C_DRONE := Color(0.32, 0.34, 0.42)
const C_TANK := Color(0.25, 0.85, 0.4)
const FX_BLACK := Color(0, 0, 0, 1)

# ---- Level state ----
var n_lanes := 5
var lane_h := 0.0
var lane_wind := PackedFloat32Array()    # px/s, sign = direction
var lane_vel := PackedFloat32Array()     # px/s of this layer's hazards
var lane_kind := PackedInt32Array()      # hazard kind, -1 = none
var lane_count := PackedInt32Array()
var lane_scale := PackedFloat32Array()
var lane_amp := PackedFloat32Array()     # bob amplitude, px
var hz_x := PackedFloat32Array()
var hz_y := PackedFloat32Array()
var hz_phase := PackedFloat32Array()
var pk_x := PackedFloat32Array()
var pk_y := PackedFloat32Array()
var pk_lane := PackedInt32Array()
var pk_on := PackedByteArray()
var pk_count := 0
var pt_x := PackedFloat32Array()
var pt_y := PackedFloat32Array()
var pt_len := PackedFloat32Array()
var pt_f := PackedFloat32Array()
var st_x := PackedFloat32Array()
var st_ph := PackedFloat32Array()
var fx_x := PackedFloat32Array()
var fx_y := PackedFloat32Array()
var fx_vx := PackedFloat32Array()
var fx_vy := PackedFloat32Array()
var fx_life := PackedFloat32Array()
var fx_col := PackedColorArray()
var _fx_next := 0
var last_hit_kind := 0
var level := 1
var rng := RandomNumberGenerator.new()
var showcase := false            # pre-warm: every shape on screen at once
var _t := 0.0

# ---- Pre-built shapes: [polygon, closed outline] ----
var _bird_body: Array
var _bird_head: Array
var _bird_tail: Array
var _bird_beak: Array
var _bird_wings: Array = []
var _kite_l: Array
var _kite_r: Array
var _tail_pts := PackedVector2Array()
var _bal_env: Array
var _bal_stripe: Array
var _bal_basket: Array
var _drone_body: Array
var _tank: Array
var _tank_band: Array
var _statics: Array = []                  # [polygon, closed outline, fill colour]
var _stream := PackedVector2Array()       # scratch for one streamer
var _chev := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

func _ready() -> void:
	rng.randomize()
	lane_wind.resize(MAX_LANES)
	lane_vel.resize(MAX_LANES)
	lane_kind.resize(MAX_LANES)
	lane_count.resize(MAX_LANES)
	lane_scale.resize(MAX_LANES)
	lane_amp.resize(MAX_LANES)
	hz_x.resize(MAX_HAZ)
	hz_y.resize(MAX_HAZ)
	hz_phase.resize(MAX_HAZ)
	pk_x.resize(MAX_LANES)
	pk_y.resize(MAX_LANES)
	pk_lane.resize(MAX_LANES)
	pk_on.resize(MAX_LANES)
	pt_x.resize(MAX_LANES * PARTS_PER_LANE)
	pt_y.resize(MAX_LANES * PARTS_PER_LANE)
	pt_len.resize(MAX_LANES * PARTS_PER_LANE)
	pt_f.resize(MAX_LANES * PARTS_PER_LANE)
	st_x.resize(MAX_LANES * STREAMERS_PER_LANE)
	st_ph.resize(MAX_LANES * STREAMERS_PER_LANE)
	fx_x.resize(FX_MAX)
	fx_y.resize(FX_MAX)
	fx_vx.resize(FX_MAX)
	fx_vy.resize(FX_MAX)
	fx_life.resize(FX_MAX)
	fx_col.resize(FX_MAX)
	_stream.resize(STREAM_PTS)
	_tail_pts.resize(5)
	_build_shapes()
	setup(1)

static func _pair(pts: Array) -> Array:
	var poly := PackedVector2Array(pts)
	var closed := poly.duplicate()
	closed.append(poly[0])
	return [poly, closed]

func _build_shapes() -> void:
	_bird_body = _pair([Vector2(-24, 2), Vector2(-14, -9), Vector2(8, -10), Vector2(20, -4), Vector2(22, 6), Vector2(8, 11), Vector2(-12, 10)])
	_bird_head = _pair([Vector2(14, -14), Vector2(24, -14), Vector2(30, -7), Vector2(24, 0), Vector2(14, 0), Vector2(10, -7)])
	_bird_tail = _pair([Vector2(-20, 1), Vector2(-40, -8), Vector2(-38, 8)])
	_bird_beak = _pair([Vector2(29, -10), Vector2(42, -5), Vector2(29, -2)])
	_bird_wings = [
		_pair([Vector2(-8, -8), Vector2(12, -8), Vector2(20, -40), Vector2(-2, -34)]),
		_pair([Vector2(-8, -6), Vector2(12, -6), Vector2(36, -14), Vector2(10, -24)]),
		_pair([Vector2(-8, -2), Vector2(12, -2), Vector2(30, 20), Vector2(6, 16)]),
	]
	_kite_l = _pair([Vector2(0, -44), Vector2(0, 32), Vector2(-30, -4)])
	_kite_r = _pair([Vector2(0, -44), Vector2(30, -4), Vector2(0, 32)])
	var env := PackedVector2Array()
	for deg in range(180, 361, 30):
		var a := deg_to_rad(float(deg))
		env.append(Vector2(cos(a) * 48.0, -12.0 + sin(a) * 46.0))
	env.append_array(PackedVector2Array([Vector2(36, 14), Vector2(18, 34), Vector2(-18, 34), Vector2(-36, 14)]))
	_bal_env = _pair(env)
	var st := PackedVector2Array()
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		st.append(Vector2(x, -12.0 - 46.0 * sqrt(1.0 - pow(x / 48.0, 2.0))))
	st.append(Vector2(9, 34))
	st.append(Vector2(-9, 34))
	_bal_stripe = _pair(st)
	_bal_basket = _pair([Vector2(-13, 46), Vector2(13, 46), Vector2(11, 64), Vector2(-11, 64)])
	_drone_body = _pair([Vector2(-28, -6), Vector2(-20, -14), Vector2(20, -14), Vector2(28, -6), Vector2(20, 10), Vector2(-20, 10)])
	_tank = _pair([Vector2(-12, -16), Vector2(12, -16), Vector2(15, -8), Vector2(15, 10), Vector2(10, 18), Vector2(-10, 18), Vector2(-15, 10), Vector2(-15, -8)])
	_tank_band = _pair([Vector2(-15, -4), Vector2(15, -4), Vector2(15, 6), Vector2(-15, 6)])
	# Scenery: low-poly mountains, trees, clouds and sun.
	_add_static([Vector2(-120, GROUND_Y), Vector2(130, 1560), Vector2(380, GROUND_Y)], Color(0.26, 0.5, 0.36))
	_add_static([Vector2(240, GROUND_Y), Vector2(560, 1580), Vector2(880, GROUND_Y)], Color(0.2, 0.42, 0.34))
	_add_static([Vector2(700, GROUND_Y), Vector2(950, 1530), Vector2(1200, GROUND_Y)], Color(0.27, 0.52, 0.38))
	for tx in [90.0, 210.0, 830.0, 990.0]:
		_add_static([Vector2(tx - 26, GROUND_Y - 10), Vector2(tx, GROUND_Y - 84), Vector2(tx + 26, GROUND_Y - 10)], Color(0.16, 0.5, 0.26))
	_add_static([Vector2(-60, 1700), Vector2(1140, 1700), Vector2(1140, 1960), Vector2(-60, 1960)], Color(0.36, 0.62, 0.3))
	_add_static([Vector2(430, 1700), Vector2(650, 1700), Vector2(650, 1722), Vector2(430, 1722)], Color(0.55, 0.57, 0.62))
	for c in [[190.0, 205.0, 1.0], [640.0, 195.0, 1.2], [420.0, 215.0, 0.6]]:
		_add_static(_octagon(Vector2(c[0], c[1]), 70.0 * c[2], 34.0 * c[2]), Color(1, 1, 1))
	_add_static(_octagon(Vector2(950, 205), 38.0, 38.0), Color(1.0, 0.88, 0.3))

static func _octagon(c: Vector2, rx: float, ry: float) -> Array:
	var pts: Array = []
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _add_static(pts: Array, fill: Color) -> void:
	var p := _pair(pts)
	_statics.append([p[0], p[1], fill])

# ---------------------------------------------------------------------------------------------------------
# Level setup
# ---------------------------------------------------------------------------------------------------------

func layers_for(lv: int) -> int:
	return clampi(int(Tuning.layers_base) + lv - 1, 3, mini(int(Tuning.layers_max), MAX_LANES))

func density_for(lv: int) -> float:
	return minf(Tuning.hazard_density + Tuning.density_per_level * float(lv - 1), Tuning.density_max)

func wind_for(lv: int) -> float:
	return minf(Tuning.wind_base + Tuning.wind_per_level * float(lv - 1), Tuning.wind_max)

## Lay out level `lv`: layers, winds, hazards, pickups and particles, all in place.
## `show` fills every slot with every kind (used by the start-up pre-warm).
func setup(lv: int, show: bool = false) -> void:
	level = lv
	showcase = show
	n_lanes = MAX_LANES if show else layers_for(lv)
	lane_h = (BAND_BOTTOM - BAND_TOP) / float(n_lanes)
	var balloon_w := Balloon.WIDTH * Tuning.balloon_scale
	var min_gap := Tuning.min_gap_factor * balloon_w
	var prev := 1.0 if rng.randf() < 0.5 else -1.0
	var empty_chance := maxf(Tuning.empty_lane_chance - 0.04 * float(lv - 1), 0.0)
	var kinds_open := 4 if show else mini(lv + 1, 4)
	var any_hazard := false
	var prev_kind := -1
	for i in MAX_LANES:
		lane_count[i] = 0
		lane_kind[i] = -1
		pk_on[i] = 0
		if i >= n_lanes:
			lane_wind[i] = 0.0
			lane_vel[i] = 0.0
			continue
		var sgn := -prev if rng.randf() < 0.75 else prev
		prev = sgn
		var mag := minf(wind_for(lv) + rng.randf() * Tuning.wind_variation, Tuning.wind_max)
		lane_wind[i] = sgn * mag
		lane_vel[i] = lane_wind[i]
		# The bottom layer (start) and the top one (goal approach) are always clear; the others carry hazards.
		var hazardous := i > 0 and i < n_lanes - 1
		if hazardous and not show and rng.randf() < empty_chance and (any_hazard or i < n_lanes - 2):
			hazardous = false
		if not hazardous:
			continue
		any_hazard = true
		var k := (i % 4) if show else rng.randi() % kinds_open
		if k == prev_kind and kinds_open > 1 and not show:
			k = (k + 1 + rng.randi() % (kinds_open - 1)) % kinds_open
		prev_kind = k
		lane_kind[i] = k
		var sc := Tuning.hazard_scale * clampf(lane_h / 230.0, 0.7, 1.15)
		lane_scale[i] = sc
		lane_vel[i] = lane_wind[i] * KIND_SPEED[k]
		lane_amp[i] = maxf(lane_h * 0.5 - float(KIND_HY[k]) * sc - 6.0, 0.0) * KIND_BOB[k]
		# As many hazards as asked for, but never more than leave every gap passable.
		var hw := 2.0 * float(KIND_HX[k]) * sc
		var fit := int(floor(RING / (hw + min_gap)))
		var want := roundi(density_for(lv) + rng.randf_range(-0.5, 0.5))
		var cnt := clampi(want, 1, mini(fit, MAX_PER_LANE))
		var spacing := RING / float(cnt)
		var free := maxf(spacing - hw - min_gap, 0.0)
		var start := rng.randf() * RING
		for j in cnt:
			var idx := i * MAX_PER_LANE + j
			hz_x[idx] = -MARGIN + fposmod(start + float(j) * spacing + rng.randf_range(-0.5, 0.5) * free, RING)
			hz_phase[idx] = rng.randf() * TAU
		lane_count[i] = cnt
	# Pickups: some layers carry propane, floating in the middle of their widest gap.
	pk_count = 0
	for i in range(1, n_lanes):
		if not show and rng.randf() >= Tuning.propane_chance:
			continue
		pk_lane[i] = i
		pk_on[i] = 1
		pk_count += 1
		var cnt2 := lane_count[i]
		if cnt2 == 0:
			pk_x[i] = rng.randf_range(100.0, W - 100.0)
		else:
			var best_gap := -1.0
			var best_x := 0.0
			for j in cnt2:
				var a := hz_x[i * MAX_PER_LANE + j]
				var nearest := RING
				for m in cnt2:
					var d := fposmod(hz_x[i * MAX_PER_LANE + m] - a, RING)
					if m != j and d > 0.0 and d < nearest:
						nearest = d
				if nearest > best_gap:
					best_gap = nearest
					best_x = a + nearest * 0.5
			pk_x[i] = -MARGIN + fposmod(best_x + MARGIN, RING)
		pk_y[i] = _lane_cy(i)
	# Particles and streamers.
	for i in n_lanes:
		for j in PARTS_PER_LANE:
			var idx2 := i * PARTS_PER_LANE + j
			pt_x[idx2] = rng.randf() * W
			pt_y[idx2] = rng.randf_range(0.1, 0.9)
			pt_len[idx2] = rng.randf_range(24.0, 70.0)
			pt_f[idx2] = rng.randf_range(0.6, 1.4)
		for j in STREAMERS_PER_LANE:
			var idx3 := i * STREAMERS_PER_LANE + j
			st_x[idx3] = rng.randf() * W
			st_ph[idx3] = rng.randf() * TAU
	clear_fx()
	update(0.0)

func _lane_cy(i: int) -> float:
	return BAND_BOTTOM - (float(i) + 0.5) * lane_h

## The layer a height is in (0 = bottom).
func lane_of(y: float) -> int:
	return clampi(int((BAND_BOTTOM - y) / lane_h), 0, n_lanes - 1)

func wind_at(y: float) -> float:
	return lane_wind[lane_of(y)]

# ---------------------------------------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------------------------------------

func update(dt: float) -> void:
	_t += dt
	for i in n_lanes:
		var wnd := lane_wind[i]
		for j in PARTS_PER_LANE:
			var idx := i * PARTS_PER_LANE + j
			var x := pt_x[idx] + wnd * pt_f[idx] * dt
			if x > W + 80.0:
				x -= W + 160.0
			elif x < -80.0:
				x += W + 160.0
			pt_x[idx] = x
		for j in STREAMERS_PER_LANE:
			var idx2 := i * STREAMERS_PER_LANE + j
			var x2 := st_x[idx2] + wnd * 0.8 * dt
			if x2 > W + 120.0:
				x2 -= W + 240.0
			elif x2 < -120.0:
				x2 += W + 240.0
			st_x[idx2] = x2
		var k := lane_kind[i]
		for j in lane_count[i]:
			var idx3 := i * MAX_PER_LANE + j
			var x3 := hz_x[idx3] + lane_vel[i] * dt
			if x3 >= W + MARGIN:
				x3 -= RING
			elif x3 < -MARGIN:
				x3 += RING
			hz_x[idx3] = x3
			hz_y[idx3] = _lane_cy(i) + sin(_t * float(KIND_RATE[k]) + hz_phase[idx3]) * lane_amp[i]
		if pk_on[i] == 1 or showcase:
			var px := pk_x[i] + lane_vel[i] * dt
			if px >= W + MARGIN:
				px -= RING
			elif px < -MARGIN:
				px += RING
			pk_x[i] = px
			pk_y[i] = _lane_cy(i) + sin(_t * 2.0 + float(i)) * minf(lane_h * 0.18, 24.0)
	for f in FX_MAX:
		if fx_life[f] > 0.0:
			fx_life[f] -= dt
			fx_x[f] += fx_vx[f] * dt
			fx_y[f] += fx_vy[f] * dt
			fx_vy[f] += 600.0 * dt
	queue_redraw()

## Does the balloon touch a hazard? Its hit circles against each hazard's ellipse.
func hits(balloon: Balloon) -> bool:
	for c in 3:
		var p := balloon.hit_pos(c)
		var r := balloon.hit_radius(c)
		for i in n_lanes:
			var k := lane_kind[i]
			if k < 0:
				continue
			var ex := float(KIND_HX[k]) * lane_scale[i] + r
			var ey := float(KIND_HY[k]) * lane_scale[i] + r
			for j in lane_count[i]:
				var idx := i * MAX_PER_LANE + j
				var dx := (p.x - hz_x[idx]) / ex
				var dy := (p.y - hz_y[idx]) / ey
				if dx * dx + dy * dy < 1.0:
					last_hit_kind = k
					return true
	return false

## Pick up any propane the balloon touches; returns how many.
func collect(balloon: Balloon) -> int:
	var got := 0
	for i in n_lanes:
		if pk_on[i] == 0:
			continue
		for c in 3:
			var p := balloon.hit_pos(c)
			if p.distance_to(Vector2(pk_x[i], pk_y[i])) < balloon.hit_radius(c) + 30.0:
				pk_on[i] = 0
				got += 1
				burst(Vector2(pk_x[i], pk_y[i]), C_TANK, 14, 320.0)
				break
	return got

## A pooled burst of square sparks.
func burst(p: Vector2, color: Color, n: int, speed: float) -> void:
	for j in n:
		var f := _fx_next
		_fx_next = (_fx_next + 1) % FX_MAX
		var a := rng.randf() * TAU
		var sp := speed * rng.randf_range(0.4, 1.0)
		fx_x[f] = p.x
		fx_y[f] = p.y
		fx_vx[f] = cos(a) * sp
		fx_vy[f] = sin(a) * sp - 120.0
		fx_life[f] = rng.randf_range(0.5, 0.9)
		fx_col[f] = color

func clear_fx() -> void:
	for f in FX_MAX:
		fx_life[f] = 0.0

# ---------------------------------------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------------------------------------

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Sky: one tinted band per layer, warm near the ground and deep blue at the top.
	draw_rect(Rect2(0, 0, W, BAND_TOP), Color(0.27, 0.5, 0.88))
	draw_rect(Rect2(0, BAND_BOTTOM, W, H - BAND_BOTTOM), Color(1.0, 0.85, 0.65))
	for i in n_lanes:
		var t := (float(i) + 0.5) / float(n_lanes)
		var col := Color(1.0, 0.85, 0.55).lerp(Color(0.62, 0.88, 0.8), minf(t * 2.0, 1.0)) if t < 0.5 else Color(0.62, 0.88, 0.8).lerp(Color(0.3, 0.58, 0.95), (t - 0.5) * 2.0)
		if i % 2 == 1:
			col = col.lightened(0.07)
		draw_rect(Rect2(0, BAND_BOTTOM - float(i + 1) * lane_h, W, lane_h + 1.0), col)
	_draw_scenery_back()
	for i in n_lanes:
		_draw_lane_wind(i)
	for i in n_lanes:
		if pk_on[i] == 1:
			_draw_tank(pk_x[i], pk_y[i])
	for i in n_lanes:
		var k := lane_kind[i]
		for j in lane_count[i]:
			var idx := i * MAX_PER_LANE + j
			_draw_hazard(k, hz_x[idx], hz_y[idx], signf(lane_vel[i]), lane_scale[i], hz_phase[idx])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_goal()
	for f in FX_MAX:
		if fx_life[f] > 0.0:
			var r := Rect2(fx_x[f] - 5.0, fx_y[f] - 5.0, 10.0, 10.0)
			draw_rect(r, fx_col[f])
			draw_rect(r, FX_BLACK, false, 2.0)

func _draw_scenery_back() -> void:
	for s in _statics:
		draw_colored_polygon(s[0], s[2])
		draw_polyline(s[1], FX_BLACK, 4.0)

func _draw_goal() -> void:
	var size := 34.0
	for row in 2:
		for c in int(W / size) + 1:
			if (c + row) % 2 == 0:
				draw_rect(Rect2(float(c) * size, GOAL_Y - 2.0 * size + float(row) * size, size, size), FX_BLACK)
			else:
				draw_rect(Rect2(float(c) * size, GOAL_Y - 2.0 * size + float(row) * size, size, size), Color.WHITE)
	draw_rect(Rect2(0, GOAL_Y - 2.0 * size, W, 2.0 * size), FX_BLACK, false, 4.0)

func _draw_lane_wind(i: int) -> void:
	var wnd := lane_wind[i]
	var dir := signf(wnd)
	var top := BAND_BOTTOM - float(i + 1) * lane_h
	var strength := clampf(absf(wnd) / 200.0, 0.0, 1.0)
	# Particles
	var pcol := Color(1, 1, 1, 0.55)
	for j in PARTS_PER_LANE:
		var idx := i * PARTS_PER_LANE + j
		var y := top + pt_y[idx] * lane_h
		var x := pt_x[idx]
		draw_line(Vector2(x, y), Vector2(x - dir * pt_len[idx] * (0.6 + strength), y), pcol, 3.0)
	# Chevrons that point where the wind blows: more of them in a stronger wind.
	var cy := top + lane_h * 0.5
	var chevrons := 3 + int(strength * 3.0)
	for c in chevrons:
		var cx := fposmod(_t * wnd * 0.6 + float(c) * W / float(chevrons), W + 100.0) - 50.0
		_chev[0] = Vector2(cx - dir * 12.0, cy - 16.0)
		_chev[1] = Vector2(cx + dir * 12.0, cy)
		_chev[2] = Vector2(cx - dir * 12.0, cy + 16.0)
		draw_polyline(_chev, Color(1, 1, 1, 0.3), 5.0)
	# Streamers: wavy ribbons trailing behind the wind.
	for j in STREAMERS_PER_LANE:
		var idx2 := i * STREAMERS_PER_LANE + j
		var sx := st_x[idx2]
		var sy := top + lane_h * (0.3 + 0.4 * float(j))
		for p in STREAM_PTS:
			var f := float(p) / float(STREAM_PTS - 1)
			_stream[p] = Vector2(sx - dir * float(p) * 16.0, sy + sin(_t * 5.0 + st_ph[idx2] + float(p) * 0.9) * 7.0 * f)
		draw_polyline(_stream, FX_BLACK, 9.0)
		draw_polyline(_stream, Color(1.0, 0.95, 0.4) if (i + j) % 2 == 0 else Color(1.0, 0.5, 0.65), 5.0)

func _fill(pair: Array, fill: Color, w: float) -> void:
	draw_colored_polygon(pair[0], fill)
	draw_polyline(pair[1], FX_BLACK, w)

func _draw_tank(x: float, y: float) -> void:
	draw_set_transform(Vector2(x, y), 0.0, Vector2(1.25, 1.25))
	var w := 3.2
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	draw_arc(Vector2.ZERO, 34.0 + 4.0 * pulse, 0.0, TAU, 20, Color(1, 1, 1, 0.45), 3.0)
	draw_rect(Rect2(-5, -25, 10, 9), Color(0.6, 0.62, 0.68))
	draw_rect(Rect2(-5, -25, 10, 9), FX_BLACK, false, w)
	_fill(_tank, C_TANK, w)
	_fill(_tank_band, Color.WHITE, w)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_hazard(k: int, x: float, y: float, dir: float, s: float, phase: float) -> void:
	draw_set_transform(Vector2(x, y), 0.0, Vector2(dir * s, s))
	var w := 4.0 / s
	match k:
		BIRD:
			var q := int(floor(_t * 7.0 + phase * 0.64)) & 3
			var frame := 0 if q == 0 else (2 if q == 2 else 1)
			_fill(_bird_tail, C_BIRD_WING, w)
			_fill(_bird_body, C_BIRD, w)
			_fill(_bird_wings[frame], C_BIRD_WING, w)
			_fill(_bird_head, C_BIRD, w)
			_fill(_bird_beak, Color(1.0, 0.8, 0.2), w * 0.8)
			draw_circle(Vector2(22, -8), 3.2, Color.WHITE)
			draw_circle(Vector2(23, -8), 1.6, FX_BLACK)
		KITE:
			_fill(_kite_l, C_KITE_A, w)
			_fill(_kite_r, C_KITE_B, w)
			draw_line(Vector2(-30, -4), Vector2(30, -4), FX_BLACK, w * 0.7)
			for p in 5:
				_tail_pts[p] = Vector2(sin(_t * 5.0 + phase + float(p)) * 8.0 * float(p) / 4.0, 32.0 + float(p) * 11.0)
			draw_polyline(_tail_pts, FX_BLACK, w * 0.8)
			for p in range(1, 5, 2):
				draw_circle(_tail_pts[p], 5.0, C_KITE_B)
		BALLOON:
			_fill(_bal_env, C_BALLOON, w)
			_fill(_bal_stripe, C_BALLOON_B, w * 0.8)
			draw_line(Vector2(-18, 34), Vector2(-11, 46), FX_BLACK, w * 0.8)
			draw_line(Vector2(18, 34), Vector2(11, 46), FX_BLACK, w * 0.8)
			_fill(_bal_basket, Color(0.55, 0.38, 0.22), w)
		DRONE:
			draw_line(Vector2(-26, -8), Vector2(-46, -18), FX_BLACK, w * 1.6)
			draw_line(Vector2(26, -8), Vector2(46, -18), FX_BLACK, w * 1.6)
			draw_line(Vector2(-18, 10), Vector2(-24, 18), FX_BLACK, w)
			draw_line(Vector2(18, 10), Vector2(24, 18), FX_BLACK, w)
			var blur := 20.0 if int(floor(_t * 30.0 + phase)) % 2 == 0 else 27.0
			draw_line(Vector2(-46 - blur, -20), Vector2(-46 + blur, -20), FX_BLACK, w * 1.4)
			draw_line(Vector2(46 - blur, -20), Vector2(46 + blur, -20), FX_BLACK, w * 1.4)
			_fill(_drone_body, C_DRONE, w)
			draw_circle(Vector2(14, -1), 5.0, Color(0.5, 0.85, 1.0))
			draw_circle(Vector2(-10, 2), 4.5, Color(1.0, 0.2, 0.2) if int(floor(_t * 3.0 + phase)) % 2 == 0 else Color(0.4, 0.1, 0.1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
