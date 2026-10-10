// The minigame curtain (MatchScene): heavy burgundy velvet in vertical pleats with gold piping on
// the leading edge and a gold fringe along the hem. As it opens (`gather` 0 → 1) the fabric is
// pulled to the outer edge and caught by a gold rope tieback, so the leading edge sweeps into the
// classic hourglass swag. `mode` 1 draws the top valance instead: scalloped swags with a fringe.
shader_type canvas_item;

uniform float gather : hint_range(0.0, 1.0) = 0.0;
// 0: left panel (outer edge on the left), 1: right panel (mirrored).
uniform float mirrored = 0.0;
uniform float mode = 0.0;
uniform float folds = 7.0;
uniform vec4 velvet_dark : source_color = vec4(0.17, 0.035, 0.06, 1.0);
uniform vec4 velvet : source_color = vec4(0.408, 0.122, 0.173, 1.0);
uniform vec4 velvet_light : source_color = vec4(0.62, 0.2, 0.25, 1.0);
uniform vec4 gold : source_color = vec4(0.84, 0.66, 0.29, 1.0);
uniform vec4 gold_light : source_color = vec4(1.0, 0.86, 0.5, 1.0);
uniform vec4 gold_dark : source_color = vec4(0.48, 0.33, 0.1, 1.0);
// Panel height over width in pixels (keeps the fringe and rope round on any window).
uniform float aspect = 2.0;

const float TIE_Y = 0.6;

vec3 velvet_at(float u, float y, float n) {
	// One pleat = a soft cosine ridge with a sharper dark crease in the valley between ridges.
	float ph = u * n;
	float ridge = pow(0.5 + 0.5 * cos(ph * 6.28318), 0.7);
	float crease = smoothstep(0.08, 0.0, abs(fract(ph) - 0.5));
	vec3 c = mix(velvet_dark.rgb, velvet.rgb, smoothstep(0.0, 0.55, ridge));
	c = mix(c, velvet_light.rgb, smoothstep(0.7, 1.0, ridge) * 0.55);
	c *= 1.0 - crease * 0.35;
	// Shadow under the rail at the top, a little light pooling lower down.
	c *= mix(0.55, 1.0, smoothstep(0.0, 0.18, y));
	c *= 0.92 + 0.08 * smoothstep(0.3, 0.9, y);
	return c;
}

vec4 fringe(float u, float y, float y0, float h, float px) {
	// A gold braid on top, tassels hanging below it with rounded tips.
	float t = (y - y0) / h;
	float tassel = fract(u * px);
	float hang = 1.0 - 0.3 * smoothstep(0.0, 0.5, abs(tassel - 0.5));
	if (t > hang) {
		return vec4(0.0);
	}
	vec3 c;
	if (t < 0.32) {
		float braid = fract(u * px * 0.5 + t * 4.0);
		c = mix(gold_dark.rgb, gold_light.rgb, smoothstep(0.0, 0.5, braid) * smoothstep(1.0, 0.5, braid));
	} else {
		float strand = 0.5 + 0.5 * cos(tassel * 6.28318 * 3.0);
		c = mix(gold_dark.rgb, gold.rgb, strand);
		c = mix(c, gold_light.rgb, smoothstep(0.85, 1.0, strand) * 0.6);
		c *= 1.0 - 0.35 * smoothstep(0.0, 0.5, abs(tassel - 0.5));
	}
	return vec4(c, 1.0);
}

vec4 valance(vec2 uv) {
	// Three swags per screen hanging from the top, fringe on their scalloped hem.
	float sw = fract(uv.x * 3.0);
	float hem = 0.62 + 0.3 * sin(sw * 3.14159);
	if (uv.y > hem + 0.22) {
		return vec4(0.0);
	}
	if (uv.y > hem) {
		return fringe(uv.x * 3.0, uv.y, hem, 0.22, 26.0);
	}
	vec3 c = velvet_at(sw, uv.y * 0.5 + 0.1, 1.0);
	// Horizontal drape folds following the swag curve.
	float drape = 0.5 + 0.5 * cos((uv.y / hem) * 6.28318 * 2.5);
	c = mix(c * 0.65, c, drape);
	return vec4(c, 1.0);
}

vec4 panel(vec2 uv) {
	// x measured from the outer edge (0) to the leading edge (1).
	float x = mirrored > 0.5 ? 1.0 - uv.x : uv.x;
	float y = uv.y;
	// The leading edge: straight when closed, swept into an hourglass at the tieback when open.
	float k = 1.0 - smoothstep(0.0, 0.62, abs(y - TIE_Y));
	float top_pull = 0.5 * smoothstep(TIE_Y, 0.0, y);
	float edge = clamp(1.0 - gather * (0.5 + 0.4 * k - 0.1 * top_pull), 0.08, 1.0);
	if (x > edge) {
		return vec4(0.0);
	}
	float u = x / edge;  // across the (gathered) fabric
	float hem_y = 0.955 - 0.015 * gather * (1.0 - u);
	if (y > hem_y) {
		return fringe(u * edge * 6.0, y, hem_y, 1.0 - hem_y, 9.0);
	}
	// Bunching: more, tighter folds where the fabric is pulled in.
	float n = folds * (1.0 + gather * 0.6 * k);
	vec3 c = velvet_at(u, y, n);
	// Shade towards the leading edge and give it gold piping.
	c *= mix(1.0, 0.7, smoothstep(0.75, 1.0, u));
	float pipe = smoothstep(0.991, 0.995, u);
	c = mix(c, mix(gold.rgb, gold_light.rgb, 0.5 + 0.5 * sin(y * 400.0)), pipe);
	// Gold rope tieback across the gathered fabric (fades in as the curtain opens).
	float show = smoothstep(0.05, 0.25, gather);
	float dy = (y - TIE_Y) / 0.018;
	if (abs(dy) < 1.0) {
		float twist = fract((x * 40.0 + dy * 0.6) * aspect * 0.25);
		vec3 r = mix(gold_dark.rgb, gold_light.rgb, smoothstep(0.0, 0.5, twist) * smoothstep(1.0, 0.5, twist));
		r *= 0.75 + 0.25 * (1.0 - dy * dy);
		c = mix(c, r, show);
	}
	// The rope's tassel hangs at the leading edge.
	float ty = (y - TIE_Y) / 0.09;
	if (ty > 0.0 && ty < 1.0 && abs(x - edge + 0.012) < 0.012 + 0.025 * ty) {
		float strand = 0.5 + 0.5 * cos(x * 900.0);
		c = mix(c, mix(gold_dark.rgb, gold.rgb, strand), show);
	}
	return vec4(c, 1.0);
}

void fragment() {
	vec4 c = mode > 0.5 ? valance(UV) : panel(UV);
	if (c.a < 0.5) {
		discard;
	}
	COLOR = c;
}
