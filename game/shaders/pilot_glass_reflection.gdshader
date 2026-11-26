shader_type spatial;
// Faint virtual image of a lit display in the windshield: the display's texture
// on a quad mirrored across the glass plane (so it sits outside the glass, is
// hidden by the flight deck everywhere but through the window, and moves with
// correct parallax). Additive, a few percent like real glass reflectance.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : source_color, filter_linear_mipmap;
uniform float strength = 0.018;

void fragment() {
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.06, min(e.x, e.y));
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// The display viewport has no mipmaps (GLES3 reads higher levels as black), and a
	// sharp level 0 shows up as a bright green patch over the glareshield: blur it with a
	// wide 4x4 box instead, as the mip level 3 does elsewhere, and keep it fainter.
	vec3 acc = vec3(0.0);
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			acc += textureLod(screen_tex, UV + (vec2(float(i), float(j)) - 1.5) * 0.06, 0.0).rgb;
		}
	}
	ALBEDO = acc / 16.0 * strength * 0.6 * edge;
#else
	ALBEDO = textureLod(screen_tex, UV, 3.0).rgb * strength * edge;
#endif
}
