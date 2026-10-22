class_name HazardMeshes
extends RefCounted
## The meshes of every hazard and pickup, built once at start-up from the same low-poly designs the game always
## had (design units: origin at the shape's centre, y down; Lanes scales them per layer).
## Mesh ids: the hazard kinds 0-8 (Lanes.BIRD ... Lanes.GOOSE), VULTURE (a Sahara bird), then the pickups and goal objects.

## (the kinds 0-8 are Lanes.BIRD ... Lanes.GOOSE)
const GOOSE := 8
const VULTURE := 9
const TANK := 10
const COIN := 11
const STAR := 12      # a Star Collect star
const MARKER := 13    # the pulsing ring on the active mooring platform
const AIRSHIP := 14
const COUNT := 15

const INK := Color(0.039, 0.063, 0.125)
const BEAK := Color("ffc933")
const GONDOLA_TOP := 86.0   # the gondola's hanger reaches this far above its centre: the cable runs there (Storybook Sky)

static func build_all() -> Array:
	var meshes: Array = []
	meshes.append(_bird(Color("e8453c"), Color("c0282f"), Color("e8453c")))   # BIRD
	meshes.append(_kite())
	meshes.append(_balloon())
	meshes.append(_drone())
	meshes.append(_eagle())
	meshes.append(_cable())
	meshes.append(_carpet())
	meshes.append(_glider())
	meshes.append(_geese())
	meshes.append(_bird(Color("c9a468"), Color("8a6a3a"), Color("e0a090")))      # VULTURE
	meshes.append(_tank())
	meshes.append(_coin())
	meshes.append(_star())
	meshes.append(_marker())
	meshes.append(_airship())
	return meshes

## The animation id of a wing that flaps about the shoulder (x, y) in the mesh's final units (see hazard.gdshader).
static func _wing(sy: float, mirror: bool) -> float:
	return (8.0 if mirror else 7.0) + clampf((sy + 200.0) / 400.0, 0.01, 0.99)

static func _bird(body: Color, wing: Color, head: Color) -> ArrayMesh:
	var m := ShapeMesh.new()
	m.k = 2.0
	m.poly([Vector2(-20, 1), Vector2(-40, -8), Vector2(-38, 8)], wing, false)
	m.poly([Vector2(-24, 2), Vector2(-14, -9), Vector2(8, -10), Vector2(20, -4), Vector2(22, 6), Vector2(8, 11), Vector2(-12, 10)], body, false)
	m.poly([Vector2(-8, -6), Vector2(12, -6), Vector2(36, -14), Vector2(10, -24)], wing, false, _wing(-6.0 * 2.0, false), 2.0 * 2.0)   # the flapping wing
	m.poly([Vector2(14, -14), Vector2(24, -14), Vector2(30, -7), Vector2(24, 0), Vector2(14, 0), Vector2(10, -7)], head, false)
	m.poly([Vector2(29, -10), Vector2(42, -5), Vector2(29, -2)], BEAK, false)
	m.circle(Vector2(22, -8), 3.4, Color.WHITE, false, 0.0, 0.0, 8)
	m.circle(Vector2(23, -8), 1.7, INK, false, 0.0, 0.0, 6)
	return m.build()

static func _eagle() -> ArrayMesh:
	var m := ShapeMesh.new()
	var o := Vector2(-40.0, -22.0)   # symbol (40, 22) is the centre
	var sc := 2.8
	var shoulder_y := (24.0 - 22.0) * sc
	m.fill_path("M2 18C14 8 28 10 36 20L38 28L30 28C22 22 14 20 2 18Z", Color("6b4a2e"), o, sc, _wing(shoulder_y, false), (37.0 - 40.0) * sc)
	m.fill_path("M44 20C52 10 62 6 78 14C64 16 54 22 50 28L42 28Z", Color("5a3d24"), o, sc, _wing(shoulder_y, true), (43.0 - 40.0) * sc)
	m.fill_path("M36 28L44 28L40 38Z", Color("5a3d24"), o, sc)
	m.poly(Array(SvgArt.ellipse((Vector2(40, 24) + o) * sc, 9.0 * sc, 7.0 * sc, 0.0, 14)), Color("6b4a2e"), false)
	m.circle((Vector2(40, 20) + o) * sc, 6.0 * sc, Color.WHITE, false, 0.0, 0.0, 12)
	m.fill_path("M44 20L50 22L44 24Z", BEAK, o, sc)
	m.circle((Vector2(42, 19) + o) * sc, 1.3 * sc, INK, false, 0.0, 0.0, 6)
	return m.build()

static func _kite() -> ArrayMesh:
	var m := ShapeMesh.new()
	var o := Vector2(-25.0, -29.0)
	var sc := 2.3
	m.fill_path("M25 2L46 26L25 56L4 26Z", Color("ff5c4d"), o, sc)
	m.fill_path("M25 2L46 26L25 56L25 2Z", Color("e0483a"), o, sc)
	m.line((Vector2(25, 2) + o) * sc, (Vector2(25, 56) + o) * sc, 4.0, Color(1, 1, 1, 0.7))
	m.line((Vector2(4, 26) + o) * sc, (Vector2(46, 26) + o) * sc, 4.0, Color(1, 1, 1, 0.7))
	var tail: Array = []
	var weights: Array = []
	var pts: PackedVector2Array = SvgArt.path("M25 56C20 64 30 70 25 78C20 84 26 88 24 90", o, sc)[0]
	for i in pts.size():
		tail.append(pts[i])
		weights.append(float(i) / float(pts.size() - 1))
	m.polyline(tail, 3.0, Color(INK, 0.55), 2.0, 0.0, weights)
	for q in [Vector2(23, 64), Vector2(27, 76)]:   # bows on the tail
		var c: Vector2 = (q + o) * sc
		m.poly([c + Vector2(-9, -8), c + Vector2(10, -2), c + Vector2(-9, 8)], BEAK, false, 2.0, 0.55)
	return m.build()

static func _balloon() -> ArrayMesh:
	var m := ShapeMesh.new()
	var o := Vector2(-50.0, -62.0)
	var sc := 1.3
	m.fill_path(BalloonArt.ENV, Color("a06bff"), o, sc)
	m.fill_path(BalloonArt.GORE, Color(1, 1, 1, 0.92), o, sc)
	m.fill_path(BalloonArt.SHADE, Color(INK, 0.14), o, sc)
	m.poly(Array(SvgArt.ellipse((Vector2(72, 30) + o) * sc, 7.0 * sc, 14.0 * sc, deg_to_rad(20.0), 12)), Color(1, 1, 1, 0.35), false)
	m.line((Vector2(40, 98) + o) * sc, (Vector2(41, 118) + o) * sc, 2.2, BalloonArt.ROPE)
	m.line((Vector2(60, 98) + o) * sc, (Vector2(59, 118) + o) * sc, 2.2, BalloonArt.ROPE)
	m.poly(Array(SvgArt.rrect(37.0, 116.0, 26.0, 18.0, 4.0, o, sc)), Color("c4844a"), false)
	m.k = 1.0
	return m.build()

static func _drone() -> ArrayMesh:
	var m := ShapeMesh.new()
	var o := Vector2(-35.0, -17.0)
	var sc := 3.0
	for sx in [-1.0, 1.0]:   # skids
		m.line((Vector2(35.0 + sx * 11.0, 24) + o) * sc, (Vector2(35.0 + sx * 14.0, 29) + o) * sc, 3.0, Color("5a6070"))
	m.poly(Array(SvgArt.rrect(22.0, 12.0, 26.0, 12.0, 5.0, o, sc)), Color("3a3f4a"), false)
	m.poly(Array(SvgArt.rrect(8.0, 10.0, 54.0, 4.0, 2.0, o, sc)), Color("5a6070"), false)
	for rx in [10.0, 60.0]:   # rotors: they flicker about their centres
		var c := (Vector2(rx, 8.0) + o) * sc
		m.poly(Array(SvgArt.ellipse(c, 10.0 * sc, 2.6 * sc, 0.0, 12)), Color(0.84, 0.86, 0.9, 0.9), false, 3.0, c.x)
	var light := (Vector2(35, 18) + o) * sc
	m.circle(light, 9.0 * 1.0, Color(1.0, 0.36, 0.3, 0.3), false, 4.0, 0.0, 10)
	m.circle(light, 3.2 * sc, Color("ff5c4d"), false, 0.0, 0.0, 10)
	return m.build()

static func _cable() -> ArrayMesh:
	var m := ShapeMesh.new()
	var o := Vector2(-30.0, -33.0)
	var sc := 2.6
	m.line((Vector2(30, 0) + o) * sc, (Vector2(30, 16) + o) * sc, 4.0, Color("3a3f4a"))
	m.circle((Vector2(30, 1) + o) * sc, 7.0, Color("3a3f4a"), false, 0.0, 0.0, 10)
	m.poly(Array(SvgArt.rrect(10.0, 16.0, 40.0, 34.0, 8.0, o, sc)), Color("ff5c4d"), false)
	m.poly(Array(SvgArt.rrect(10.0, 40.0, 40.0, 10.0, 6.0, o, sc)), Color("d94239"), false)
	m.poly(Array(SvgArt.rrect(16.0, 22.0, 12.0, 12.0, 3.0, o, sc)), Color("9ec3ff"), false)
	m.poly(Array(SvgArt.rrect(32.0, 22.0, 12.0, 12.0, 3.0, o, sc)), Color("9ec3ff"), false)
	return m.build()

static func _carpet() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.k = 2.0
	m.poly([Vector2(-52, -5), Vector2(52, -5), Vector2(52, 6), Vector2(-52, 6)], Color("c2185b"), false)
	m.line(Vector2(-46, 0), Vector2(46, 0), 3.0, Color("ffc933"))
	for fy in [-3.0, 3.0]:
		m.line(Vector2(-52, fy), Vector2(-62, fy), 2.5, Color("ffc933"))
		m.line(Vector2(52, fy), Vector2(62, fy), 2.5, Color("ffc933"))
	m.poly(Array(SvgArt.rrect(-8.0, -17.0, 16.0, 12.0, 3.0)), Color("3d8bff"), false)
	m.circle(Vector2(0, -23), 7.0, Color("f5d9b8"), false, 0.0, 0.0, 10)
	m.circle(Vector2(0, -27), 6.0, Color.WHITE, false, 0.0, 0.0, 10)
	return m.build()

static func _glider() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.k = 1.9
	m.line(Vector2(-30, -8), Vector2(0, 24), 2.0, Color(INK, 0.5))
	m.line(Vector2(30, -8), Vector2(0, 24), 2.0, Color(INK, 0.5))
	m.poly([Vector2(-58, 0), Vector2(-44, -26), Vector2(0, -38), Vector2(44, -26), Vector2(58, 0), Vector2(30, -8), Vector2(-30, -8)], Color("ff7a2e"), false)
	m.poly([Vector2(-14, -36), Vector2(14, -36), Vector2(20, -8), Vector2(-20, -8)], Color("fff0cc"), false)
	m.poly(Array(SvgArt.rrect(-5.0, 28.0, 10.0, 16.0, 4.0)), Color("3d8bff"), false)
	m.circle(Vector2(0, 22), 7.0, Color("f5d9b8"), false, 0.0, 0.0, 10)
	return m.build()

## A propane tank with a pulsing ring around it.
static func _tank() -> ArrayMesh:
	var m := ShapeMesh.new()
	var o := Vector2(-15.0, -22.0)
	var sc := 2.4
	var ring: Array = []
	for i in 21:
		var a := TAU * float(i) / 20.0
		ring.append(Vector2(cos(a), sin(a)) * 62.0)
	m.polyline(ring, 3.0, Color(1, 1, 1, 0.55), 4.0)
	m.poly(Array(SvgArt.rrect(11.0, 2.0, 8.0, 7.0, 2.0, o, sc)), Color("d6dbe4"), false)
	m.poly(Array(SvgArt.rrect(6.0, 8.0, 18.0, 30.0, 7.0, o, sc)), Color("35c98a"), false)
	m.poly(Array(SvgArt.rrect(9.0, 16.0, 12.0, 4.0, 2.0, o, sc)), Color(1, 1, 1, 0.8), false)
	m.poly(Array(SvgArt.rrect(6.0, 8.0, 7.0, 30.0, 6.0, o, sc)), Color(INK, 0.12), false)
	return m.build()

## A gold coin that spins, with a pulsing ring.
static func _coin() -> ArrayMesh:
	var m := ShapeMesh.new()
	var ring: Array = []
	for i in 21:
		var a := TAU * float(i) / 20.0
		ring.append(Vector2(cos(a), sin(a)) * 52.0)
	m.polyline(ring, 3.0, Color(1.0, 0.95, 0.5, 0.5), 4.0)
	m.circle(Vector2.ZERO, 31.0, Color("ffc933"), false, 5.0, 0.0, 20)
	m.circle(Vector2.ZERO, 20.0, Color("ffd95c"), false, 5.0, 0.0, 16)
	m.poly(Array(SvgArt.rrect(-5.0, -12.0, 10.0, 24.0, 5.0)), Color("c98a0b"), false, 5.0)
	return m.build()

## Five geese in a V, flapping together (each wing about its own shoulder).
static func _geese() -> ArrayMesh:
	var m := ShapeMesh.new()
	var sc := 1.25
	var offs := [Vector2(76, 0), Vector2(38, -26), Vector2(38, 26), Vector2(0, -52), Vector2(0, 52)]
	var origin := Vector2(-22.0, 0.0)
	for g in 5:
		var o: Vector2 = (offs[g] + origin) / sc - Vector2(30.0, 15.0)   # (symbol units: the paths add it before scaling)
		m.fill_path("M10 17L2 14L4 20Z", Color("3a3f4a"), o, sc)
		m.poly(Array(SvgArt.ellipse((Vector2(26, 18) + o) * sc, 16.0 * sc, 6.5 * sc, 0.0, 14)), Color("f4f1ea"), false)
		m.fill_path("M38 16C44 12 46 8 50 8C53 8 54 10 54 11L50 12C48 12 46 16 42 19Z", Color("3a3f4a"), o, sc)
		m.fill_path("M54 10L59 11L54 13Z", Color("ff9f2e"), o, sc)
		var sh := (Vector2(27, 17) + o) * sc
		m.fill_path("M18 16C22 6 30 2 34 4C32 10 30 14 26 18Z", Color("9aa3b2"), o, sc, _wing(sh.y, false), sh.x)
	return m.build()

## A gold Star Collect star with a pulsing ring.
static func _star() -> ArrayMesh:
	var m := ShapeMesh.new()
	var ring: Array = []
	for i in 21:
		var a := TAU * float(i) / 20.0
		ring.append(Vector2(cos(a), sin(a)) * 56.0)
	m.polyline(ring, 3.0, Color(1.0, 0.95, 0.6, 0.55), 4.0)
	var d := "M14 2L17.6 9.6L26 10.6L19.8 16.3L21.5 24.6L14 20.4L6.5 24.6L8.2 16.3L2 10.6L10.4 9.6Z"
	m.fill_path(d, Color("ffc933"), Vector2(-14.0, -14.0), 2.6, 5.0)
	m.fill_path("M14 2L17.6 9.6L14 14L10.4 9.6Z", Color(1, 1, 1, 0.45), Vector2(-14.0, -14.0), 2.6, 5.0)
	return m.build()

## The pulsing target ring and a down arrow over the platform to go to.
static func _marker() -> ArrayMesh:
	var m := ShapeMesh.new()
	var ring: Array = []
	for i in 25:
		var a := TAU * float(i) / 24.0
		ring.append(Vector2(cos(a) * 96.0, sin(a) * 64.0))
	m.polyline(ring, 6.0, Color(1.0, 0.95, 0.3, 0.9), 4.0)
	m.poly([Vector2(-18, -118), Vector2(18, -118), Vector2(18, -92), Vector2(30, -92), Vector2(0, -66), Vector2(-30, -92), Vector2(-18, -92)], Color("ffc933"), false, 4.0)
	return m.build()

## The airship; the origin is the middle of its deck's top surface (x +-130, hull below).
static func _airship() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.poly([Vector2(-150, 6), Vector2(-196, -26), Vector2(-196, 34), Vector2(-140, 36)], Color("ff5c4d"), false)
	m.poly([Vector2(-130, 0), Vector2(130, 0), Vector2(166, 18), Vector2(132, 44), Vector2(70, 58), Vector2(-70, 58), Vector2(-132, 44), Vector2(-166, 18)], Color("e9eef8"), false)
	m.poly([Vector2(-150, 24), Vector2(150, 24), Vector2(138, 36), Vector2(-138, 36)], Color("ff5c4d"), false)
	m.rect(-130.0, -7.0, 260.0, 9.0, Color("c4844a"), false)   # the deck
	for i in 6:
		var x := -115.0 + float(i) * 46.0
		m.line(Vector2(x, -7.0), Vector2(x, -30.0), 4.0, Color("3a3f4a"))
	m.line(Vector2(-118.0, -30.0), Vector2(118.0, -30.0), 4.0, Color("3a3f4a"))
	for i in 4:
		m.circle(Vector2(-60.0 + float(i) * 40.0, 14.0), 7.0, Color("9ec3ff"), false, 0.0, 0.0, 10)
	return m.build()
