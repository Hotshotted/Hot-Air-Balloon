shader_type canvas_item;
// Time of day: a warm (dawn) or violet (dusk) wash over the sky and scenery, strongest near the horizon. tint.a = strength.
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.42, 0.0);
void fragment() {
	COLOR = vec4(tint.rgb, tint.a * mix(0.45, 1.0, UV.y));
}
