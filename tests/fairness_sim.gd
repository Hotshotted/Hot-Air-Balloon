extends SceneTree
## Offline fairness check (not part of CI; minutes, not seconds):
##   godot --headless --path . --script res://tests/fairness_sim.gd -- [flights=0,7,13|all] [legs=0,1,2,3,4] [dt=0.1] [margin=18] [cap=3000]
## For every chosen leg of every chosen Flight it asks: is there ANY sequence of inputs that finishes the leg without
## touching anything, when the player has to keep `margin` extra pixels of clearance from every hazard and the
## goal is the leg's own goal (climb / stars / delivery / storm / landing)? It searches the real generated layout
## (hazard positions, winds incl. reversing layers, kite beat, lightning, storm, airship) exactly like the game rolls
## it forward, on a time grid of `dt` seconds, with the real burner physics (hold / release every dt: heat spool, buoyancy lag,
## speed caps, thin air); thermals, Sandbag, Anchor and Quick Vent only help, so they are ignored.
## It is a PLANNER, not a human: it knows the future and has no reaction time (the margin and the time grid stand in for
## that). Propane: the cost of the cheapest found path is reported; pickups are ignored (they only help).
## "solvable" means a path was found within `cap` states per step: if not, the state cap may have hidden one, so a
## failure is reported as "no path found", not as a proof.

const BUCKET_X := 12.0
const BUCKET_Y := 14.0

var dt := 0.1
var margin := 18.0
var cap := 600
var tmax_s := 45.0
var tank := -1.0       # the propane the leg starts with (-1: Tuning.propane_start); the cost of the found path is reported either way
var extra_s := 6.0     # keep searching this long after the first success, for a cheaper path
var only_star := -1   # debug: the goal is just this star
var tn: Node
var lanes: Node2D
var bal: Node2D
var recipe
var K := 0
# per lane, per step
var lane_w := PackedFloat32Array()   # [lane * (K+1) + step]: the wind
var hz_px := PackedFloat32Array()    # [(lane * MAX_PER_LANE + j) * (K+1) + step]: hazard x
var hz_py := PackedFloat32Array()    # ...and y
var ship_xs := PackedFloat32Array()
var lt_on_k := PackedByteArray()
var lt_x_k := PackedFloat32Array()
var storm_k := PackedFloat32Array()

func _initialize() -> void:
	await process_frame
	tn = root.get_node("Tuning")
	var LanesS = load("res://scripts/Lanes.gd")
	var BalloonS = load("res://scripts/Balloon.gd")
	var FlightsS = load("res://scripts/Flights.gd")
	var flights: Array = []
	var legs: Array = [0, 1, 2, 3, 4]
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"dt": dt = float(kv[1])
			"margin": margin = float(kv[1])
			"cap": cap = int(kv[1])
			"tmax": tmax_s = float(kv[1])
			"only": only_star = int(kv[1])
			"tank": tank = float(kv[1])
			"flights":
				if kv[1] != "all":
					for x in kv[1].split(","):
						flights.append(int(x))
			"legs":
				legs = []
				for x in kv[1].split(","):
					legs.append(int(x))
	if flights.is_empty():
		for f in 24:
			flights.append(f)
	root.get_node("Save").persist = false
	lanes = LanesS.new()
	root.add_child(lanes)
	bal = BalloonS.new()
	root.add_child(bal)
	await process_frame
	bal.lanes = lanes
	var goal_names := ["climb", "stars", "delivery", "storm", "landing"]
	var tot := {}
	var ok_n := 0
	var all_n := 0
	var fuel_over := 0
	var slow := 0
	for fid in flights:
		var reg: int = FlightsS.region_of(fid)
		var idx: int = FlightsS.index_of(fid)
		var fs: int = FlightsS.seed_of(fid)
		var line := "F%-2d %-9s" % [fid + 1, ["Country", "Alps", "Sahara", "Himalaya"][reg]]
		for l in legs:
			recipe = FlightsS.leg_recipe(fid, l, FlightsS.leg_seed(fs, l))
			lanes.setup(FlightsS.eff_level(reg, idx, l), false, FlightsS.leg_seed(fs, l), reg, recipe)
			bal.reset()
			var t0 := Time.get_ticks_msec()
			var res := _solve()
			var g: String = goal_names[recipe.goal]
			if not tot.has(g):
				tot[g] = [0, 0]
			tot[g][1] += 1
			all_n += 1
			if res[0] >= 0.0:
				tot[g][0] += 1
				ok_n += 1
				if res[1] > tn.propane_start * 0.5:
					fuel_over += 1
				if res[0] > 40.0:
					slow += 1
			line += "  L%d %-8s %s" % [l + 1, g, ("%4.1fs %2.0fp" % [res[0], res[1]]) if res[0] >= 0.0 else " NO PATH "]
		print(line)
	print("--- burner physics: %d / %d legs solvable (margin %.0f px, dt %.2f)" % [ok_n, all_n, margin, dt])
	for g in tot:
		print("    %-9s %d / %d" % [g, tot[g][0], tot[g][1]])
	print("    paths needing more than half a tank: %d, slower than 40 s: %d" % [fuel_over, slow])
	quit()

# ---- precompute the whole timeline of the leg ----
func _prepare(tmax: float) -> void:
	var L = lanes
	K = int(ceil(tmax / dt))
	var MAXP: int = L.MAX_PER_LANE
	var K1 := K + 1
	lane_w.resize(L.MAX_LANES * K1)
	hz_px.resize(L.MAX_LANES * MAXP * K1)
	hz_py.resize(L.MAX_LANES * MAXP * K1)
	var acc := PackedFloat32Array()
	acc.resize(L.MAX_LANES)
	for k in K + 1:
		var t := float(k) * dt
		for i in L.n_lanes:
			var base: float = L.lane_base[i]
			var w := base
			var k0: int = L.lane_kind[i]
			if L.lane_rev[i] > 0.0:
				w = base * clampf(3.0 * sin(PI * (t + L.lane_rev_off[i]) / L.lane_rev[i]), -1.0, 1.0)
			lane_w[i * K1 + k] = w
			var vel: float = L._haz_vel(w, k0) if k0 >= 0 else w
			for j in L.lane_count[i]:
				var idx: int = i * MAXP + j
				var x: float = L.hz_x[idx] + acc[i]
				hz_px[idx * K1 + k] = -L.MARGIN + fposmod(x + L.MARGIN, L.RING)
				var cy: float = L._lane_cy(i)
				if L.lane_beat[i] > 0.0:
					hz_py[idx * K1 + k] = cy - L.lane_amp[i] * 0.45 + L.lane_amp[i] * 0.9 * tn.kite_dip * L._dip(fposmod(t / L.lane_beat[i] + L.lane_gph[i] / TAU, 1.0))
				else:
					hz_py[idx * K1 + k] = cy + sin(t * float(L.KIND_RATE[k0]) + L.hz_phase[idx]) * L.lane_amp[i]
			acc[i] += vel * dt
	ship_xs.resize(K + 1)
	var sx: float = L.ship_x
	var sd: float = L.ship_dir
	for k in K + 1:
		ship_xs[k] = sx
		sx += sd * tn.airship_speed * dt
		if sx > L.SHIP_MAX_X:
			sx = L.SHIP_MAX_X
			sd = -1.0
		elif sx < L.SHIP_MIN_X:
			sx = L.SHIP_MIN_X
			sd = 1.0
	lt_on_k.resize(K + 1)
	lt_x_k.resize(K + 1)
	for k in K + 1:
		var t := float(k) * dt
		var phase := fposmod(t, tn.lightning_period)
		lt_on_k[k] = 1 if (L.lt_on and phase >= tn.lightning_period - tn.lightning_strike) else 0
		lt_x_k[k] = L.lt_cols[int(floor(t / tn.lightning_period)) % 3]
	storm_k.resize(K + 1)
	for k in K + 1:
		var t := float(k) * dt
		storm_k[k] = L.storm_y - L.storm_speed * maxf(t - tn.storm_start_delay, 0.0) if L.storm_on else 99999.0

func _hits(x: float, y: float, k: int, back: float) -> bool:
	var L = lanes
	var s: float = bal.s()
	for c in 3:
		var py: float = y + float(bal.HIT[c][0]) * s
		var r: float = float(bal.HIT[c][1]) * s * tn.hit_forgiveness + margin
		var li: int = L.lane_of(py)
		for i in range(maxi(li - 1, 0), mini(li + 2, L.n_lanes)):
			var kd: int = L.lane_kind[i]
			if kd < 0:
				continue
			var ex: float = float(L.KIND_HX[kd]) * L.lane_scale[i] + r
			var ey: float = float(L.KIND_HY[kd]) * L.lane_scale[i] + r
			for j in L.lane_count[i]:
				var idx: int = i * L.MAX_PER_LANE + j
				var hx: float = hz_px[idx * (K + 1) + k]
				var hy: float = hz_py[idx * (K + 1) + k]
				if back > 0.0:   # half way between step k-1 and k
					var hx0: float = hz_px[idx * (K + 1) + k - 1]
					if absf(hx - hx0) < 300.0:
						hx = (hx + hx0) * 0.5
					hy = (hy + hz_py[idx * (K + 1) + k - 1]) * 0.5
				var dx: float = (x - hx) / ex
				var dy: float = (py - hy) / ey
				if dx * dx + dy * dy < 1.0:
					return true
	return false

func _star_hit(x: float, y: float, k: int, q: int) -> bool:
	var L = lanes
	var s: float = bal.s()
	var t := float(k) * dt
	var cy: float = L._lane_cy(L.gs_lane[q]) + sin(t * 2.1 + float(q) * 1.3) * minf(L.lane_h * 0.18, 24.0)
	for c in 3:
		var p := Vector2(x, y + float(bal.HIT[c][0]) * s)
		if p.distance_to(Vector2(L.gs_x[q], cy)) < float(bal.HIT[c][1]) * s * tn.hit_forgiveness + 32.0:
			return true
	return false

func _wind_at(y: float, k: int) -> float:
	var L = lanes
	if y >= bal.floor_y() - 0.01:
		return 0.0
	return lane_w[L.lane_of(y) * (K + 1) + k]

## [time of the first success or -1, propane the cheapest path used]
## State: [x, y, fuel, rise, heat, mask]. Every step the player holds or releases the burner for dt seconds (the real
## Balloon physics: heat spool, buoyancy lag, speed caps, thin air); the wind of the layer carries the balloon sideways.
func _solve() -> Array:
	var L = lanes
	_prepare(tmax_s)
	var s: float = bal.s()
	var half: float = bal.WIDTH * 0.5 * s
	var fy: float = bal.floor_y()
	var goal: int = recipe.goal
	var blocked_top := goal == 1 or goal == 2   # stars / delivery: no going through the top until done
	var n_stars: int = L.gs_count
	var want_mask := (1 << n_stars) - 1 if only_star < 0 else (1 << only_star)
	var cur := {}
	var tank0: float = tank if tank > 0.0 else tn.propane_start
	var start := [L.W * 0.5, fy, tank0, 0.0, 0.0, 0]
	cur[_key(start)] = start
	var best_fuel_used := 1.0e9
	var t_ok := -1.0
	var ceil_base: float = L.GOAL_Y + 14.0 if blocked_top else (L.CEILING_Y if goal == 4 else -1.0e5)
	var sub := 3
	var sdt := dt / float(sub)
	for k in K:
		if cur.is_empty():
			break
		var nxt := {}
		var kk := k + 1
		var states: Array = cur.values()
		if states.size() > cap:   # keep a random share of every goal-progress group (a mask), so no group starves
			var groups := {}
			for st0 in states:
				var m0: int = st0[5]
				if not groups.has(m0):
					groups[m0] = []
				groups[m0].append(st0)
			var share: int = maxi(cap / groups.size(), 40)
			states = []
			for m0 in groups:
				var g: Array = groups[m0]
				if g.size() > share:
					g.shuffle()
					g = g.slice(0, share)
				states.append_array(g)
		for st in states:
			var mask: int = st[5]
			var ceil_y := ceil_base
			if (goal == 1 and mask & want_mask == want_mask) or (goal == 2 and mask == 3):
				ceil_y = -1.0e5   # the goal is met: the top is open
			for hold in [true, false]:
				var fuel: float = st[2]
				if hold and fuel <= 0.0:
					continue
				var x: float = st[0]
				var y: float = st[1]
				var r: float = st[3]
				var h: float = st[4]
				var dead := false
				var landed := false
				var hard := false
				for q in sub:
					h = move_toward(h, 1.0 if hold else 0.0, (tn.heat_rate if hold else tn.cool_rate) * sdt)
					r = bal._next_rise(r, h, false, false, 0.0, L.climb_mult_at(y), sdt)
					y -= r * sdt
					if y < ceil_y:
						y = ceil_y
						r = minf(r, 0.0)
					if y >= fy:
						y = fy
						r = maxf(r, 0.0)
					x += _wind_at(y, k) * sdt
					if x > L.W + half:
						x -= L.W + 2.0 * half
					elif x < -half:
						x += L.W + 2.0 * half
					if goal == 4:   # the airship: a solid hull below, a deck above
						var dx: float = x - ship_xs[k]
						if absf(dx) <= tn.airship_deck_half + 28.0 * s:
							if y - 56.0 * s < L.SHIP_DECK_Y + L.SHIP_HULL_H and y > L.SHIP_DECK_Y:
								y = L.SHIP_DECK_Y + L.SHIP_HULL_H + 56.0 * s
								r = minf(r, 0.0)
							elif y + 84.0 * s >= L.SHIP_DECK_Y and y <= L.SHIP_DECK_Y and absf(dx) <= tn.airship_deck_half - margin * 0.5:
								landed = true
								hard = -r > tn.land_speed
								break
				if landed:
					if hard:
						continue
					if t_ok < 0.0:
						t_ok = float(kk) * dt
					best_fuel_used = minf(best_fuel_used, tank0 - fuel)
					continue
				if hold:
					fuel = maxf(fuel - tn.burn_rate * dt, 0.0)
				# collisions at the end of the step and half way (the hazards at the average of their two positions)
				if _hits(x, y, kk, 0.0) or _hits((x + st[0]) * 0.5 if absf(x - st[0]) < 300.0 else x, (y + st[1]) * 0.5, kk, 0.5):
					continue
				if lt_on_k[kk] == 1 and absf(x - lt_x_k[kk]) < tn.lightning_width * 0.5 + 20.0 + margin:
					continue
				if y + 84.0 * s * 0.8 > storm_k[kk]:
					continue
				for q in n_stars:
					if (mask >> q) & 1 == 0 and _star_hit(x, y, kk, q):
						mask |= 1 << q
				if goal == 2:   # delivery: mask 1 = mail on board, 3 = delivered
					var d0: Vector2 = L.dock_pos(0)
					var d1: Vector2 = L.dock_pos(1)
					if mask == 0 and absf(x - d0.x) < tn.dock_half_w and absf(y - d0.y) < tn.dock_half_h:
						mask = 1
					elif mask == 1 and absf(x - d1.x) < tn.dock_half_w and absf(y - d1.y) < tn.dock_half_h:
						mask = 3
				var done_goal := true
				if goal == 1:
					done_goal = mask & want_mask == want_mask
				elif goal == 2:
					done_goal = mask == 3
				if goal != 4 and done_goal and y <= L.GOAL_Y:
					if t_ok < 0.0:
						t_ok = float(kk) * dt
					best_fuel_used = minf(best_fuel_used, tank0 - fuel)
					continue
				var ns := [x, y, fuel, r, h, mask]
				var key := _key(ns)
				if not nxt.has(key) or nxt[key][2] < fuel:
					nxt[key] = ns
		if t_ok >= 0.0 and float(kk) * dt > t_ok + extra_s:
			break
		cur = nxt
	return [t_ok, best_fuel_used] if t_ok >= 0.0 else [-1.0, 0.0]

func _key(st: Array) -> int:
	var xb := int((st[0] + 200.0) / BUCKET_X)
	var yb := int((st[1] + 100.0) / BUCKET_Y)
	var rb := int((st[3] + 300.0) / 70.0)
	var hb := int(st[4] * 2.99)
	return ((((yb * 256 + xb) * 64 + int(st[5])) * 16 + rb) * 4 + hb)
