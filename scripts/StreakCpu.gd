class_name StreakCpu
extends Node2D
## The fallback for the wind streaks: the same streaks, drawn on the CPU as a few dozen pooled polylines (no custom shader, no
## instance data), used when the shader path fails on a device (see LaneRender's self-test) or with ?streaks=cpu. It reads the
## streak instances LaneRender already prepared and moves them exactly like wind.gdshader does. Redrawn every frame (<= 64 lines).

const PTS := 9
var render: LaneRender
var count := 0
var debug := false
var _pts := PackedVector2Array()
var _cols := PackedColorArray()

func _ready() -> void:
	_pts.resize(PTS)
	_cols.resize(PTS)

func _draw() -> void:
	if render == null or count == 0:
		return
	var L := render.lanes
	var buf := render._streak_buf
	var cyc := Lanes.W + 520.0
	for n in count:
		var o := n * LaneRender.WIND_STRIDE
		var lane := int(buf[o + 12] + 0.5)
		var d := render._dir[lane]
		var xh := fposmod(buf[o + 13] + render._scroll[lane], cyc)
		var u := xh / cyc
		var fade := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.86, 1.0, u))
		var calm := smoothstep(0.0, 0.4, absf(d))
		var a: float = buf[o + 10] * fade * lerpf(0.5, 1.0, calm) * smoothstep(0.0, 0.18, absf(d) + 0.1)
		if debug:
			a = maxf(a, 0.7)
		if a < 0.02:
			continue
		var len: float = buf[o + 9] * maxf(absf(d), 0.18) * (1.0 if d >= 0.0 else -1.0)
		var y := Lanes.BAND_BOTTOM - (float(lane) + 1.0) * L.lane_h + buf[o + 14] * L.lane_h
		var x0 := xh - 260.0
		for i in PTS:
			var t := float(i) / float(PTS - 1)
			_pts[i] = Vector2(x0 - len * (1.0 - t), y - 10.0 * sin(PI * t) + 4.0 * sin(TAU * t))
			var taper := sin(PI * t)
			_cols[i] = Color(1.0, 0.0, 1.0, a * (0.25 + 0.75 * taper)) if debug else Color(1, 1, 1, a * (0.25 + 0.75 * taper))
		if not debug:   # the soft shadow, then the streak
			for i in PTS:
				_pts[i].y += 7.0
				_cols[i] = Color(0.12, 0.28, 0.55, _cols[i].a * 0.3)
			draw_polyline_colors(_pts, _cols, 12.0, false)
			for i in PTS:
				_pts[i].y -= 7.0
				var tp := sin(PI * float(i) / float(PTS - 1))
				_cols[i] = Color(1, 1, 1, a * (0.25 + 0.75 * tp))
		draw_polyline_colors(_pts, _cols, 14.0 if debug else 12.0, false)
