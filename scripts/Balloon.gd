class_name Balloon
extends Node2D
## The player's balloon: only altitude is controlled, and it does exactly what the input says (no buoyancy lag, no
## momentum). Three control schemes (?controls=):
##   LANES  : a tap hops one wind layer up or down. The hop takes Tuning.hop_time with smooth easing; a tap during a hop
##            queues at most one more. Each hop UP costs Tuning.hop_fuel (free inside a thermal and from a Sandbag).
##   DRAG   : the balloon follows the finger 1:1 (only Tuning.drag_smooth of smoothing, capped at drag_max_speed);
##            letting go holds the altitude. Climbing burns propane per distance.
##   STEADY : hold to rise at a constant speed, release to sink at a constant speed. Climbing burns propane per distance.
## Descending is free everywhere. Sideways, the balloon moves at exactly the wind of the layer it is in; it blends to a
## new layer's wind over Tuning.wind_blend_time. Drawn from pre-built polygons: nothing is allocated while playing.

enum { LANES, DRAG, STEADY }
const SCHEME_NAMES := ["lanes", "drag", "steady"]
const WIDTH := 84.0            # design width (before Tuning.balloon_scale)
const BASKET_BOTTOM := 84.0    # design distance from the envelope centre (the node origin) to the basket's base
## Hit circles in design units: [dy from the origin, radius]. Envelope top, envelope bottom, basket.
const HIT := [[-10.0, 38.0], [24.0, 22.0], [72.0, 13.0]]
const PRED_N := 12             # points of the drift preview
const BURST_SPEED := 650.0     # px/s of a Sandbag burst (drag / steady)

var scheme := LANES
var lanes: Lanes        # the wind layers (Main sets it): the levels of the lanes scheme and the wind come from here
var rise := 0.0        # vertical speed, px/s, positive = up (measured from the actual movement)
var vx := 0.0          # sideways speed, px/s
var heat := 0.0        # 0..1: only the flame's look (it burns while the balloon climbs)
var burning := false   # climbing right now
var on_ground := true
var sway := 0.0
var _t := 0.0

var flame: Node2D       # the burner flame: its own tiny node, redrawn only while it burns
var _flame_on := false
var anchor_left := 0.0   # Anchor (Sahara): seconds of holding position left
var vent_left := 0.0     # Quick Vent (Himalayas, steady only): seconds of fast descent left
var ceiling_y := -100000.0   # the balloon cannot rise above this (a leg whose goal is not met yet)
var body_draws := 0     # times the body has been drawn (only on a cosmetics change or a fresh leg)
var env_id := 0        # equipped cosmetics (purely visual)
var basket_id := 0
var pass_id := 0

# --- propane the movement cost since Main last took it ---
var paid_hops := 0       # lanes: hops up that were not free
var climbed_px := 0.0    # drag / steady: px climbed under the balloon's own power
# --- lanes: the hop in progress ---
var hopping := false
var hop_t := 0.0
var hop_y0 := 0.0
var hop_y1 := 0.0
var hop_dir := 0
var queued_dir := 0      # a tap during a hop: the next hop (at most one)
var _free_hops := 0      # Sandbag: hops up that cost nothing
# --- drag ---
var drag_target := 0.0   # the altitude the finger asks for
var _drag_f0 := 0.0
var _drag_y0 := 0.0
# --- steady / drag: Sandbag burst ---
var _burst_px := 0.0
# --- wind ---
var _wind_lane := -2
var _wind_from := 0.0
var _blend_t := 99.0
# --- drift preview ---
var pred := PackedVector2Array()

func _ready() -> void:
	flame = BalloonFlame.new()
	flame.balloon = self
	add_child(flame)
	pred.resize(PRED_N)
	reset()

func s() -> float:
	return Tuning.balloon_scale

func scheme_name() -> String:
	return SCHEME_NAMES[scheme]

## Resting y (envelope centre) when the basket sits on the ground.
func floor_y() -> float:
	return Lanes.GROUND_Y - BASKET_BOTTOM * s()

## Back on the ground in the middle, still.
func reset() -> void:
	rise = 0.0
	vx = 0.0
	heat = 0.0
	anchor_left = 0.0
	vent_left = 0.0
	ceiling_y = -100000.0
	burning = false
	on_ground = true
	sway = 0.0
	paid_hops = 0
	climbed_px = 0.0
	hopping = false
	queued_dir = 0
	_free_hops = 0
	_burst_px = 0.0
	_wind_lane = -2
	_blend_t = 99.0
	env_id = Save.equipped(Cosmetics.ENV)
	basket_id = Save.equipped(Cosmetics.BASKET)
	pass_id = Save.equipped(Cosmetics.PASSENGER)
	position = Vector2(Lanes.W * 0.5, floor_y())
	drag_target = position.y
	rotation = 0.0
	scale = Vector2(s(), s())
	queue_redraw()   # the body: only now (a cosmetics change or a fresh leg)
	flame.queue_redraw()

## Teleport to height y (tests, the start of a leg): no hop, no drag in progress.
func set_altitude(y: float) -> void:
	position.y = minf(y, floor_y())
	hopping = false
	queued_dir = 0
	drag_target = position.y
	on_ground = position.y >= floor_y()

# ---------------------------------------------------------------------------------------------------------
# Levels (lanes): the ground, the centre of every wind layer, and the goal / the sky above the top layer
# ---------------------------------------------------------------------------------------------------------

func top_level() -> int:
	return lanes.n_lanes

func level_y(lv: int) -> float:
	if lv < 0:
		return floor_y()
	if lv >= lanes.n_lanes:
		# Above the top layer: the goal line, or on a landing leg the sky over the airship's deck.
		return Lanes.SHIP_DECK_Y - 96.0 * s() if lanes.ship_on else Lanes.GOAL_Y - 1.0
	return lanes._lane_cy(lv)

## The level whose height is nearest to y.
func nearest_level(y: float) -> int:
	var best := -1
	var bd := 1.0e9
	for lv in range(-1, lanes.n_lanes + 1):
		var d := absf(level_y(lv) - y)
		if d < bd:
			bd = d
			best = lv
	return best

## Is hopping dir (+1 up, -1 down) from the nearest level possible right now?
func can_hop(dir: int) -> bool:
	var to := nearest_level(position.y) + dir
	return to >= -1 and to <= lanes.n_lanes and level_y(to) >= ceiling_y

## A tap (lanes). `fuel_ok`: the tank is not empty. Returns true if the tap did something (a hop began or was queued).
func request_hop(dir: int, fuel_ok: bool) -> bool:
	if scheme != LANES or anchor_left > 0.0:
		return false
	if hopping:
		queued_dir = dir
		return true
	return _start_hop(dir, fuel_ok)

func _start_hop(dir: int, fuel_ok: bool) -> bool:
	var from := nearest_level(position.y)
	var to := from + dir
	if to < -1 or to > lanes.n_lanes or level_y(to) < ceiling_y:
		return false
	if dir > 0:
		if _free_hops > 0:
			_free_hops -= 1
		elif lanes.thermal_lift(position.x) > 0.0:
			pass   # a thermal lifts you for free
		elif fuel_ok:
			paid_hops += 1
		else:
			return false
	hopping = true
	hop_t = 0.0
	hop_y0 = position.y
	hop_y1 = level_y(to)
	hop_dir = dir
	return true

# ---------------------------------------------------------------------------------------------------------
# Drag
# ---------------------------------------------------------------------------------------------------------

## The finger went down at screen y `fy`.
func drag_begin(fy: float) -> void:
	_drag_f0 = fy
	_drag_y0 = position.y
	drag_target = position.y

## The finger is now at screen y `fy`: the balloon wants to be as far from where it was as the finger from where it started.
func drag_move(fy: float) -> void:
	drag_target = clampf(_drag_y0 + (fy - _drag_f0), maxf(ceiling_y, -1.0e5), floor_y())

# ---------------------------------------------------------------------------------------------------------
# Step
# ---------------------------------------------------------------------------------------------------------

## Advance by dt. `hold` (steady): the player is holding; `fuel_ok`: the tank is not empty; `lift`: free rise from a
## thermal, px/s (drag / steady; in lanes a thermal makes the hop up free instead).
func step(dt: float, hold: bool, fuel_ok: bool, lift: float = 0.0) -> void:
	_t += dt
	var anchored := anchor_left > 0.0
	if anchored:
		anchor_left = maxf(anchor_left - dt, 0.0)
	var venting := vent_left > 0.0
	if venting:
		vent_left = maxf(vent_left - dt, 0.0)
	var y0 := position.y
	var y := y0
	var own_climb := false
	if not anchored:
		match scheme:
			LANES:
				if hopping:
					hop_t += dt
					var dur := maxf(Tuning.hop_time, 0.02)
					var p := clampf(hop_t / dur, 0.0, 1.0)
					y = lerpf(hop_y0, hop_y1, p * p * (3.0 - 2.0 * p))
					if hop_dir > 0:
						own_climb = true
					if p >= 1.0:
						hopping = false
						if queued_dir != 0:
							var q := queued_dir
							queued_dir = 0
							_start_hop(q, fuel_ok)
			DRAG:
				var want := drag_target
				if not fuel_ok:
					want = maxf(want, y)   # out of propane: the finger can lower the balloon, not raise it
				var dy := (want - y) * (1.0 - exp(-Tuning.drag_smooth * dt))
				var cap := Tuning.drag_max_speed * dt
				dy = clampf(dy, -cap, cap)
				y += dy
				if dy < 0.0:
					climbed_px -= dy
					own_climb = true
			STEADY:
				if venting:
					y += Tuning.steady_sink_speed * Tuning.vent_mult * dt
				elif hold and fuel_ok:
					y -= Tuning.steady_climb_speed * dt
					climbed_px += Tuning.steady_climb_speed * dt
					own_climb = true
				else:
					y += Tuning.steady_sink_speed * dt
		if scheme != LANES:
			if lift > 0.0:
				y -= lift * dt
				drag_target -= lift * dt
			if _burst_px > 0.0:
				var b := minf(BURST_SPEED * dt, _burst_px)
				_burst_px -= b
				y -= b
				drag_target -= b
				own_climb = true
	if y < ceiling_y:
		y = ceiling_y
		if hopping and hop_dir > 0:
			hopping = false
	var fy := floor_y()
	on_ground = y >= fy - 0.01
	if on_ground:
		y = fy
	position.y = y
	if scheme == DRAG:
		drag_target = clampf(drag_target, maxf(ceiling_y, -1.0e5), fy)
	rise = (y0 - y) / dt if dt > 0.0 else 0.0
	burning = own_climb and not anchored
	heat = move_toward(heat, 1.0 if burning else 0.0, 8.0 * dt)
	_sideways(dt, anchored)
	var x := position.x + vx * dt
	var half := WIDTH * 0.5 * s()
	if Tuning.edge_wrap:
		if x > Lanes.W + half:
			x -= Lanes.W + 2.0 * half
		elif x < -half:
			x += Lanes.W + 2.0 * half
	elif x > Lanes.W - half:
		x = Lanes.W - half
		vx = minf(vx, 0.0)
	elif x < half:
		x = half
		vx = maxf(vx, 0.0)
	position.x = x
	sway += (clampf(vx / 300.0, -1.0, 1.0) * 0.2 - sway) * (1.0 - exp(-4.0 * dt))
	rotation = sway
	scale = Vector2(s(), s())
	var on := heat > 0.04
	if on or _flame_on:   # (the node's own transform moves the whole balloon: no redraw needed)
		flame.queue_redraw()
	_flame_on = on

## Sideways speed: exactly the wind of the layer the balloon is in (0 on the ground and while anchored); blended
## over wind_blend_time only when the layer changes.
func _sideways(dt: float, anchored: bool) -> void:
	var lane := -1 if on_ground else lanes.lane_of(position.y)
	if anchored:
		vx = 0.0
		_wind_lane = -2
		return
	if lane != _wind_lane:
		_wind_lane = lane
		_wind_from = vx
		_blend_t = 0.0
	var target := 0.0 if lane < 0 else lanes.lane_wind[lane]
	_blend_t += dt
	var bt := maxf(Tuning.wind_blend_time, 0.001)
	if _blend_t >= bt:
		vx = target
	else:
		var a := _blend_t / bt
		vx = lerpf(_wind_from, target, a * a * (3.0 - 2.0 * a))

# ---------------------------------------------------------------------------------------------------------
# Propane, tools
# ---------------------------------------------------------------------------------------------------------

## Propane the movement since the last call cost; `climb_mult` < 1 (thin air) makes it cost more.
func take_fuel_cost(climb_mult: float) -> float:
	var c := float(paid_hops) * Tuning.hop_fuel + climbed_px * 0.01 * Tuning.climb_burn_per_100px
	paid_hops = 0
	climbed_px = 0.0
	return c / maxf(climb_mult, 0.2)

## Sandbag: a free climb: one layer (lanes) or Tuning.sandbag_px (drag, steady). False if there is nowhere to go.
func use_sandbag() -> bool:
	if scheme == LANES:
		if not can_hop(1) or anchor_left > 0.0:
			return false
		if hopping:
			_free_hops += 1
			queued_dir = 1
			return true
		_free_hops += 1
		var ok := _start_hop(1, true)
		if not ok:
			_free_hops -= 1
		return ok
	if position.y <= ceiling_y + 1.0:
		return false
	_burst_px += minf(Tuning.sandbag_px, maxf(position.y - ceiling_y, 0.0))
	on_ground = false
	return true

func use_anchor() -> void:
	anchor_left = Tuning.anchor_seconds

func use_vent() -> void:
	vent_left = Tuning.vent_seconds

## Does this scheme offer tool t (0 sandbag, 1 anchor, 2 quick vent)? Quick Vent only exists for the steady scheme:
## lanes already drops a layer per tap and drag can move down as fast as the finger.
static func tool_fits(sch: int, t: int) -> bool:
	return t != 2 or sch == STEADY

## Speed of the descent, px/s (0 if rising).
func descent_speed() -> float:
	if scheme == LANES:
		return 0.0   # a hop is a controlled move: touching down on the deck from one is always gentle
	return maxf(-rise, 0.0)

## The hull of the airship pushed the balloon back out underneath it.
func bump_down() -> void:
	hopping = false
	queued_dir = 0
	drag_target = position.y
	_burst_px = 0.0

# ---------------------------------------------------------------------------------------------------------
# Drift preview: where the balloon will be over the next Tuning.preview_seconds if the input stays as it is
# ---------------------------------------------------------------------------------------------------------

## Fills `pred` (PRED_N points). Allocation-free.
func predict(hold: bool, fuel_ok: bool) -> void:
	var total := Tuning.preview_seconds
	var dt := total / float(PRED_N)
	var x := position.x
	var vxp := vx
	var half := WIDTH * 0.5 * s()
	var fy := floor_y()
	var hq := hopping
	var ht := hop_t
	var hy0 := hop_y0
	var hy1 := hop_y1
	var qd := queued_dir
	var cur_y := position.y
	var anchored := anchor_left > 0.0
	for k in PRED_N:
		var t := dt * float(k + 1)
		var y := cur_y
		if anchored and t <= anchor_left:
			y = position.y
		else:
			match scheme:
				LANES:
					if hq:
						var dur := maxf(Tuning.hop_time, 0.02)
						var p := (ht + dt) / dur
						ht += dt
						if p >= 1.0:
							y = hy1
							hq = false
							if qd != 0:   # the queued tap: the next hop starts where this one ended
								hq = true
								ht = 0.0
								hy0 = hy1
								hy1 = level_y(clampi(nearest_level(hy0) + qd, -1, lanes.n_lanes))
								qd = 0
						else:
							y = lerpf(hy0, hy1, p * p * (3.0 - 2.0 * p))
				DRAG:
					var want := drag_target if fuel_ok else maxf(drag_target, cur_y)
					y = cur_y + (want - cur_y) * (1.0 - exp(-Tuning.drag_smooth * dt))
				STEADY:
					y = cur_y - Tuning.steady_climb_speed * dt if (hold and fuel_ok) else cur_y + Tuning.steady_sink_speed * dt
			y = clampf(y, maxf(ceiling_y, -1.0e5), fy)
		cur_y = y
		var lane := -1 if y >= fy - 0.01 else lanes.lane_of(y)
		var target := 0.0 if (lane < 0 or (anchored and t <= anchor_left)) else lanes.lane_wind[lane]
		vxp = lerpf(vxp, target, minf(dt / maxf(Tuning.wind_blend_time, 0.001), 1.0))
		x += vxp * dt
		if Tuning.edge_wrap:
			if x > Lanes.W + half:
				x -= Lanes.W + 2.0 * half
			elif x < -half:
				x += Lanes.W + 2.0 * half
		pred[k] = Vector2(x, y)

## Centre of hit circle i, and its radius (scaled and made forgiving).
func hit_pos(i: int) -> Vector2:
	return position + Vector2(0.0, HIT[i][0] * s())

func hit_radius(i: int) -> float:
	return HIT[i][1] * s() * Tuning.hit_forgiveness

func _draw() -> void:
	body_draws += 1
	BalloonArt.shared().draw_body(self, env_id, basket_id, pass_id, 4.0 / s())

## The time the flame flickers with.
func flicker_time() -> float:
	return _t
