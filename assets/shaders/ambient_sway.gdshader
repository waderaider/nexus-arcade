shader_type spatial;
render_mode unshaded, cull_disabled;
// Animator's vertex-shader sway: pennants, banners, awnings, grass.
// Phase comes from the instance world position, so N instances never sync.
// sway_f ramps with UV.y (0 = pinned edge, 1 = free edge).
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float sway_amp = 0.08;
uniform float sway_speed = 1.6;
uniform float gust_amp = 0.05;
uniform float gust_speed = 0.23;

void vertex() {
	vec3 ipos = vec3(MODEL_MATRIX[3][0], MODEL_MATRIX[3][1], MODEL_MATRIX[3][2]);
	float phase = ipos.x * 1.7 + ipos.z * 2.3 + ipos.y * 1.1;
	float f = clamp(UV.y, 0.0, 1.0);
	float gust = 0.5 + 0.5 * sin(TIME * gust_speed * 6.2831 + phase * 0.37);
	float amp = (sway_amp + gust_amp * gust) * f;
	VERTEX.x += sin(TIME * sway_speed + phase) * amp;
	VERTEX.z += cos(TIME * sway_speed * 0.8 + phase * 1.3) * amp * 0.6;
}

void fragment() {
	ALBEDO = albedo_color.rgb;
	ALPHA = albedo_color.a;
}
