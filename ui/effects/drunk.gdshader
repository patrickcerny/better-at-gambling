shader_type canvas_item;
// Beer: wobbly, double-vision blur over the 3D view (drawn under the HUD).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	uv.x += sin(TIME * 1.7 + uv.y * 6.0) * 0.006 * strength;
	uv.y += cos(TIME * 1.3 + uv.x * 5.0) * 0.005 * strength;
	vec3 base = textureLod(screen_tex, uv, 1.6 * strength).rgb;
	vec2 offset = vec2(0.014 * sin(TIME * 0.9), 0.004 * cos(TIME * 1.1)) * strength;
	vec3 ghost = textureLod(screen_tex, uv + offset, 2.2 * strength).rgb;
	COLOR = vec4(mix(base, ghost, 0.4 * strength), 1.0);
}
