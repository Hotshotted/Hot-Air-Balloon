class_name Balloon
extends Node2D
## The player's balloon: only altitude is controlled, in hops between wind layers, and it does exactly what the input says
## (no buoyancy, no momentum). A swipe up hops one layer up, a swipe down one layer down. A hop takes Tuning.hop_time with
## smooth easing and the balloon stops dead (a slight bob settles it); a second swipe during a hop queues at most one more.
## Each hop UP costs Tuning.hop_fuel propane (free inside a thermal and from a Sandbag); going down is free.
## Sideways it moves at exactly the wind of the layer it is in (blending over Tuning.wind_blend_time on a layer change).
## Drawn from pre-built polygons: nothing is allocated while playing.

const WIDTH := 84.0            # design width (before Tuning.balloon_scale)
const BASKET_BOTTOM := 84.0    # design distance from the envelope centre (the node origin) to the basket's base
## Hit circles in design units: [dy from the origin, radius]. Envelope top, envelope bottom, basket.
const HIT := [[-10.0, 38.0], [24.0, 22.0], [72.0, 13.0]]
const PRED_N := 12             # points of the drift preview

var lanes: Lanes        # the wind layers (Main sets it): the levels and the wind come from here
var rise := 0.0        # vertical speed, px/s, positive = up (measured from the actual movement)
var vx := 0.0          # sideways speed, px/s
var heat := 0.0        # 0..1: only the flame's look (a burst at every hop up)
var on_ground := true
var sway := 0.0
var _t := 0.0

var flame: Node2D       # the burner flame: its own tiny node, redrawn only while it burns
var _flame_on := false
var anchor_left := 0.0   # Anchor (Sahara): seconds of holding position left
var ceiling_y := -100000.0   # the balloon cannot rise above this (a leg whose goal is not met yet)
var body_draws := 0     # times the body has been drawn (only on a cosmetics change or a fresh leg)
var env_id := 0        # equipped cosmetics (purely visual)
var basket_id := 0
var pass_id := 0

# --- propane the movement cost since Main last took it ---
var paid_hops := 0       # hops up that were not free
var hop_event := 0       # +1 a hop up just began, -1 a hop down (Main reads and clears it: flame burst, puff, sound)
# --- the hop in progress ---
var hopping := false
var hop_t := 0.0
var hop_y0 := 0.0
var hop_y1 := 0.0
var hop_dir := 0
var queued_dir := 0      # a swipe during a hop: the next hop (at most one)
var _free_hops := 0      # Sandbag: hops up that cost nothing
var _bob_t := 99.0       # time since the balloon settled into a layer (a slight bob)
var _bob_y := 0.0        # the bob's offset in position.y right now
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

## Resting y (envelope centre) when the basket sits on the ground.
func floor_y() -> float:
	return Lanes.GROUND_Y - BASKET_BOTTOM * s()

## Back on the ground in the middle, still.
func reset() -> void:
	rise = 0.0
	vx = 0.0
	heat = 0.0
	anchor_left = 0.0
	ceiling_y = -100000.0
	on_ground = true
	sway = 0.0
	paid_hops = 0
	hop_event = 0
	hopping = false
	queued_dir = 0
	_free_hops = 0
	_bob_t = 99.0
	_bob_y = 0.0
	_wind_lane = -2
	_blend_t = 99.0
	env_id = Save.equipped(Cosmetics.ENV)
	basket_id = Save.equipped(Cosmetics.BASKET)
	pass_id = Save.equipped(Cosmetics.PASSENGER)
	position = Vector2(Lanes.W * 0.5, floor_y())
	rotation = 0.0
	scale = Vector2(s(), s())
	queue_redraw()   # the body: only now (a cosmetics change or a fresh leg)
	flame.queue_redraw()

## Teleport to height y (tests): no hop in progress, no bob.
func set_altitude(y: float) -> void:
	position.y = minf(y, floor_y())
	_bob_y = 0.0
	_bob_t = 99.0
	hopping = false
	queued_dir = 0
	on_ground = position.y >= floor_y()

## The height without the settling bob.
func rest_y() -> float:
	return position.y - _bob_y

# ---------------------------------------------------------------------------------------------------------
# Levels: the ground, the centre of every wind layer, and the goal / the sky above the top layer
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

## How many layers (0, 1 or up to `want`) the balloon can move in direction dir right now (the ground, the top and the
## ceiling of an unfinished goal stop it).
func hop_room(dir: int, want: int) -> int:
	var from := nearest_level(rest_y())
	var n := 0
	for k in range(1, want + 1):
		var to := from + dir * k
		if to < -1 or to > lanes.n_lanes or level_y(to) < ceiling_y:
			break
		n = k
	return n

func can_hop(dir: int) -> bool:
	return hop_room(dir, 1) > 0

## A swipe (or a tool): hop `layers` layers up (dir +1) or down (-1) from the nearest level. Returns true if it did something
## (a hop began or was queued). `fuel_ok`: the tank is not empty. `free`: costs no propane (Sandbag).
func request_hop(dir: int, fuel_ok: bool, layers: int = 1, free: bool = false) -> bool:
	if anchor_left > 0.0:
		return false
	if hopping:
		if layers == 1 and not free:   # a swipe during a hop: queue at most one more
			queued_dir = dir
			return true
		hopping = false   # a tool during a hop: take over from where the balloon is now
		queued_dir = 0
	return _start_hop(dir, fuel_ok, layers, free)

func _start_hop(dir: int, fuel_ok: bool, layers: int, free: bool) -> bool:
	var k := hop_room(dir, layers)
	if k == 0:
		return false
	var from := nearest_level(rest_y())
	if dir > 0 and not free and lanes.thermal_lift(position.x) <= 0.0:
		if not fuel_ok:
			return false
		paid_hops += 1
	hopping = true
	hop_t = 0.0
	hop_y0 = rest_y()
	hop_y1 = level_y(from + dir * k)
	hop_dir = dir
	hop_event = dir
	if dir > 0:
		heat = 1.0
	_bob_t = 99.0
	_bob_y = 0.0
	return true

# ---------------------------------------------------------------------------------------------------------
# Step
# ---------------------------------------------------------------------------------------------------------

## Advance by dt. `fuel_ok`: the tank is not empty.
func step(dt: float, fuel_ok: bool) -> void:
	_t += dt
	var anchored := anchor_left > 0.0
	if anchored:
		anchor_left = maxf(anchor_left - dt, 0.0)
	var y0 := rest_y()
	var y := y0
	if hopping and not anchored:
		hop_t += dt
		var p := clampf(hop_t / maxf(Tuning.hop_time, 0.02), 0.0, 1.0)
		y = lerpf(hop_y0, hop_y1, p * p * (3.0 - 2.0 * p))
		if p >= 1.0:
			hopping = false
			_bob_t = 0.0   # settled: a slight bob
			if queued_dir != 0:
				var q := queued_dir
				queued_dir = 0
				_start_hop(q, fuel_ok, 1, false)
	if y < ceiling_y:
		y = ceiling_y
		if hopping and hop_dir > 0:
			hopping = false
	var fy := floor_y()
	on_ground = y >= fy - 0.01
	if on_ground:
		y = fy
	# the bob: a damped wobble after settling (it never moves the balloon off its layer in any way that matters)
	_bob_t += dt
	_bob_y = Tuning.bob_amp * exp(-_bob_t * Tuning.bob_decay) * sin(_bob_t * Tuning.bob_rate) if (not hopping and _bob_t < 2.0 and not on_ground) else 0.0
	position.y = y + _bob_y
	rise = (y0 - y) / dt if dt > 0.0 else 0.0
	heat = move_toward(heat, 0.0, 2.5 * dt)
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
	var lane := -1 if on_ground else lanes.lane_of(rest_y())
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

## Propane the hops since the last call cost; `climb_mult` < 1 (thin air) makes it cost more.
func take_fuel_cost(climb_mult: float) -> float:
	var c := float(paid_hops) * Tuning.hop_fuel
	paid_hops = 0
	return c / maxf(climb_mult, 0.2)

## Which hop event happened since the last call (+1 up, -1 down, 0 none).
func take_hop_event() -> int:
	var e := hop_event
	hop_event = 0
	return e

## Sandbag: an instant two-layer hop up that costs no propane (one layer if only one is left). False if there is no room.
func use_sandbag() -> bool:
	return request_hop(1, true, Tuning.tool_layers, true)

## Quick Vent: an instant two-layer drop (one layer if only one is left). False if there is no room.
func use_vent() -> bool:
	return request_hop(-1, true, Tuning.tool_layers, true)

## Anchor: no sideways drift (and no hopping) for Tuning.anchor_seconds, in the current layer.
func use_anchor() -> void:
	anchor_left = Tuning.anchor_seconds

## The hull of the airship pushed the balloon back out underneath it.
func bump_down() -> void:
	hopping = false
	queued_dir = 0

# ---------------------------------------------------------------------------------------------------------
# Drift preview: where the balloon will be over the next Tuning.preview_seconds if nothing more is tapped
# ---------------------------------------------------------------------------------------------------------

## Fills `pred` (PRED_N points). Allocation-free.
func predict() -> void:
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
	var cur_y := rest_y()
	var anchored := anchor_left > 0.0
	for k in PRED_N:
		var t := dt * float(k + 1)
		var y := cur_y
		if anchored and t <= anchor_left:
			y = rest_y()
		elif hq:
			var p := (ht + dt) / maxf(Tuning.hop_time, 0.02)
			ht += dt
			if p >= 1.0:
				y = hy1
				hq = false
				if qd != 0:   # the queued swipe: the next hop starts where this one ended
					hq = true
					ht = 0.0
					hy0 = hy1
					hy1 = level_y(clampi(nearest_level(hy0) + qd, -1, lanes.n_lanes))
					qd = 0
			else:
				y = lerpf(hy0, hy1, p * p * (3.0 - 2.0 * p))
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
