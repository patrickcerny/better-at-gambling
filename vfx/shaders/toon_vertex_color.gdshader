// Simple stylised lit shader: soft 3-step ramp + warm rim, cheap and readable (docs/ART_DIRECTION.md).
// Outfit pieces (OutfitMeshes): the beans' toon look, albedo times the vertex colour; client only.
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.9, 0.8, 0.6, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec4 rim_color : source_color = vec4(1.0, 0.82, 0.5, 1.0);
uniform float steps = 3.0;
uniform float softness : hint_range(0.0, 0.5) = 0.08;
// Vertex alpha below 1 marks a twinkling part (stars on a wizard's robe, light-up soles): it
// glows in its own colour, pulsing over time, the less alpha the brighter.
varying vec3 v_pos;

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	ALBEDO = albedo.rgb * COLOR.rgb;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	float glow = 1.0 - COLOR.a;
	if (glow > 0.01) {
		float pulse = 0.5 + 0.5 * sin(TIME * 3.0 + dot(v_pos, vec3(23.1, 17.7, 11.3)));
		EMISSION = COLOR.rgb * glow * (0.4 + 2.2 * pulse);
	}
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	// Banded ramp with slightly softened band edges so it never looks aliased.
	float x = ndl * steps;
	float band = floor(x);
	float ramp = (band + smoothstep(1.0 - softness, 1.0, fract(x))) / steps;
	ramp = mix(0.3, 1.0, ramp);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ramp / 3.14159;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * rim_strength;
	DIFFUSE_LIGHT += rim_color.rgb * LIGHT_COLOR * rim * ATTENUATION * clamp(dot(NORMAL, LIGHT) + 0.4, 0.0, 1.0) / 3.14159;
}
