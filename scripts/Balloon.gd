class_name Balloon
extends Node2D
## The player's balloon: only altitude is controlled. Holding fires the burner (the air heats up over
## heat_rate, and the climb speed follows the heat with buoyancy_lag), releasing lets it cool and sink
## slowly. Sideways it drifts with the wind of the layer it is in, again with a lag (wind_follow).
## Drawn from pre-built polygons: nothing is allocated while playing.

const WIDTH := 84.0            # design width (before Tuning.balloon_scale)
const BASKET_BOTTOM := 84.0    # design distance from the envelope centre (the node origin) to the basket's base
## Hit circles in design units: [dy from the origin, radius]. Envelope top, envelope bottom, basket.
const HIT := [[-10.0, 38.0], [24.0, 22.0], [72.0, 13.0]]

var rise := 0.0        # vertical speed, px/s, positive = up
var vx := 0.0          # sideways speed, px/s
var heat := 0.0        # 0..1, how hot the air is
var burning := false   # the burner is firing right now
var on_ground := true
var sway := 0.0
var _t := 0.0

var env_id := 0        # equipped cosmetics (purely visual)
var basket_id := 0
var pass_id := 0

func _ready() -> void:
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
	burning = false
	on_ground = true
	sway = 0.0
	env_id = Save.equipped(Cosmetics.ENV)
	basket_id = Save.equipped(Cosmetics.BASKET)
	pass_id = Save.equipped(Cosmetics.PASSENGER)
	position = Vector2(Lanes.W * 0.5, floor_y())
	rotation = 0.0
	scale = Vector2(s(), s())
	queue_redraw()

## Advance by dt. `hold`: the player is holding; `fuel_left`: the tank is not empty; `wind`: the wind of this layer.
## `lift`: extra rise from a thermal (px/s); `climb_mult`: share of the climb speed the burner keeps (thin air).
func step(dt: float, hold: bool, fuel_left: bool, wind: float, lift: float = 0.0, climb_mult: float = 1.0) -> void:
	_t += dt
	burning = hold and fuel_left
	heat = move_toward(heat, 1.0 if burning else 0.0, (Tuning.heat_rate if burning else Tuning.cool_rate) * dt)
	var target := lerpf(-Tuning.sink_speed, Tuning.climb_speed * climb_mult, heat) + lift
	rise += (target - rise) * (1.0 - exp(-Tuning.buoyancy_lag * dt))
	var y := position.y - rise * dt
	var fy := floor_y()
	on_ground = y >= fy
	if on_ground:
		y = fy
		rise = maxf(rise, 0.0)
	# Sideways: tethered on the ground, otherwise follows the wind with a lag.
	vx += ((0.0 if on_ground else wind) - vx) * (1.0 - exp(-(8.0 if on_ground else Tuning.wind_follow) * dt))
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
	position = Vector2(x, y)
	sway += (clampf(vx / 300.0, -1.0, 1.0) * 0.2 - sway) * (1.0 - exp(-4.0 * dt))
	rotation = sway
	scale = Vector2(s(), s())
	queue_redraw()

## Centre of hit circle i, and its radius (scaled and made forgiving).
func hit_pos(i: int) -> Vector2:
	return position + Vector2(0.0, HIT[i][0] * s())

func hit_radius(i: int) -> float:
	return HIT[i][1] * s() * Tuning.hit_forgiveness

func _draw() -> void:
	BalloonArt.shared().draw(self, env_id, basket_id, pass_id, heat, _t, 4.0 / s())
