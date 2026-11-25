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
	ALBEDO = textureLod(screen_tex, UV, 3.0).rgb * strength * edge;
}
