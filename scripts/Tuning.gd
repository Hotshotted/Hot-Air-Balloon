extends Node
## Every "feel" value of the game lives here, in one place.
## Registered as the autoload `Tuning`, so any script can read `Tuning.some_value`.
## They are plain vars (not consts) so the ?tune panel can edit them live.
## Distances are pixels on the fixed 1080 x 1920 screen, speeds are pixels per second, y grows downward.

# ---------- Frame time ----------
## The simulation never advances more than this per frame (seconds), whatever the real frame took.
var max_frame_delta := 0.05
## A frame longer than this (a tab switch, a long hitch) is a stall: it is not simulated at all.
var stall_delta := 0.25
## Frames skipped (no simulation) after a stall or the window coming back, so nothing catches up.
var resume_skip_frames := 2

# ---------- Balloon: buoyancy and burner ----------
## Vertical speed (px/s) at full burner heat, and at zero heat (the slow sink).
var climb_speed := 250.0
var sink_speed := 90.0
## Buoyancy lag (1/s): how fast vertical speed follows what the heat asks for. Lower = more sluggish.
var buoyancy_lag := 2.0
## Burner spool (heat per second): how fast the air heats up while the burner fires, and cools after.
var heat_rate := 1.8
var cool_rate := 1.1
## How fast the balloon picks up the wind of the layer it is in (1/s). Lower = more drift lag.
var wind_follow := 1.5
## true: leaving one side of the screen brings the balloon back on the other. false: the edges block.
var edge_wrap := true
## Balloon size multiplier, and how much of its drawn size counts for collisions (0.85 = forgiving).
var balloon_scale := 0.8
var hit_forgiveness := 0.85

# ---------- Wind layers ----------
## Layers in level 1, one more per level, never more than layers_max (the sky is a fixed height).
var layers_base := 5.0
var layers_max := 9.0
## Moderate on purpose: difficulty past these caps comes from variety (goal types, rhythm hazards, tools), not from more or faster.
## Wind speed (px/s) of a layer: wind_base + wind_per_level * (level - 1) + up to wind_variation, capped at wind_max.
var wind_base := 70.0
var wind_per_level := 10.0
var wind_variation := 35.0
var wind_max := 170.0
## Chance that a layer in the middle has no hazards at all (a rest layer). Falls by 4 points a level.
var empty_lane_chance := 0.25

# ---------- Regions ----------
## Countryside winds are this much of the base speed (gentle).
var countryside_wind_mult := 0.8
## Alps: a layer's wind swells and fades by +-gust_amp around its steady speed, once per 2*pi/gust_rate seconds.
var gust_amp := 0.55
var gust_rate := 0.5
## Sahara: thermals are columns (half width thermal_width px) that add up to thermal_lift px/s of rise.
## Sand haze: layers more than haze_clear_lanes away from the balloon fade, haze_per_lane alpha per layer, up to haze_max.
var thermal_width := 95.0
var thermal_lift := 210.0
var haze_clear_lanes := 1.0
var haze_per_lane := 0.38
var haze_max := 0.9
## Himalayas: the burner loses up to thin_air_loss of its climb speed at the top; the top layer is a jet stream (px/s).
var thin_air_loss := 0.45
var jet_wind := 250.0

# ---------- Hazards ----------
## Hazards per hazard layer: hazard_density at level 1, plus density_per_level each level, capped at density_max.
## (A layer never holds more than fit with the gaps below, so every layer can be crossed.)
var hazard_density := 2.2
var density_per_level := 0.25
var density_max := 3.2
## The smallest gap between two hazards in a layer, in balloon widths. Below ~1.4 it is not passable.
var min_gap_factor := 1.8
## Hazard size multiplier.
var hazard_scale := 1.0

# ---------- Flights ----------
## A Flight is this many legs (levels) in a row on ONE tank: leftover propane carries into the next leg.
var legs_per_flight := 5.0
## Coins floating in the layers of each leg (a Flight's third star needs star_coin_frac of all of them).
var coins_per_leg := 3.0
## Stars: 1 for finishing; 2 for finishing with at least star_propane_frac of the tank left; 3 for
## collecting at least star_coin_frac of the Flight's floating coins.
var star_propane_frac := 0.3
var star_coin_frac := 0.6

# ---------- Propane ----------
## Tank size, which is also what a Flight starts with (a fresh tank every Flight).
var propane_start := 100.0
## Propane burned per second while the burner fires.
var burn_rate := 4.5
## What one pickup gives back, the chance a layer carries one, and what clearing a leg refills (0 = nothing).
var propane_refill := 20.0
var propane_chance := 0.4
var leg_refill := 0.0
## The gauge flashes below this fraction of the tank.
var propane_low_fraction := 0.25

# ---------- Score and coins ----------
## Score per leg cleared, plus speed_bonus_per_s for every second under par (par = par_base + par_per_layer * layers).
var level_points := 100.0
var speed_bonus_per_s := 10.0
var par_base := 8.0
var par_per_layer := 2.5
## Coins (the currency): per leg cleared, per floating coin collected, and per unit of propane left at the end of a Flight.
var leg_coins := 10.0
var coin_value := 5.0
var propane_coins := 0.3

# ---------- Leg goals ----------
## Rising Storm: it rises from below at storm_speed (+ storm_speed_per_leg for each leg of the Flight), starting
## storm_start_delay seconds after lift-off. Star Collect: this many stars per leg.
var storm_speed := 40.0
var storm_speed_per_leg := 2.0
var storm_start_delay := 2.0
var stars_per_leg := 4.0
## Precision Landing: the airship drifts at airship_speed (px/s); its deck is +-airship_deck_half wide; the balloon may
## touch down at up to land_speed (px/s of descent), faster is a hard landing.
var airship_speed := 45.0
var airship_deck_half := 130.0
var land_speed := 170.0
## Delivery: a mooring platform picks up / takes the mail when the balloon is within these distances of it.
var dock_half_w := 100.0
var dock_half_h := 70.0

# ---------- Player tools (unlocked by region) ----------
## Sandbag (Alps): drop it for an instant climb burst of sandbag_boost px/s. Anchor (Sahara): hold position for
## anchor_seconds. Quick Vent (Himalayas): descend vent_mult times faster for vent_seconds. Charges are per leg.
var sandbag_charges := 2.0
var sandbag_boost := 300.0
var anchor_charges := 1.0
var anchor_seconds := 2.0
var vent_charges := 2.0
var vent_seconds := 1.6
var vent_mult := 3.0

# ---------- Rhythm and changing winds ----------
## Kites dip on a beat: all the kites of a layer dip together every kite_beat_period seconds (by kite_dip of the free height).
## Lightning: every lightning_period seconds a column of the sky flashes (the warning, lightning_warning seconds), then
## is struck (lightning_strike seconds); the column is lightning_width wide.
## Reversing layers flip their wind every reverse_period seconds, with a visible countdown.
var kite_beat_period := 2.4
var kite_dip := 0.85
var lightning_period := 6.0
var lightning_warning := 1.1
var lightning_strike := 0.3
var lightning_width := 110.0
var reverse_period := 8.0

# ---------- Daily Flight ----------
## The Daily Flight (seeded by the date): coins for the first completion of the day, plus a bonus per day of the
## streak (up to daily_streak_cap days). Its difficulty is the region's mid Flight plus daily_level_bonus.
var daily_bonus_coins := 100.0
var daily_streak_bonus := 10.0
var daily_streak_cap := 7.0
var daily_level_bonus := 0.8

# ---------- Ads (stubs: no SDK yet; a fake "Ad playing" screen stands in) ----------
var ads_enabled := true   # (a bool: edited by the ?tune switch)
## How long the fake ad plays before it can be closed / claimed (seconds).
var ad_fake_seconds := 2.0
## Rewarded: "+50% propane" on the ground at the start of a leg (offered while the tank is at or below
## ad_boost_below of its size, at most ad_boost_max_per_flight times per Flight), and "Retry this leg" after a
## failed leg (at most ad_retry_max_per_flight per Flight).
var ad_boost_frac := 0.5
var ad_boost_below := 0.75
var ad_boost_max_per_flight := 2.0
var ad_retry_max_per_flight := 1.0
## Interstitial: only BETWEEN Flights (on the result / failed screens, never during play): once every
## ad_interstitial_every Flights, and not at all until more than ad_interstitial_after Flights have been played.
var ad_interstitial_every := 3.0
var ad_interstitial_after := 2.0

# ---------- Start-up pre-warm (splash screen) ----------
## At boot every shape is drawn for real behind a splash screen so shaders, buffers and font glyphs
## are set up before play. It lasts at least prewarm_min_seconds, then until frames are calm.
var prewarm_min_seconds := 1.0
var prewarm_stable_frames := 10
var prewarm_stable_ms := 45.0
var prewarm_max_seconds := 5.0

## Number with thousands separators.
func fmt(v: float) -> String:
	var s := str(int(roundf(v)))
	var out := ""
	var n := s.length()
	for i in n:
		out += s[i]
		var left := n - 1 - i
		if left > 0 and left % 3 == 0:
			out += ","
	return out
