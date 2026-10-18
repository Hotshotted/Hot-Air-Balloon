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
## Wind speed (px/s) of a layer: wind_base + wind_per_level * (level - 1) + up to wind_variation, capped at wind_max.
var wind_base := 80.0
var wind_per_level := 16.0
var wind_variation := 50.0
var wind_max := 280.0
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
var jet_wind := 380.0

# ---------- Hazards ----------
## Hazards per hazard layer: hazard_density at level 1, plus density_per_level each level, capped at density_max.
## (A layer never holds more than fit with the gaps below, so every layer can be crossed.)
var hazard_density := 2.4
var density_per_level := 0.35
var density_max := 6.0
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
