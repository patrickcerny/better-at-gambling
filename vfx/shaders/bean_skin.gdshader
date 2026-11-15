// Animated bean skins (CosmeticDef KIND_SKIN, ToonMaterial.make_skin): a moving pattern over the
// whole bean, in the beans' toon light (soft 3-band ramp + warm rim). Warm casino colours, no neon
// (docs/ART_DIRECTION.md). `mode`: 0 gold rush, 1 rainbow, 2 molten lava, 3 starry night,
// 4 lucky felt, 5 candy swirl, 6 deep sea, 7 marble, 8 the house (developers only). Client only.
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
	} else if (mode == 8) {
		// The House (developers only): black lacquer with burgundy depth, gold filigree flowing up,
		// card suits raining down in gold and red, a gold scan ring rising, embers in the cracks.
		float deep = fbm(p * 2.2 + vec3(0.0, -t * 0.15, 0.0));
		c = mix(vec3(0.03, 0.02, 0.02), vec3(0.28, 0.04, 0.07), smoothstep(0.35, 0.8, deep));
		// Filigree: two interleaved sine scrolls, gold lines.
		float f1 = sin(ang * 6.0 + p.y * 9.0 - t * 0.9 + sin(p.y * 4.0 + t * 0.4) * 1.5);
		float f2 = sin(ang * -6.0 + p.y * 9.0 - t * 0.7 + 1.57);
		float fil = max(smoothstep(0.09, 0.0, abs(f1)), smoothstep(0.09, 0.0, abs(f2)) * 0.8);
		fil *= smoothstep(0.3, 0.55, noise3(p * 4.0 + vec3(0.0, -t * 0.3, 0.0)) + 0.2);
		vec3 gold = vec3(0.95, 0.72, 0.28);
		c = mix(c, gold, fil);
		e += vec3(0.55, 0.36, 0.08) * fil * (0.6 + 0.4 * sin(t * 3.0 + p.y * 6.0));
		// Falling suits: diamonds (red) and spades-ish drops (gold) in a column grid round the bean.
		vec2 q = vec2(ang / 6.2832 * 14.0, p.y * 5.0 + t * 0.8);
		vec2 cid = floor(q);
		q.y += hash3(vec3(cid.x, 0.0, 7.0)) * 10.0;
		cid = floor(q);
		vec2 lq = fract(q) - 0.5;
		float h = hash3(vec3(cid, 1.3));
		float on = step(0.72, h);
		float dia = smoothstep(0.26, 0.2, abs(lq.x) + abs(lq.y) * 0.75);
		float drop = smoothstep(0.24, 0.18, length(lq + vec2(0.0, 0.06))) + smoothstep(0.2, 0.14, abs(lq.x) + abs(lq.y - 0.12) * 1.3);
		float suit = on * (h > 0.86 ? dia : clamp(drop, 0.0, 1.0));
		vec3 sc = h > 0.86 ? vec3(0.85, 0.12, 0.12) : gold;
		c = mix(c, sc, suit);
		e += sc * suit * 0.7;
		// Scan ring: a thin gold band climbing the bean every 2.5 s, flaring the filigree as it passes.
		float ring = fract(t * 0.4) * 2.4 - 1.2;
		float band = smoothstep(0.06, 0.0, abs(p.y - ring));
		c = mix(c, vec3(1.0, 0.86, 0.5), band * 0.8);
		e += vec3(1.0, 0.75, 0.3) * (band * 1.4 + fil * smoothstep(0.35, 0.0, abs(p.y - ring)));
		// Embers: rare glints in the dark lacquer.
		vec3 cell = floor(p * 26.0);
		float em = step(0.96, hash3(cell)) * pow(max(sin(t * 3.0 + hash3(cell + 2.7) * 40.0), 0.0), 6.0);
		e += vec3(1.0, 0.55, 0.2) * em * smoothstep(0.5, 0.1, length(fract(p * 26.0) - 0.5));
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
