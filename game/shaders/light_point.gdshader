shader_type spatial;
// Camera-facing light points with a fog halo, drawn additively from a MultiMesh.
// Per instance: COLOR.rgb = light colour,
// INSTANCE_CUSTOM = (core size m, flash period s (0 = steady), flash phase 0..1, intensity).
// Fog is applied by hand (exp extinction) because built-in fog would tint the
// additive quad into a visible grey square.
// The depth test is done by hand against the lamp centre only (like a lens
// flare), so a halo larger than the lamp's height is not sliced by the ground.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled,
	shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float occlusion_bias_m = 1.2;

uniform vec3 beam_dir = vec3(0.0, 0.0, 0.0); // local space; zero = omnidirectional
uniform float beam_power : hint_range(0.5, 400.0) = 2.0;
uniform float beam_min : hint_range(0.0, 1.0) = 0.05;
uniform float extinction_per_m = 0.0025;
uniform float halo_size_m = 3.0;
uniform float halo_gain = 0.08;
uniform float min_core_angle = 0.0022; // radians, keeps distant lights >= ~2 px
uniform float min_halo_angle = 0.03;
uniform float strobe_decay = 22.0;
uniform float strobe_gain = 3.0;
uniform float intensity_scale = 1.0;

varying vec3 v_color;
varying float v_core_r;
varying float v_halo_gain;
varying vec4 v_center_clip;
varying float v_center_z;

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = max(length(center), 0.01);
	float core_m = max(INSTANCE_CUSTOM.r, dist * min_core_angle);
	float quad_m = max(max(halo_size_m, dist * min_halo_angle), core_m * 3.0);
	v_core_r = core_m / quad_m;
	// Push the quad a little toward the camera so it does not clip into its fixture.
	vec3 c = center + normalize(-center) * min(1.0, dist * 0.5);
	VERTEX = c + vec3(VERTEX.xy * quad_m, 0.0);
	v_center_clip = PROJECTION_MATRIX * vec4(center, 1.0);
	v_center_z = center.z;

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
	if (v_center_clip.w <= 0.0) {
		discard;
	}
	vec2 ndc = v_center_clip.xy / v_center_clip.w;
	float vis = 1.0;
	if (all(lessThan(abs(ndc), vec2(1.0)))) {
		float depth = textureLod(depth_tex, ndc * 0.5 + 0.5, 0.0).r;
		vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, depth, 1.0);
		float scene_z = scene.z / scene.w;
		float bias = occlusion_bias_m + abs(v_center_z) * 0.002;
		vis = smoothstep(bias, 0.0, scene_z - v_center_z);
	}
	if (vis <= 0.0) {
		discard;
	}
	float d = length(UV * 2.0 - 1.0);
	float x = d / max(v_core_r, 1e-4);
	float core = exp(-x * x * 2.2);
	float halo = exp(-d * d * 7.0) * v_halo_gain;
	ALBEDO = v_color * (core + halo) * vis;
	ALPHA = 1.0;
}
