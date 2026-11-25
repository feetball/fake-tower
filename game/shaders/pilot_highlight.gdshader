shader_type spatial;
// Hover highlight for cockpit controls, used as a material overlay: a soft
// cool rim plus a faint lift of the whole control, pulsing gently.
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.45, 0.75, 1.0);

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float pulse = 0.75 + 0.25 * sin(TIME * 5.0);
	ALBEDO = tint * (0.05 + rim * 0.55) * pulse;
}
