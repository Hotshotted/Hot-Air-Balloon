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
const MAX_COINS := MAX_LANES
const MAX_THERMALS := 3
const THERMAL_PARTS := 10

enum { BIRD, KITE, BALLOON, DRONE, EAGLE, CABLE, CARPET, GLIDER }
const KIND_NAME := ["a bird", "a kite", "another balloon", "a drone", "an eagle", "a cable car", "a flying carpet", "a paraglider"]
## Hit ellipse half sizes, speed relative to the wind of the layer, how much of the free layer height the
## hazard bobs through, and bob rate.
const KIND_HX := [34.0, 30.0, 48.0, 50.0, 46.0, 36.0, 52.0, 56.0]
const KIND_HY := [22.0, 44.0, 60.0, 20.0, 28.0, 34.0, 16.0, 38.0]
const KIND_SPEED := [1.55, 0.75, 0.45, 2.1, 1.8, 0.6, 1.3, 0.9]
const KIND_BOB := [0.35, 1.0, 0.5, 0.6, 0.3, 0.0, 0.8, 0.7]
const KIND_RATE := [2.2, 1.5, 0.8, 2.6, 2.0, 1.0, 1.8, 1.0]

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
var lane_wind := PackedFloat32Array()    # px/s right now, sign = direction (gusts make it change)
var lane_base := PackedFloat32Array()    # the layer's steady wind
var lane_gph := PackedFloat32Array()     # gust phase
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
var cn_x := PackedFloat32Array()      # floating coins (they count toward a Flight's third star)
var cn_y := PackedFloat32Array()
var cn_on := PackedByteArray()
var _order := PackedInt32Array()
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
var th_x := PackedFloat32Array()         # thermals (Sahara): columns of updraft
var th_dx := PackedFloat32Array()
var th_count := 0
var thp_x := PackedFloat32Array()
var thp_y := PackedFloat32Array()
var region := 0
var gusty := false
var haze_on := false
var thin_air := false
var jet := false
var focus_lane := 0                      # the layer the balloon is in (sand haze clears around it)
var _fx_next := 0
var last_hit_kind := 0
var level := 1.0
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
var _scn: Array = []                      # per region: a list of [polygon, closed outline, fill colour]
var _cable_body: Array
var _cable_roof: Array
var _glider_canopy: Array
var _glider_panel: Array
var _carpet: Array
var _stream := PackedVector2Array()       # scratch for one streamer
var _chev := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

func _ready() -> void:
	rng.randomize()
	lane_wind.resize(MAX_LANES)
	lane_base.resize(MAX_LANES)
	lane_gph.resize(MAX_LANES)
	th_x.resize(MAX_THERMALS)
	th_dx.resize(MAX_THERMALS)
	thp_x.resize(MAX_THERMALS * THERMAL_PARTS)
	thp_y.resize(MAX_THERMALS * THERMAL_PARTS)
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
	cn_x.resize(MAX_COINS)
	cn_y.resize(MAX_COINS)
	cn_on.resize(MAX_COINS)
	_order.resize(MAX_LANES)
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
	setup(1.0)

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
	_cable_body = _pair([Vector2(-34, -14), Vector2(34, -14), Vector2(38, 24), Vector2(-38, 24)])
	_cable_roof = _pair([Vector2(-30, -14), Vector2(-20, -24), Vector2(20, -24), Vector2(30, -14)])
	_glider_canopy = _pair([Vector2(-58, 0), Vector2(-44, -26), Vector2(0, -38), Vector2(44, -26), Vector2(58, 0), Vector2(30, -8), Vector2(-30, -8)])
	_glider_panel = _pair([Vector2(-14, -36), Vector2(14, -36), Vector2(20, -8), Vector2(-20, -8)])
	_carpet = _pair([Vector2(-52, -5), Vector2(52, -5), Vector2(52, 6), Vector2(-52, 6)])
	_build_scenery()

# Scenery per region: peaks (with snow caps), trees, dunes, a sun, ground and a launch pad.
func _build_scenery() -> void:
	var peak_y := [1560.0, 1440.0, 1630.0, 1370.0]
	for r in Regions.COUNT:
		var list: Array = []
		var py: float = peak_y[r]
		var gy := GROUND_Y
		_scn_add(list, [Vector2(-140, gy), Vector2(130, py), Vector2(400, gy)], Regions.PEAK_A[r])
		_scn_add(list, [Vector2(220, gy), Vector2(560, py + 30.0), Vector2(900, gy)], Regions.PEAK_B[r])
		_scn_add(list, [Vector2(690, gy), Vector2(950, py - 25.0), Vector2(1220, gy)], Regions.PEAK_A[r])
		if Regions.SNOW[r].a > 0.5:
			for pk in [Vector2(130, py), Vector2(560, py + 30.0), Vector2(950, py - 25.0)]:
				var cap_h: float = (gy - pk.y) * 0.3
				_scn_add(list, [pk, pk + Vector2(-cap_h * 0.62, cap_h), pk + Vector2(cap_h * 0.62, cap_h)], Regions.SNOW[r])
		if r == 0 or r == 1:
			for tx in [90.0, 210.0, 830.0, 990.0]:
				_scn_add(list, [Vector2(tx - 26, gy - 10), Vector2(tx, gy - 84), Vector2(tx + 26, gy - 10)], Color(0.16, 0.5, 0.26) if r == 0 else Color(0.14, 0.38, 0.3))
		if r == 2:
			_scn_add(list, _octagon(Vector2(880, 1600), 70.0, 70.0), Color(1.0, 0.84, 0.3))
			for cx in [160.0, 760.0]:   # cacti: a box with an arm
				_scn_add(list, [Vector2(cx - 9, gy), Vector2(cx - 9, gy - 78), Vector2(cx + 9, gy - 78), Vector2(cx + 9, gy)], Color(0.3, 0.55, 0.3))
				_scn_add(list, [Vector2(cx + 9, gy - 40), Vector2(cx + 30, gy - 40), Vector2(cx + 30, gy - 62), Vector2(cx + 20, gy - 62), Vector2(cx + 20, gy - 50), Vector2(cx + 9, gy - 50)], Color(0.3, 0.55, 0.3))
		_scn_add(list, [Vector2(-60, gy), Vector2(1140, gy), Vector2(1140, 1960), Vector2(-60, 1960)], Regions.GROUND[r])
		_scn_add(list, [Vector2(430, gy), Vector2(650, gy), Vector2(650, gy + 22), Vector2(430, gy + 22)], Color(0.55, 0.57, 0.62))
		_scn.append(list)

func _scn_add(list: Array, pts: Array, fill: Color) -> void:
	var p := _pair(pts)
	list.append([p[0], p[1], fill])

static func _octagon(c: Vector2, rx: float, ry: float) -> Array:
	var pts: Array = []
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


# ---------------------------------------------------------------------------------------------------------
# Level setup
# ---------------------------------------------------------------------------------------------------------

func layers_for(lv: float) -> int:
	return clampi(int(Tuning.layers_base) + int(lv) - 1, 3, mini(int(Tuning.layers_max), MAX_LANES))

func density_for(lv: float) -> float:
	return minf(Tuning.hazard_density + Tuning.density_per_level * (lv - 1.0), Tuning.density_max)

func wind_for(lv: float) -> float:
	return minf(Tuning.wind_base + Tuning.wind_per_level * (lv - 1.0), Tuning.wind_max)

## Lay out a leg of difficulty `lv`: layers, winds, hazards, pickups, coins and particles, all in place.
## `seed_val` >= 0 fixes the whole layout (a Flight's legs are the same every time); -1 = random.
## `show` fills every slot with every kind (used by the start-up pre-warm).
func setup(lv: float, show: bool = false, seed_val: int = -1, reg: int = 0) -> void:
	if seed_val >= 0:
		rng.seed = seed_val
	level = lv
	showcase = show
	region = 2 if show else clampi(reg, 0, Regions.COUNT - 1)
	gusty = show or Regions.GUSTY[region]
	haze_on = show or Regions.HAZE[region]
	thin_air = Regions.THIN_AIR[region]
	jet = show or Regions.JET[region]
	_t = 0.0
	hz_x.fill(0.0)
	hz_y.fill(0.0)
	hz_phase.fill(0.0)
	pk_x.fill(0.0)
	cn_x.fill(0.0)
	n_lanes = MAX_LANES if show else layers_for(lv)
	lane_h = (BAND_BOTTOM - BAND_TOP) / float(n_lanes)
	var balloon_w := Balloon.WIDTH * Tuning.balloon_scale
	var min_gap := Tuning.min_gap_factor * balloon_w
	var prev := 1.0 if rng.randf() < 0.5 else -1.0
	var empty_chance := maxf(Tuning.empty_lane_chance - 0.04 * (lv - 1.0), 0.0)
	var kinds_open := 4 if show else Regions.kinds_open(region, lv)
	var klist: Array = Regions.KINDS[region]
	var wmult := Tuning.countryside_wind_mult if region == 0 and not show else 1.0
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
		var mag := minf(wind_for(lv) * wmult + rng.randf() * Tuning.wind_variation, Tuning.wind_max)
		var jet_lane: bool = jet and i == n_lanes - 1   # Himalayas: a fast jet stream on top
		if jet_lane:
			mag = Tuning.jet_wind
		lane_base[i] = sgn * mag
		lane_wind[i] = lane_base[i]
		lane_vel[i] = lane_wind[i]
		lane_gph[i] = rng.randf() * TAU
		# The bottom layer (start) is always clear and so is the top one (goal approach), except for a jet stream;
		# the others carry hazards.
		var hazardous: bool = i > 0 and (i < n_lanes - 1 or jet_lane)
		if show:
			hazardous = i > 0
		if hazardous and not show and not jet_lane and rng.randf() < empty_chance and (any_hazard or i < n_lanes - 2):
			hazardous = false
		if not hazardous:
			continue
		any_hazard = true
		var k := (i - 1) % 8 if show else GLIDER
		if not show and not jet_lane:
			var idx_k := rng.randi() % kinds_open
			k = klist[idx_k]
			if k == prev_kind and kinds_open > 1:
				k = klist[(idx_k + 1 + rng.randi() % (kinds_open - 1)) % kinds_open]
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
	for i in MAX_COINS:
		cn_on[i] = 0
	for i in range(1, n_lanes):
		if not show and rng.randf() >= Tuning.propane_chance:
			continue
		pk_on[i] = 1
		pk_count += 1
		if lane_count[i] == 0:
			pk_x[i] = rng.randf_range(100.0, W - 100.0)
		else:
			pk_x[i] = _gap_center(i, 0)
		pk_y[i] = _lane_cy(i)
	# Coins: coins_per_leg of them, preferably in layers with no propane (shuffled order, seeded).
	var n_cand := n_lanes - 1
	for k in n_cand:
		_order[k] = k + 1
	for k in range(n_cand - 1, 0, -1):
		var r := rng.randi() % (k + 1)
		var tmp := _order[k]
		_order[k] = _order[r]
		_order[r] = tmp
	var want_coins := mini(int(Tuning.coins_per_leg), n_cand)
	var placed := 0
	for pass_i in 2:
		for k in n_cand:
			if placed >= want_coins:
				break
			var i2 := _order[k]
			if cn_on[i2] == 1 or (pass_i == 0 and pk_on[i2] == 1):
				continue
			var cx := 0.0
			if lane_count[i2] == 0:
				cx = pk_x[i2] + 300.0 if pk_on[i2] == 1 else rng.randf_range(100.0, W - 100.0)
			elif pk_on[i2] == 1:
				cx = _gap_center(i2, 1) if lane_count[i2] >= 2 else pk_x[i2] + 300.0
			else:
				cx = _gap_center(i2, 0)
			cn_x[i2] = -MARGIN + fposmod(cx + MARGIN, RING)
			cn_y[i2] = _lane_cy(i2)
			cn_on[i2] = 1
			placed += 1
	# Thermals: columns of updraft (Sahara; more of them at higher difficulty).
	th_count = 0
	if show or Regions.THERMALS[region]:
		th_count = MAX_THERMALS if show else clampi(2 + int((lv - float(Flights.REGION_BASE[region])) / 3.0), 2, MAX_THERMALS)
		for t in th_count:
			th_x[t] = rng.randf_range(160.0, W - 160.0)
			th_dx[t] = rng.randf_range(-30.0, 30.0)
			for j in THERMAL_PARTS:
				thp_x[t * THERMAL_PARTS + j] = rng.randf_range(-0.85, 0.85)
				thp_y[t * THERMAL_PARTS + j] = rng.randf()
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

## Centre (on the ring) of the rank-th widest gap between the hazards of a layer (rank 0 = widest).
func _gap_center(i: int, rank: int) -> float:
	var c := lane_count[i]
	var used := 0
	var best_j := 0
	var best_gap := 0.0
	for r in mini(rank, c - 1) + 1:
		best_gap = -1.0
		for j in c:
			if used & (1 << j):
				continue
			var a := hz_x[i * MAX_PER_LANE + j]
			var nearest := RING
			for m in c:
				var d := fposmod(hz_x[i * MAX_PER_LANE + m] - a, RING)
				if m != j and d > 0.0 and d < nearest:
					nearest = d
			if nearest > best_gap:
				best_gap = nearest
				best_j = j
		used |= 1 << best_j
	return hz_x[i * MAX_PER_LANE + best_j] + best_gap * 0.5

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
		var k0 := lane_kind[i]
		if gusty:   # Alps: the layer's wind swells and fades around its steady speed
			lane_wind[i] = lane_base[i] * (1.0 + Tuning.gust_amp * sin(_t * Tuning.gust_rate + lane_gph[i]))
			lane_vel[i] = lane_wind[i] * (float(KIND_SPEED[k0]) if k0 >= 0 else 1.0)
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
	for i in n_lanes:
		if cn_on[i] == 1 or showcase:
			var cx := cn_x[i] + lane_vel[i] * dt
			if cx >= W + MARGIN:
				cx -= RING
			elif cx < -MARGIN:
				cx += RING
			cn_x[i] = cx
			cn_y[i] = _lane_cy(i) + sin(_t * 2.3 + float(i) * 1.7) * minf(lane_h * 0.18, 24.0)
	for t in th_count:
		var tx := th_x[t] + th_dx[t] * dt
		if tx > W - 120.0 or tx < 120.0:
			th_dx[t] = -th_dx[t]
		th_x[t] = clampf(tx, 120.0, W - 120.0)
		for j in THERMAL_PARTS:
			var ti := t * THERMAL_PARTS + j
			thp_y[ti] -= dt * 0.22
			if thp_y[ti] < 0.0:
				thp_y[ti] += 1.0
	for f in FX_MAX:
		if fx_life[f] > 0.0:
			fx_life[f] -= dt
			fx_x[f] += fx_vx[f] * dt
			fx_y[f] += fx_vy[f] * dt
			fx_vy[f] += 600.0 * dt
	queue_redraw()

## Extra rise (px/s) from the thermals at horizontal position x (0 outside them).
func thermal_lift(x: float) -> float:
	var l := 0.0
	for t in th_count:
		var d := absf(x - th_x[t]) / Tuning.thermal_width
		if d < 1.0:
			l = maxf(l, Tuning.thermal_lift * (1.0 - d * d))
	return l

## Opacity of the sand haze over layer i (0 around the balloon's own layer, more with distance).
func haze_alpha(i: int) -> float:
	return clampf((float(absi(i - focus_lane)) - Tuning.haze_clear_lanes) * Tuning.haze_per_lane, 0.0, Tuning.haze_max)

## How much of its climb speed the burner keeps at height y (Himalayas: thin air weakens it with altitude).
func climb_mult_at(y: float) -> float:
	if not thin_air:
		return 1.0
	return 1.0 - Tuning.thin_air_loss * clampf((BAND_BOTTOM - y) / (BAND_BOTTOM - GOAL_Y), 0.0, 1.0)

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

## Collect any floating coin the balloon touches; returns how many.
func collect_coins(balloon: Balloon) -> int:
	var got := 0
	for i in n_lanes:
		if cn_on[i] == 0:
			continue
		for c in 3:
			if balloon.hit_pos(c).distance_to(Vector2(cn_x[i], cn_y[i])) < balloon.hit_radius(c) + 30.0:
				cn_on[i] = 0
				got += 1
				burst(Vector2(cn_x[i], cn_y[i]), Color(1.0, 0.85, 0.2), 12, 300.0)
				break
	return got

func coins_left() -> int:
	var n := 0
	for i in n_lanes:
		n += cn_on[i]
	return n

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
	var c_low: Color = Regions.SKY_LOW[region]
	var c_mid: Color = Regions.SKY_MID[region]
	var c_high: Color = Regions.SKY_HIGH[region]
	draw_rect(Rect2(0, 0, W, BAND_TOP), Regions.SKY_TOP[region])
	draw_rect(Rect2(0, BAND_BOTTOM, W, H - BAND_BOTTOM), c_low)
	for i in n_lanes:
		var t := (float(i) + 0.5) / float(n_lanes)
		var col := c_low.lerp(c_mid, minf(t * 2.0, 1.0)) if t < 0.5 else c_mid.lerp(c_high, (t - 0.5) * 2.0)
		if i % 2 == 1:
			col = col.lightened(0.07)
		draw_rect(Rect2(0, BAND_BOTTOM - float(i + 1) * lane_h, W, lane_h + 1.0), col)
	_draw_scenery_back()
	for i in n_lanes:
		_draw_lane_wind(i)
	for t in th_count:
		_draw_thermal(t)
	for i in n_lanes:
		if lane_kind[i] == CABLE:
			var cy := _lane_cy(i) - 44.0 * lane_scale[i]
			draw_line(Vector2(0, cy), Vector2(W, cy), FX_BLACK, 5.0)
	for i in n_lanes:
		if pk_on[i] == 1:
			_draw_tank(pk_x[i], pk_y[i])
	for i in n_lanes:
		if cn_on[i] == 1:
			_draw_coin(cn_x[i], cn_y[i], float(i))
	for i in n_lanes:
		var k := lane_kind[i]
		for j in lane_count[i]:
			var idx := i * MAX_PER_LANE + j
			_draw_hazard(k, hz_x[idx], hz_y[idx], signf(lane_vel[i]), lane_scale[i], hz_phase[idx])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if haze_on:   # sand haze hides the layers away from the balloon, more the further they are
		for i in n_lanes:
			var a := haze_alpha(i)
			if a > 0.01:
				draw_rect(Rect2(0, BAND_BOTTOM - float(i + 1) * lane_h, W, lane_h + 1.0), Color(0.93, 0.8, 0.56, a))
	_draw_goal()
	for f in FX_MAX:
		if fx_life[f] > 0.0:
			var r := Rect2(fx_x[f] - 5.0, fx_y[f] - 5.0, 10.0, 10.0)
			draw_rect(r, fx_col[f])
			draw_rect(r, FX_BLACK, false, 2.0)

func _draw_scenery_back() -> void:
	for s in _scn[region]:
		draw_colored_polygon(s[0], s[2])
		draw_polyline(s[1], FX_BLACK, 4.0)

func _draw_thermal(t: int) -> void:
	var hw := Tuning.thermal_width
	var x := th_x[t]
	draw_rect(Rect2(x - hw, BAND_TOP, hw * 2.0, BAND_BOTTOM - BAND_TOP), Color(1.0, 0.62, 0.2, 0.16))
	draw_line(Vector2(x - hw, BAND_TOP), Vector2(x - hw, BAND_BOTTOM), Color(1.0, 0.7, 0.3, 0.5), 3.0)
	draw_line(Vector2(x + hw, BAND_TOP), Vector2(x + hw, BAND_BOTTOM), Color(1.0, 0.7, 0.3, 0.5), 3.0)
	for j in THERMAL_PARTS:
		var ti := t * THERMAL_PARTS + j
		var px := x + thp_x[ti] * hw
		var py := BAND_TOP + thp_y[ti] * (BAND_BOTTOM - BAND_TOP)
		_chev[0] = Vector2(px - 14.0, py + 12.0)
		_chev[1] = Vector2(px, py - 6.0)
		_chev[2] = Vector2(px + 14.0, py + 12.0)
		draw_polyline(_chev, Color(1.0, 0.95, 0.7, 0.75), 4.0)

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

func _draw_coin(x: float, y: float, ph: float) -> void:
	var sq := 0.35 + 0.65 * absf(cos(_t * 3.0 + ph))
	draw_set_transform(Vector2(x, y), 0.0, Vector2(sq, 1.0))
	var pulse := 0.5 + 0.5 * sin(_t * 4.0 + ph)
	draw_arc(Vector2.ZERO, 34.0 + 3.0 * pulse, 0.0, TAU, 20, Color(1.0, 0.95, 0.5, 0.4), 3.0)
	draw_set_transform(Vector2(x, y), 0.0, Vector2(sq * 27.0, 27.0))
	draw_colored_polygon(Ui.star_unit(), Color(1.0, 0.82, 0.15))
	draw_polyline(Ui.star_closed(), FX_BLACK, 3.0 / 27.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_bird(phase: float, body: Color, wing: Color, head: Color, w: float) -> void:
	var q := int(floor(_t * 7.0 + phase * 0.64)) & 3
	var frame := 0 if q == 0 else (2 if q == 2 else 1)
	_fill(_bird_tail, wing, w)
	_fill(_bird_body, body, w)
	_fill(_bird_wings[frame], wing, w)
	_fill(_bird_head, head, w)
	_fill(_bird_beak, Color(1.0, 0.8, 0.2), w * 0.8)
	draw_circle(Vector2(22, -8), 3.2, Color.WHITE)
	draw_circle(Vector2(23, -8), 1.6, FX_BLACK)

func _draw_hazard(k: int, x: float, y: float, dir: float, s: float, phase: float) -> void:
	draw_set_transform(Vector2(x, y), 0.0, Vector2(dir * s, s))
	var w := 4.0 / s
	match k:
		BIRD:
			if region == 2:   # Sahara: a vulture
				_draw_bird(phase, Color(0.62, 0.5, 0.34), Color(0.4, 0.3, 0.2), Color(0.85, 0.55, 0.5), w)
			else:
				_draw_bird(phase, C_BIRD, C_BIRD_WING, C_BIRD, w)
		EAGLE:
			draw_set_transform(Vector2(x, y), 0.0, Vector2(dir * s * 1.3, s * 1.3))
			_draw_bird(phase, Color(0.5, 0.34, 0.18), Color(0.34, 0.22, 0.12), Color(0.96, 0.94, 0.9), 4.0 / (s * 1.3))
		CABLE:
			_fill(_cable_roof, Color(0.3, 0.32, 0.38), w)
			_fill(_cable_body, Color(0.9, 0.25, 0.25), w)
			for wx in [-24.0, -6.0, 12.0]:
				draw_rect(Rect2(wx, -8.0, 14.0, 14.0), Color(0.75, 0.92, 1.0))
				draw_rect(Rect2(wx, -8.0, 14.0, 14.0), FX_BLACK, false, w * 0.6)
			draw_line(Vector2(0, -24), Vector2(0, -44), FX_BLACK, w)
			draw_circle(Vector2(0, -44), 6.0, Color(0.6, 0.62, 0.68))
		CARPET:
			_fill(_carpet, Color(0.75, 0.15, 0.35), w)
			draw_line(Vector2(-46, 0), Vector2(46, 0), Color(1.0, 0.82, 0.2), w * 0.7)
			for fy in [-3.0, 3.0]:
				draw_line(Vector2(-52, fy), Vector2(-62, fy), FX_BLACK, w * 0.6)
				draw_line(Vector2(52, fy), Vector2(62, fy), FX_BLACK, w * 0.6)
			draw_rect(Rect2(-8.0, -17.0, 16.0, 12.0), Color(0.2, 0.5, 0.8))
			draw_rect(Rect2(-8.0, -17.0, 16.0, 12.0), FX_BLACK, false, w * 0.7)
			draw_circle(Vector2(0, -23), 7.0, Color(0.95, 0.75, 0.55))
			draw_circle(Vector2(0, -27), 6.0, Color(0.95, 0.95, 0.9))
		GLIDER:
			draw_line(Vector2(-30, -8), Vector2(0, 24), FX_BLACK, w * 0.7)
			draw_line(Vector2(30, -8), Vector2(0, 24), FX_BLACK, w * 0.7)
			_fill(_glider_canopy, Color(0.95, 0.5, 0.15), w)
			_fill(_glider_panel, Color(1.0, 0.95, 0.8), w * 0.7)
			draw_rect(Rect2(-5.0, 28.0, 10.0, 16.0), Color(0.2, 0.4, 0.75))
			draw_rect(Rect2(-5.0, 28.0, 10.0, 16.0), FX_BLACK, false, w * 0.7)
			draw_circle(Vector2(0, 22), 7.0, Color(0.95, 0.75, 0.55))
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
