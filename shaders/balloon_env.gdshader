shader_type canvas_item;
// The game balloon's envelope. `air` (0..1) is the temperature of the air inside: a cold envelope is dull, greyed and slightly
// slack; a warm one gets its colour back; a hot one is bright, full and glows from the burner's light.
uniform float air = 0.0;
varying vec2 lp;

void vertex() {
	lp = VERTEX;
	// fullness: about the neck (the local origin), wider and taller when hot
	VERTEX.x *= 0.95 + 0.075 * air;
	VERTEX.y *= 0.935 + 0.085 * air;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float mask = smoothstep(0.08, 0.28, max(c.r, max(c.g, c.b)));
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	// cold: duller and a touch darker; warming brings the colour back
	float cold = 1.0 - smoothstep(0.0, 0.55, air);
	c = mix(c, vec3(lum) * 0.92 + c * 0.1, 0.4 * cold);
	c *= 1.0 - 0.1 * cold;
	// warmth
	c = mix(c, c * vec3(1.1, 1.02, 0.86) + vec3(0.04, 0.02, 0.0), air * 0.5);
	// the burner's light from inside: strongest low in the envelope, fading upward
	float g = air * smoothstep(80.0, 6.0, length((lp - vec2(0.0, -8.0)) * vec2(1.0, 0.8)));
	c += vec3(1.0, 0.7, 0.25) * g * 0.26 * mask;
	// a hot top shimmers faintly
	c += vec3(0.08, 0.05, 0.0) * air * mask * (0.5 + 0.5 * sin(TIME * 5.0 + lp.y * 0.12)) * smoothstep(-20.0, -60.0, lp.y);
	COLOR = vec4(c, COLOR.a);
}
