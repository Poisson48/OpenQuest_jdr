shader_type spatial;
render_mode cull_disabled;

// Matière procédurale des toits : variation de tuiles par rangées, petites
// irrégularités, aucune texture externe. La couleur vient des vertex colors.

uniform float tile_rows = 9.0;
uniform float variation = 0.14;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float row = floor(world_pos.y * tile_rows + world_pos.x * 0.7);
	float n = hash(vec2(row, floor(world_pos.z * 2.0)));
	float tile = 0.92 + variation * n;
	vec3 base = COLOR.rgb;
	ALBEDO = base * tile;
	ROUGHNESS = 0.86;
	METALLIC = 0.0;
}
