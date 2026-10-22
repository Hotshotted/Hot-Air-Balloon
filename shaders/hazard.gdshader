shader_type canvas_item;
// Merged flat shapes, drawn as one MultiMesh per kind of hazard / pickup.
// The mesh vertices carry an animation id in UV.x and a weight in UV.y:
//   0 static   2 wavy tail (weight 0..1 along the tail)   3 rotor flicker (UV.y = the rotor's centre x)
//   4 pulsing ring   5 coin spin
//   7..8.99 a wing that flaps about its own shoulder: UV.y = the shoulder's x, the shoulder's y = (id - floor(id)) * 400 - 200,
//   ids 7.x turn one way and 8.x the other, so a pair of wings flaps together (up, then down)
// INSTANCE_CUSTOM.x is a per-instance phase.
void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float a = UV.x;
	float w = UV.y;
	if (a > 1.5 && a < 2.5) {
		VERTEX.x += sin(TIME * 5.0 + phase + w * 4.0) * 8.0 * w;
	} else if (a > 2.5 && a < 3.5) {
		VERTEX.x = w + (VERTEX.x - w) * (1.0 + 0.3 * step(0.0, sin(TIME * 60.0 + phase)));
	} else if (a > 3.5 && a < 4.5) {
		VERTEX *= 1.0 + 0.12 * sin(TIME * 4.0 + phase);
	} else if (a > 4.5 && a < 5.5) {
		VERTEX.x *= 0.35 + 0.65 * abs(cos(TIME * 3.0 + phase));
	} else if (a > 6.5) {
		float sgn = a > 8.0 ? -1.0 : 1.0;
		float sy = (fract(a) * 400.0) - 200.0;
		vec2 sh = vec2(w, sy);
		float ang = sin(TIME * 6.0 + phase) * 0.55 * sgn;
		vec2 p = VERTEX - sh;
		float c = cos(ang);
		float s = sin(ang);
		VERTEX = sh + vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	}
}

void fragment() {
	// a little more saturated than the raw vertex colours: hazards stay the loudest thing in the sky
	float l = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = clamp(mix(vec3(l), COLOR.rgb, 1.15), 0.0, 1.0);
}
