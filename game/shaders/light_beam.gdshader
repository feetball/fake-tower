shader_type spatial;
// A light shaft through fog, drawn additively on a CylinderMesh of height
// length_m used as a cone: narrow end (top, +Y) at the lamp. Brightest near the lamp and
// along the axis; edges fade with the view angle so the cone has no outline.
// Cheaper and more readable than relying on volumetric froxels for a thin beam.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 beam_color : source_color = vec3(1.0);
uniform float intensity = 1.0;
uniform float length_m = 600.0;
uniform float falloff = 3.0;
uniform float extinction_per_m = 0.002;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
// Distance band over which the beam fades in from the camera (m).
uniform vec2 near_fade_m = vec2(30.0, 250.0);
// Soft-intersection depth with geometry (m).
uniform float soft_m = 20.0;

varying float v_along;

void vertex() {
	v_along = clamp(0.5 - VERTEX.y / length_m, 0.0, 1.0);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(facing, 4.0);
	float along = exp(-v_along * falloff) * smoothstep(0.0, 0.02, v_along);
	float dist = length(VERTEX);
	float ext = exp(-dist * extinction_per_m);
	// Soft intersection with geometry.
	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0; // OpenGL NDC z is -1..1 (Vulkan: 0..1, used as is)
#endif
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = scene.z / scene.w;
	float soft = clamp((VERTEX.z - scene_z) / soft_m, 0.0, 1.0);
	// Fade out close to the camera so a beam sweeping past does not fill the screen.
	float near_fade = smoothstep(near_fade_m.x, near_fade_m.y, dist);
	ALBEDO = beam_color * intensity * edge * along * ext * soft * near_fade;
	ALPHA = 1.0;
}
