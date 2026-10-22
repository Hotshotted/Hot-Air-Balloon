shader_type canvas_item;
// The sky's wind decoration for every layer in three MultiMeshes (particles, clouds, far-off birds) sharing this one
// material. Nothing is moved from script: each layer's accumulated scroll (px) and direction come in as two uniform arrays,
// and every instance works out its own position. EVERYTHING in a layer drifts at exactly the layer's wind (scroll), so the
// sky ahead is readable from how it moves. INSTANCE_CUSTOM = (layer, x0, y fraction in the layer, mode);
// COLOR = (unused, size, alpha, phase). mode 0 particle, 1 cloud, 2 bird.
uniform float scroll[9];
uniform float dir[9];
uniform float lane_h = 200.0;
uniform float band_bottom = 1640.0;
const float W = 1080.0;

void vertex() {
	int lane = int(INSTANCE_CUSTOM.x + 0.5);
	float d = dir[lane];
	float sc = scroll[lane];
	float top = band_bottom - (INSTANCE_CUSTOM.x + 1.0) * lane_h;
	float y = top + INSTANCE_CUSTOM.z * lane_h;
	int mode = int(INSTANCE_CUSTOM.w + 0.5);
	float alpha = COLOR.b;
	float size = COLOR.g;
	if (mode == 0) {
		float x = mod(INSTANCE_CUSTOM.y + sc + 80.0, W + 160.0) - 80.0;
		VERTEX = vec2(x + d * VERTEX.x * size, y + VERTEX.y);
		COLOR = vec4(1.0, 1.0, 1.0, alpha);
	} else if (mode == 1) {
		float x = mod(INSTANCE_CUSTOM.y + sc + 200.0, W + 400.0) - 200.0;
		VERTEX = vec2(x + VERTEX.x * size, y + VERTEX.y * size);
		COLOR = UV.x > 0.5 ? vec4(0.42, 0.5, 0.66, alpha * 0.9) : vec4(1.0, 1.0, 1.0, alpha * 0.8);
	} else {
		float x = mod(INSTANCE_CUSTOM.y + sc + 60.0, W + 120.0) - 60.0;
		float flap = sin(TIME * 6.0 + size) * abs(VERTEX.x) * 0.55;
		VERTEX = vec2(x + d * VERTEX.x, y + VERTEX.y - flap);
		COLOR = vec4(0.18, 0.22, 0.34, alpha * 0.7);
	}
}
