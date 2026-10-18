shader_type canvas_item;
// Sand haze as ONE quad over all the layers: clear around the balloon's own layer, thicker the further a layer is.
uniform float band_bottom = 1640.0;
uniform float lane_h = 200.0;
uniform float focus = 0.0;
uniform float clear_lanes = 1.0;
uniform float per_lane = 0.38;
uniform float max_alpha = 0.9;
varying float wy;

void vertex() {
	wy = VERTEX.y + 330.0;   // the quad's top is at the top of the highest layer
}

void fragment() {
	float lane = floor((band_bottom - wy) / lane_h);
	float a = clamp((abs(lane - focus) - clear_lanes) * per_lane, 0.0, max_alpha);
	COLOR = vec4(0.93, 0.8, 0.56, a);
}
