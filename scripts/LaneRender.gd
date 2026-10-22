class_name LaneRender
extends Node2D
## Draws the sky for Lanes with as few draw calls as possible. Nothing is drawn with per-shape draw_* calls any more:
##   - Backdrop: bands, scenery, goal strip, cables: drawn once per leg.
##   - Wind streaks, chevrons and streamers: three MultiMeshes moved ENTIRELY by shaders/wind.gdshader (script only
##     passes each layer's scroll and direction: two small arrays per frame).
##   - Thermals: one shader quad + one MultiMesh of rising chevrons. Sand haze: one shader quad over all layers.
##   - Hazards, propane tanks and coins: merged meshes (outlines included, see ShapeMesh / HazardMeshes) in one
##     MultiMesh per kind; per frame only each instance's position is written into a pre-allocated buffer.
##   - Sparks: one node that redraws only while a spark is alive.
## Everything is created once in _ready (and drawn during the start-up pre-warm); a leg start only rewrites buffers.

var lanes: Lanes
var backdrop: Backdrop
var parallax: ParallaxBack
var front: BackdropFront
var fx: FxLayer
var _wind_mat: ShaderMaterial
var _haze: ColorRect
var _haze_mat: ShaderMaterial
var _th_rect: ColorRect
var _th_mat: ShaderMaterial
var _thc_mat: ShaderMaterial
var _thc: MultiMeshInstance2D
var _streaks: MultiMeshInstance2D
var _clouds: MultiMeshInstance2D
var _birds: MultiMeshInstance2D
var _hz: Array = []                      # per mesh id: MultiMeshInstance2D
var _hz_buf: Array = []                  # per mesh id: PackedFloat32Array (12 floats per instance)
var _hz_n := PackedInt32Array()          # per mesh id: instances in use
var _hz_mesh := PackedInt32Array()       # per hazard: its mesh id and instance slot
var _hz_slot := PackedInt32Array()
var _gs: MultiMeshInstance2D           # Star Collect stars
var _mk: MultiMeshInstance2D           # the pulsing target ring on the active mooring platform
var _ship: MultiMeshInstance2D         # the airship
var _gs_buf := PackedFloat32Array()
var _mk_buf := PackedFloat32Array()
var _ship_buf := PackedFloat32Array()
var _storm: ColorRect
var _storm_mat: ShaderMaterial
var lightning: LightningFx
var _pills: Array[LayerPill] = []        # per layer: the navy pill at the left edge (direction, speed, reversal countdown)
var _pv_dots: MultiMeshInstance2D        # drift preview: the balloon's path if the burner keeps firing
var _pv_dots2: MultiMeshInstance2D       # ...and if it is released now
var _pv_dot_buf2 := PackedFloat32Array()
var _pv_ghosts: MultiMeshInstance2D      # ...and where each hazard will be at the end of it
var _pv_dot_buf := PackedFloat32Array()
var _pv_ghost_buf := PackedFloat32Array()
var _tk: MultiMeshInstance2D
var _cn: MultiMeshInstance2D
var _tk_buf := PackedFloat32Array()
var _cn_buf := PackedFloat32Array()
var _streak_buf := PackedFloat32Array()  # 16 floats per instance: transform 8, colour 4, custom 4
var _cloud_buf := PackedFloat32Array()
var _bird_buf := PackedFloat32Array()
var _thc_buf := PackedFloat32Array()
var _scroll := PackedFloat32Array()
var _dir := PackedFloat32Array()
var _th_x := PackedFloat32Array()
var _focus_shown := -1
var _built := false

## Meshes that are not hazards (they have their own MultiMeshes).
const SPECIAL := [HazardMeshes.TANK, HazardMeshes.COIN, HazardMeshes.STAR, HazardMeshes.MARKER, HazardMeshes.AIRSHIP]
const HZ_STRIDE := 12
const WIND_STRIDE := 16
const THC_PER := 10

func _ready() -> void:
	_scroll.resize(Lanes.MAX_LANES)
	_dir.resize(Lanes.MAX_LANES)
	_dir.fill(1.0)
	_th_x.resize(Lanes.MAX_THERMALS)
	_hz_n.resize(HazardMeshes.COUNT)
	_hz_mesh.resize(Lanes.MAX_HAZ)
	_hz_slot.resize(Lanes.MAX_HAZ)
	backdrop = Backdrop.new()
	backdrop.lanes = lanes
	add_child(backdrop)
	parallax = ParallaxBack.new()
	parallax.lanes = lanes
	add_child(parallax)
	front = BackdropFront.new()
	front.lanes = lanes
	add_child(front)
	backdrop.parallax = parallax
	backdrop.front = front
	# --- wind ---
	_wind_mat = ShaderMaterial.new()
	_wind_mat.shader = load("res://shaders/wind.gdshader")
	_streaks = _make_mm(_streak_mesh(), Lanes.MAX_LANES * Lanes.PARTS_PER_LANE, true, _wind_mat)
	_clouds = _make_mm(_cloud_mesh(), Lanes.MAX_LANES * Lanes.CLOUDS_PER_LANE, true, _wind_mat)
	_birds = _make_mm(_bird_mesh(), Lanes.MAX_LANES * Lanes.BIRDS_PER_LANE, true, _wind_mat)
	_streak_buf.resize(Lanes.MAX_LANES * Lanes.PARTS_PER_LANE * WIND_STRIDE)
	_cloud_buf.resize(Lanes.MAX_LANES * Lanes.CLOUDS_PER_LANE * WIND_STRIDE)
	_bird_buf.resize(Lanes.MAX_LANES * Lanes.BIRDS_PER_LANE * WIND_STRIDE)
	# --- thermals ---
	_th_mat = ShaderMaterial.new()
	_th_mat.shader = load("res://shaders/thermal.gdshader")
	_th_rect = ColorRect.new()
	_th_rect.position = Vector2(0, Lanes.BAND_TOP)
	_th_rect.size = Vector2(Lanes.W, Lanes.BAND_BOTTOM - Lanes.BAND_TOP)
	_th_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_th_rect.material = _th_mat
	add_child(_th_rect)
	_thc_mat = ShaderMaterial.new()
	_thc_mat.shader = load("res://shaders/thermal_chev.gdshader")
	_thc = _make_mm(_thermal_chevron_mesh(), Lanes.MAX_THERMALS * THC_PER, false, _thc_mat, HZ_STRIDE)
	_thc_buf.resize(Lanes.MAX_THERMALS * THC_PER * HZ_STRIDE)
	# --- pickups and hazards ---
	var hazard_mat := ShaderMaterial.new()
	hazard_mat.shader = load("res://shaders/hazard.gdshader")
	var meshes := HazardMeshes.build_all()
	_tk = _make_mm(meshes[HazardMeshes.TANK], Lanes.MAX_LANES, false, hazard_mat, HZ_STRIDE)
	_cn = _make_mm(meshes[HazardMeshes.COIN], Lanes.MAX_COINS, false, hazard_mat, HZ_STRIDE)
	_gs = _make_mm(meshes[HazardMeshes.STAR], Lanes.MAX_STARS, false, hazard_mat, HZ_STRIDE)
	_mk = _make_mm(meshes[HazardMeshes.MARKER], 1, false, hazard_mat, HZ_STRIDE)
	_ship = _make_mm(meshes[HazardMeshes.AIRSHIP], 1, false, hazard_mat, HZ_STRIDE)
	_tk_buf.resize(Lanes.MAX_LANES * HZ_STRIDE)
	_cn_buf.resize(Lanes.MAX_COINS * HZ_STRIDE)
	_gs_buf.resize(Lanes.MAX_STARS * HZ_STRIDE)
	_mk_buf.resize(HZ_STRIDE)
	_ship_buf.resize(HZ_STRIDE)
	for m in HazardMeshes.COUNT:
		if m in SPECIAL:
			_hz.append(null)
			_hz_buf.append(PackedFloat32Array())
			continue
		_hz.append(_make_mm(meshes[m], Lanes.MAX_HAZ, false, hazard_mat, HZ_STRIDE))
		var buf := PackedFloat32Array()
		buf.resize(Lanes.MAX_HAZ * HZ_STRIDE)
		_hz_buf.append(buf)
	# --- haze (above the hazards) ---
	_haze_mat = ShaderMaterial.new()
	_haze_mat.shader = load("res://shaders/haze.gdshader")
	_haze = ColorRect.new()
	_haze.position = Vector2(0, Lanes.BAND_TOP)
	_haze.size = Vector2(Lanes.W, Lanes.BAND_BOTTOM - Lanes.BAND_TOP)
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze.material = _haze_mat
	add_child(_haze)
	# --- the Rising Storm (above the haze): one quad ---
	_storm_mat = ShaderMaterial.new()
	_storm_mat.shader = load("res://shaders/storm.gdshader")
	_storm = ColorRect.new()
	_storm.size = Vector2(Lanes.W, Lanes.H)
	_storm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storm.material = _storm_mat
	_storm.visible = false
	add_child(_storm)
	lightning = LightningFx.new()
	lightning.lanes = lanes
	add_child(lightning)
	fx = FxLayer.new()
	fx.lanes = lanes
	add_child(fx)
	# the wind of every layer at its left edge: a small navy pill (chevrons by strength, "calm", or a reversal countdown)
	for i in Lanes.MAX_LANES:
		var pl := LayerPill.new()
		pl.visible = false
		add_child(pl)
		_pills.append(pl)
	# the drift preview: dots along the predicted path, a ring per hazard where it will be
	var dm := ShapeMesh.new()
	dm.circle(Vector2.ZERO, 1.0, Color.WHITE, false, 0.0, 0.0, 8)
	_pv_dots = _make_mm(dm.build(), Balloon.PRED_N, false, null, HZ_STRIDE)
	_pv_dots.modulate = Color(1.0, 0.6, 0.2, 0.85)
	_pv_dots2 = _make_mm(dm.build(), Balloon.PRED_N, false, null, HZ_STRIDE)
	_pv_dots2.modulate = Color(0.85, 0.95, 1.0, 0.85)
	_pv_dot_buf2.resize(Balloon.PRED_N * HZ_STRIDE)
	_pv_dot_buf.resize(Balloon.PRED_N * HZ_STRIDE)
	var gm := ShapeMesh.new()
	var ring: Array = []
	for a in 17:
		ring.append(Vector2(cos(TAU * float(a) / 16.0), sin(TAU * float(a) / 16.0)))
	gm.polyline(ring, 0.1, Color.WHITE)
	_pv_ghosts = _make_mm(gm.build(), Lanes.MAX_HAZ, false, null, HZ_STRIDE)
	_pv_ghosts.modulate = Color(1, 1, 1, 0.55)
	_pv_ghost_buf.resize(Lanes.MAX_HAZ * HZ_STRIDE)
	_built = true

func _make_mm(mesh: Mesh, count: int, colors: bool, mat: Material, _stride: int = WIND_STRIDE) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = colors
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.material = mat
	add_child(node)
	return node

# ---- the small meshes of the wind decoration ----

## A wind ribbon (nominal length 100, stretched along x by the shader to the ribbon's length; the arrowhead at the tip stays its size, UV.x 1): a gently
## waving white stroke with an arrowhead. It points +x; the shader flips it for a layer blowing the other way.
func _streak_mesh() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.polyline([Vector2(-100.0, 0.0), Vector2(-75.0, -5.0), Vector2(-50.0, 0.0), Vector2(-25.0, 5.0), Vector2(0.0, 0.0)], 8.0, Color.WHITE, 0.0)
	m.polyline([Vector2(-20.0, -15.0), Vector2(0.0, 0.0), Vector2(-20.0, 15.0)], 8.0, Color.WHITE, 1.0)
	return m.build()

## A cloud: a flat-bottomed puff (white fill, UV.x 0) with a soft blue-grey outline (UV.x 1); the shader tints both.
func _cloud_mesh() -> ArrayMesh:
	var m := ShapeMesh.new()
	var pts: Array = []
	for i in 13:   # the bumpy top: overlapping domes
		var u := float(i) / 12.0
		var dome := absf(sin(u * PI * 2.5))
		pts.append(Vector2(lerpf(-38.0, 38.0, u), -4.0 - 22.0 * pow(dome, 0.7) * (1.0 - absf(u - 0.5) * 0.9)))
	pts.append(Vector2(38.0, 8.0))
	pts.append(Vector2(-38.0, 8.0))
	m.poly(pts, Color.WHITE, false, 0.0)
	return m.build()

## A tiny far-off bird: a V that flaps (the shader moves the wing tips).
func _bird_mesh() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.polyline([Vector2(-9, 0), Vector2(0, 3), Vector2(9, 0)], 2.6, Color.WHITE, 2.0)
	return m.build()

func _thermal_chevron_mesh() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.polyline([Vector2(-14, 12), Vector2(0, -6), Vector2(14, 12)], 4.0, Color(1.0, 0.95, 0.7, 0.75))
	return m.build()

# ---- a leg starts: fill the buffers (nothing is created) ----

func on_setup() -> void:
	var L := lanes
	var t_prof := Time.get_ticks_usec() if Lanes.prof_on else 0
	_scroll.fill(0.0)
	# hazards: one instance slot per hazard in its kind's MultiMesh
	_hz_n.fill(0)
	for i in L.n_lanes:
		var k := L.lane_kind[i]
		for j in L.lane_count[i]:
			var idx := i * Lanes.MAX_PER_LANE + j
			var m := _mesh_for(k, j)
			var slot := _hz_n[m]
			_hz_n[m] = slot + 1
			_hz_mesh[idx] = m
			_hz_slot[idx] = slot
			var b := slot * HZ_STRIDE
			var buf: PackedFloat32Array = _hz_buf[m]
			buf[b + 1] = 0.0
			buf[b + 2] = 0.0
			buf[b + 4] = 0.0
			buf[b + 6] = 0.0
			buf[b + 8] = L.hz_phase[idx]
			buf[b + 9] = 0.0
			buf[b + 10] = 0.0
			buf[b + 11] = 0.0
	for m in HazardMeshes.COUNT:
		if _hz[m] != null:
			(_hz[m] as MultiMeshInstance2D).multimesh.visible_instance_count = _hz_n[m]
	for i in Lanes.MAX_LANES:   # pickups: instance i belongs to layer i
		for buf2 in [_tk_buf, _cn_buf]:
			var b2 := i * HZ_STRIDE
			buf2[b2 + 1] = 0.0
			buf2[b2 + 2] = 0.0
			buf2[b2 + 4] = 0.0
			buf2[b2 + 6] = 0.0
			buf2[b2 + 8] = float(i) * 1.7
	_tk.multimesh.visible_instance_count = L.n_lanes
	_cn.multimesh.visible_instance_count = L.n_lanes
	# wind decoration
	var rng := L.rng
	var np := 0
	var nc := 0
	var ns := 0
	for i in L.n_lanes:
		var strength := clampf(absf(L.lane_base[i]) / 220.0, 0.0, 1.0)
		var calm := absf(L.lane_base[i]) < 30.0
		var ribbons := 1 if calm else mini(1 + int(strength * 4.0), Lanes.PARTS_PER_LANE)   # more ribbons, and longer, the faster the layer
		for j in ribbons:
			_wind_instance(_streak_buf, np, float(i), rng.randf() * Lanes.W, rng.randf_range(0.12, 0.88), 0.0,
				1.0, (60.0 if calm else (130.0 + 300.0 * strength)) * rng.randf_range(0.8, 1.2), 0.35 if calm else rng.randf_range(0.6, 0.9), 0.0)
			np += 1
		for c in Lanes.CLOUDS_PER_LANE:   # clouds: every layer has some, sized by luck, all moving at exactly the layer's wind
			_wind_instance(_cloud_buf, nc, float(i), (float(c) + rng.randf_range(0.0, 0.8)) * Lanes.W / float(Lanes.CLOUDS_PER_LANE),
				rng.randf_range(0.18, 0.62), 1.0, 1.0, rng.randf_range(0.8, 1.5), 0.5, 0.0)
			nc += 1
		for j in Lanes.BIRDS_PER_LANE:
			_wind_instance(_bird_buf, ns, float(i), rng.randf() * Lanes.W, rng.randf_range(0.2, 0.8), 2.0, 1.0, rng.randf() * TAU, 0.5, 0.0)
			ns += 1
	_streaks.multimesh.visible_instance_count = np
	_clouds.multimesh.visible_instance_count = nc
	_birds.multimesh.visible_instance_count = ns
	_streaks.multimesh.buffer = _streak_buf
	_clouds.multimesh.buffer = _cloud_buf
	_birds.multimesh.buffer = _bird_buf
	_wind_mat.set_shader_parameter("lane_h", L.lane_h)
	_wind_mat.set_shader_parameter("band_bottom", Lanes.BAND_BOTTOM)
	# thermals
	var on := L.th_count > 0
	_th_rect.visible = on
	_thc.visible = on
	if on:
		for t in L.th_count:
			for j in THC_PER:
				var b3 := (t * THC_PER + j) * HZ_STRIDE
				_thc_buf[b3] = 1.0
				_thc_buf[b3 + 1] = 0.0
				_thc_buf[b3 + 2] = 0.0
				_thc_buf[b3 + 3] = 0.0
				_thc_buf[b3 + 4] = 0.0
				_thc_buf[b3 + 5] = 1.0
				_thc_buf[b3 + 6] = 0.0
				_thc_buf[b3 + 7] = 0.0
				_thc_buf[b3 + 8] = float(t)
				_thc_buf[b3 + 9] = rng.randf_range(-0.85, 0.85)
				_thc_buf[b3 + 10] = rng.randf()
				_thc_buf[b3 + 11] = 0.0
		_thc.multimesh.visible_instance_count = L.th_count * THC_PER
		_thc.multimesh.buffer = _thc_buf
		_th_mat.set_shader_parameter("th_n", L.th_count)
		_th_mat.set_shader_parameter("hw", Tuning.thermal_width)
		_thc_mat.set_shader_parameter("hw", Tuning.thermal_width)
	# goal objects
	for q in Lanes.MAX_STARS:
		var b4 := q * HZ_STRIDE
		_gs_buf[b4 + 1] = 0.0
		_gs_buf[b4 + 2] = 0.0
		_gs_buf[b4 + 4] = 0.0
		_gs_buf[b4 + 6] = 0.0
		_gs_buf[b4 + 8] = float(q) * 1.3
	_gs.multimesh.visible_instance_count = L.gs_count
	_mk.multimesh.visible_instance_count = 1 if L.goal == Flights.DELIVERY else 0
	_ship.multimesh.visible_instance_count = 1 if L.ship_on else 0
	_storm.visible = L.storm_on
	for i in Lanes.MAX_LANES:   # the pill of every layer
		var pl := _pills[i]
		pl.visible = i < L.n_lanes
		if i < L.n_lanes:
			pl.position = Vector2(14.0, Lanes.BAND_BOTTOM - (float(i) + 0.5) * L.lane_h - LayerPill.H * 0.5)
			pl.text = "?"
			pl.set_state(L.lane_wind[i], ceili(L.rev_timer(i)) if L.lane_rev[i] > 0.0 else 0)
	# haze
	_haze.visible = L.haze_on
	if L.haze_on:
		_haze_mat.set_shader_parameter("lane_h", L.lane_h)
		_haze_mat.set_shader_parameter("clear_lanes", Tuning.haze_clear_lanes)
		_haze_mat.set_shader_parameter("per_lane", Tuning.haze_per_lane)
		_haze_mat.set_shader_parameter("max_alpha", Tuning.haze_max)
		_focus_shown = -1
	backdrop.redraw()
	if Lanes.prof_on:
		Lanes.prof_us[2] += float(Time.get_ticks_usec() - t_prof)

## One wind instance: an identity transform, colour (f, size, alpha, hue) and custom (layer, x0, y, mode).
func _wind_instance(buf: PackedFloat32Array, n: int, lane: float, x0: float, yf: float, mode: float, a: float, b: float, alpha: float, hue: float) -> void:
	var o := n * WIND_STRIDE
	buf[o] = 1.0
	buf[o + 1] = 0.0
	buf[o + 2] = 0.0
	buf[o + 3] = 0.0
	buf[o + 4] = 0.0
	buf[o + 5] = 1.0
	buf[o + 6] = 0.0
	buf[o + 7] = 0.0
	buf[o + 8] = a        # colour: parallax / (streamer: unused), size / (streamer: wave phase), alpha, hue
	buf[o + 9] = b
	buf[o + 10] = alpha
	buf[o + 11] = hue
	buf[o + 12] = lane    # custom: layer, x0, y fraction, mode
	buf[o + 13] = x0
	buf[o + 14] = yf
	buf[o + 15] = mode

## Which mesh a hazard of kind k draws with.
func _mesh_for(k: int, j: int) -> int:
	if k == Lanes.BIRD and (lanes.region == 2 and not lanes.showcase or (lanes.showcase and j % 2 == 0)):
		return HazardMeshes.VULTURE
	return k

# ---- the drift preview ----

func _update_preview(L: Lanes) -> void:
	var bal := L.preview_balloon
	if bal == null:
		_pv_dots.visible = false
		_pv_dots2.visible = false
		_pv_ghosts.visible = false
		return
	_pv_dots.visible = true
	_pv_dots2.visible = true
	_pv_ghosts.visible = true
	for k in Balloon.PRED_N:
		var b := k * HZ_STRIDE
		var r := 4.0 + 5.0 * float(k) / float(Balloon.PRED_N - 1)   # growing: the end of the path stands out
		_pv_dot_buf[b] = r
		_pv_dot_buf[b + 3] = bal.pred_burn[k].x
		_pv_dot_buf[b + 5] = r
		_pv_dot_buf[b + 7] = bal.pred_burn[k].y + 20.0 * bal.s()   # (the path of the basket's middle)
		_pv_dot_buf2[b] = r
		_pv_dot_buf2[b + 3] = bal.pred_rel[k].x
		_pv_dot_buf2[b + 5] = r
		_pv_dot_buf2[b + 7] = bal.pred_rel[k].y + 20.0 * bal.s()
	_pv_dots.multimesh.buffer = _pv_dot_buf
	_pv_dots.multimesh.visible_instance_count = Balloon.PRED_N
	_pv_dots2.multimesh.buffer = _pv_dot_buf2
	_pv_dots2.multimesh.visible_instance_count = Balloon.PRED_N
	var n := 0
	for i in L.n_lanes:
		var k := L.lane_kind[i]
		if k < 0:
			continue
		var sc := L.lane_scale[i]
		var hx := float(Lanes.KIND_HX[k]) * sc
		var hy := float(Lanes.KIND_HY[k]) * sc
		for j in L.lane_count[i]:
			var b := n * HZ_STRIDE
			_pv_ghost_buf[b] = hx
			_pv_ghost_buf[b + 3] = L.hazard_x_in(i, j, Tuning.preview_seconds)
			_pv_ghost_buf[b + 5] = hy
			_pv_ghost_buf[b + 7] = L.hz_y[i * Lanes.MAX_PER_LANE + j]
			n += 1
	_pv_ghosts.multimesh.buffer = _pv_ghost_buf
	_pv_ghosts.multimesh.visible_instance_count = n

# ---- every frame: positions only ----

func update(dt: float) -> void:
	if not _built:
		return
	var t_prof := Time.get_ticks_usec() if Lanes.prof_on else 0
	var L := lanes
	for i in L.n_lanes:
		var w := L.lane_wind[i]
		_scroll[i] += w * dt
		_dir[i] = 1.0 if w >= 0.0 else -1.0
	_wind_mat.set_shader_parameter("scroll", _scroll)
	_wind_mat.set_shader_parameter("dir", _dir)
	parallax.tick(dt, L.lane_wind[clampi(L.focus_lane, 0, L.n_lanes - 1)])
	# hazards
	for i in L.n_lanes:
		var d := 1.0 if L.lane_vel[i] >= 0.0 else -1.0
		var k := L.lane_kind[i]
		var sc := L.lane_scale[i] * (1.3 if k == Lanes.EAGLE else 1.0)
		for j in L.lane_count[i]:
			var idx := i * Lanes.MAX_PER_LANE + j
			var buf: PackedFloat32Array = _hz_buf[_hz_mesh[idx]]
			var b := _hz_slot[idx] * HZ_STRIDE
			buf[b] = d * sc
			buf[b + 3] = L.hz_x[idx]
			buf[b + 5] = sc
			buf[b + 7] = L.hz_y[idx]
	for m in HazardMeshes.COUNT:
		if _hz_n[m] > 0:
			(_hz[m] as MultiMeshInstance2D).multimesh.buffer = _hz_buf[m]
	# propane tanks and coins (a hidden one is a zero-size instance)
	for i in L.n_lanes:
		var b2 := i * HZ_STRIDE
		var tank_on := L.pk_on[i] == 1
		_tk_buf[b2] = 1.0 if tank_on else 0.0
		_tk_buf[b2 + 3] = L.pk_x[i]
		_tk_buf[b2 + 5] = 1.0 if tank_on else 0.0
		_tk_buf[b2 + 7] = L.pk_y[i]
		var coin_on := L.cn_on[i] == 1
		_cn_buf[b2] = 1.0 if coin_on else 0.0
		_cn_buf[b2 + 3] = L.cn_x[i]
		_cn_buf[b2 + 5] = 1.0 if coin_on else 0.0
		_cn_buf[b2 + 7] = L.cn_y[i]
	_tk.multimesh.buffer = _tk_buf
	_cn.multimesh.buffer = _cn_buf
	# thermals drift; the haze clears around the balloon's layer
	if L.th_count > 0:
		for t in L.th_count:
			_th_x[t] = L.th_x[t]
		_th_mat.set_shader_parameter("th_x", _th_x)
		_thc_mat.set_shader_parameter("th_x", _th_x)
	if L.haze_on and L.focus_lane != _focus_shown:
		_focus_shown = L.focus_lane
		_haze_mat.set_shader_parameter("focus", float(_focus_shown))
	# goal objects
	if L.gs_count > 0:
		for q in L.gs_count:
			var b5 := q * HZ_STRIDE
			var on := 1.0 if L.gs_on[q] == 1 else 0.0
			_gs_buf[b5] = on
			_gs_buf[b5 + 3] = L.gs_x[q]
			_gs_buf[b5 + 5] = on
			_gs_buf[b5 + 7] = L.gs_y[q]
		_gs.multimesh.buffer = _gs_buf
	if L.goal == Flights.DELIVERY:
		var tgt := L.dock_target()
		var shown := 1.0 if tgt.x >= 0.0 else 0.0
		_mk_buf[0] = shown
		_mk_buf[3] = tgt.x
		_mk_buf[5] = shown
		_mk_buf[7] = tgt.y
		_mk.multimesh.buffer = _mk_buf
	if L.ship_on:
		_ship_buf[0] = 1.0
		_ship_buf[3] = L.ship_x
		_ship_buf[5] = 1.0
		_ship_buf[7] = Lanes.SHIP_DECK_Y
		_ship.multimesh.buffer = _ship_buf
	if L.storm_on:
		_storm_mat.set_shader_parameter("top_y", L.storm_y)
	for i in L.n_lanes:   # (constant winds: the pill only changes in a reversing layer)
		_pills[i].set_state(L.lane_wind[i], ceili(L.rev_timer(i)) if L.lane_rev[i] > 0.0 else 0)
	_update_preview(L)
	lightning.tick()
	fx.tick()
	if Lanes.prof_on:
		Lanes.prof_us[1] += float(Time.get_ticks_usec() - t_prof)
