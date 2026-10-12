shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Animator's cloud layer: procedural puffs scrolling at TIME speed.
// 0 CPU, 0 textures, 1 draw per layer.
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float scroll_speed = 0.03;
uniform float coverage = 0.45;
uniform float alpha = 0.5;

void fragment() {
	vec2 uv = UV + vec2(TIME * scroll_speed, TIME * scroll_speed * 0.63);
	float n = sin(uv.x * 21.0) * sin(uv.y * 17.0 + 1.3)
		* sin((uv.x + uv.y) * 13.0 + 4.1) * sin(uv.x * 7.0 - uv.y * 9.0);
	n = n * 0.5 + 0.5;
	float a = smoothstep(1.0 - coverage - 0.28, 1.0 - coverage + 0.28, n) * alpha;
	ALBEDO = cloud_color.rgb;
	ALPHA = a;
}
