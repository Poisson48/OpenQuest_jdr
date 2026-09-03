shader_type canvas_item;

// Opaque token overlay: keep rgb, force alpha 1 or discard.
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.5) {
		discard;
	}
	COLOR = vec4(c.rgb, 1.0);
}
