class_name LegPlanner
extends RefCounted
## Self-checking generation. Whenever a leg is about to be generated (a Flight's legs, the Daily Flight's seeds), the planner
## runs the fairness solver (LegSolver, a coarse early-exiting setting) on a probe copy of the sky. No path: the seed is bumped
## and the leg regenerated, up to Tuning.leg_tries attempts; then a sparser version of the leg (half the hazard layers, one
## hazard each) is used. The answer for a leg is cached, deterministic from (level, seed, region, Flight, leg), and the work is
## time-sliced (tick) and only done while no leg is being flown (menus, the leg-complete screen): nothing is solved during play.

const SEED_STEP := 7919

var solver := LegSolver.new()
var probe: Lanes
var bal: Balloon
var cache := {}              # key -> [seed, sparse]
var stats := {"planned": 0, "first_try": 0, "reseeded": 0, "sparse": 0}
var force_fail := false      # tests: pretend no seed is ever solvable
var _queue: Array = []
var _job = null              # {key, level, seed, region, fid, leg, attempt, sparse}

func attach(parent: Node) -> void:
	probe = Lanes.new()
	probe.probe = true
	probe.visible = false
	parent.add_child(probe)
	bal = Balloon.new()      # (not in the tree: only its size and physics are used)
	solver.early = true
	solver.sub = 2

func detach() -> void:
	if bal != null:
		bal.free()
		bal = null

static func key_of(level: float, seed_val: int, region: int, fid: int, leg: int) -> String:
	return "%d|%d|%d|%d|%d" % [roundi(level * 100.0), seed_val, region, fid, leg]

func busy() -> bool:
	return _job != null or not _queue.is_empty()

## The plan [seed, sparse] for a leg, or null if it has not been worked out yet.
func get_plan(level: float, seed_val: int, region: int, fid: int, leg: int):
	return cache.get(key_of(level, seed_val, region, fid, leg), null)

## Ask for a leg to be planned (a no-op if it is cached or queued).
func request(level: float, seed_val: int, region: int, fid: int, leg: int) -> void:
	var key := key_of(level, seed_val, region, fid, leg)
	if cache.has(key) or (_job != null and _job["key"] == key):
		return
	for j in _queue:
		if j["key"] == key:
			return
	_queue.append({"key": key, "level": level, "seed": seed_val, "region": region, "fid": fid, "leg": leg, "attempt": 0, "sparse": false})

## Plan for up to `budget_us` microseconds. Returns true while there is still work.
func tick(budget_us: int) -> bool:
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < budget_us or budget_us >= 1000000000:
		if _job == null:
			if _queue.is_empty():
				return false
			_job = _queue.pop_front()
			_start()
		var left := maxi(budget_us - (Time.get_ticks_usec() - t0), 1) if budget_us < 1000000000 else budget_us
		var st := solver.run(left)
		if st == LegSolver.RUNNING:
			return true
		_finish(st == LegSolver.SOLVABLE and not force_fail)
	return busy()

## Plan everything queued, now (tests, offline checks).
func plan_all() -> void:
	while tick(1000000000):
		pass

func _attempt_seed() -> int:
	return _job["seed"] + (_job["attempt"] * SEED_STEP if not _job["sparse"] else 0)

func _start() -> void:
	var seed_a := _attempt_seed()
	var rec := Flights.leg_recipe(_job["fid"], _job["leg"], seed_a)
	probe.setup(_job["level"], false, seed_a, _job["region"], rec, _job["sparse"])
	solver.dt = Tuning.plan_dt
	solver.cap = int(Tuning.plan_cap)
	solver.tmax_s = 40.0
	solver.margin = 18.0
	solver.begin(probe, bal, rec)

func _finish(ok: bool) -> void:
	var j = _job
	if ok or j["sparse"]:   # solvable, or the sparse fallback (taken as it is)
		stats["planned"] += 1
		if j["sparse"]:
			stats["sparse"] += 1
		elif j["attempt"] == 0:
			stats["first_try"] += 1
		else:
			stats["reseeded"] += 1
		cache[j["key"]] = [_attempt_seed(), j["sparse"]]
		_job = null
		return
	j["attempt"] += 1
	if j["attempt"] >= int(Tuning.leg_tries):   # out of tries: a sparser version of the original leg
		j["sparse"] = true
	_start()
