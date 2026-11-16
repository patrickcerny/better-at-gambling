shader_type spatial;
// The plate behind a results name tag (ResultsStage): a rounded walnut card with a brass border
// and a stripe in the player's colour along the top. Always faces the camera like its Label3D.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 fill : source_color = vec4(0.11, 0.075, 0.06, 0.88);
uniform vec4 border : source_color = vec4(0.84, 0.66, 0.29, 1.0);
uniform vec4 accent : source_color = vec4(0.89, 0.73, 0.36, 1.0);
uniform vec2 size = vec2(1.6, 0.6);
uniform float radius = 0.12;
uniform float border_w = 0.022;
uniform float accent_h = 0.05;

void vertex() {
	// Billboard: keep the node's position and scale, take the camera's rotation.
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc.x, INV_VIEW_MATRIX[1] * sc.y, INV_VIEW_MATRIX[2] * sc.z, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 q = abs(p) - (size * 0.5 - vec2(radius));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float aa = fwidth(d) * 0.75;
	float inside = 1.0 - smoothstep(-aa, aa, d);
	if (inside <= 0.001) {
		discard;
	}
	float edge = smoothstep(-border_w - aa, -border_w + aa, d);
	vec4 c = fill;
	// The colour stripe just inside the top edge.
	float top = size.y * 0.5 - border_w * 1.6;
	if (p.y < 0.0 && -p.y > top - accent_h && -p.y < top && abs(p.x) < size.x * 0.5 - radius * 0.6) {
		c = accent;
	}
	c = mix(c, border, edge);
	ALBEDO = c.rgb;
	ALPHA = c.a * inside;
}
