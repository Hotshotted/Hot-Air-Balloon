extends Node
## Versioned save (autoload `Save`): stars per Flight, coins, unlocks. Stored as JSON in user:// (browser
## storage on the web). New versions only ADD fields: _migrate() fills anything an older file lacks from the
## defaults, so old saves keep working. Tests switch `persist` off.

const VERSION := 2
const PATH := "user://wind_layers_save.json"
## Stars needed in a region (of 18) to open the next one.
const REGION_UNLOCK_STARS := 12

var persist := true
var data := {}

func _ready() -> void:
	data = _defaults()
	if persist:
		_load()

func _defaults() -> Dictionary:
	var stars := []
	var best := []
	for i in Flights.TOTAL:
		stars.append(0)
		best.append(0)
	return {
		"version": VERSION,
		"coins": 0,
		"stars": stars,           # best stars per Flight (0-3)
		"best_score": best,       # best score per Flight
		"flights_played": 0,
		"unlock_all": false,      # ?tune debug: every region and Flight open
		"seen_regions": [true, false, false, false],   # regions whose "unlocked" message has been shown (v2)
		"last_flight": 0,         # the Flight last opened (v2)
	}

func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		data = _migrate(parsed)

## Bring a loaded dictionary up to the current version: keep what it has, add what it lacks.
func _migrate(old: Dictionary) -> Dictionary:
	var d := _defaults()
	for k in d.keys():
		if not old.has(k):
			continue
		var both_numbers: bool = (typeof(old[k]) == TYPE_FLOAT or typeof(old[k]) == TYPE_INT) and (typeof(d[k]) == TYPE_FLOAT or typeof(d[k]) == TYPE_INT)   # JSON gives floats
		if both_numbers or typeof(old[k]) == typeof(d[k]):
			d[k] = old[k]
	for k in ["stars", "best_score", "seen_regions"]:
		var arr: Array = d[k]
		for i in arr.size():
			arr[i] = bool(arr[i]) if k == "seen_regions" else int(arr[i])
		while arr.size() < (Flights.REGION_COUNT if k == "seen_regions" else Flights.TOTAL):
			arr.append(false if k == "seen_regions" else 0)
	d["coins"] = int(d["coins"])
	d["flights_played"] = int(d["flights_played"])
	d["last_flight"] = clampi(int(d["last_flight"]), 0, Flights.TOTAL - 1)
	d["version"] = VERSION
	return d

func save() -> void:
	if not persist:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func reset_all() -> void:
	data = _defaults()
	save()

# ---- queries ----

var coins: int:
	get: return int(data["coins"])

func stars_of(id: int) -> int:
	return int(data["stars"][id]) if id >= 0 and id < Flights.TOTAL else 0

func best_score_of(id: int) -> int:
	return int(data["best_score"][id]) if id >= 0 and id < Flights.TOTAL else 0

func total_stars() -> int:
	var n := 0
	for s in data["stars"]:
		n += int(s)
	return n

func region_stars(region: int) -> int:
	var n := 0
	for i in Flights.PER_REGION:
		n += stars_of(Flights.id_of(region, i))
	return n

func region_unlocked(region: int) -> bool:
	if data["unlock_all"] or region == 0:
		return true
	return region_stars(region - 1) >= REGION_UNLOCK_STARS

## A Flight opens when the one before it in its region has been completed (1+ stars) and its region is open.
func flight_unlocked(id: int) -> bool:
	if id < 0 or id >= Flights.TOTAL:
		return false
	if data["unlock_all"]:
		return true
	if not region_unlocked(Flights.region_of(id)):
		return false
	var idx := Flights.index_of(id)
	return idx == 0 or stars_of(id - 1) >= 1

## The furthest open Flight that is not yet 3-starred (where "play" should point), else the last open one.
func suggested_flight() -> int:
	var last_open := 0
	for id in Flights.TOTAL:
		if flight_unlocked(id):
			last_open = id
			if stars_of(id) < 3:
				return id
	return last_open

## Regions that are open but whose message has not been shown yet; marks them seen. Returns the first, or -1.
func take_new_region() -> int:
	for r in range(1, Flights.REGION_COUNT):
		if region_unlocked(r) and not data["seen_regions"][r]:
			data["seen_regions"][r] = true
			save()
			return r
	return -1

# ---- debug (?tune) ----

func three_star_everything() -> void:
	for i in Flights.TOTAL:
		data["stars"][i] = 3
	save()

func unlock_everything() -> void:
	data["unlock_all"] = true
	save()

# ---- changes ----

func add_coins(n: int) -> void:
	data["coins"] = maxi(int(data["coins"]) + n, 0)
	save()

func spend(n: int) -> bool:
	if int(data["coins"]) < n:
		return false
	data["coins"] = int(data["coins"]) - n
	save()
	return true

## Record a finished Flight: keeps the best stars and the best score.
func record_flight(id: int, stars: int, score: int) -> void:
	if id < 0 or id >= Flights.TOTAL:
		return
	data["flights_played"] = int(data["flights_played"]) + 1
	data["stars"][id] = maxi(stars_of(id), stars)
	data["best_score"][id] = maxi(best_score_of(id), score)
	save()
