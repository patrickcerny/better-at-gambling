// The bean's mouth, drawn on a small patch that hugs the face (AvatarVisuals): one shape that
// blends between a flat line `-`, a smile, a frown, a toothy grin and a round `O`.
//   smile  -1 (frown) .. 1 (grin): how far the corners curl
//   open    0 (closed line) .. 1 (wide open)
//   round   0 (lens mouth) .. 1 (round `O`)
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

void fragment() {
	// x: -1 (left) .. 1 (right), y: -1 (down) .. 1 (up).
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float w = width;
	float k = clamp(1.0 - (p.x * p.x) / (w * w), 0.0, 1.0);
	// The mouth's centre line curls up at the corners for a smile, down for a frown.
	float centre = smile * 0.5 * ((p.x * p.x) / (w * w) - 0.45) + smirk * 0.5 * pow(max(p.x / w, 0.0), 2.0);
	float line = 0.075;
	float upper = centre + line + open * 0.18 * k;
	float lower = centre - line - open * 0.85 * k;
	float d_lens = max(max(lower - p.y, p.y - upper), abs(p.x) - w);
	vec2 o = vec2(p.x / (0.36 + 0.3 * open), (p.y + 0.1) / (0.36 + 0.52 * open));
	float d_round = (length(o) - 1.0) * 0.28;
	float d = mix(d_lens, d_round, round_o);
	if (d > 0.0) {
		discard;
	}
	vec3 c = line_color.rgb;
	float rim = 0.05;
	if (open > 0.12 && d < -rim) {
		c = inside_color.rgb;
		float floor_y = mix(lower, -0.1 - (0.34 + 0.52 * open), round_o);
		if (p.y < floor_y + 0.32 * open) {
			c = tongue_color.rgb;
		}
		float roof = mix(upper, -0.1 + (0.34 + 0.52 * open), round_o);
		if (smile > 0.25 && round_o < 0.5 && p.y > roof - 0.16 * open) {
			c = teeth_color.rgb;
		}
	}
	ALBEDO = c;
}
