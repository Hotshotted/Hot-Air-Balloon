class_name Balloon
extends Node2D
## The player's balloon: only altitude is controlled. Holding fires the burner (the air heats up over heat_rate, and the
## climb speed follows the heat with buoyancy_lag), releasing lets it cool and sink slowly. Climb and sink speeds are
## capped (max_climb_speed / max_sink_speed). Sideways it moves at exactly the wind of the layer it is in (blending over
## wind_blend_time when it changes layer). Drawn from pre-built polygons: nothing is allocated while playing.

const WIDTH := 84.0            # design width (before Tuning.balloon_scale)
const BASKET_BOTTOM := 84.0    # design distance from the envelope centre (the node origin) to the basket's base
## Hit circles in design units: [dy from the origin, radius]. Envelope top, envelope bottom, basket.
const HIT := [[-10.0, 38.0], [24.0, 22.0], [72.0, 13.0]]
const PRED_N := 12             # points of each drift-preview line
const PRED_SUB := 8            # simulation steps between two points

var lanes: Lanes        # the wind layers (Main sets it): the wind of the balloon's layer comes from here
var rise := 0.0        # vertical speed, px/s, positive = up
var vx := 0.0          # sideways speed, px/s
var heat := 0.0        # 0..1, how hot the air is
var burning := false   # the burner is firing right now
var on_ground := true
var sway := 0.0
var _t := 0.0

var flame: Node2D       # the burner flame: its own tiny node, redrawn only while it burns
var _flame_on := false
var anchor_left := 0.0   # Anchor (Sahara): seconds of no sideways drift left
var vent_left := 0.0     # Quick Vent (Himalayas): seconds of strong descent left
var boost_left := 0.0    # Sandbag (Alps): seconds of full climb push left
var ceiling_y := -100000.0   # the balloon cannot rise above this (a leg whose goal is not met yet)
var body_draws := 0     # times the body has been drawn (only on a cosmetics change or a fresh leg)
var env_id := 0        # equipped cosmetics (purely visual)
var basket_id := 0
var pass_id := 0
# --- wind ---
var _wind_lane := -2
var _wind_from := 0.0
var _blend_t := 99.0
# --- drift preview: the path if the burner keeps firing, and if it is released now ---
var pred_burn := PackedVector2Array()
var pred_rel := PackedVector2Array()

func _ready() -> void:
	flame = BalloonFlame.new()
	flame.balloon = self
	add_child(flame)
	pred_burn.resize(PRED_N)
	pred_rel.resize(PRED_N)
	reset()

func s() -> float:
	return Tuning.balloon_scale

## Resting y (envelope centre) when the basket sits on the ground.
func floor_y() -> float:
	return Lanes.GROUND_Y - BASKET_BOTTOM * s()

## Back on the ground in the middle, cold and still.
func reset() -> void:
	rise = 0.0
	vx = 0.0
	heat = 0.0
	anchor_left = 0.0
	vent_left = 0.0
	boost_left = 0.0
	ceiling_y = -100000.0
	burning = false
	on_ground = true
	sway = 0.0
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

## Teleport to height y at rest (tests).
func set_altitude(y: float) -> void:
	position.y = minf(y, floor_y())
	rise = 0.0
	on_ground = position.y >= floor_y()

## One vertical-speed step shared by step() and the preview: the speed the heat asks for, lagged, capped.
func _next_rise(r: float, h: float, venting: bool, boosting: bool, lift: float, climb_mult: float, dt: float) -> float:
	var target := lerpf(-Tuning.sink_speed, Tuning.climb_speed * climb_mult, h) + lift
	if boosting:   # Sandbag: a push to the full climb speed
		target = Tuning.max_climb_speed
	if venting:   # Quick Vent: dump the hot air, a strong descent
		target = -Tuning.sink_speed * Tuning.vent_mult
	target = clampf(target, -Tuning.max_sink_speed, Tuning.max_climb_speed)
	r += (target - r) * (1.0 - exp(-(Tuning.buoyancy_lag * (2.0 if venting else 1.0)) * dt))
	return clampf(r, -Tuning.max_sink_speed, Tuning.max_climb_speed)

## Advance by dt. `hold`: the player is holding; `fuel_left`: the tank is not empty.
## `lift`: extra rise from a thermal (px/s); `climb_mult`: share of the climb speed the burner keeps (thin air).
func step(dt: float, hold: bool, fuel_left: bool, lift: float = 0.0, climb_mult: float = 1.0) -> void:
	_t += dt
	var anchored := anchor_left > 0.0
	if anchored:
		anchor_left = maxf(anchor_left - dt, 0.0)
	var venting := vent_left > 0.0
	if venting:
		vent_left = maxf(vent_left - dt, 0.0)
	burning = hold and fuel_left and not venting
	heat = move_toward(heat, 1.0 if burning else 0.0, (Tuning.heat_rate if burning else Tuning.cool_rate) * dt)
	rise = _next_rise(rise, heat, venting, boost_left > 0.0, lift, climb_mult, dt)
	if boost_left > 0.0:
		boost_left = maxf(boost_left - dt, 0.0)
	var y := position.y - rise * dt
	if y < ceiling_y:
		y = ceiling_y
		rise = minf(rise, 0.0)
	var fy := floor_y()
	on_ground = y >= fy
	if on_ground:
		y = fy
		rise = maxf(rise, 0.0)
	position.y = y
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

## Player tools. Sandbag: an instant climb burst. Anchor: no sideways drift. Quick Vent: a strong descent burst.
func use_sandbag() -> void:
	rise = clampf(maxf(rise, 0.0) + Tuning.sandbag_boost, -Tuning.max_sink_speed, Tuning.max_climb_speed)
	boost_left = Tuning.sandbag_seconds
	on_ground = false

func use_anchor() -> void:
	anchor_left = Tuning.anchor_seconds

func use_vent() -> void:
	vent_left = Tuning.vent_seconds

## Speed of the descent, px/s (0 if rising).
func descent_speed() -> float:
	return maxf(-rise, 0.0)

# ---------------------------------------------------------------------------------------------------------
# Drift preview: where the balloon will be over the next Tuning.preview_seconds if it keeps burning / lets go now
# ---------------------------------------------------------------------------------------------------------

## Fills pred_burn and pred_rel (PRED_N points each). `fuel_left`: the tank is not empty. Allocation-free.
func predict(fuel_left: bool) -> void:
	_predict(true and fuel_left, pred_burn)
	_predict(false, pred_rel)

func _predict(burn: bool, out: PackedVector2Array) -> void:
	var dt := Tuning.preview_seconds / float(PRED_N * PRED_SUB)
	var x := position.x
	var y := position.y
	var r := rise
	var h := heat
	var vxp := vx
	var half := WIDTH * 0.5 * s()
	var fy := floor_y()
	var t := 0.0
	for k in PRED_N:
		for q in PRED_SUB:
			t += dt
			var venting := t <= vent_left
			var burning_now := burn and not venting
			h = move_toward(h, 1.0 if burning_now else 0.0, (Tuning.heat_rate if burning_now else Tuning.cool_rate) * dt)
			r = _next_rise(r, h, venting, t <= boost_left, lanes.thermal_lift(x), lanes.climb_mult_at(y), dt)
			y -= r * dt
			if y < ceiling_y:
				y = ceiling_y
				r = minf(r, 0.0)
			if y >= fy:
				y = fy
				r = maxf(r, 0.0)
			var anchored := t <= anchor_left
			var lane := -1 if y >= fy else lanes.lane_of(y)
			var target := 0.0 if (lane < 0 or anchored) else lanes.lane_wind[lane]
			vxp = 0.0 if anchored else lerpf(vxp, target, minf(dt / maxf(Tuning.wind_blend_time, 0.001), 1.0))
			x += vxp * dt
			if Tuning.edge_wrap:
				if x > Lanes.W + half:
					x -= Lanes.W + 2.0 * half
				elif x < -half:
					x += Lanes.W + 2.0 * half
		out[k] = Vector2(x, y)

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
