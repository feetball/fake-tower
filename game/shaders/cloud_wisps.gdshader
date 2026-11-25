shader_type spatial;
// Ragged scud hanging under the cloud base: camera-facing, horizontally
// stretched billboards with drifting fbm noise, alpha blended and lit by the
// real lights (landing lights, strobes, beacon) with a soft scattering term.
// Per instance: INSTANCE_CUSTOM = (size m, seed, opacity, unused).
// Faded out close to the camera so flying through one never fills the screen.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec3 albedo : source_color = vec3(0.78, 0.8, 0.84);
uniform vec3 underglow : source_color = vec3(0.006, 0.0055, 0.005);
uniform float opacity = 0.4;
uniform vec2 drift = vec2(0.012, 0.004);
uniform vec2 near_fade_m = vec2(25.0, 90.0);

varying vec3 v_seed;
varying float v_fade;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(13.7, 5.1);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	vec3 center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float size = INSTANCE_CUSTOM.x;
	VERTEX = center + vec3(VERTEX.x * size, VERTEX.y * size * 0.42, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	float dist = length(center);
	v_fade = smoothstep(near_fade_m.x, near_fade_m.y, dist) * INSTANCE_CUSTOM.z;
	v_seed = vec3(INSTANCE_CUSTOM.y * 37.0, INSTANCE_CUSTOM.y * 11.0, 0.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, 2.0);
	float r = length(p * vec2(1.0, 1.25));
	vec2 q = UV * vec2(3.2, 1.6) + v_seed.xy + drift * TIME;
	float n = fbm(q + 0.6 * vec2(fbm(q * 1.7 + 4.0), fbm(q * 1.3 - 2.0)));
	float shape = smoothstep(1.0, 0.25, r);
	float dens = smoothstep(0.45, 0.85, n * (0.55 + 0.6 * shape)) * shape * shape;
	ALBEDO = albedo;
	EMISSION = underglow;
	ALPHA = clamp(dens * opacity * v_fade, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// Wrapped, mostly isotropic scattering with a forward lobe.
	float c = dot(LIGHT, -VIEW);
	float g = 0.55;
	float hg = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * c, 1.5);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (0.12 + 0.12 * hg) / PI;
}
