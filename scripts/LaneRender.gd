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
var fx: FxLayer
var _wind_mat: ShaderMaterial
var _haze: ColorRect
var _haze_mat: ShaderMaterial
var _th_rect: ColorRect
var _th_mat: ShaderMaterial
var _thc_mat: ShaderMaterial
var _thc: MultiMeshInstance2D
var _streaks: MultiMeshInstance2D
var _chevs: MultiMeshInstance2D
var _streamers: MultiMeshInstance2D
var _hz: Array = []                      # per mesh id: MultiMeshInstance2D
var _hz_buf: Array = []                  # per mesh id: PackedFloat32Array (12 floats per instance)
var _hz_n := PackedInt32Array()          # per mesh id: instances in use
var _hz_mesh := PackedInt32Array()       # per hazard: its mesh id and instance slot
var _hz_slot := PackedInt32Array()
var _tk: MultiMeshInstance2D
var _cn: MultiMeshInstance2D
var _tk_buf := PackedFloat32Array()
var _cn_buf := PackedFloat32Array()
var _streak_buf := PackedFloat32Array()  # 16 floats per instance: transform 8, colour 4, custom 4
var _chev_buf := PackedFloat32Array()
var _streamer_buf := PackedFloat32Array()
var _thc_buf := PackedFloat32Array()
var _scroll := PackedFloat32Array()
var _dir := PackedFloat32Array()
var _th_x := PackedFloat32Array()
var _focus_shown := -1
var _built := false

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
	# --- wind ---
	_wind_mat = ShaderMaterial.new()
	_wind_mat.shader = load("res://shaders/wind.gdshader")
	_streaks = _make_mm(_streak_mesh(), Lanes.MAX_LANES * Lanes.PARTS_PER_LANE, true, _wind_mat)
	_chevs = _make_mm(_chevron_mesh(), Lanes.MAX_LANES * Lanes.CHEVRONS_PER_LANE, true, _wind_mat)
	_streamers = _make_mm(_streamer_mesh(), Lanes.MAX_LANES * Lanes.STREAMERS_PER_LANE, true, _wind_mat)
	_streak_buf.resize(Lanes.MAX_LANES * Lanes.PARTS_PER_LANE * WIND_STRIDE)
	_chev_buf.resize(Lanes.MAX_LANES * Lanes.CHEVRONS_PER_LANE * WIND_STRIDE)
	_streamer_buf.resize(Lanes.MAX_LANES * Lanes.STREAMERS_PER_LANE * WIND_STRIDE)
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
	_tk_buf.resize(Lanes.MAX_LANES * HZ_STRIDE)
	_cn_buf.resize(Lanes.MAX_COINS * HZ_STRIDE)
	for m in HazardMeshes.COUNT:
		if m == HazardMeshes.TANK or m == HazardMeshes.COIN:
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
	fx = FxLayer.new()
	fx.lanes = lanes
	add_child(fx)
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

func _streak_mesh() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.poly([Vector2(0, -1.5), Vector2(-1, -1.5), Vector2(-1, 1.5), Vector2(0, 1.5)], Color.WHITE, false)
	return m.build()

func _chevron_mesh() -> ArrayMesh:
	var m := ShapeMesh.new()
	m.polyline([Vector2(-12, -16), Vector2(12, 0), Vector2(-12, 16)], 5.0, Color.WHITE)
	return m.build()

func _streamer_mesh() -> ArrayMesh:
	var m := ShapeMesh.new()
	var pts: Array = []
	for p in 7:
		pts.append(Vector2(float(p) * 16.0, 0))
	m.polyline(pts, 9.0, Color.WHITE, 0.0)   # the black underlay
	m.polyline(pts, 5.0, Color.WHITE, 1.0)   # the coloured ribbon
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
		var strength := clampf(absf(L.lane_base[i]) / 200.0, 0.0, 1.0)
		for j in Lanes.PARTS_PER_LANE:
			_wind_instance(_streak_buf, np, float(i), rng.randf() * Lanes.W, rng.randf_range(0.1, 0.9), 0.0,
				rng.randf_range(0.6, 1.4), rng.randf_range(24.0, 70.0) * (0.6 + strength), 0.55, 0.0)
			np += 1
		var chev_n := 2 + int(strength * 2.0)   # a stronger wind shows more chevrons
		for c in Lanes.CHEVRONS_PER_LANE:
			_wind_instance(_chev_buf, nc, float(i), float(c) * Lanes.W / float(Lanes.CHEVRONS_PER_LANE), 0.5, 1.0,
				1.0, 1.0, 0.3 if c < chev_n else 0.0, 0.0)
			nc += 1
		for j in Lanes.STREAMERS_PER_LANE:
			_wind_instance(_streamer_buf, ns, float(i), rng.randf() * Lanes.W, 0.5, 2.0, 0.0, rng.randf() * TAU, 1.0, float((i + j) % 2))
			ns += 1
	_streaks.multimesh.visible_instance_count = np
	_chevs.multimesh.visible_instance_count = nc
	_streamers.multimesh.visible_instance_count = ns
	_streaks.multimesh.buffer = _streak_buf
	_chevs.multimesh.buffer = _chev_buf
	_streamers.multimesh.buffer = _streamer_buf
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
		_tk_buf[b2] = 1.25 if tank_on else 0.0
		_tk_buf[b2 + 3] = L.pk_x[i]
		_tk_buf[b2 + 5] = 1.25 if tank_on else 0.0
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
	fx.tick()
	if Lanes.prof_on:
		Lanes.prof_us[1] += float(Time.get_ticks_usec() - t_prof)
