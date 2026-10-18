shader_type canvas_item;
// The Rising Storm: everything below `top_y` is dark storm cloud with a rolling, ragged top edge. One full-screen quad.
uniform float top_y = 2000.0;
varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

void fragment() {
	float edge = top_y + sin(wp.x * 0.018 + TIME * 1.3) * 16.0 + sin(wp.x * 0.047 - TIME * 0.9) * 9.0;
	float a = smoothstep(edge - 26.0, edge + 14.0, wp.y);
	vec3 deep = vec3(0.1, 0.08, 0.18);
	vec3 rim = vec3(0.32, 0.26, 0.42);
	float t = clamp((wp.y - edge) / 140.0, 0.0, 1.0);
	COLOR = vec4(mix(rim, deep, t), a * 0.94);
}
