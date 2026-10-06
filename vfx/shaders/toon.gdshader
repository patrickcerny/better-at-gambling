// Simple stylised lit shader: soft 3-step ramp + warm rim, cheap and readable (docs/ART_DIRECTION.md).
// Used for the beans (client only, see ToonMaterial). Ambient light is applied by the engine as usual.
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.9, 0.8, 0.6, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec4 rim_color : source_color = vec4(1.0, 0.82, 0.5, 1.0);
uniform float steps = 3.0;
uniform float softness : hint_range(0.0, 0.5) = 0.08;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
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
