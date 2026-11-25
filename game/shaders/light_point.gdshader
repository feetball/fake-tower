shader_type spatial;
// Camera-facing light points with a fog halo, drawn additively from a MultiMesh.
// Per instance: COLOR.rgb = light colour,
// INSTANCE_CUSTOM = (core size m, flash period s (0 = steady), flash phase 0..1, intensity).
// Fog is applied by hand (exp extinction) because built-in fog would tint the
// additive quad into a visible grey square.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled,
	fog_disabled, skip_vertex_transform;

uniform vec3 beam_dir = vec3(0.0, 0.0, 0.0); // local space; zero = omnidirectional
uniform float beam_power : hint_range(0.5, 400.0) = 2.0;
uniform float beam_min : hint_range(0.0, 1.0) = 0.05;
uniform float extinction_per_m = 0.0025;
uniform float halo_size_m = 9.0;
uniform float halo_gain = 0.18;
uniform float min_core_angle = 0.0022; // radians, keeps distant lights >= ~2 px
uniform float min_halo_angle = 0.03;
uniform float strobe_decay = 22.0;
uniform float strobe_gain = 3.0;
uniform float intensity_scale = 1.0;

varying vec3 v_color;
varying float v_core_r;
varying float v_halo_gain;

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = max(length(center), 0.01);
	float core_m = max(INSTANCE_CUSTOM.r, dist * min_core_angle);
	float quad_m = max(max(halo_size_m, dist * min_halo_angle), core_m * 3.0);
	v_core_r = core_m / quad_m;
	// Push the quad a little toward the camera so it does not clip into its fixture.
	vec3 c = center + normalize(-center) * min(1.0, dist * 0.5);
	VERTEX = c + vec3(VERTEX.xy * quad_m, 0.0);

	float dir_k = 1.0;
	if (dot(beam_dir, beam_dir) > 0.0) {
		vec3 bd = normalize((MODELVIEW_MATRIX * vec4(beam_dir, 0.0)).xyz);
		dir_k = mix(beam_min, 1.0, pow(max(dot(bd, normalize(-center)), 0.0), beam_power));
	}
	float k = INSTANCE_CUSTOM.a * intensity_scale * dir_k * exp(-dist * extinction_per_m);
	float period = INSTANCE_CUSTOM.g;
	if (period > 0.0) {
		float t = fract(TIME / period + INSTANCE_CUSTOM.b);
		k *= strobe_gain * exp(-t * period * strobe_decay);
	}
	v_color = COLOR.rgb * k;
	// Halos are a scattering effect: they matter more the deeper into fog the light is.
	v_halo_gain = halo_gain * (0.6 + 0.4 * (1.0 - exp(-dist * 0.004)));
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float x = d / max(v_core_r, 1e-4);
	float core = exp(-x * x * 2.2);
	float halo = exp(-d * d * 7.0) * v_halo_gain;
	ALBEDO = v_color * (core + halo);
	ALPHA = 1.0;
}
