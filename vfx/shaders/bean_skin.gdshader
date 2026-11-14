// Animated bean skins (CosmeticDef KIND_SKIN, ToonMaterial.make_skin): a moving pattern over the
// whole bean, in the beans' toon light (soft 3-band ramp + warm rim). Warm casino colours, no neon
// (docs/ART_DIRECTION.md). `mode`: 0 gold rush, 1 rainbow, 2 molten lava, 3 starry night,
// 4 lucky felt, 5 candy swirl, 6 deep sea, 7 marble. Client only.
shader_type spatial;
render_mode cull_back;

uniform int mode = 0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.4;
uniform vec4 rim_color : source_color = vec4(1.0, 0.82, 0.5, 1.0);
uniform float steps = 3.0;
uniform float softness : hint_range(0.0, 0.5) = 0.08;

varying vec3 v_pos;

void vertex() {
	v_pos = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

vec3 hsv(float h, float s, float v) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), k, s);
}

void fragment() {
	vec3 p = v_pos;
	float t = TIME;
	float ang = atan(p.x, -p.z);
	vec3 c;
	vec3 e = vec3(0.0);
	if (mode == 0) {
		// Gold rush: polished gold, a shine sweeping up over it, glints popping.
		c = mix(vec3(0.55, 0.36, 0.1), vec3(0.95, 0.75, 0.32), fbm(p * 3.0) * 0.7 + 0.25);
		float sweep = smoothstep(0.1, 0.0, abs(fract(p.y * 0.6 - p.x * 0.35 - t * 0.35) - 0.5));
		c += vec3(0.35, 0.28, 0.12) * sweep;
		e += vec3(0.3, 0.22, 0.06) * sweep;
		vec3 cell = floor(p * 22.0);
		float glint = step(0.93, hash3(cell)) * pow(max(sin(t * 4.0 + hash3(cell + 3.1) * 30.0), 0.0), 8.0);
		e += vec3(1.0, 0.85, 0.5) * glint * smoothstep(0.5, 0.1, length(fract(p * 22.0) - 0.5));
	} else if (mode == 1) {
		// Rainbow: soft bands rolling up and around the bean.
		float h = fract(p.y * 0.45 + ang / 6.2832 * 0.5 - t * 0.12);
		c = hsv(h, 0.55, 0.9);
		e = c * 0.08;
	} else if (mode == 2) {
		// Molten lava: dark crust, glowing cracks flowing down.
		float n = fbm(p * 3.0 + vec3(0.0, t * 0.25, 0.0));
		float crack = smoothstep(0.06, 0.0, abs(n - 0.5));
		float heat = 0.5 + 0.5 * sin(t * 1.7 + n * 9.0);
		c = mix(vec3(0.12, 0.06, 0.05), vec3(0.95, 0.42, 0.1), crack);
		e = vec3(1.0, 0.4, 0.08) * crack * (0.8 + 0.6 * heat) + vec3(0.25, 0.05, 0.0) * smoothstep(0.18, 0.0, abs(n - 0.5));
	} else if (mode == 3) {
		// Starry night: deep blue swirls, stars twinkling.
		float sw = fbm(vec3(ang * 1.5 + t * 0.05, p.y * 2.0 - t * 0.08, 0.0) * 1.8 + p);
		c = mix(vec3(0.07, 0.08, 0.24), vec3(0.28, 0.17, 0.4), sw);
		vec3 cell = floor(p * 18.0);
		float h = hash3(cell);
		float star = step(0.88, h) * smoothstep(0.35, 0.0, length(fract(p * 18.0) - 0.5)) * (0.4 + 0.6 * sin(t * 3.0 + h * 40.0));
		star = max(star, 0.0);
		c += vec3(1.0, 0.92, 0.75) * star;
		e = vec3(1.0, 0.92, 0.75) * star * 1.5 + c * 0.05;
	} else if (mode == 4) {
		// Lucky felt: table felt with a gold diamond lattice drifting up.
		c = vec3(0.12, 0.33, 0.24) + vec3(noise3(p * 60.0) * 0.05);
		vec2 q = vec2(ang * 1.6, p.y * 3.0 - t * 0.2);
		vec2 g = abs(fract(vec2(q.x + q.y, q.x - q.y)) - 0.5);
		float line = smoothstep(0.045, 0.0, min(g.x, g.y));
		c = mix(c, vec3(0.85, 0.66, 0.3), line * 0.85);
		e = vec3(0.4, 0.28, 0.08) * line * (0.5 + 0.5 * sin(t * 2.0 + q.y * 3.0));
	} else if (mode == 5) {
		// Candy swirl: stripes twisting round the bean.
		float s = fract(ang / 6.2832 * 4.0 + p.y * 1.2 - t * 0.25);
		c = s < 0.42 ? vec3(0.93, 0.55, 0.6) : (s < 0.5 ? vec3(0.72, 0.18, 0.16) : vec3(0.97, 0.92, 0.85));
	} else if (mode == 6) {
		// Deep sea: light rippling over blue-green water.
		float w = sin(p.x * 9.0 + t * 1.1 + sin(p.y * 7.0 - t)) + sin(p.y * 11.0 - t * 1.3 + sin(p.z * 8.0 + t * 0.7)) + sin(p.z * 10.0 + t * 0.9);
		float caus = smoothstep(0.35, 0.0, abs(w));
		c = mix(vec3(0.06, 0.2, 0.32), vec3(0.15, 0.42, 0.45), clamp(0.5 + p.y * 0.5, 0.0, 1.0));
		c += vec3(0.45, 0.7, 0.62) * caus * 0.6;
		e = vec3(0.25, 0.45, 0.4) * caus * 0.4;
	} else {
		// Marble: slowly drifting veins with gold flecks.
		float v = sin(p.y * 5.0 + fbm(p * 2.5 + vec3(t * 0.03)) * 6.0);
		float vein = smoothstep(0.14, 0.0, abs(v));
		c = mix(vec3(0.9, 0.86, 0.8), vec3(0.4, 0.37, 0.35), vein * 0.8);
		float fleck = step(0.975, hash3(floor(p * 30.0)));
		c = mix(c, vec3(0.85, 0.66, 0.3), fleck);
		e = vec3(0.6, 0.42, 0.12) * fleck * (0.5 + 0.5 * sin(t * 2.0 + p.x * 20.0));
	}
	ALBEDO = c;
	EMISSION = e;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float x = ndl * steps;
	float band = floor(x);
	float ramp = (band + smoothstep(1.0 - softness, 1.0, fract(x))) / steps;
	ramp = mix(0.3, 1.0, ramp);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ramp / 3.14159;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * rim_strength;
	DIFFUSE_LIGHT += rim_color.rgb * LIGHT_COLOR * rim * ATTENUATION * clamp(dot(NORMAL, LIGHT) + 0.4, 0.0, 1.0) / 3.14159;
}
