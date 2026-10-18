class_name Flights
extends RefCounted
## Flights: a fixed chain of legs (levels), generated from a seed, so a Flight is the same every time it is
## played. Flights are numbered 0..23 (region * 6 + index); the Daily Flight uses id DAILY and a date seed.
## Pure data and arithmetic: nothing here is created while playing.

## Leg goals.
enum { CLIMB, STARS, DELIVERY, STORM, LANDING }
const GOAL_NAMES := ["Climb", "Star Collect", "Delivery", "Rising Storm", "Precision Landing"]
const GOAL_HINTS := ["CLIMB TO THE TOP", "COLLECT EVERY STAR", "DELIVER THE MAIL", "OUTRUN THE STORM", "LAND ON THE AIRSHIP"]
## The ONE new idea each Flight introduces (nothing else is new in it); the legs of a Flight only use ideas introduced
## in that Flight or an earlier one. "region" = the region's own mechanic. Tools (sandbag, anchor, vent) come with
## the second Flight of Alps / Sahara / Himalayas.
const CURRICULUM := [
	"climb", "stars", "kitebeat", "delivery", "reverse", "storm",
	"region", "sandbag", "geese", "landing", "lightning", "",
	"region", "anchor", "", "", "", "",
	"region", "vent", "", "", "", "",
]
const IDEA_ORDER := ["climb", "stars", "kitebeat", "delivery", "reverse", "storm", "region", "sandbag", "geese", "landing", "lightning", "anchor", "vent"]

const REGION_COUNT := 4
const PER_REGION := 6
const TOTAL := REGION_COUNT * PER_REGION
const DAILY := -1
## Difficulty ("effective level", see Lanes.setup) of leg 0 of a region's first Flight, the step between
## the Flights of a region and the step between the legs of a Flight.
const REGION_BASE := [1.0, 3.5, 6.0, 8.5]
const FLIGHT_STEP := 0.45
const LEG_STEP := 0.5

## The Daily Flight: one a day, seeded by the date (UTC). Its region rotates; it is the region's mid Flight, a bit harder.
const DAILY_INDEX := 3
static var debug_today := -1        # ?tune / tests: pretend it is this day

## Days since 1970-01-01 (UTC).
static func today() -> int:
	return debug_today if debug_today >= 0 else int(floor(Time.get_unix_time_from_system() / 86400.0))

static func daily_region(day: int) -> int:
	return posmod(day, REGION_COUNT)

static func daily_seed(day: int) -> int:
	return day * 7919 + 31337

static func region_of(id: int) -> int:
	return clampi(id / PER_REGION, 0, REGION_COUNT - 1)

static func index_of(id: int) -> int:
	return id % PER_REGION

static func id_of(region: int, index: int) -> int:
	return region * PER_REGION + index

## The seed that fixes a whole Flight.
static func seed_of(id: int) -> int:
	return (id + 1) * 7919 + 104729

static func leg_seed(flight_seed: int, leg: int) -> int:
	return flight_seed * 31 + (leg + 1) * 104729

## Difficulty of a leg: rises across the Flights of a region and across the legs of a Flight.
static func eff_level(region: int, index: int, leg: int) -> float:
	return float(REGION_BASE[region]) + float(index) * FLIGHT_STEP + float(leg) * LEG_STEP

## Coins floating in the layers across the whole Flight, and how many earn the third star.
static func coin_total() -> int:
	return int(Tuning.legs_per_flight) * int(Tuning.coins_per_leg)

static func coin_target() -> int:
	return ceili(Tuning.star_coin_frac * float(coin_total()))

## Propane needed at the end of a Flight for the second star.
static func propane_target() -> float:
	return Tuning.star_propane_frac * Tuning.propane_start

static func stars_for(completed: bool, propane_left: float, coins: int) -> int:
	if not completed:
		return 0
	var s := 1
	if propane_left >= propane_target():
		s += 1
	if coins >= coin_target():
		s += 1
	return s

# ---------------------------------------------------------------------------------------------------------
# Leg recipes: which goal and twists each leg of a Flight has
# ---------------------------------------------------------------------------------------------------------

## The Flight (0..23) in which an idea is introduced.
static func idea_flight(idea: String) -> int:
	return CURRICULUM.find(idea)

## Is `idea` available in Flight f? (introduced in f or before.) The Daily Flight (f < 0) has every idea.
static func idea_available(idea: String, f: int) -> bool:
	if f < 0:
		return true
	var at := CURRICULUM.find(idea)
	return at >= 0 and at <= f

## The tools a Flight offers: sandbag (Alps 2+), anchor (Sahara 2+), vent (Himalayas 2+). Region r's tool is
## available from the second Flight of region r on, in every later region too.
static func tools_for(region: int, index: int) -> Array:
	var out: Array = []
	for r in range(1, REGION_COUNT):
		if region > r or (region == r and index >= 1):
			out.append(r - 1)   # 0 sandbag, 1 anchor, 2 vent
	return out

## The five goals of a Flight, fixed by its seed: the goal this Flight introduces is on one of legs 2-4, a gentle
## first leg (Climb) in the first Flights, never the same goal twice in a row, and the legs that are left favour the
## goals used least so far, so a Flight with several goals available really mixes them.
static func plan_goals(f: int, flight_seed: int) -> Array:
	var legs := int(Tuning.legs_per_flight)
	var rng := RandomNumberGenerator.new()
	rng.seed = flight_seed * 5 + 17
	var avail: Array = [CLIMB]
	for pair in [["stars", STARS], ["delivery", DELIVERY], ["storm", STORM], ["landing", LANDING]]:
		if idea_available(pair[0], f):
			avail.append(pair[1])
	var intro: String = CURRICULUM[f] if f >= 0 else ""
	var forced := -1
	match intro:
		"stars": forced = STARS
		"delivery": forced = DELIVERY
		"storm": forced = STORM
		"landing": forced = LANDING
	var forced_leg := 1 + rng.randi() % maxi(legs - 2, 1)
	var plan: Array = []
	var used := {}
	for l in legs:
		var g := CLIMB
		if forced >= 0 and l == forced_leg:
			g = forced
		elif l == 0 and f >= 0 and f < 12:
			g = CLIMB   # a gentle first leg
		else:
			var pool: Array = avail.duplicate()
			if forced >= 0:
				pool.erase(forced)
			if not plan.is_empty() and pool.size() > 1:
				pool.erase(plan[l - 1])
			var least := 1 << 30
			for c in pool:
				least = mini(least, int(used.get(c, 0)))
			var cands: Array = []
			for c in pool:
				if int(used.get(c, 0)) == least:
					cands.append(c)
			g = cands[rng.randi() % cands.size()]
		plan.append(g)
		used[g] = int(used.get(g, 0)) + 1
	return plan

## Build the recipe of leg `leg` of a Flight. `f` is the Flight id (Daily: -1), `seed_val` the leg's seed.
static func leg_recipe(f: int, leg: int, seed_val: int) -> LegRecipe:
	var flight_seed := (seed_val - (leg + 1) * 104729) / 31   # (leg_seed = flight_seed * 31 + (leg + 1) * 104729)
	var legs := int(Tuning.legs_per_flight)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val * 7 + 13
	var r := LegRecipe.new()
	r.leg_index = leg
	r.goal = plan_goals(f, flight_seed)[mini(leg, legs - 1)]
	# --- twists (rhythm hazards, a reversing layer, lightning): at most two per leg, never clutter ---
	var intro: String = CURRICULUM[f] if f >= 0 else ""
	var intro_twist: bool = intro in ["kitebeat", "reverse", "geese", "lightning"]
	var picks: Array[String] = []
	for t in ["kitebeat", "reverse", "geese", "lightning"]:
		if not idea_available(t, f):
			continue
		var want := false
		if intro_twist and t == intro:
			want = leg == 1 or leg == 3   # the new idea shows up on two legs of its Flight
		else:
			want = rng.randf() < 0.38
		if want:
			picks.append(t)
	if picks.size() > 2:   # at most two; the one this Flight introduces is kept first
		var keep: Array[String] = []
		if intro_twist and picks.has(intro):
			keep.append(intro)
			picks.erase(intro)
		while keep.size() < 2 and not picks.is_empty():
			keep.append(picks.pop_at(rng.randi() % picks.size()))
		picks = keep
	r.kite_beat = picks.has("kitebeat")
	r.reverse = picks.has("reverse")
	r.geese = picks.has("geese")
	r.lightning = picks.has("lightning")
	if r.goal == STORM:
		r.storm_speed = Tuning.storm_speed + Tuning.storm_speed_per_leg * float(leg)
		r.lightning = false   # (a storm leg already has plenty to watch)
	return r
