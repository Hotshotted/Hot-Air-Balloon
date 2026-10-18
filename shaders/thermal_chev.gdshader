shader_type canvas_item;
// Rising chevrons inside the thermals, positioned entirely here. INSTANCE_CUSTOM = (column, x offset -1..1, y phase).
uniform float th_x[3];
uniform float hw = 95.0;
uniform float band_top = 330.0;
uniform float band_bottom = 1640.0;

void vertex() {
	int c = int(INSTANCE_CUSTOM.x + 0.5);
	float y = band_top + fract(INSTANCE_CUSTOM.z - TIME * 0.22) * (band_bottom - band_top);
	VERTEX = vec2(th_x[c] + INSTANCE_CUSTOM.y * hw + VERTEX.x, y + VERTEX.y);
}
