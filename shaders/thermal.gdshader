shader_type canvas_item;
// Thermal columns (Sahara) as one quad: a light warm fill with brighter edges, up to three columns.
uniform float th_x[3];
uniform int th_n = 0;
uniform float hw = 95.0;
varying float wx;

void vertex() {
	wx = VERTEX.x;
}

void fragment() {
	float fill = 0.0;
	float edge = 0.0;
	for (int i = 0; i < 3; i++) {
		if (i >= th_n) {
			break;
		}
		float d = abs(wx - th_x[i]);
		fill = max(fill, step(d, hw));
		edge = max(edge, step(abs(d - hw), 1.6));
	}
	COLOR = vec4(1.0, mix(0.62, 0.7, edge), mix(0.2, 0.3, edge), max(fill * 0.16, edge * 0.5));
}
