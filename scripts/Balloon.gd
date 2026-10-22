class_name Balloon
extends Node2D
## The player's balloon: only altitude is controlled. Holding fires the burner (the air heats up over heat_rate, and the
## climb speed follows the heat with buoyancy_lag), releasing lets it cool and sink slowly. Climb and sink speeds are
## capped (max_climb_speed / max_sink_speed). Sideways it moves at exactly the wind of the layer it is in (blending over
## wind_blend_time when it changes layer). Drawn from pre-built polygons: nothing is allocated while playing.

const WIDTH := 88.0            # design width (before Tuning.balloon_scale)
const BASKET_BOTTOM := 84.0    # design distance from the envelope centre (the node origin) to the basket's base
## Hit circles in design units: [dy from the origin, radius]. Envelope top, envelope bottom, basket.
const HIT := [[-2.0, 26.0], [32.0, 16.0], [72.0, 10.0]]
const NECK_Y := 48.0           # design y of the envelope's neck: the envelope leans about it
const BASKET_PIVOT := 52.0     # design y where the basket hangs: it swings about it
const PRED_N := 12             # points of each drift-preview line
const PRED_SUB := 8            # simulation steps between two points

var lanes: Lanes        # the wind layers (Main sets it): the wind of the balloon's layer comes from here
var rise := 0.0        # vertical speed, px/s, positive = up
var vx := 0.0          # sideways speed, px/s
var heat := 0.0        # 0..1, how hot the air is
var burning := false   # the burner is firing right now
var on_ground := true
var _t := 0.0

# --- the rig: the envelope (leans, glows), the swinging basket with its flame and streamers, the ropes between them ---
var env_node: BalloonEnvelope
var basket_node: BalloonBasket
var ropes: BalloonRopes
var flame: BalloonFlame
var streamers: BalloonStreamers
var passenger: BalloonPassenger
var _env_mat: ShaderMaterial
var halo: Sprite2D      # the warm halo behind a hot envelope
var _flame_on := false
var air := 0.0           # the temperature of the air in the envelope, 0..1: it follows `heat` up fast and cools slowly
var flame_power := 0.0   # burner output, 0..1 (what the flame draws)
var sputter := 1.0       # 1 = steady; below 1 while the burner is lighting
var lean := 0.0          # the envelope's lean (rad) with the wind at its altitude
var swing := 0.0         # the basket's swing (rad) on its ropes
var wind_alt := 0.0      # the wind at the balloon's exact altitude (display)
var _lean_v := 0.0
var pass_look := 0.0     # the passenger's head turn -1..1
var pass_cheer := 0.0    # 0..1 while cheering
var pass_sad := 0.0      # 0..1 after a crash
var cheer_left := 0.0
var deflating := false   # a crash: the envelope empties and the balloon sinks (no collisions any more)
var deflate_t := 0.0
var _swing_v := 0.0
var _vx_prev := 0.0
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
	halo = Sprite2D.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1.0, 0.79, 0.2, 0.6), Color(1.0, 0.79, 0.2, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 1.0])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	halo.texture = gt
	halo.modulate.a = 0.0
	add_child(halo)
	ropes = BalloonRopes.new()
	ropes.balloon = self
	add_child(ropes)
	env_node = BalloonEnvelope.new()
	env_node.balloon = self
	env_node.position = Vector2(0, NECK_Y)
	_env_mat = ShaderMaterial.new()
	_env_mat.shader = load("res://shaders/balloon_env.gdshader")
	env_node.material = _env_mat
	add_child(env_node)
	basket_node = BalloonBasket.new()
	basket_node.balloon = self
	basket_node.position = Vector2(0, BASKET_PIVOT)
	add_child(basket_node)
	passenger = BalloonPassenger.new()
	passenger.balloon = self
	basket_node.add_child(passenger)
	streamers = BalloonStreamers.new()
	streamers.balloon = self
	basket_node.add_child(streamers)
	flame = BalloonFlame.new()
	flame.balloon = self
	basket_node.add_child(flame)
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
	air = 0.0
	flame_power = 0.0
	sputter = 1.0
	lean = 0.0
	swing = 0.0
	wind_alt = 0.0
	_lean_v = 0.0
	_swing_v = 0.0
	_vx_prev = 0.0
	pass_look = 0.0
	pass_cheer = 0.0
	pass_sad = 0.0
	cheer_left = 0.0
	deflating = false
	deflate_t = 0.0
	env_node.scale = Vector2.ONE
	_wind_lane = -2
	_blend_t = 99.0
	env_id = Save.equipped(Cosmetics.ENV)
	basket_id = Save.equipped(Cosmetics.BASKET)
	pass_id = Save.equipped(Cosmetics.PASSENGER)
	position = Vector2(Lanes.W * 0.5, floor_y())
	rotation = 0.0
	scale = Vector2(s(), s())
	redraw_body()   # the envelope, passenger and basket: only now (a cosmetics change or a fresh leg)
	_update_rig(0.0)

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
	scale = Vector2(s(), s())
	_update_rig(dt)

## Redraw the envelope and the basket (their cosmetics changed, or a fresh leg).
func redraw_body() -> void:
	env_node.queue_redraw()
	basket_node.queue_redraw()
	passenger.queue_redraw()

## Pre-warm: show the balloon fully hot, burning, leaning and swinging so every shader and node draws once behind the splash.
func warm_visuals() -> void:
	heat = 1.0
	air = 1.0
	burning = true
	wind_alt = 150.0
	_update_rig(1.0 / 60.0)
	lean = 0.2
	swing = 0.25
	basket_node.rotation = swing
	env_node.rotation = lean
	burning = false

## The readable physics, every frame: the air's heat, the flame, the envelope's lean and the basket's swing. Nothing is
## drawn here except the small per-frame nodes (flame, ropes, streamers); the envelope's glow is a shader uniform.
func _update_rig(dt: float) -> void:
	# the air in the envelope: heats at the burner's pace, cools slowly (so it is still hot while the balloon coasts up)
	air = move_toward(air, heat, (6.0 if heat > air else 0.9) * dt)
	# the burner: its output follows the heat; while it is lighting (heat still low) it sputters
	flame_power = heat if (burning or heat > 0.04) else 0.0
	sputter = 1.0
	if burning and heat < 0.6:
		sputter = 0.35 + 0.65 * (1.0 if sin(_t * 61.0) * sin(_t * 23.0 + 1.0) >= 0.0 else 0.0)
	wind_alt = lanes.wind_smooth(position.y) if lanes != null else 0.0
	if dt > 0.0:
		var h := minf(dt, 0.05)
		# lean: toward the wind at this altitude, and with the air that is not yet moving with it
		var lean_target := clampf(wind_alt / 260.0 * 0.24 + (wind_alt - vx) / 170.0 * 0.2, -0.34, 0.34)
		_lean_v += ((lean_target - lean) * 49.0 - 2.0 * 0.72 * 7.0 * _lean_v) * h
		lean += _lean_v * h
		# swing: a pendulum on its ropes, shaken by the sideways acceleration (a faster or reversed layer), settling in ~1 s
		var ax := (vx - _vx_prev) / dt
		_vx_prev = vx
		var sw_target := clampf(-ax * 0.00032, -0.7, 0.7)
		_swing_v += ((sw_target - swing) * 36.0 - 2.0 * 0.35 * 6.0 * _swing_v) * h
		swing = clampf(swing + _swing_v * h, -0.7, 0.7)
	_update_passenger(dt)
	_env_mat.set_shader_parameter("air", air)
	halo.modulate.a = clampf((air - 0.15) / 0.85, 0.0, 1.0)
	halo.scale = Vector2.ONE * (2.0 * (62.0 + 40.0 * air) / 128.0)
	env_node.rotation = lean
	basket_node.rotation = swing
	ropes.queue_redraw()
	streamers.queue_redraw()
	if flame_power > 0.04 or _flame_on:
		flame.queue_redraw()
	_flame_on = flame_power > 0.04

## The passenger: glances left and right now and then, cheers after a landing, droops after a crash.
func _update_passenger(dt: float) -> void:
	if pass_id == 0:
		return
	cheer_left = maxf(cheer_left - dt, 0.0)
	var cheer_to := minf(cheer_left * 2.5, 1.0) if cheer_left > 0.0 else 0.0
	pass_cheer = move_toward(pass_cheer, cheer_to, 8.0 * dt)
	pass_sad = move_toward(pass_sad, 1.0 if deflating else 0.0, 2.0 * dt)
	var glance := sin(_t * 0.9) * 0.6 + sin(_t * 2.3 + 1.0) * 0.4
	pass_look = clampf(glance * (1.0 - pass_cheer) * (1.0 - pass_sad * 0.6) + (wind_alt / 400.0) * 0.4, -1.0, 1.0)
	passenger.pose_changed()

## The passenger cheers for `secs` seconds.
func cheer(secs: float = 1.2) -> void:
	cheer_left = secs

## A crash: the envelope empties and flutters, the basket drops, the passenger droops. Main runs `deflate_step`.
func start_deflate() -> void:
	deflating = true
	deflate_t = 0.0
	burning = false
	heat = 0.0
	flame_power = 0.0
	rise = minf(rise, 0.0)

## Between legs and on the failed screen the balloon is not simulated: only its passenger / deflate animation runs.
func idle_step(dt: float) -> void:
	_t += dt
	if deflating:
		deflate_step(dt)
	elif visible:
		_update_passenger(dt)

func deflate_step(dt: float) -> void:
	if not deflating:
		return
	deflate_t += dt
	var k := clampf(deflate_t / 0.9, 0.0, 1.0)
	air = move_toward(air, 0.0, 3.0 * dt)
	rise = maxf(rise - 520.0 * dt, -420.0)   # falling, faster and faster
	position.y = minf(position.y - rise * dt, floor_y())
	position.x += vx * 0.4 * dt
	var flutter := sin(deflate_t * 16.0) * 0.16 * (1.0 - k)
	env_node.scale = Vector2(1.0 + 0.12 * k + flutter, 1.0 - 0.5 * k)
	env_node.rotation = lean + sin(deflate_t * 9.0) * 0.2 * (1.0 - k)
	basket_node.rotation = swing + sin(deflate_t * 7.0 + 1.0) * 0.15 * (1.0 - k)
	_env_mat.set_shader_parameter("air", air)
	halo.modulate.a = clampf((air - 0.15) / 0.85, 0.0, 1.0)
	flame.queue_redraw()
	_update_passenger(dt)
	ropes.queue_redraw()

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

## The time the flame flickers with.
func flicker_time() -> float:
	return _t
