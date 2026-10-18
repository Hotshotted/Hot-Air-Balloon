extends Node
## Versioned save (autoload `Save`): stars per Flight, coins, unlocks. Stored as JSON in user:// (browser
## storage on the web). New versions only ADD fields: _migrate() fills anything an older file lacks from the
## defaults, so old saves keep working. Tests switch `persist` off.

const VERSION := 6
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
		"postcards": [0, 0, 0, 0],   # per region: 0 none, 1 postcard, 2 gold postcard (v3)
		"owned": [_owned_default(Cosmetics.ENV), _owned_default(Cosmetics.BASKET), _owned_default(Cosmetics.PASSENGER)],   # per category: owned flags (v4)
		"equipped": [0, 0, 0],    # per category: the equipped item (v4)
		"daily_last": -1,         # the day (days since 1970) the Daily Flight was last completed (v5)
		"daily_streak": 0,        # consecutive days completed (v5)
		"ad_counter": 0,          # Flights ended since the last interstitial (v5)
		"flights_ended": 0,       # Flights ended in total, completed or failed (v5)
		"tools_seen": 0,          # bit mask of the player tools whose one-line intro has been shown (v6)
	}

func _owned_default(cat: int) -> Array:
	var a := []
	for i in Cosmetics.count(cat):
		a.append(i == 0)   # item 0 is the free default
	return a

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
	for k in ["stars", "best_score", "seen_regions", "postcards"]:
		var arr: Array = d[k]
		for i in arr.size():
			arr[i] = bool(arr[i]) if k == "seen_regions" else int(arr[i])
		while arr.size() < (Flights.REGION_COUNT if k == "seen_regions" or k == "postcards" else Flights.TOTAL):
			arr.append(false if k == "seen_regions" else 0)
	# Cosmetics: grow the owned lists if the catalogue grew, and keep the equipped items valid and owned.
	while d["owned"].size() < 3:
		d["owned"].append([])
	for cat in 3:
		var owned: Array = d["owned"][cat] if d["owned"][cat] is Array else []
		while owned.size() < Cosmetics.count(cat):
			owned.append(owned.size() == 0)
		owned = owned.slice(0, Cosmetics.count(cat))
		for i in owned.size():
			owned[i] = bool(owned[i])
		owned[0] = true
		d["owned"][cat] = owned
	while d["equipped"].size() < 3:
		d["equipped"].append(0)
	for cat in 3:
		var e := int(d["equipped"][cat])
		d["equipped"][cat] = e if e >= 0 and e < Cosmetics.count(cat) and d["owned"][cat][e] else 0
	d["coins"] = int(d["coins"])
	d["flights_played"] = int(d["flights_played"])
	for k in ["daily_last", "daily_streak", "ad_counter", "flights_ended", "tools_seen"]:
		d[k] = int(d[k])
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

## Everything open: the saved debug switch (?tune) or the ?unlockall URL flag (which is never saved).
func all_unlocked() -> bool:
	return bool(data["unlock_all"]) or DebugFlags.unlockall_enabled()

func region_unlocked(region: int) -> bool:
	if all_unlocked() or region == 0:
		return true
	return region_stars(region - 1) >= REGION_UNLOCK_STARS

## A Flight opens when the one before it in its region has been completed (1+ stars) and its region is open.
func flight_unlocked(id: int) -> bool:
	if id < 0 or id >= Flights.TOTAL:
		return false
	if all_unlocked():
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
	if all_unlocked():   # nothing is "new" when everything was opened by a debug switch
		return -1
	for r in range(1, Flights.REGION_COUNT):
		if region_unlocked(r) and not data["seen_regions"][r]:
			data["seen_regions"][r] = true
			save()
			return r
	return -1

func postcard_of(region: int) -> int:
	return int(data["postcards"][region])

func region_three_stars(region: int) -> int:
	var n := 0
	for i in Flights.PER_REGION:
		if stars_of(Flights.id_of(region, i)) >= 3:
			n += 1
	return n

## Award postcards: completing a region's last Flight earns its postcard, 3 stars on all six upgrade it to gold.
## Returns [region, new level] of the first change, or [] when nothing changed.
func update_postcards() -> Array:
	for r in Flights.REGION_COUNT:
		var want := 0
		if stars_of(Flights.id_of(r, Flights.PER_REGION - 1)) >= 1:
			want = 1
		if region_three_stars(r) == Flights.PER_REGION:
			want = 2
		if want > postcard_of(r):
			data["postcards"][r] = want
			save()
			return [r, want]
	return []

# ---- cosmetics ----

func owns(cat: int, i: int) -> bool:
	return i >= 0 and i < Cosmetics.count(cat) and bool(data["owned"][cat][i])

func equipped(cat: int) -> int:
	return int(data["equipped"][cat])

## Buy item i of a category with coins (and equip it). False if already owned or too expensive.
func buy(cat: int, i: int) -> bool:
	if i < 0 or i >= Cosmetics.count(cat) or owns(cat, i):
		return false
	if not spend(Cosmetics.price(cat, i)):
		return false
	data["owned"][cat][i] = true
	data["equipped"][cat] = i
	save()
	return true

func equip(cat: int, i: int) -> bool:
	if not owns(cat, i):
		return false
	data["equipped"][cat] = i
	save()
	return true

# ---- player tools ----

func tool_seen(i: int) -> bool:
	return (int(data["tools_seen"]) >> i) & 1 == 1

func mark_tool_seen(i: int) -> void:
	data["tools_seen"] = int(data["tools_seen"]) | (1 << i)
	save()

# ---- Daily Flight ----

func daily_done(day: int) -> bool:
	return int(data["daily_last"]) == day

## The streak as it stands on `day`: kept while yesterday or today was completed, else lost.
func daily_streak_now(day: int) -> int:
	return int(data["daily_streak"]) if int(data["daily_last"]) >= day - 1 else 0

## Complete the Daily Flight of `day`. Returns the bonus coins (0 if it was already completed that day).
func complete_daily(day: int) -> int:
	if daily_done(day):
		return 0
	data["daily_streak"] = daily_streak_now(day) + 1
	data["daily_last"] = day
	save()
	return roundi(Tuning.daily_bonus_coins + Tuning.daily_streak_bonus * float(mini(int(data["daily_streak"]), int(Tuning.daily_streak_cap)) - 1))

func reset_daily() -> void:
	data["daily_last"] = -1
	data["daily_streak"] = 0
	save()

## A Flight ended (completed or failed): counts toward the next interstitial.
func note_flight_ended() -> void:
	data["flights_ended"] = int(data["flights_ended"]) + 1
	data["ad_counter"] = int(data["ad_counter"]) + 1
	save()

## Is an interstitial due between Flights now?
func interstitial_due() -> bool:
	return Tuning.ads_enabled and int(data["flights_ended"]) > int(Tuning.ad_interstitial_after) and int(data["ad_counter"]) >= int(Tuning.ad_interstitial_every)

func interstitial_shown() -> void:
	data["ad_counter"] = 0
	save()

# ---- debug (?tune) ----

## Unlock every region and every Flight in every region (and mark the regions as seen, so no "new region" message
## fires later). Saved immediately.
func unlock_everything() -> void:
	data["unlock_all"] = true
	for r in Flights.REGION_COUNT:
		data["seen_regions"][r] = true
	save()

## 3 stars on every Flight, which also unlocks everything and awards every postcard (all gold). Saved immediately.
func three_star_everything() -> void:
	for i in Flights.TOTAL:
		data["stars"][i] = 3
	while not update_postcards().is_empty():
		pass
	unlock_everything()

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
