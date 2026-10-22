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
const ITEM_MIN_X := 110.0        # pickups stay on the screen
const HAZ_MAX_SPEED := 260.0     # hazards never outrun this (px/s), so every gap stays passable
const GOAL_Y := 310.0            # the balloon's centre above this line clears the level
const MARGIN := 160.0            # hazards live on a ring this far past each screen edge
const RING := W + 2.0 * MARGIN
const MAX_LANES := 9
## Hard caps (performance): hazards per layer, wind particles / chevrons / streamers per layer, sparks.
const MAX_PER_LANE := 4
const MAX_HAZ := MAX_LANES * MAX_PER_LANE
const PARTS_PER_LANE := 8
const CLOUDS_PER_LANE := 3     # drifting clouds per layer (they move at exactly the layer's wind)
const BIRDS_PER_LANE := 2      # tiny faint far-off birds per layer (ditto)
const FX_MAX := 24
const RING_MAX := 8            # pooled expanding rings (pickups, handoffs, landings)
const MAX_COINS := MAX_LANES
const MAX_STARS := 5
## Precision Landing: the airship's deck (its top surface) and hull, and the range it drifts over.
const SHIP_DECK_Y := 380.0
const SHIP_HULL_H := 56.0
const SHIP_MIN_X := 270.0
const SHIP_MAX_X := 810.0
const CEILING_Y := 100.0       # how high a balloon may fly (above the goal strip)
const MAX_THERMALS := 3
const THERMAL_PARTS := 10

enum { BIRD, KITE, BALLOON, DRONE, EAGLE, CABLE, CARPET, GLIDER, GOOSE }
const KIND_NAME := ["a bird", "a kite", "another balloon", "a drone", "an eagle", "a cable car", "a flying carpet", "a paraglider", "a flock of geese"]
## Hit ellipse half sizes, speed relative to the wind of the layer, how much of the free layer height the
## hazard bobs through, and bob rate.
const KIND_HX := [62.0, 44.0, 54.0, 100.0, 100.0, 56.0, 100.0, 100.0, 75.0]
const KIND_HY := [42.0, 58.0, 70.0, 36.0, 36.0, 46.0, 32.0, 68.0, 58.0]
const KIND_SPEED := [1.55, 0.75, 0.45, 2.1, 1.8, 0.6, 1.3, 0.9, 1.25]
const KIND_BOB := [0.35, 1.0, 0.5, 0.6, 0.3, 0.0, 0.8, 0.7, 0.5]
const KIND_RATE := [2.2, 1.5, 0.8, 2.6, 2.0, 1.0, 1.8, 1.0, 1.1]

const C_TANK := Color(0.25, 0.85, 0.4)
const FX_BLACK := Color(0, 0, 0, 1)

# ---- Level state ----
var n_lanes := 5
var lane_h := 0.0
var lane_wind := PackedFloat32Array()    # px/s right now, sign = direction: constant, except in a reversing layer
var lane_base := PackedFloat32Array()    # the layer's steady wind (a reversing layer swings between +- this)
var lane_gph := PackedFloat32Array()     # kite beat phase
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
var _gap_used := PackedInt32Array()     # bit mask per layer: the gaps that already hold an item
var _items := PackedInt32Array()        # items (tank / coin / star) already placed in each layer
var _base_x := PackedFloat32Array()     # where items go in a layer with no hazards
# --- this leg's recipe: goal and twists ---
var recipe: LegRecipe
var goal := Flights.CLIMB
var lane_beat := PackedFloat32Array()   # kite layers: beat period (s), 0 = none
var lane_rev := PackedFloat32Array()    # reversing layers: seconds between flips, 0 = steady
var lane_rev_off := PackedFloat32Array()
var _forced := PackedInt32Array()       # hazard kind forced onto a layer by the recipe (-1 = free)
# Star Collect
var gs_x := PackedFloat32Array()
var gs_y := PackedFloat32Array()
var gs_lane := PackedInt32Array()
var gs_on := PackedByteArray()
var gs_count := 0
# Delivery: two mooring platforms (0 = pick up, 1 = drop off); mail_state 0 = to collect, 1 = carrying, 2 = delivered
var dl_x := PackedFloat32Array([0.0, 0.0])
var dl_lane := PackedInt32Array([0, 0])
var mail_state := 0
# Rising Storm
var storm_on := false
var storm_y := 0.0
var storm_speed := 0.0
var storm_go := false                   # Main sets this once the leg has started
# Precision Landing
var ship_on := false
var ship_x := 540.0
var ship_dir := 1.0
# Lightning
var lt_on := false
var lt_clock := 0.0
var lt_cols := PackedFloat32Array([0.0, 0.0, 0.0])
var lt_state := 0                       # 0 idle, 1 warning, 2 striking
var lt_x := 0.0
var lt_flash := 0.0
var fx_x := PackedFloat32Array()
var fx_y := PackedFloat32Array()
var fx_vx := PackedFloat32Array()
var fx_vy := PackedFloat32Array()
var fx_life := PackedFloat32Array()
var fx_col := PackedColorArray()
var rg_x := PackedFloat32Array()
var rg_y := PackedFloat32Array()
var rg_age := PackedFloat32Array()       # seconds since it started; <0 = free
var rg_life := PackedFloat32Array()
var rg_max := PackedFloat32Array()       # final radius
var rg_col := PackedColorArray()
var _rg_next := 0
var th_x := PackedFloat32Array()         # thermals (Sahara): columns of updraft
var th_dx := PackedFloat32Array()
var th_count := 0
var region := 0
var haze_on := false
var thin_air := false
var jet := false
var focus_lane := 0                      # the layer the balloon is in (sand haze clears around it)
var _fx_next := 0
var last_hit_kind := 0
var level := 1.0
var daylight := 0.5                      # 0 dawn .. 0.5 day .. 1 dusk: the Flight's progress, tints the sky (set before setup())
var rng := RandomNumberGenerator.new()
var preview_balloon: Balloon     # set while the drift preview is on: LaneRender draws its predicted path and the hazards' ghosts
var showcase := false            # pre-warm: every shape on screen at once
## ?perf / tests/perf_profile.gd: microseconds spent per frame in each part of the Lanes work, summed over frames.
static var prof_on := false
static var prof_us := PackedFloat32Array([0, 0, 0])
const PROF_NAMES := ["Lanes.update (simulation)", "LaneRender.update (buffers, uniforms)", "setup + backdrop redraw"]
var render: LaneRender
var _t := 0.0

# ---- Pre-built shapes: [polygon, closed outline] ----

func _ready() -> void:
	rng.randomize()
	lane_wind.resize(MAX_LANES)
	lane_base.resize(MAX_LANES)
	lane_gph.resize(MAX_LANES)
	th_x.resize(MAX_THERMALS)
	th_dx.resize(MAX_THERMALS)
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
	_items.resize(MAX_LANES)
	_gap_used.resize(MAX_LANES)
	_base_x.resize(MAX_LANES)
	lane_beat.resize(MAX_LANES)
	lane_rev.resize(MAX_LANES)
	lane_rev_off.resize(MAX_LANES)
	_forced.resize(MAX_LANES)
	gs_x.resize(MAX_STARS)
	gs_y.resize(MAX_STARS)
	gs_lane.resize(MAX_STARS)
	gs_on.resize(MAX_STARS)
	fx_x.resize(FX_MAX)
	fx_y.resize(FX_MAX)
	fx_vx.resize(FX_MAX)
	fx_vy.resize(FX_MAX)
	fx_life.resize(FX_MAX)
	fx_col.resize(FX_MAX)
	rg_x.resize(RING_MAX)
	rg_y.resize(RING_MAX)
	rg_age.resize(RING_MAX)
	rg_age.fill(-1.0)
	rg_life.resize(RING_MAX)
	rg_max.resize(RING_MAX)
	rg_col.resize(RING_MAX)
	render = LaneRender.new()
	render.lanes = self
	add_child(render)
	setup(1.0)

static func _pair(pts: Array) -> Array:
	var poly := PackedVector2Array(pts)
	var closed := poly.duplicate()
	closed.append(poly[0])
	return [poly, closed]

## The time-of-day wash for this leg: rgb = the colour, a = the strength at the horizon (0 at midday). Baked into the colours the
## backdrop, the ridges and the scenery are drawn with (they are drawn once per leg), so it costs nothing per frame.
func day_tint() -> Color:
	var k := 0.55 if region == 2 else 1.0
	if daylight < 0.5:
		return Color(1.0, 0.62, 0.42, lerpf(0.26, 0.0, daylight * 2.0) * k)
	return Color(0.62, 0.36, 0.74, lerpf(0.0, 0.26, (daylight - 0.5) * 2.0) * k)

## `c` washed by the day tint at height y (stronger toward the horizon).
func tinted(c: Color, y: float) -> Color:
	var t := day_tint()
	var a := t.a * lerpf(0.45, 1.0, clampf(y / H, 0.0, 1.0))
	return Color(lerpf(c.r, t.r, a), lerpf(c.g, t.g, a), lerpf(c.b, t.b, a), c.a)

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
func setup(lv: float, show: bool = false, seed_val: int = -1, reg: int = 0, rec: LegRecipe = null) -> void:
	if seed_val >= 0:
		rng.seed = seed_val
	recipe = rec
	goal = rec.goal if rec != null else Flights.CLIMB
	level = lv
	showcase = show
	region = 2 if show else clampi(reg, 0, Regions.COUNT - 1)
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
	# The recipe's twists pick their layers first: geese and kite-beat layers, reversing layers.
	_forced.fill(-1)
	lane_beat.fill(0.0)
	lane_rev.fill(0.0)
	_items.fill(0)
	_gap_used.fill(0)
	for i in MAX_LANES:
		_base_x[i] = rng.randf_range(100.0, W - 100.0)
	if rec != null and not show:
		var pool: Array = []
		for i in range(1, n_lanes - 1):
			pool.append(i)
		for a in range(pool.size() - 1, 0, -1):
			var b := rng.randi() % (a + 1)
			var tmp: int = pool[a]
			pool[a] = pool[b]
			pool[b] = tmp
		if rec.geese and not pool.is_empty():
			_forced[pool.pop_back()] = GOOSE
		if rec.kite_beat and not pool.is_empty():
			_forced[pool.pop_back()] = KITE
		if rec.reverse:
			var rl := 1 + rng.randi() % maxi(n_lanes - 2, 1)
			lane_rev[rl] = Tuning.reverse_period
			lane_rev_off[rl] = rng.randf() * Tuning.reverse_period
			if n_lanes >= 8:   # a second one, out of step with the first
				var rl2 := 1 + rng.randi() % maxi(n_lanes - 2, 1)
				if rl2 != rl:
					lane_rev[rl2] = Tuning.reverse_period * 1.25
					lane_rev_off[rl2] = rng.randf() * Tuning.reverse_period
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
		if region == 1:   # Alps: strong, but steady
			mag = minf(mag * Tuning.alps_wind_mult, Tuning.wind_max)
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
			hazardous = true
		if _forced[i] >= 0:
			hazardous = true
		if hazardous and not show and not jet_lane and _forced[i] < 0 and rng.randf() < empty_chance and (any_hazard or i < n_lanes - 2):
			hazardous = false
		if not hazardous:
			continue
		any_hazard = true
		var k := i % 9 if show else GLIDER
		if not show and not jet_lane:
			var idx_k := rng.randi() % kinds_open
			k = klist[idx_k]
			if k == prev_kind and kinds_open > 1:
				k = klist[(idx_k + 1 + rng.randi() % (kinds_open - 1)) % kinds_open]
		if _forced[i] >= 0:
			k = _forced[i]
		prev_kind = k
		lane_kind[i] = k
		var sc := Tuning.hazard_scale * clampf(lane_h / 230.0, 0.7, 1.15)
		lane_scale[i] = sc
		lane_vel[i] = _haz_vel(lane_wind[i], k)
		lane_amp[i] = maxf(lane_h * 0.5 - float(KIND_HY[k]) * sc - 6.0, 0.0) * KIND_BOB[k]
		# As many hazards as asked for, but never more than leave every gap passable.
		var hw := 2.0 * float(KIND_HX[k]) * sc
		var fit := int(floor(RING / (hw + min_gap)))
		var want := roundi(density_for(lv) + rng.randf_range(-0.5, 0.5))
		var cnt := clampi(want, 1, mini(fit, 1 if jet_lane else 2))   # (at most two big hazards per layer, one in the fast jet stream)
		var spacing := RING / float(cnt)
		var free := maxf(spacing - hw - min_gap, 0.0)
		var start := rng.randf() * RING
		for j in cnt:
			var idx := i * MAX_PER_LANE + j
			hz_x[idx] = -MARGIN + fposmod(start + float(j) * spacing + rng.randf_range(-0.5, 0.5) * free, RING)
			hz_phase[idx] = rng.randf() * TAU
		lane_count[i] = cnt
		if rec != null and rec.kite_beat and k == KITE:
			lane_beat[i] = Tuning.kite_beat_period
	# Pickups: some layers carry propane, floating in the middle of their widest gap.
	pk_count = 0
	for i in MAX_COINS:
		cn_on[i] = 0
	for i in range(1, n_lanes):
		if not show and rng.randf() >= Tuning.propane_chance:
			continue
		pk_on[i] = 1
		pk_count += 1
		pk_x[i] = _slot_x(i)
		pk_y[i] = _lane_cy(i)
	# Coins: coins_per_leg of them, preferably in layers with no other item (shuffled order, seeded).
	var n_cand := n_lanes - 1
	_shuffle_lanes(n_cand)
	var want_coins := mini(int(Tuning.coins_per_leg), n_cand)
	var placed := 0
	for pass_i in 2:
		for k in n_cand:
			if placed >= want_coins:
				break
			var i2 := _order[k]
			if cn_on[i2] == 1 or (pass_i == 0 and _items[i2] > 0):
				continue
			cn_x[i2] = _slot_x(i2)
			cn_y[i2] = _lane_cy(i2)
			cn_on[i2] = 1
			placed += 1
	# Goal objects.
	gs_count = 0
	for st in MAX_STARS:
		gs_on[st] = 0
	mail_state = 0
	storm_on = false
	storm_go = false
	ship_on = false
	lt_on = false
	lt_state = 0
	lt_flash = 0.0
	match goal:
		Flights.STARS:   # Star Collect: every star must be collected before the top counts
			_shuffle_lanes(n_cand)
			var want_stars := mini(mini(int(Tuning.stars_per_leg), MAX_STARS), n_cand)
			for pass_i in 2:
				for k in n_cand:
					if gs_count >= want_stars:
						break
					var i3 := _order[k]
					if pass_i == 0 and _items[i3] > 0:
						continue
					if pass_i == 1 and _items[i3] >= 2:
						continue
					var already := false
					for q in gs_count:
						already = already or gs_lane[q] == i3
					if already:
						continue
					lane_count[i3] = mini(lane_count[i3], 1)   # a layer that holds a star carries at most one (big) hazard: the star can always be reached
					gs_lane[gs_count] = i3
					gs_x[gs_count] = _slot_x(i3)
					gs_y[gs_count] = _lane_cy(i3)
					gs_on[gs_count] = 1
					gs_count += 1
		Flights.DELIVERY:   # pick the mail up at a mooring platform low down, drop it at one higher up
			dl_lane[0] = 1 + rng.randi() % maxi(n_lanes - 3, 1)
			dl_lane[1] = dl_lane[0] + 1 + rng.randi() % maxi(n_lanes - 2 - dl_lane[0], 1)
			dl_x[0] = rng.randf_range(200.0, 880.0)
			dl_x[1] = rng.randf_range(200.0, 880.0)
			if absf(dl_x[1] - dl_x[0]) < 260.0:
				dl_x[1] = fposmod(dl_x[0] + 380.0 - 100.0, W - 400.0) + 200.0
		Flights.STORM:   # a storm rising from below the ground
			storm_on = true
			storm_y = GROUND_Y + 160.0
			storm_speed = rec.storm_speed if rec != null else Tuning.storm_speed
		Flights.LANDING:   # an airship drifting over the top
			ship_on = true
			ship_x = rng.randf_range(SHIP_MIN_X + 60.0, SHIP_MAX_X - 60.0)
			ship_dir = 1.0 if rng.randf() < 0.5 else -1.0
	if show:   # the pre-warm shows every goal object and twist at once
		goal = Flights.DELIVERY
		dl_lane[0] = 2
		dl_lane[1] = 5
		dl_x[0] = 300.0
		dl_x[1] = 760.0
		gs_count = MAX_STARS
		for q in MAX_STARS:
			gs_lane[q] = 1 + q
			gs_x[q] = 150.0 + float(q) * 190.0
			gs_y[q] = _lane_cy(1 + q)
			gs_on[q] = 1
		ship_on = true
		ship_x = 540.0
		storm_on = true
		storm_y = 1500.0
		lane_rev[3] = Tuning.reverse_period
		lane_beat[2] = Tuning.kite_beat_period
		lt_on = true
		lt_clock = 2.0
		for q in 3:
			lt_cols[q] = W * (0.2 + 0.3 * float(q))
	if rec != null and rec.lightning:   # periodic lightning: three columns in a repeating order, the first warning after 3 s
		lt_on = true
		lt_clock = -3.0
		var cols := [W * 0.2, W * 0.5, W * 0.8]
		for a2 in range(2, 0, -1):
			var b2 := rng.randi() % (a2 + 1)
			var tmp2: float = cols[a2]
			cols[a2] = cols[b2]
			cols[b2] = tmp2
		for q in 3:
			lt_cols[q] = cols[q]
	# Thermals: columns of updraft (Sahara; more of them at higher difficulty).
	th_count = 0
	if show or Regions.THERMALS[region]:
		th_count = MAX_THERMALS if show else clampi(2 + int((lv - float(Flights.REGION_BASE[region])) / 3.0), 2, MAX_THERMALS)
		for t in th_count:
			th_x[t] = rng.randf_range(160.0, W - 160.0)
			th_dx[t] = rng.randf_range(-30.0, 30.0)
	clear_fx()
	var t_setup := Time.get_ticks_usec() if prof_on else 0
	render.on_setup()
	if prof_on:
		prof_us[2] += float(Time.get_ticks_usec() - t_setup)
	update(0.0)

## Shuffle the layers 1..n into _order (seeded).
func _shuffle_lanes(n_cand: int) -> void:
	for k in n_cand:
		_order[k] = k + 1
	for k in range(n_cand - 1, 0, -1):
		var r := rng.randi() % (k + 1)
		var tmp := _order[k]
		_order[k] = _order[r]
		_order[r] = tmp

## Where the next item (tank, coin, star) goes in layer i: in a gap between hazards, never on top of another item.
func _slot_x(i: int) -> float:
	var k := _items[i]
	_items[i] = k + 1
	var c := lane_count[i]
	var x := 0.0
	if c == 0:   # (spread over the screen's width, so two items never pile up at its edge)
		return ITEM_MIN_X + fposmod(_base_x[i] - ITEM_MIN_X + 300.0 * float(k), W - 2.0 * ITEM_MIN_X)
	elif k < c:
		# the first free gap whose middle is on the screen (items hang still, so they must be where the balloon can go)
		var pick := -1
		var fallback := -1   # a free gap that is off the screen
		for jj in c:
			var gj := (k + jj) % c
			if (_gap_used[i] >> gj) & 1 == 1:
				continue
			var gx := -MARGIN + fposmod(_gap_center(i, gj) + MARGIN, RING)
			if gx >= ITEM_MIN_X and gx <= W - ITEM_MIN_X:
				pick = gj
				break
			if fallback < 0:
				fallback = gj
		if pick < 0:
			pick = fallback if fallback >= 0 else k
		_gap_used[i] |= 1 << pick
		x = _gap_center(i, pick)
	else:
		x = _gap_center(i, 0) + 260.0 * float(k - c + 1)
	x = -MARGIN + fposmod(x + MARGIN, RING)
	return clampf(x, ITEM_MIN_X, W - ITEM_MIN_X)

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

## A hazard kind's speed in a layer with this wind.
func _haz_vel(w: float, k: int) -> float:
	return clampf(w * float(KIND_SPEED[k]), -HAZ_MAX_SPEED, HAZ_MAX_SPEED)

## Where hazard j of layer i will be in `t` seconds (it keeps its speed; the bob is ignored): for the drift preview.
func hazard_x_in(i: int, j: int, t: float) -> float:
	var x := hz_x[i * MAX_PER_LANE + j] + lane_vel[i] * t
	return -MARGIN + fposmod(x + MARGIN, RING)

func _lane_cy(i: int) -> float:
	return BAND_BOTTOM - (float(i) + 0.5) * lane_h

## The layer a height is in (0 = bottom).
func lane_of(y: float) -> int:
	return clampi(int((BAND_BOTTOM - y) / lane_h), 0, n_lanes - 1)

func wind_at(y: float) -> float:
	return lane_wind[lane_of(y)]

## The wind at exactly height y for DISPLAY (the streamers, the lean): the layer's wind, blended with the next layer's across
## the last pixels before a boundary so the cue changes smoothly as the balloon climbs through (the physics uses wind_at).
func wind_smooth(y: float) -> float:
	var i := lane_of(y)
	var top := BAND_BOTTOM - float(i + 1) * lane_h
	var d_top := y - top                 # distance below this layer's upper edge
	var d_bot := top + lane_h - y        # distance above its lower edge
	const BLEND := 40.0
	if d_top < BLEND and i + 1 < n_lanes:
		return lerpf(lane_wind[i], lane_wind[i + 1], smoothstep(BLEND, 0.0, d_top) * 0.5)
	if d_bot < BLEND and i > 0:
		return lerpf(lane_wind[i], lane_wind[i - 1], smoothstep(BLEND, 0.0, d_bot) * 0.5)
	return lane_wind[i]

# ---------------------------------------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------------------------------------

func update(dt: float) -> void:
	var t_prof := Time.get_ticks_usec() if prof_on else 0
	_t += dt
	for i in n_lanes:
		var k0 := lane_kind[i]
		if lane_rev[i] > 0.0:   # the layer's wind flips on a timer (the countdown is on screen)
			var w := lane_base[i] * clampf(3.0 * sin(PI * (_t + lane_rev_off[i]) / lane_rev[i]), -1.0, 1.0)
			lane_wind[i] = w
			lane_vel[i] = _haz_vel(w, k0) if k0 >= 0 else w
		var k := lane_kind[i]
		for j in lane_count[i]:
			var idx3 := i * MAX_PER_LANE + j
			var x3 := hz_x[idx3] + lane_vel[i] * dt
			if x3 >= W + MARGIN:
				x3 -= RING
			elif x3 < -MARGIN:
				x3 += RING
			hz_x[idx3] = x3
			if lane_beat[i] > 0.0:   # kites that dip together on a beat: up, up, up, DIP
				hz_y[idx3] = _lane_cy(i) - lane_amp[i] * 0.45 + lane_amp[i] * 0.9 * Tuning.kite_dip * _dip(fposmod(_t / lane_beat[i] + lane_gph[i] / TAU, 1.0))
			else:
				hz_y[idx3] = _lane_cy(i) + sin(_t * float(KIND_RATE[k]) + hz_phase[idx3]) * lane_amp[i]
		if pk_on[i] == 1 or showcase:   # pickups hang still in the air (they only bob): the balloon sweeps past them
			pk_y[i] = _lane_cy(i) + sin(_t * 2.0 + float(i)) * minf(lane_h * 0.18, 24.0)
	for i in n_lanes:
		if cn_on[i] == 1 or showcase:
			cn_y[i] = _lane_cy(i) + sin(_t * 2.3 + float(i) * 1.7) * minf(lane_h * 0.18, 24.0)
	for q in gs_count:
		if gs_on[q] == 1 or showcase:
			gs_y[q] = _lane_cy(gs_lane[q]) + sin(_t * 2.1 + float(q) * 1.3) * minf(lane_h * 0.18, 24.0)
	if ship_on:   # the airship drifts to and fro over the top
		ship_x += ship_dir * Tuning.airship_speed * dt
		if ship_x > SHIP_MAX_X:
			ship_x = SHIP_MAX_X
			ship_dir = -1.0
		elif ship_x < SHIP_MIN_X:
			ship_x = SHIP_MIN_X
			ship_dir = 1.0
	if storm_on and storm_go:
		storm_y -= storm_speed * dt
	if lt_on:
		lt_clock += dt
		lt_flash = maxf(lt_flash - dt, 0.0)
		var phase := fposmod(lt_clock, Tuning.lightning_period)
		var cycle := int(floor(lt_clock / Tuning.lightning_period)) if lt_clock >= 0.0 else 0
		var st := 0
		if lt_clock >= 0.0:
			if phase >= Tuning.lightning_period - Tuning.lightning_strike:
				st = 2
			elif phase >= Tuning.lightning_period - Tuning.lightning_strike - Tuning.lightning_warning:
				st = 1
		if st == 1 and lt_state == 0:
			lt_flash = 0.18   # the warning flash
		lt_state = st
		lt_x = lt_cols[cycle % 3]
	for t in th_count:
		var tx := th_x[t] + th_dx[t] * dt
		if tx > W - 120.0 or tx < 120.0:
			th_dx[t] = -th_dx[t]
		th_x[t] = clampf(tx, 120.0, W - 120.0)
	for f in FX_MAX:
		if fx_life[f] > 0.0:
			fx_life[f] -= dt
			fx_x[f] += fx_vx[f] * dt
			fx_y[f] += fx_vy[f] * dt
			fx_vy[f] += 600.0 * dt
	for r in RING_MAX:
		if rg_age[r] >= 0.0:
			rg_age[r] += dt
			if rg_age[r] >= rg_life[r]:
				rg_age[r] = -1.0
	if prof_on:
		prof_us[0] += float(Time.get_ticks_usec() - t_prof)
	render.update(dt)

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
			if p.distance_to(Vector2(pk_x[i], pk_y[i])) < balloon.hit_radius(c) + 46.0:
				pk_on[i] = 0
				got += 1
				burst(Vector2(pk_x[i], pk_y[i]), C_TANK, 14, 320.0)
				ring(Vector2(pk_x[i], pk_y[i]), C_TANK, 110.0, 0.5)
				break
	return got

## Collect any floating coin the balloon touches; returns how many.
func collect_coins(balloon: Balloon) -> int:
	var got := 0
	for i in n_lanes:
		if cn_on[i] == 0:
			continue
		for c in 3:
			if balloon.hit_pos(c).distance_to(Vector2(cn_x[i], cn_y[i])) < balloon.hit_radius(c) + 46.0:
				cn_on[i] = 0
				got += 1
				burst(Vector2(cn_x[i], cn_y[i]), Color(1.0, 0.85, 0.2), 12, 300.0)
				ring(Vector2(cn_x[i], cn_y[i]), Color(1.0, 0.85, 0.2), 70.0, 0.35)
				break
	return got

func coins_left() -> int:
	var n := 0
	for i in n_lanes:
		n += cn_on[i]
	return n

## The kites' dip: 0 at rest, up to 1 at the bottom of the dip (a quick drop, a slower return).
func _dip(u: float) -> float:
	if u < 0.62:
		return 0.0
	if u < 0.74:
		return (u - 0.62) / 0.12
	if u < 0.82:
		return 1.0
	return 1.0 - (u - 0.82) / 0.18

## Seconds until layer i flips its wind (0 if it never does): the visible timer.
func rev_timer(i: int) -> float:
	if lane_rev[i] <= 0.0:
		return 0.0
	return lane_rev[i] - fposmod(_t + lane_rev_off[i], lane_rev[i])

# ---- goals ----

func stars_left() -> int:
	var n := 0
	for q in gs_count:
		n += gs_on[q]
	return n

## Collect the Star Collect stars the balloon touches; returns how many.
func collect_stars(balloon: Balloon) -> int:
	var got := 0
	for q in gs_count:
		if gs_on[q] == 0:
			continue
		for c in 3:
			if balloon.hit_pos(c).distance_to(Vector2(gs_x[q], gs_y[q])) < balloon.hit_radius(c) + 48.0:
				gs_on[q] = 0
				got += 1
				burst(Vector2(gs_x[q], gs_y[q]), Color(0.6, 0.95, 1.0), 14, 320.0)
				ring(Vector2(gs_x[q], gs_y[q]), Color(0.6, 0.95, 1.0), 130.0, 0.55)
				ring(Vector2(gs_x[q], gs_y[q]), Color(1, 1, 1), 80.0, 0.35)
				break
	return got

## Where a mooring platform is (0 = pick up, 1 = drop off).
func dock_pos(which: int) -> Vector2:
	return Vector2(dl_x[which], _lane_cy(dl_lane[which]))

## Is the balloon at mooring platform `which`?
func at_dock(balloon: Balloon, which: int) -> bool:
	var d := balloon.position - dock_pos(which)
	return absf(d.x) < Tuning.dock_half_w and absf(d.y) < Tuning.dock_half_h

## Where the active mooring target is (the platform to go to next), or Vector2(-1, -1) when the mail is delivered.
func dock_target() -> Vector2:
	if mail_state >= 2:
		return Vector2(-1.0, -1.0)
	return dock_pos(mail_state)

## The storm covers everything below storm_y: caught when the balloon's basket is in it.
func storm_hits(balloon: Balloon) -> bool:
	return storm_on and balloon.position.y + Balloon.BASKET_BOTTOM * balloon.s() * 0.8 > storm_y

## Lightning striking right now on the balloon's column?
func lightning_hits(balloon: Balloon) -> bool:
	return lt_on and lt_state == 2 and absf(balloon.position.x - lt_x) < Tuning.lightning_width * 0.5 + 20.0

## Airship and balloon. Returns 0 nothing, 1 landed, 2 hard landing. The hull is solid from below and from the side
## (the balloon is pushed back under / beside it); only the deck, from above and slowly, counts as a landing.
func ship_contact(balloon: Balloon) -> int:
	if not ship_on:
		return 0
	var s := balloon.s()
	var half := Tuning.airship_deck_half
	var dx := balloon.position.x - ship_x
	if absf(dx) > half + 28.0 * s:
		return 0
	var hull_bottom := SHIP_DECK_Y + SHIP_HULL_H
	var basket_y := balloon.position.y + Balloon.BASKET_BOTTOM * s
	var top_y := balloon.position.y - 56.0 * s
	if top_y < hull_bottom and balloon.position.y > SHIP_DECK_Y:
		# below / inside the hull: pushed back out underneath it
		balloon.position.y = hull_bottom + 56.0 * s
		balloon.rise = minf(balloon.rise, 0.0)
		return 0
	if basket_y >= SHIP_DECK_Y and balloon.position.y <= SHIP_DECK_Y and absf(dx) <= half:
		return 1 if balloon.descent_speed() <= Tuning.land_speed else 2
	return 0

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

## A pooled ring that swells to `radius` and fades over `life` seconds.
func ring(p: Vector2, color: Color, radius: float, life: float) -> void:
	var r := _rg_next
	_rg_next = (_rg_next + 1) % RING_MAX
	rg_x[r] = p.x
	rg_y[r] = p.y
	rg_age[r] = 0.0
	rg_life[r] = life
	rg_max[r] = radius
	rg_col[r] = color

func clear_fx() -> void:
	for f in FX_MAX:
		fx_life[f] = 0.0
	rg_age.fill(-1.0)
