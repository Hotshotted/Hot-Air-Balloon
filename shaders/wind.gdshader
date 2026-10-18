shader_type canvas_item;
// Wind decoration for every layer in three MultiMeshes (streaks, chevrons, streamers) sharing this one material.
// Nothing is moved from script: each layer's accumulated scroll (px) and direction come in as two uniform arrays,
// and every instance works out its own position. INSTANCE_CUSTOM = (layer, x0, y fraction in the layer, mode);
// COLOR = (parallax factor, size, alpha, hue); for streamers COLOR.g is the wave phase. mode 0 streak, 1 chevron, 2 streamer.
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
	if (mode == 0) {
		float x = mod(INSTANCE_CUSTOM.y + sc * COLOR.r + 80.0, W + 160.0) - 80.0;
		VERTEX = vec2(x + d * VERTEX.x * COLOR.g, y + VERTEX.y);
		COLOR = vec4(1.0, 1.0, 1.0, alpha);
	} else if (mode == 1) {
		float x = mod(INSTANCE_CUSTOM.y + sc * 0.6 + 50.0, W + 100.0) - 50.0;
		VERTEX = vec2(x + d * VERTEX.x, y + VERTEX.y);
		COLOR = vec4(1.0, 1.0, 1.0, alpha);
	} else {
		float x = mod(INSTANCE_CUSTOM.y + sc * 0.8 + 120.0, W + 240.0) - 120.0;
		float p = VERTEX.x / 16.0;
		float wave = sin(TIME * 5.0 + COLOR.g + p * 0.9) * 7.0 * (p / 6.0);
		VERTEX = vec2(x - d * VERTEX.x, y + VERTEX.y + wave);
		// UV.x tells the black underlay (0) from the coloured ribbon (1); the instance hue 0 is yellow, 1 pink
		vec3 ribbon = mix(vec3(1.0, 0.95, 0.4), vec3(1.0, 0.5, 0.65), COLOR.a);
		COLOR = UV.x > 0.5 ? vec4(ribbon, 1.0) : vec4(0.0, 0.0, 0.0, 1.0);
	}
}
