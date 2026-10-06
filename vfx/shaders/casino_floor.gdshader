// Casino floors from world position, no textures (docs/ART_DIRECTION.md: simple, low-poly):
// mode 0 = patterned carpet (diamond lattice + small gold dots), mode 1 = marble checkerboard
// with soft veins. One cheap fragment function, fine on gl_compatibility.
shader_type spatial;
render_mode cull_back;

uniform int mode = 0;
uniform vec4 base_color : source_color = vec4(0.42, 0.13, 0.13, 1.0);
uniform vec4 alt_color : source_color = vec4(0.32, 0.09, 0.10, 1.0);
uniform vec4 accent_color : source_color = vec4(0.84, 0.66, 0.29, 1.0);
uniform float tile = 1.2;
uniform float roughness_value = 0.95;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = world_pos.xz / tile;
	vec3 col;
	if (mode == 0) {
		// Diamond lattice: |x| + |y| distance inside each cell.
		vec2 c = fract(p) - 0.5;
		float d = abs(c.x) + abs(c.y);
		col = mix(base_color.rgb, alt_color.rgb, step(0.32, d));
		float line = smoothstep(0.035, 0.0, abs(d - 0.32));
		col = mix(col, accent_color.rgb * 0.55, line * 0.6);
		float dot_ = smoothstep(0.07, 0.04, length(c));
		col = mix(col, accent_color.rgb * 0.8, dot_);
		ROUGHNESS = roughness_value;
		SPECULAR = 0.1;
	} else {
		vec2 cell = floor(p);
		float checker = mod(cell.x + cell.y, 2.0);
		col = mix(base_color.rgb, alt_color.rgb, checker);
		float vein = noise(p * 1.7 + vec2(noise(p * 0.6) * 2.5));
		vein = smoothstep(0.46, 0.5, vein) * smoothstep(0.54, 0.5, vein);
		col = mix(col, col * 0.86, vein * 0.5);
		vec2 g = abs(fract(p) - 0.5);
		float grout = smoothstep(0.485, 0.5, max(g.x, g.y));
		col = mix(col, accent_color.rgb * 0.7, grout * 0.8);
		ROUGHNESS = roughness_value;
		SPECULAR = 0.5;
	}
	ALBEDO = col;
}
