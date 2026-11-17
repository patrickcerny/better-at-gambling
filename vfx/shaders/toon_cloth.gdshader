// Simple stylised lit shader: soft 3-step ramp + warm rim, cheap and readable (docs/ART_DIRECTION.md).
// Capes (CapeCloth): the outfit toon look plus cloth. UV2 is the vertex's place on the cape (u
// across, v down); `cloth` holds how far each point of a coarse NU x NV grid has moved from its rest
// place (mesh space), blended bilinearly onto the vertices. Client only.
shader_type spatial;
render_mode cull_back;

const int NU = 7;
const int NV = 6;
uniform vec3 cloth[42];

uniform vec4 albedo : source_color = vec4(0.9, 0.8, 0.6, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec4 rim_color : source_color = vec4(1.0, 0.82, 0.5, 1.0);
uniform float steps = 3.0;
uniform float softness : hint_range(0.0, 0.5) = 0.08;
// Vertex alpha below 1 marks a twinkling part (stars on a wizard's robe, light-up soles): it
// glows in its own colour, pulsing over time, the less alpha the brighter.
varying vec3 v_pos;
varying vec2 v_uv;
// The expensive capes' own life (`ToonMaterial.CAPE_FX`): a glint of light that sweeps down the
// cloth now and then, and twinkles scattered over it (0 = off).
uniform vec4 sheen_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float sheen = 0.0;
uniform float sheen_speed = 0.22;
uniform vec4 sparkle_color : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float sparkle = 0.0;

float cape_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 cloth_at(int i, int j) {
	return cloth[clamp(j, 0, NV - 1) * NU + clamp(i, 0, NU - 1)];
}

void vertex() {
	vec2 c = clamp(UV2, vec2(0.0), vec2(1.0)) * vec2(float(NU - 1), float(NV - 1));
	ivec2 g = clamp(ivec2(floor(c)), ivec2(0), ivec2(NU - 2, NV - 2));
	vec2 f = c - vec2(g);
	vec3 top = mix(cloth_at(g.x, g.y), cloth_at(g.x + 1, g.y), f.x);
	vec3 bottom = mix(cloth_at(g.x, g.y + 1), cloth_at(g.x + 1, g.y + 1), f.x);
	VERTEX += mix(top, bottom, f.y);
	v_pos = VERTEX;
	v_uv = UV2;
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
	if (sheen > 0.0) {
		// A slanted band of light running down the cape, then a pause before the next one.
		float s = fract(TIME * sheen_speed) * 1.8 - 0.4;
		float d = abs(v_uv.y * 0.85 + v_uv.x * 0.3 - s);
		float band = smoothstep(0.12, 0.0, d);
		EMISSION += sheen_color.rgb * band * band * sheen;
	}
	if (sparkle > 0.0) {
		vec2 grid = vec2(18.0, 22.0);
		vec2 cell = floor(v_uv * grid);
		float h = cape_hash(cell);
		if (h > 0.78) {
			float ph = fract(TIME * (0.35 + 0.3 * h) + h * 9.0);
			float tw = smoothstep(0.0, 0.08, ph) * smoothstep(0.22, 0.08, ph);
			vec2 off = vec2(cape_hash(cell + 3.1), cape_hash(cell + 7.7)) * 0.5 + 0.25;
			vec2 q = (fract(v_uv * grid) - off) * vec2(1.0, grid.x / grid.y);
			float star = smoothstep(0.18, 0.0, length(q)) + smoothstep(0.03, 0.0, abs(q.x)) * smoothstep(0.3, 0.0, abs(q.y)) + smoothstep(0.03, 0.0, abs(q.y)) * smoothstep(0.3, 0.0, abs(q.x));
			EMISSION += sparkle_color.rgb * tw * star * sparkle;
		}
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
