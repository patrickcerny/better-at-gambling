shader_type canvas_item;
// Soft blur, warm darkening and a vignette over the live casino panorama (menu and loading
// screen). Two 3x3 rings (full and half radius) on the half-resolution viewport texture: soft
// enough without the grid pattern a single wide ring leaves.

uniform float blur_px : hint_range(0.0, 8.0) = 2.0;
uniform float darken : hint_range(0.0, 1.0) = 0.35;
uniform float vignette : hint_range(0.0, 2.0) = 0.9;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * blur_px;
	vec3 c = vec3(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 o = vec2(float(x), float(y));
			c += texture(TEXTURE, UV + o * px).rgb;
			c += texture(TEXTURE, UV + o * px * 0.5).rgb;
		}
	}
	c /= 18.0;
	float d = distance(UV, vec2(0.5));
	c *= (1.0 - darken) * (1.0 - vignette * d * d);
	COLOR = vec4(c, 1.0);
}
