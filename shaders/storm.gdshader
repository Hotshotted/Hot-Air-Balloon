shader_type canvas_item;
// The Rising Storm: everything below `top_y` is a churning dark front: ragged rolling top edge, billows that boil
// upwards, a lit rim and lightning flickers inside it. One full-screen quad.
uniform float top_y = 2000.0;
varying vec2 wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wp = VERTEX;
}

void fragment() {
	float rag = (fbm(vec2(wp.x * 0.0065 + TIME * 0.12, TIME * 0.3)) - 0.5) * 90.0 + sin(wp.x * 0.018 + TIME * 1.3) * 10.0;
	float edge = top_y + rag;
	if (wp.y < edge - 90.0) {
		COLOR = vec4(0.0);
	} else {
		float a = smoothstep(edge - 40.0, edge + 16.0, wp.y);
		float churn = fbm(vec2(wp.x * 0.0045, wp.y * 0.0045 + TIME * 0.35) * 2.0 + vec2(0.0, TIME * 0.22));
		float t = clamp((wp.y - edge) / 160.0, 0.0, 1.0);
		vec3 deep = vec3(0.07, 0.05, 0.14);
		vec3 mid = vec3(0.2, 0.15, 0.3);
		vec3 rim = vec3(0.45, 0.38, 0.58);
		vec3 col = mix(rim, deep, t);
		col = mix(col, mid, churn * (1.0 - t * 0.5) * 0.85);
		// lightning: an irregular flash lighting the billows around a flickering spot
		float slot = floor(TIME * 6.0);
		float on = step(0.88, hash(vec2(slot, 4.0))) * (0.5 + 0.5 * sin(TIME * 90.0));
		float fx = hash(vec2(slot, 9.0)) * 1080.0;
		float near = smoothstep(420.0, 0.0, length(vec2(wp.x - fx, (wp.y - edge) * 1.6)));
		col += vec3(0.75, 0.7, 1.0) * on * near * (0.35 + churn);
		COLOR = vec4(col, a * 0.95);
	}
}
