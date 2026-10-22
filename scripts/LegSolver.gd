class_name LegSolver
extends RefCounted
## The fairness planner, as a reusable, time-sliceable solver: is there ANY sequence of burner inputs that finishes a generated
## leg without touching anything, keeping `margin` px of clearance from every hazard? It searches the real layout (hazard
## positions, winds incl. reversals, kite beat, lightning, storm, airship) forward on a time grid of `dt` seconds with the real
## burner physics. tests/fairness_sim.gd runs it offline over every Flight; the game runs a coarser, early-exiting setting on
## every leg it generates (LegPlanner), a few milliseconds at a time. "No path" means none was found within `cap` states per step.

const BUCKET_X := 12.0
const BUCKET_Y := 14.0
enum { RUNNING, SOLVABLE, NO_PATH }

var dt := 0.1
var margin := 18.0
var cap := 600
var tmax_s := 45.0
var tank := -1.0           # the propane the leg starts with (-1: Tuning.propane_start)
var extra_s := 6.0         # keep searching this long after the first success, for a cheaper path (ignored when `early`)
var only_star := -1
var early := false         # stop at the first success
var sub := 3               # physics sub-steps per time step
var lanes: Lanes
var bal: Balloon
var recipe
var K := 0
var result_time := -1.0
var result_fuel := 0.0
var status := RUNNING
var rng := RandomNumberGenerator.new()
# per lane, per step
var _lane_w := PackedFloat32Array()   # [lane * (K+1) + step]: the wind
var _hz_px := PackedFloat32Array()    # [(lane * MAX_PER_LANE + j) * (K+1) + step]: hazard x
var _hz_py := PackedFloat32Array()    # ...and y
var _ship_xs := PackedFloat32Array()
var _lt_on_k := PackedByteArray()
var _lt_x_k := PackedFloat32Array()
var _storm_k := PackedFloat32Array()
# search state
var _cur := {}
var _nxt := {}
var _states: Array = []
var _si := 0
var _k := 0
var _tank0 := 0.0
var _best_fuel_used := 1.0e9
var _t_ok := -1.0
var _goal := 0
var _blocked_top := false
var _n_stars := 0
var _want_mask := 0
var _ceil_base := 0.0
var _fy := 0.0
var _half := 0.0
var _sdt := 0.0

## Prepare a search of the leg currently set up in `lanes` (with `bal` as the balloon whose physics and size to use).
func begin(l: Lanes, b: Balloon, rec) -> void:
	lanes = l
	bal = b
	recipe = rec
	rng.seed = 12345
	status = RUNNING
	result_time = -1.0
	result_fuel = 0.0
	_prepare(tmax_s)
	var s: float = bal.s()
	_half = Balloon.WIDTH * 0.5 * s
	_fy = bal.floor_y()
	_goal = recipe.goal
	_blocked_top = _goal == Flights.STARS or _goal == Flights.DELIVERY
	_n_stars = lanes.gs_count
	_want_mask = (1 << _n_stars) - 1 if only_star < 0 else (1 << only_star)
	_tank0 = tank if tank > 0.0 else Tuning.propane_start
	var start := [Lanes.W * 0.5, _fy, _tank0, 0.0, 0.0, 0]
	_cur = {}
	_cur[_key(start)] = start
	_nxt = {}
	_states = []
	_si = 0
	_k = 0
	_best_fuel_used = 1.0e9
	_t_ok = -1.0
	_ceil_base = Lanes.GOAL_Y + 14.0 if _blocked_top else (Lanes.CEILING_Y if _goal == Flights.LANDING else -1.0e5)
	_sdt = dt / float(sub)
	_next_step()

## Run for at most `budget_us` microseconds; returns RUNNING, SOLVABLE or NO_PATH.
func run(budget_us: int) -> int:
	var t0 := Time.get_ticks_usec()
	while status == RUNNING:
		if _si >= _states.size():
			_finish_step()
			if status != RUNNING:
				break
			_next_step()
			if status != RUNNING:
				break
		_expand(_states[_si])
		_si += 1
		if Time.get_ticks_usec() - t0 > budget_us:
			break
	return status

## Solve to the end (offline use).
func solve() -> Array:
	while run(1000000000) == RUNNING:
		pass
	return [result_time, result_fuel]

func _next_step() -> void:
	if _cur.is_empty() or _k >= K:
		_conclude()
		return
	_nxt = {}
	_si = 0
	_states = _cur.values()
	if _states.size() > cap:   # keep a random share of every goal-progress group (a mask), so no group starves
		var groups := {}
		for st0 in _states:
			var m0: int = st0[5]
			if not groups.has(m0):
				groups[m0] = []
			groups[m0].append(st0)
		var share: int = maxi(cap / groups.size(), 40)
		_states = []
		for m0 in groups:
			var g: Array = groups[m0]
			if g.size() > share:
				_shuffle(g)
				g = g.slice(0, share)
			_states.append_array(g)

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

func _finish_step() -> void:
	_k += 1
	if early and _t_ok >= 0.0:
		_conclude()
		return
	if _t_ok >= 0.0 and float(_k) * dt > _t_ok + extra_s:
		_conclude()
		return
	_cur = _nxt
	if _cur.is_empty() or _k >= K:
		_conclude()

func _conclude() -> void:
	if _t_ok >= 0.0:
		status = SOLVABLE
		result_time = _t_ok
		result_fuel = _best_fuel_used
	else:
		status = NO_PATH

# ---- precompute the whole timeline of the leg ----
func _prepare(tmax: float) -> void:
	var L := lanes
	K = int(ceil(tmax / dt))
	var MAXP := Lanes.MAX_PER_LANE
	var K1 := K + 1
	_lane_w.resize(Lanes.MAX_LANES * K1)
	_hz_px.resize(Lanes.MAX_LANES * MAXP * K1)
	_hz_py.resize(Lanes.MAX_LANES * MAXP * K1)
	var acc := PackedFloat32Array()
	acc.resize(Lanes.MAX_LANES)
	for k in K + 1:
		var t := float(k) * dt
		for i in L.n_lanes:
			var base: float = L.lane_base[i]
			var w := base
			var k0: int = L.lane_kind[i]
			if L.lane_rev[i] > 0.0:
				w = base * clampf(3.0 * sin(PI * (t + L.lane_rev_off[i]) / L.lane_rev[i]), -1.0, 1.0)
			_lane_w[i * K1 + k] = w
			var vel: float = L._haz_vel(w, k0) if k0 >= 0 else w
			for j in L.lane_count[i]:
				var idx: int = i * MAXP + j
				var x: float = L.hz_x[idx] + acc[i]
				_hz_px[idx * K1 + k] = -Lanes.MARGIN + fposmod(x + Lanes.MARGIN, Lanes.RING)
				var cy: float = L._lane_cy(i)
				if L.lane_beat[i] > 0.0:
					_hz_py[idx * K1 + k] = cy - L.lane_amp[i] * 0.45 + L.lane_amp[i] * 0.9 * Tuning.kite_dip * L._dip(fposmod(t / L.lane_beat[i] + L.lane_gph[i] / TAU, 1.0))
				else:
					_hz_py[idx * K1 + k] = cy + sin(t * float(Lanes.KIND_RATE[k0]) + L.hz_phase[idx]) * L.lane_amp[i]
			acc[i] += vel * dt
	_ship_xs.resize(K + 1)
	var sx: float = L.ship_x
	var sd: float = L.ship_dir
	for k in K + 1:
		_ship_xs[k] = sx
		sx += sd * Tuning.airship_speed * dt
		if sx > Lanes.SHIP_MAX_X:
			sx = Lanes.SHIP_MAX_X
			sd = -1.0
		elif sx < Lanes.SHIP_MIN_X:
			sx = Lanes.SHIP_MIN_X
			sd = 1.0
	_lt_on_k.resize(K + 1)
	_lt_x_k.resize(K + 1)
	for k in K + 1:
		var t := float(k) * dt
		var phase := fposmod(t, Tuning.lightning_period)
		_lt_on_k[k] = 1 if (L.lt_on and phase >= Tuning.lightning_period - Tuning.lightning_strike) else 0
		_lt_x_k[k] = L.lt_cols[int(floor(t / Tuning.lightning_period)) % 3]
	_storm_k.resize(K + 1)
	for k in K + 1:
		var t := float(k) * dt
		_storm_k[k] = L.storm_y - L.storm_speed * maxf(t - Tuning.storm_start_delay, 0.0) if L.storm_on else 99999.0

func _hits(x: float, y: float, k: int, back: float) -> bool:
	var L := lanes
	var s: float = bal.s()
	for c in 3:
		var py: float = y + float(Balloon.HIT[c][0]) * s
		var r: float = float(Balloon.HIT[c][1]) * s * Tuning.hit_forgiveness + margin
		var li: int = L.lane_of(py)
		for i in range(maxi(li - 1, 0), mini(li + 2, L.n_lanes)):
			var kd: int = L.lane_kind[i]
			if kd < 0:
				continue
			var ex: float = float(Lanes.KIND_HX[kd]) * L.lane_scale[i] + r
			var ey: float = float(Lanes.KIND_HY[kd]) * L.lane_scale[i] + r
			for j in L.lane_count[i]:
				var idx: int = i * Lanes.MAX_PER_LANE + j
				var hx: float = _hz_px[idx * (K + 1) + k]
				var hy: float = _hz_py[idx * (K + 1) + k]
				if back > 0.0:   # half way between step k-1 and k
					var hx0: float = _hz_px[idx * (K + 1) + k - 1]
					if absf(hx - hx0) < 300.0:
						hx = (hx + hx0) * 0.5
					hy = (hy + _hz_py[idx * (K + 1) + k - 1]) * 0.5
				var dx: float = (x - hx) / ex
				var dy: float = (py - hy) / ey
				if dx * dx + dy * dy < 1.0:
					return true
	return false

func _star_hit(x: float, y: float, k: int, q: int) -> bool:
	var L := lanes
	var s: float = bal.s()
	var t := float(k) * dt
	var cy: float = L._lane_cy(L.gs_lane[q]) + sin(t * 2.1 + float(q) * 1.3) * minf(L.lane_h * 0.18, 24.0)
	for c in 3:
		var p := Vector2(x, y + float(Balloon.HIT[c][0]) * s)
		if p.distance_to(Vector2(L.gs_x[q], cy)) < float(Balloon.HIT[c][1]) * s * Tuning.hit_forgiveness + 32.0:
			return true
	return false

func _wind_at(y: float, k: int) -> float:
	if y >= _fy - 0.01:
		return 0.0
	return _lane_w[lanes.lane_of(y) * (K + 1) + k]

## Expand one state by one time step: the player holds or releases the burner for dt seconds.
func _expand(st: Array) -> void:
	var L := lanes
	var s: float = bal.s()
	var k := _k
	var kk := k + 1
	var mask: int = st[5]
	var ceil_y := _ceil_base
	if (_goal == Flights.STARS and mask & _want_mask == _want_mask) or (_goal == Flights.DELIVERY and mask == 3):
		ceil_y = -1.0e5   # the goal is met: the top is open
	for hold in [true, false]:
		var fuel: float = st[2]
		if hold and fuel <= 0.0:
			continue
		var x: float = st[0]
		var y: float = st[1]
		var r: float = st[3]
		var h: float = st[4]
		var landed := false
		var hard := false
		var m2 := mask
		for q in sub:
			h = move_toward(h, 1.0 if hold else 0.0, (Tuning.heat_rate if hold else Tuning.cool_rate) * _sdt)
			r = bal._next_rise(r, h, false, false, 0.0, L.climb_mult_at(y), _sdt)
			y -= r * _sdt
			if y < ceil_y:
				y = ceil_y
				r = minf(r, 0.0)
			if y >= _fy:
				y = _fy
				r = maxf(r, 0.0)
			x += _wind_at(y, k) * _sdt
			if x > Lanes.W + _half:
				x -= Lanes.W + 2.0 * _half
			elif x < -_half:
				x += Lanes.W + 2.0 * _half
			if _goal == Flights.LANDING:   # the airship: a solid hull below, a deck above
				var dx: float = x - _ship_xs[k]
				if absf(dx) <= Tuning.airship_deck_half + 28.0 * s:
					if y - 56.0 * s < Lanes.SHIP_DECK_Y + Lanes.SHIP_HULL_H and y > Lanes.SHIP_DECK_Y:
						y = Lanes.SHIP_DECK_Y + Lanes.SHIP_HULL_H + 56.0 * s
						r = minf(r, 0.0)
					elif y + 84.0 * s >= Lanes.SHIP_DECK_Y and y <= Lanes.SHIP_DECK_Y and absf(dx) <= Tuning.airship_deck_half - margin * 0.5:
						landed = true
						hard = -r > Tuning.land_speed
						break
		if landed:
			if hard:
				continue
			if _t_ok < 0.0:
				_t_ok = float(kk) * dt
			_best_fuel_used = minf(_best_fuel_used, _tank0 - fuel)
			continue
		if hold:
			fuel = maxf(fuel - Tuning.burn_rate * dt, 0.0)
		# collisions at the end of the step and half way (the hazards at the average of their two positions)
		if _hits(x, y, kk, 0.0) or _hits((x + st[0]) * 0.5 if absf(x - st[0]) < 300.0 else x, (y + st[1]) * 0.5, kk, 0.5):
			continue
		if _lt_on_k[kk] == 1 and absf(x - _lt_x_k[kk]) < Tuning.lightning_width * 0.5 + 20.0 + margin:
			continue
		if y + 84.0 * s * 0.8 > _storm_k[kk]:
			continue
		for q in _n_stars:
			if (m2 >> q) & 1 == 0 and _star_hit(x, y, kk, q):
				m2 |= 1 << q
		if _goal == Flights.DELIVERY:   # delivery: mask 1 = mail on board, 3 = delivered
			var d0: Vector2 = L.dock_pos(0)
			var d1: Vector2 = L.dock_pos(1)
			if m2 == 0 and absf(x - d0.x) < Tuning.dock_half_w and absf(y - d0.y) < Tuning.dock_half_h:
				m2 = 1
			elif m2 == 1 and absf(x - d1.x) < Tuning.dock_half_w and absf(y - d1.y) < Tuning.dock_half_h:
				m2 = 3
		var done_goal := true
		if _goal == Flights.STARS:
			done_goal = m2 & _want_mask == _want_mask
		elif _goal == Flights.DELIVERY:
			done_goal = m2 == 3
		if _goal != Flights.LANDING and done_goal and y <= Lanes.GOAL_Y:
			if _t_ok < 0.0:
				_t_ok = float(kk) * dt
			_best_fuel_used = minf(_best_fuel_used, _tank0 - fuel)
			continue
		var ns := [x, y, fuel, r, h, m2]
		var key := _key(ns)
		if not _nxt.has(key) or _nxt[key][2] < fuel:
			_nxt[key] = ns

func _key(st: Array) -> int:
	var xb := int((st[0] + 200.0) / BUCKET_X)
	var yb := int((st[1] + 100.0) / BUCKET_Y)
	var rb := int((st[3] + 300.0) / 70.0)
	var hb := int(st[4] * 2.99)
	return ((((yb * 256 + xb) * 64 + int(st[5])) * 16 + rb) * 4 + hb)
