shader_type spatial;
render_mode blend_mix, cull_disabled;

// UV2 suit la grille pour le masque et la profondeur. Sur une rivière, UV.y
// mesure la distance parcourue le long du ruban en cases et UV.x le traverse.
uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform vec2 map_cells = vec2(1.0);
uniform float depth_scale = 1.0;
uniform vec4 shallow_color : source_color = vec4(0.20, 0.47, 0.48, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.20, 0.28, 1.0);
uniform vec4 foam_color : source_color = vec4(0.78, 0.88, 0.88, 1.0);
uniform vec4 night_tint : source_color = vec4(1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.78;
uniform float alpha_depth : hint_range(0.0, 0.3) = 0.10;
uniform float wave_strength : hint_range(0.0, 0.5) = 0.08;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.9;
uniform float foam_strength : hint_range(0.0, 2.0) = 1.0;
uniform float foam_width : hint_range(0.01, 0.5) = 0.12; // Profondeur en cases
uniform vec2 flow_dir = vec2(1.0, 0.0);
uniform float flow_speed = 0.0; // Cases par seconde
uniform float flow_strength : hint_range(0.0, 1.0) = 0.0;
uniform bool ribbon = false;
uniform float flow_width = 1.0;
uniform float edge_softness : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 depth_mask = texture(depth_map, UV2).rg;
	if (depth_mask.g < 0.35) {
		discard;
	}

	float depth = depth_mask.r * depth_scale;
	float deep = smoothstep(0.04, 1.15, depth);
	vec2 grid = UV2 * map_cells;
	vec2 flow = flow_dir / max(length(flow_dir), 0.001);
	vec2 across = vec2(-flow.y, flow.x);
	vec2 moving = vec2(dot(grid, flow), dot(grid, across));
	if (ribbon) {
		moving = vec2(UV.y, (UV.x - 0.5) * flow_width);
	}
	moving.x -= TIME * flow_speed * flow_strength;
	float t = TIME * wave_speed;
	float warp = sin(grid.x * 1.31 - grid.y * 1.9) + 0.5 * sin(grid.x * 0.86 + grid.y * 0.72);
	float w1 = sin(moving.x * 2.1 + moving.y * 2.6 + warp + t * 0.65);
	float w2 = sin(moving.x * 0.75 - moving.y * 6.4 + warp * 1.4 - t * 0.8);
	float ripple = w1 * 0.55 + w2 * 0.45;
	vec3 tilt = mat3(VIEW_MATRIX) * vec3(w1, 0.0, w2);
	NORMAL = normalize(NORMAL + tilt * wave_strength * 0.65);

	vec3 water = mix(shallow_color.rgb, deep_color.rgb, deep);
	water *= 0.98 + ripple * 0.07;
	float crest = smoothstep(0.65, 0.98, ripple);
	float glint = crest * (0.18 + 0.65 * pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0));
	water = mix(water, foam_color.rgb, glint * 0.19);

	// L'écume suit la profondeur réelle. Une crique peu profonde à côté
	// d'un grand lac conserve la même largeur de transition.
	float shore = 1.0 - smoothstep(0.01, foam_width, depth);
	float flecks = smoothstep(-0.28, 0.65, w2 + w1 * 0.4);
	float foam = clamp(shore * flecks * foam_strength, 0.0, 0.78);
	water = mix(water, foam_color.rgb, foam * 0.52);
	ALBEDO = water * night_tint.rgb;
	EMISSION = foam_color.rgb * glint * 0.04 * night_tint.rgb;
	ALPHA = (base_alpha - 0.16 * (1.0 - deep) + alpha_depth * deep + foam * 0.08);
	ALPHA *= smoothstep(0.35, 0.82, depth_mask.g);
	if (ribbon) {
		float edge = smoothstep(0.0, 0.16, min(UV.x, 1.0 - UV.x));
		ALPHA *= mix(1.0, edge, edge_softness);
	}
	ROUGHNESS = mix(0.32, 0.48, foam);
	SPECULAR = 0.38;
}
