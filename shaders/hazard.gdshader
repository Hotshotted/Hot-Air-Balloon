shader_type canvas_item;
// Merged low-poly shapes (fills AND outlines in one mesh), drawn as one MultiMesh per kind of hazard / pickup.
// The mesh vertices carry an animation id in UV.x and a weight in UV.y:
//   0 static   1 wing flap (about the shoulder)   2 wavy tail (weight 0..1 along the tail)
//   3 rotor flicker (UV.y = the rotor's centre x)  4 pulsing ring   5 coin spin
// INSTANCE_CUSTOM.x is a per-instance phase.
void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float a = UV.x;
	float w = UV.y;
	if (a > 0.5 && a < 1.5) {
		vec2 shoulder = vec2(2.0, -6.0);
		float ang = sin(TIME * 7.0 + phase) * 0.8 * w;
		vec2 p = VERTEX - shoulder;
		float c = cos(ang);
		float s = sin(ang);
		VERTEX = shoulder + vec2(p.x * c - p.y * s, p.x * s + p.y * c);
	} else if (a > 1.5 && a < 2.5) {
		VERTEX.x += sin(TIME * 5.0 + phase + w * 4.0) * 8.0 * w;
	} else if (a > 2.5 && a < 3.5) {
		VERTEX.x = w + (VERTEX.x - w) * (1.0 + 0.3 * step(0.0, sin(TIME * 60.0 + phase)));
	} else if (a > 3.5 && a < 4.5) {
		VERTEX *= 1.0 + 0.12 * sin(TIME * 4.0 + phase);
	} else if (a > 4.5) {
		VERTEX.x *= 0.35 + 0.65 * abs(cos(TIME * 3.0 + phase));
	}
}
