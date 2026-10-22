extends SceneTree
## Offline fairness check (not part of CI; minutes, not seconds):
##   godot --headless --path . --script res://tests/fairness_sim.gd -- [flights=0,7,13|all] [legs=0,1,2,3,4] [dt=0.1] [margin=18] [cap=3000] [planner=1]
## For every chosen leg of every chosen Flight it asks (with scripts/LegSolver.gd at full strength): is there ANY sequence of
## inputs that finishes the leg without touching anything, when the player keeps `margin` extra pixels of clearance from every
## hazard and the goal is the leg's own goal (climb / stars / delivery / storm / landing)? It searches the real generated layout
## exactly like the game rolls it forward, with the real burner physics. It is a PLANNER, not a human: it knows the future and has
## no reaction time (the margin and the time grid stand in for that). "No path" is not a proof: the state cap may hide one.
## With planner=1 the legs are first passed through the game's self-checking generation (LegPlanner: reseed, then a sparser
## leg) and the layout that would actually be flown is what is checked, so the pass measures what players get.

func _initialize() -> void:
	await process_frame
	var tn = root.get_node("Tuning")
	var LanesS = load("res://scripts/Lanes.gd")
	var BalloonS = load("res://scripts/Balloon.gd")
	var FlightsS = load("res://scripts/Flights.gd")
	var Solver = load("res://scripts/LegSolver.gd")
	var Planner = load("res://scripts/LegPlanner.gd")
	var flights: Array = []
	var legs: Array = [0, 1, 2, 3, 4]
	var dt := 0.1
	var margin := 18.0
	var cap := 600
	var use_planner := false
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		match kv[0]:
			"dt": dt = float(kv[1])
			"margin": margin = float(kv[1])
			"cap": cap = int(kv[1])
			"planner": use_planner = kv[1] == "1"
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
	var lanes = LanesS.new()
	root.add_child(lanes)
	var bal = BalloonS.new()
	root.add_child(bal)
	await process_frame
	bal.lanes = lanes
	var planner = Planner.new()
	planner.attach(root)
	var solver = Solver.new()
	solver.dt = dt
	solver.margin = margin
	solver.cap = cap
	var goal_names := ["climb", "stars", "delivery", "storm", "landing"]
	var tot := {}
	var ok_n := 0
	var all_n := 0
	var fuel_over := 0
	var slow := 0
	var plan_ms := 0
	for fid in flights:
		var reg: int = FlightsS.region_of(fid)
		var idx: int = FlightsS.index_of(fid)
		var fs: int = FlightsS.seed_of(fid)
		var line := "F%-2d %-9s" % [fid + 1, ["Country", "Alps", "Sahara", "Himalaya"][reg]]
		for l in legs:
			var seed_v: int = FlightsS.leg_seed(fs, l)
			var lvl: float = FlightsS.eff_level(reg, idx, l)
			var sparse := false
			var tag := ""
			if use_planner:
				var t1 := Time.get_ticks_msec()
				planner.request(lvl, seed_v, reg, fid, l)
				planner.plan_all()
				plan_ms += Time.get_ticks_msec() - t1
				var plan = planner.get_plan(lvl, seed_v, reg, fid, l)
				tag = "" if (plan[0] == seed_v and not plan[1]) else ("S" if plan[1] else "r")
				seed_v = plan[0]
				sparse = plan[1]
			var recipe = FlightsS.leg_recipe(fid, l, seed_v)
			lanes.setup(lvl, false, seed_v, reg, recipe, sparse)
			bal.reset()
			solver.begin(lanes, bal, recipe)
			var res: Array = solver.solve()
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
			line += "  L%d %-8s%s %s" % [l + 1, g, tag, ("%4.1fs %2.0fp" % [res[0], res[1]]) if res[0] >= 0.0 else " NO PATH "]
		print(line)
	print("--- burner physics: %d / %d legs solvable (margin %.0f px, dt %.2f)" % [ok_n, all_n, margin, dt])
	for g in tot:
		print("    %-9s %d / %d" % [g, tot[g][0], tot[g][1]])
	print("    paths needing more than half a tank: %d, slower than 40 s: %d" % [fuel_over, slow])
	if use_planner:
		print("    self-checking generation: %d planned, %d on the first seed, %d reseeded (r), %d sparse (S); %.1f s of planning in all (%.0f ms per leg)" % [
			planner.stats["planned"], planner.stats["first_try"], planner.stats["reseeded"], planner.stats["sparse"], float(plan_ms) / 1000.0, float(plan_ms) / maxf(float(all_n), 1.0)])
	quit()
