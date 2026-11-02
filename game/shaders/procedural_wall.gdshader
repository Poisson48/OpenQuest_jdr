shader_type spatial;
render_mode cull_disabled;

// Matière procédurale du mur : pierre chaude, variation basse fréquence,
// liseré de mousse près du sol. Aucune texture externe.

uniform vec3 base_color : source_color = vec3(0.62, 0.58, 0.48);
uniform float noise_scale = 1.6;
uniform float variation = 0.22;
uniform float moss_height = 0.65;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * noise_scale + world_pos.y * 0.8;
	float n = value_noise(p) * 0.65 + value_noise(p * 3.1) * 0.35;
	float strata = 0.5 + 0.5 * sin(world_pos.y * 9.0 + n * 2.0);
	vec3 col = base_color * (1.0 - variation + variation * n);
	col *= 0.92 + 0.12 * strata;
	float moss = smoothstep(moss_height, 0.0, world_pos.y) * 0.28;
	moss *= smoothstep(0.35, 0.8, n);
	col = mix(col, vec3(0.30, 0.38, 0.22), moss);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
