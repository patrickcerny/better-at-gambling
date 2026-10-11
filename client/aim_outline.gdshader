shader_type spatial;
// Gold outline on the player an aimed item would hit (ItemController). The hull grows along the
// normal in world space by `width` metres, so it stays thin whatever the mesh's node or bone
// scale (StandardMaterial3D's grow works in model space and blew up on scaled character skins).
render_mode unshaded, cull_front, shadows_disabled, skip_vertex_transform;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float width = 0.03;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = MODEL_NORMAL_MATRIX * NORMAL;
	float len = length(n);
	if (len > 0.00001) {
		world += n / len * width;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}

void fragment() {
	ALBEDO = color.rgb;
}
