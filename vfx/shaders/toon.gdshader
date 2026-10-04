// Simple stylised lit shader: 3-step ramp + warm rim, cheap and readable (docs/ART_DIRECTION.md).
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.9, 0.8, 0.6, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;
uniform vec4 rim_color : source_color = vec4(0.84, 0.66, 0.29, 1.0);
uniform float steps = 3.0;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float ramp = floor(clamp(ndl * 0.5 + 0.5, 0.0, 1.0) * steps) / steps;
	ramp = mix(0.35, 1.0, ramp);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ramp / 3.14159;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * rim_strength;
	DIFFUSE_LIGHT += rim_color.rgb * rim * ATTENUATION * 0.5;
}
