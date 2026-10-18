class_name Flights
extends RefCounted
## Flights: a fixed chain of legs (levels), generated from a seed, so a Flight is the same every time it is
## played. Flights are numbered 0..23 (region * 6 + index); the Daily Flight uses id DAILY and a date seed.
## Pure data and arithmetic: nothing here is created while playing.

const REGION_COUNT := 4
const PER_REGION := 6
const TOTAL := REGION_COUNT * PER_REGION
const DAILY := -1
## Difficulty ("effective level", see Lanes.setup) of leg 0 of a region's first Flight, the step between
## the Flights of a region and the step between the legs of a Flight.
const REGION_BASE := [1.0, 3.5, 6.0, 8.5]
const FLIGHT_STEP := 0.45
const LEG_STEP := 0.5

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
