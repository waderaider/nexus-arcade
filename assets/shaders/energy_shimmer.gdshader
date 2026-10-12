shader_type spatial;
render_mode unshaded;
// Animator's energy shimmer: scrolling stripe energy for goal rings,
// scoreboard chases, ward pulses. 0 CPU, 1 draw.
uniform vec4 color_a : source_color = vec4(1.0, 0.7, 0.1, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform float stripes = 24.0;
uniform float scroll_speed = 1.5;
uniform float brightness = 1.6;

void fragment() {
	float s = step(0.5, fract(UV.x * stripes + TIME * scroll_speed));
	vec3 c = mix(color_a.rgb, color_b.rgb, s);
	ALBEDO = c * brightness;
}
