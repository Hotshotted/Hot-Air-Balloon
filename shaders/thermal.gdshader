shader_type canvas_item;
// Thermal columns (Sahara) as one quad: shimmering columns of warm air. Soft edges, wavering vertical bands rising
// through them and a faint wavering outline, so they read as heat, not as a box. Up to three columns.
uniform float th_x[3];
uniform int th_n = 0;
uniform float hw = 95.0;
varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

void fragment() {
	float a = 0.0;
	float glow = 0.0;
	for (int i = 0; i < 3; i++) {
		if (i >= th_n) {
			break;
		}
		float wob = sin(wp.y * 0.021 - TIME * 2.4 + float(i) * 1.7) * 7.0 + sin(wp.y * 0.053 - TIME * 3.1) * 3.0;
		float d = abs(wp.x - th_x[i] + wob);
		float inside = smoothstep(hw, hw * 0.45, d);
		// rising bands of shimmer, sheared by the wobble
		float band = 0.5 + 0.5 * sin(wp.y * 0.045 - TIME * 4.2 + (wp.x - th_x[i]) * 0.05);
		float band2 = 0.5 + 0.5 * sin(wp.y * 0.017 - TIME * 2.0 - (wp.x - th_x[i]) * 0.03);
		a = max(a, inside * (0.07 + 0.13 * band * band2));
		glow = max(glow, inside * band);
		a = max(a, smoothstep(2.6, 0.0, abs(d - hw * 0.97)) * 0.22);
	}
	COLOR = vec4(1.0, mix(0.62, 0.82, glow), mix(0.22, 0.45, glow), a);
}
