// The bean's mouth, drawn on a small patch that hugs the face (AvatarVisuals): one shape that
// blends between a flat line `-`, a smile, a frown, a toothy grin and a round `O`.
//   smile  -1 (frown) .. 1 (grin): how far the corners curl
//   open    0 (closed line) .. 1 (wide open)
//   round   0 (lens mouth) .. 1 (round `O`)
//   style   the mouth piece worn (OutfitMeshes.MOUTH_STYLES): 0 plain, 1 tongue out, 2 buck
//           teeth, 3 lipstick, 4 a gold tooth, 5 fangs, 6 a gold grill
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float smile : hint_range(-1.0, 1.0) = 0.3;
uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform float round_o : hint_range(0.0, 1.0) = 0.0;
uniform float width : hint_range(0.3, 1.0) = 0.62;
// Lifts one corner more than the other (a cocky half-smile).
uniform float smirk : hint_range(-1.0, 1.0) = 0.0;
uniform vec4 line_color : source_color = vec4(0.13, 0.08, 0.08, 1.0);
uniform vec4 inside_color : source_color = vec4(0.36, 0.08, 0.1, 1.0);
uniform vec4 tongue_color : source_color = vec4(0.93, 0.42, 0.45, 1.0);
uniform vec4 teeth_color : source_color = vec4(0.98, 0.96, 0.9, 1.0);
uniform vec4 gold_color : source_color = vec4(0.85, 0.68, 0.32, 1.0);
uniform vec4 lipstick_color : source_color = vec4(0.7, 0.14, 0.18, 1.0);
uniform int style = 0;

float sd_box(vec2 p, vec2 h) {
	vec2 q = abs(p) - h;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
}

// The piece's shape hanging under the lips (distance, < 0 inside) and its colour.
float extra(vec2 p, float lower, out vec3 col) {
	col = teeth_color.rgb;
	if (style == 1) {
		vec2 q = (p - vec2(0.12, lower - 0.08)) / vec2(0.15, 0.17);
		col = abs(p.x - 0.12) < 0.012 && p.y < lower - 0.05 ? tongue_color.rgb * 0.8 : tongue_color.rgb;
		return max((length(q) - 1.0) * 0.15, p.y - lower - 0.02);
	} else if (style == 2) {
		return sd_box(vec2(abs(p.x) - 0.095, p.y - (lower - 0.09)), vec2(0.075, 0.11)) - 0.02;
	} else if (style == 4) {
		col = gold_color.rgb;
		return sd_box(p - vec2(0.17, lower - 0.06), vec2(0.06, 0.075)) - 0.015;
	} else if (style == 5) {
		vec2 q = vec2(abs(p.x) - 0.3, p.y - lower);
		float wid = 0.065 * clamp(1.0 + q.y / 0.21, 0.0, 1.0);
		return max(abs(q.x) - wid, max(q.y - 0.04, -q.y - 0.21));
	} else if (style == 6) {
		col = fract(p.x * 7.0) < 0.12 ? gold_color.rgb * 0.7 : gold_color.rgb;
		return sd_box(p - vec2(0.0, lower - 0.05), vec2(0.36, 0.065)) - 0.02;
	}
	return 1.0;
}

void fragment() {
	// x: -1 (left) .. 1 (right), y: -1 (down) .. 1 (up).
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float w = width;
	float k = clamp(1.0 - (p.x * p.x) / (w * w), 0.0, 1.0);
	// The mouth's centre line curls up at the corners for a smile, down for a frown.
	float centre = smile * 0.5 * ((p.x * p.x) / (w * w) - 0.45) + smirk * 0.5 * pow(max(p.x / w, 0.0), 2.0);
	float line = style == 3 ? 0.11 : 0.075;
	float upper = centre + line + open * 0.18 * k;
	float lower = centre - line - open * 0.85 * k;
	float d_lens = max(max(lower - p.y, p.y - upper), abs(p.x) - w);
	vec2 o = vec2(p.x / (0.36 + 0.3 * open), (p.y + 0.1) / (0.36 + 0.52 * open));
	float d_round = (length(o) - 1.0) * 0.28;
	float d = mix(d_lens, d_round, round_o);
	vec3 piece;
	float de = extra(p, lower, piece);
	if (d > 0.0 && de > 0.0) {
		discard;
	}
	vec3 lc = style == 3 ? lipstick_color.rgb : line_color.rgb;
	if (de <= 0.0 && (d > -0.05 || open < 0.12 || style == 5 || style == 2)) {
		ALBEDO = de > -0.03 ? lc : piece;
	} else {
		vec3 c = lc;
		float rim = 0.05;
		if (open > 0.12 && d < -rim) {
			c = inside_color.rgb;
			float floor_y = mix(lower, -0.1 - (0.34 + 0.52 * open), round_o);
			if (p.y < floor_y + 0.32 * open) {
				c = tongue_color.rgb;
			}
			float roof = mix(upper, -0.1 + (0.34 + 0.52 * open), round_o);
			if (smile > 0.25 && round_o < 0.5 && p.y > roof - 0.16 * open) {
				c = style == 6 || (style == 4 && p.x > 0.1 && p.x < 0.24) ? gold_color.rgb : teeth_color.rgb;
			}
		}
		ALBEDO = c;
	}
}
