extends SceneTree
## Offline fairness check (not part of CI; minutes, not seconds):
##   godot --headless --path . --script res://tests/fairness_sim.gd -- scheme=lanes|drag|steady [flights=0,7,13|all] [legs=0,1,2,3,4] [dt=0.1] [margin=18] [cap=3000]
## For every chosen leg of every chosen Flight it asks: is there ANY sequence of inputs that finishes the leg without
## touching anything, when the player has to keep `margin` extra pixels of clearance from every hazard and the
## goal is the leg's own goal (climb / stars / delivery / storm / landing)? It searches the real generated layout
## (hazard positions, winds incl. reversing layers, kite beat, lightning, storm, airship) exactly like the game rolls
## it forward, on a time grid of `dt` seconds, with the balloon model of the chosen scheme:
##   lanes  : levels (ground, every layer's centre, the goal / the sky above the top layer), a hop = hop_time, eased
##   steady : hold = rise steady_climb_speed, release = sink steady_sink_speed
##   drag   : like lanes' hops but anywhere: the altitude may change by up to drag_max_speed * dt per step (so it is
##            a superset of lanes: reported only to confirm that)
## It is a PLANNER, not a human: it knows the future and has no reaction time (the margin and the time grid stand in for
## that). Propane: the cost of the cheapest found path is reported; pickups are ignored (they only help).
## "solvable" means a path was found within `cap` states per step: if not, the state cap may have hidden one, so a
## failure is reported as "no path found", not as a proof.

const BUCKET_X := 12.0
const BUCKET_Y := 14.0

var scheme := "lanes"
var dt := 0.1
var margin := 18.0
var cap := 600
var tmax_s := 45.0
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
			"scheme": scheme = kv[1]
			"dt": dt = float(kv[1])
			"margin": margin = float(kv[1])
			"cap": cap = int(kv[1])
			"tmax": tmax_s = float(kv[1])
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
	bal.scheme = ["lanes", "drag", "steady"].find(scheme)
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
	print("--- %s: %d / %d legs solvable (margin %.0f px, dt %.2f)" % [scheme, ok_n, all_n, margin, dt])
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

func _hits(x: float, y: float, k: int) -> bool:
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
				var dx: float = (x - hz_px[idx * (K + 1) + k]) / ex
				var dy: float = (py - hz_py[idx * (K + 1) + k]) / ey
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
func _solve() -> Array:
	var L = lanes
	_prepare(tmax_s)
	var s: float = bal.s()
	var half: float = bal.WIDTH * 0.5 * s
	var fy: float = bal.floor_y()
	var goal: int = recipe.goal
	var n: int = L.n_lanes
	var lv_hop := int(round(tn.hop_time / dt))
	var cost_hop: float = tn.hop_fuel
	var burn_px: float = tn.climb_burn_per_100px * 0.01
	var blocked_top := goal == 1 or goal == 2   # stars / delivery: no going through the top until done
	var n_stars: int = L.gs_count
	var all_mask := (1 << n_stars) - 1
	# state: [x, y, fuel, hop_p, hop_y0, hop_y1, mask]
	var cur := {}
	var start := [L.W * 0.5, fy, tn.propane_start, -1, 0.0, 0.0, 0]
	cur[_key(start)] = start
	var best_fuel_used := 1.0e9
	var t_ok := -1.0
	var ceil_y: float = L.GOAL_Y + 14.0 if blocked_top else (L.CEILING_Y if goal == 4 else -1.0e5)
	for k in K:
		if cur.is_empty():
			return [-1.0, 0.0]
		var nxt := {}
		var kk := k + 1
		var states: Array = cur.values()
		if states.size() > cap:
			states.shuffle()
			states = states.slice(0, cap)
		for st in states:
			var acts: Array = _actions(st, n, lv_hop, ceil_y, fy)
			for a in acts:
				var x: float = st[0]
				var y: float = a[0]
				var fuel: float = st[2] - a[1]
				if fuel < 0.0:
					continue
				var w := _wind_at(y, kk)
				x += w * dt
				if x > L.W + half:
					x -= L.W + 2.0 * half
				elif x < -half:
					x += L.W + 2.0 * half
				if _hits(x, y, kk):
					continue
				if lt_on_k[kk] == 1 and absf(x - lt_x_k[kk]) < tn.lightning_width * 0.5 + 20.0 + margin:
					continue
				if y + 84.0 * s * 0.8 > storm_k[kk]:
					continue
				var mask: int = st[6]
				# the airship's hull is solid from below
				var hull := false
				var landed := false
				if goal == 4:
					var dx: float = x - ship_xs[kk]
					if absf(dx) <= tn.airship_deck_half + 28.0 * s:
						if y - 56.0 * s < L.SHIP_DECK_Y + L.SHIP_HULL_H and y > L.SHIP_DECK_Y:
							hull = true
						elif y + 84.0 * s >= L.SHIP_DECK_Y and y <= L.SHIP_DECK_Y and absf(dx) <= tn.airship_deck_half - margin * 0.5:
							landed = true
				if hull:
					continue
				if landed:
					var used: float = tn.propane_start - fuel
					if t_ok < 0.0:
						t_ok = float(kk) * dt
					best_fuel_used = minf(best_fuel_used, used)
					continue
				for q in n_stars:
					if (mask >> q) & 1 == 0 and _star_hit(x, y, kk, q):
						mask |= 1 << q
				if goal == 2:   # delivery: mask bit 0 = mail on board, bit 1 = delivered
					var d0: Vector2 = L.dock_pos(0)
					var d1: Vector2 = L.dock_pos(1)
					if mask == 0 and absf(x - d0.x) < tn.dock_half_w and absf(y - d0.y) < tn.dock_half_h:
						mask = 1
					elif mask == 1 and absf(x - d1.x) < tn.dock_half_w and absf(y - d1.y) < tn.dock_half_h:
						mask = 3
				var done_goal := true
				if goal == 1:
					done_goal = mask == all_mask
				elif goal == 2:
					done_goal = mask == 3
				if goal != 4 and done_goal and y <= L.GOAL_Y:
					var used2: float = tn.propane_start - fuel
					if t_ok < 0.0:
						t_ok = float(kk) * dt
					best_fuel_used = minf(best_fuel_used, used2)
					continue
				var ns := [x, y, fuel, a[2], a[3], a[4], mask]
				var key := _key(ns)
				if not nxt.has(key) or (nxt[key][2] < fuel):
					nxt[key] = ns
		if t_ok >= 0.0:
			return [t_ok, best_fuel_used]
		cur = nxt
	return [-1.0, 0.0]

func _key(st: Array) -> int:
	var xb := int((st[0] + 200.0) / BUCKET_X)
	var yb := int((st[1] + 100.0) / BUCKET_Y)
	return (((yb * 256 + xb) * 64 + int(st[6])) * 16 + int(st[3]) + 1) * 4096 + int(st[5]) % 4096

## The moves from a state: [new y, propane, hop_p, hop_y0, hop_y1].
func _actions(st: Array, n: int, lv_hop: int, ceil_y: float, fy: float) -> Array:
	var out: Array = []
	var y: float = st[1]
	var burn_px: float = tn.climb_burn_per_100px * 0.01
	match scheme:
		"steady":
			var up: float = maxf(y - tn.steady_climb_speed * dt, ceil_y)
			var down: float = minf(y + tn.steady_sink_speed * dt, fy)
			out.append([up, (y - up) * burn_px, -1, 0.0, 0.0])
			out.append([down, 0.0, -1, 0.0, 0.0])
		"drag":
			var reach: float = tn.drag_max_speed * dt * 0.6
			for dy in [-reach, -reach * 0.5, 0.0, reach * 0.5, reach]:
				var ny: float = clampf(y + dy, ceil_y, fy)
				out.append([ny, maxf(y - ny, 0.0) * burn_px, -1, 0.0, 0.0])
		_:
			var hp: int = st[3]
			if hp >= 0:   # a hop in progress
				var p: float = float(hp + 1) / float(lv_hop)
				var ny2: float = lerpf(st[4], st[5], p * p * (3.0 - 2.0 * p))
				out.append([ny2, 0.0, (hp + 1) if hp + 1 < lv_hop else -1, st[4], st[5]])
				return out
			out.append([y, 0.0, -1, 0.0, 0.0])
			var lv: int = bal.nearest_level(y)
			for dir in [1, -1]:
				var to: int = lv + dir
				if to < -1 or to > n:
					continue
				var ty: float = bal.level_y(to)
				if ty < ceil_y:
					continue
				var cost: float = tn.hop_fuel if dir > 0 else 0.0
				if dir > 0 and lanes.thermal_lift(st[0]) > 0.0:
					cost = 0.0
				var p1: float = 1.0 / float(lv_hop)
				var ny3: float = lerpf(y, ty, p1 * p1 * (3.0 - 2.0 * p1))
				out.append([ny3, cost, 1 if lv_hop > 1 else -1, y, ty])
	return out
