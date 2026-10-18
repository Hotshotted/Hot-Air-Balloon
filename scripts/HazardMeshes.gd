class_name HazardMeshes
extends RefCounted
## The meshes of every hazard and pickup, built once at start-up from the same low-poly designs the game always
## had (design units: origin at the shape's centre, y down; Lanes scales them per layer).
## Mesh ids: the hazard kinds 0-7 (Lanes.BIRD ... Lanes.GLIDER), VULTURE (a Sahara bird), then TANK and COIN.

const VULTURE := 8
const TANK := 9
const COIN := 10
const COUNT := 11

const C_KITE_A := Color(1.0, 0.8, 0.2)
const C_KITE_B := Color(0.95, 0.35, 0.55)
const C_BALLOON := Color(0.55, 0.36, 0.9)
const C_BALLOON_B := Color(0.35, 0.85, 0.8)
const C_DRONE := Color(0.32, 0.34, 0.42)
const C_TANK := Color(0.25, 0.85, 0.4)
const BEAK := Color(1.0, 0.8, 0.2)

static func build_all() -> Array:
	var meshes: Array = []
	meshes.append(_bird(Color(0.88, 0.27, 0.23), Color(0.7, 0.16, 0.2), Color(0.88, 0.27, 0.23)))   # BIRD
	meshes.append(_kite())
	meshes.append(_balloon())
	meshes.append(_drone())
	meshes.append(_bird(Color(0.5, 0.34, 0.18), Color(0.34, 0.22, 0.12), Color(0.96, 0.94, 0.9)))   # EAGLE
	meshes.append(_cable())
	meshes.append(_carpet())
	meshes.append(_glider())
	meshes.append(_bird(Color(0.62, 0.5, 0.34), Color(0.4, 0.3, 0.2), Color(0.85, 0.55, 0.5)))      # VULTURE
	meshes.append(_tank())
	meshes.append(_coin())
	return meshes

static func _bird(body: Color, wing: Color, head: Color) -> ArrayMesh:
	var m := ShapeMesh.new()
	m.poly([Vector2(-20, 1), Vector2(-40, -8), Vector2(-38, 8)], wing)
	m.poly([Vector2(-24, 2), Vector2(-14, -9), Vector2(8, -10), Vector2(20, -4), Vector2(22, 6), Vector2(8, 11), Vector2(-12, 10)], body)
	m.poly([Vector2(-8, -6), Vector2(12, -6), Vector2(36, -14), Vector2(10, -24)], wing, true, 1.0, 1.0)   # the flapping wing
	m.poly([Vector2(14, -14), Vector2(24, -14), Vector2(30, -7), Vector2(24, 0), Vector2(14, 0), Vector2(10, -7)], head)
	m.poly([Vector2(29, -10), Vector2(42, -5), Vector2(29, -2)], BEAK)
	m.circle(Vector2(22, -8), 3.2, Color.WHITE, false, 0.0, 0.0, 8)
	m.circle(Vector2(23, -8), 1.6, Color.BLACK, false, 0.0, 0.0, 6)
	return m.build()

static func _kite() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.poly([Vector2(0, -44), Vector2(0, 32), Vector2(-30, -4)], C_KITE_A)
	m.poly([Vector2(0, -44), Vector2(30, -4), Vector2(0, 32)], C_KITE_B)
	m.line(Vector2(-30, -4), Vector2(30, -4), 3.0, ShapeMesh.BLACK)
	var tail: Array = []
	var weights: Array = []
	for p in 5:
		tail.append(Vector2(0, 32.0 + float(p) * 11.0))
		weights.append(float(p) / 4.0)
	m.polyline(tail, 3.5, ShapeMesh.BLACK, 2.0, 0.0, weights)
	for p in [1, 3]:
		m.circle(tail[p], 5.0, C_KITE_B, false, 2.0, float(p) / 4.0, 6)
	return m.build()

static func _balloon() -> ArrayMesh:
	var m := ShapeMesh.new()
	var env: Array = []
	for deg in range(180, 361, 30):
		var a := deg_to_rad(float(deg))
		env.append(Vector2(cos(a) * 48.0, -12.0 + sin(a) * 46.0))
	env.append_array([Vector2(36, 14), Vector2(18, 34), Vector2(-18, 34), Vector2(-36, 14)])
	m.poly(env, C_BALLOON)
	var st: Array = []
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		st.append(Vector2(x, -12.0 - 46.0 * sqrt(1.0 - pow(x / 48.0, 2.0))))
	st.append(Vector2(9, 34))
	st.append(Vector2(-9, 34))
	m.poly(st, C_BALLOON_B)
	m.line(Vector2(-18, 34), Vector2(-11, 46), 3.5, ShapeMesh.BLACK)
	m.line(Vector2(18, 34), Vector2(11, 46), 3.5, ShapeMesh.BLACK)
	m.poly([Vector2(-13, 46), Vector2(13, 46), Vector2(11, 64), Vector2(-11, 64)], Color(0.55, 0.38, 0.22))
	return m.build()

static func _drone() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.line(Vector2(-26, -8), Vector2(-46, -18), 6.0, ShapeMesh.BLACK)
	m.line(Vector2(26, -8), Vector2(46, -18), 6.0, ShapeMesh.BLACK)
	m.line(Vector2(-18, 10), Vector2(-24, 18), 4.0, ShapeMesh.BLACK)
	m.line(Vector2(18, 10), Vector2(24, 18), 4.0, ShapeMesh.BLACK)
	m.line(Vector2(-66, -20), Vector2(-26, -20), 5.5, ShapeMesh.BLACK, 3.0, -46.0)   # rotors: they flicker about their centres
	m.line(Vector2(26, -20), Vector2(66, -20), 5.5, ShapeMesh.BLACK, 3.0, 46.0)
	m.poly([Vector2(-28, -6), Vector2(-20, -14), Vector2(20, -14), Vector2(28, -6), Vector2(20, 10), Vector2(-20, 10)], C_DRONE)
	m.circle(Vector2(14, -1), 5.0, Color(0.5, 0.85, 1.0), false, 0.0, 0.0, 8)
	m.circle(Vector2(-10, 2), 4.5, Color(1.0, 0.2, 0.2), false, 0.0, 0.0, 8)
	return m.build()

static func _cable() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.line(Vector2(0, -24), Vector2(0, -44), 4.0, ShapeMesh.BLACK)
	m.poly([Vector2(-30, -14), Vector2(-20, -24), Vector2(20, -24), Vector2(30, -14)], Color(0.3, 0.32, 0.38))
	m.poly([Vector2(-34, -14), Vector2(34, -14), Vector2(38, 24), Vector2(-38, 24)], Color(0.9, 0.25, 0.25))
	for wx in [-24.0, -6.0, 12.0]:
		m.rect(wx, -8.0, 14.0, 14.0, Color(0.75, 0.92, 1.0))
	m.circle(Vector2(0, -44), 6.0, Color(0.6, 0.62, 0.68), false, 0.0, 0.0, 8)
	return m.build()

static func _carpet() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.poly([Vector2(-52, -5), Vector2(52, -5), Vector2(52, 6), Vector2(-52, 6)], Color(0.75, 0.15, 0.35))
	m.line(Vector2(-46, 0), Vector2(46, 0), 3.0, Color(1.0, 0.82, 0.2))
	for fy in [-3.0, 3.0]:
		m.line(Vector2(-52, fy), Vector2(-62, fy), 2.5, ShapeMesh.BLACK)
		m.line(Vector2(52, fy), Vector2(62, fy), 2.5, ShapeMesh.BLACK)
	m.rect(-8.0, -17.0, 16.0, 12.0, Color(0.2, 0.5, 0.8))
	m.circle(Vector2(0, -23), 7.0, Color(0.95, 0.75, 0.55), false, 0.0, 0.0, 8)
	m.circle(Vector2(0, -27), 6.0, Color(0.95, 0.95, 0.9), false, 0.0, 0.0, 8)
	return m.build()

static func _glider() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.line(Vector2(-30, -8), Vector2(0, 24), 3.0, ShapeMesh.BLACK)
	m.line(Vector2(30, -8), Vector2(0, 24), 3.0, ShapeMesh.BLACK)
	m.poly([Vector2(-58, 0), Vector2(-44, -26), Vector2(0, -38), Vector2(44, -26), Vector2(58, 0), Vector2(30, -8), Vector2(-30, -8)], Color(0.95, 0.5, 0.15))
	m.poly([Vector2(-14, -36), Vector2(14, -36), Vector2(20, -8), Vector2(-20, -8)], Color(1.0, 0.95, 0.8))
	m.rect(-5.0, 28.0, 10.0, 16.0, Color(0.2, 0.4, 0.75))
	m.circle(Vector2(0, 22), 7.0, Color(0.95, 0.75, 0.55), false, 0.0, 0.0, 8)
	return m.build()

## A propane tank with a pulsing ring around it (drawn 1.25x: the instance scale).
static func _tank() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.outline_w = 3.0
	var ring: Array = []
	for i in 21:
		var a := TAU * float(i) / 20.0
		ring.append(Vector2(cos(a), sin(a)) * 34.0)
	m.polyline(ring, 3.0, Color(1, 1, 1, 0.45), 4.0)
	m.rect(-5.0, -25.0, 10.0, 9.0, Color(0.6, 0.62, 0.68))
	m.poly([Vector2(-12, -16), Vector2(12, -16), Vector2(15, -8), Vector2(15, 10), Vector2(10, 18), Vector2(-10, 18), Vector2(-15, 10), Vector2(-15, -8)], C_TANK)
	m.poly([Vector2(-15, -4), Vector2(15, -4), Vector2(15, 6), Vector2(-15, 6)], Color.WHITE)
	return m.build()

## A gold star coin that spins, with a pulsing ring.
static func _coin() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.outline_w = 3.0
	var ring: Array = []
	for i in 21:
		var a := TAU * float(i) / 20.0
		ring.append(Vector2(cos(a), sin(a)) * 36.0)
	m.polyline(ring, 3.0, Color(1.0, 0.95, 0.5, 0.45), 4.0)
	var star: Array = []
	for i in 10:
		var a := -PI * 0.5 + TAU * float(i) / 10.0
		star.append(Vector2(cos(a), sin(a)) * (27.0 if i % 2 == 0 else 12.0))
	m.poly(star, Color(1.0, 0.82, 0.15), true, 5.0)
	return m.build()
