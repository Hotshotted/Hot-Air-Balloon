shader_type canvas_item;
// The sky's wind decoration for every layer in three MultiMeshes (particles, clouds, far-off birds) sharing this one
// material. Nothing is moved from script: each layer's accumulated scroll (px) and direction come in as two uniform arrays,
// and every instance works out its own position. EVERYTHING in a layer drifts at exactly the layer's wind (scroll), so the
// sky ahead is readable from how it moves. INSTANCE_CUSTOM = (layer, x0, y fraction in the layer, mode);
// COLOR = (unused, size, alpha, phase). mode 0 wind streak, 1 cloud, 2 bird.
uniform float scroll[9];
uniform float dir[9];
uniform float lane_h = 200.0;
uniform float band_bottom = 1640.0;
const float W = 1080.0;

void vertex() {
	int lane = int(INSTANCE_CUSTOM.x + 0.5);
	float d = dir[lane];                     // -1..1: the layer's wind over 60 px/s, so a reversing layer passes smoothly through 0
	float sc = scroll[lane];
	float top = band_bottom - (INSTANCE_CUSTOM.x + 1.0) * lane_h;
	float y = top + INSTANCE_CUSTOM.z * lane_h;
	int mode = int(INSTANCE_CUSTOM.w + 0.5);
	float alpha = COLOR.b;
	float size = COLOR.g;
	if (mode == 0) {
		// a wind streak: it travels across the layer at exactly the layer's wind, fades in and out along its way (never pops),
		// shrinks and fades as the wind drops, and turns round when it reverses
		float cyc = W + 520.0;
		float xh = mod(INSTANCE_CUSTOM.y + sc, cyc);
		float u = xh / cyc;
		float fade = smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.86, 1.0, u));
		float calm = smoothstep(0.0, 0.4, abs(d));
		float sgn = d >= 0.0 ? 1.0 : -1.0;
		float len = size * 0.01 * max(abs(d), 0.18) * sgn;
		VERTEX = vec2(xh - 260.0 + VERTEX.x * len, y + VERTEX.y);
		COLOR = vec4(1.0, 1.0, 1.0, alpha * fade * mix(0.5, 1.0, calm) * smoothstep(0.0, 0.18, abs(d) + 0.1));
	} else if (mode == 1) {
		float x = mod(INSTANCE_CUSTOM.y + sc + 200.0, W + 400.0) - 200.0;
		VERTEX = vec2(x + VERTEX.x * size, y + VERTEX.y * size);
		COLOR = vec4(1.0, 1.0, 1.0, alpha * 0.85);
	} else {
		float x = mod(INSTANCE_CUSTOM.y + sc + 60.0, W + 120.0) - 60.0;
		float flap = sin(TIME * 6.0 + size) * abs(VERTEX.x) * 0.55;
		VERTEX = vec2(x + (d >= 0.0 ? 1.0 : -1.0) * VERTEX.x, y + VERTEX.y - flap);
		COLOR = vec4(0.18, 0.22, 0.34, alpha * 0.7 * smoothstep(0.0, 0.3, abs(d)));
	}
}
