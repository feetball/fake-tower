shader_type spatial;
// Flat-panel display surface for the radar room: the SubViewport image as
// emission, a dark glossy glass with faint smudges that catches the room's
// lights. The viewport texture has no mipmaps, so it is box-filtered over the
// pixel footprint here to avoid shimmering rings when seen from afar.
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : source_color, filter_linear, repeat_disable;
uniform float energy = 1.35;
uniform float smudge = 0.5;
uniform float black_level = 0.004;
uniform vec2 aspect = vec2(1.25, 1.0);
uniform float seed = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec2 fw = max(fwidth(uv), vec2(1e-5)) * 0.5;
	vec3 c = texture(screen_tex, uv).rgb * 0.36;
	c += texture(screen_tex, uv + vec2(fw.x, fw.y)).rgb * 0.16;
	c += texture(screen_tex, uv + vec2(-fw.x, fw.y)).rgb * 0.16;
	c += texture(screen_tex, uv + vec2(fw.x, -fw.y)).rgb * 0.16;
	c += texture(screen_tex, uv + vec2(-fw.x, -fw.y)).rgb * 0.16;
	vec2 sp = uv * aspect * 5.0 + seed;
	float sm = smoothstep(0.45, 0.85, fbm(sp)) * smudge;
	float wipe = smoothstep(0.55, 0.8, fbm(sp * vec2(0.6, 3.0) + 4.0)) * smudge * 0.6;
	ALBEDO = vec3(black_level);
	ROUGHNESS = clamp(0.08 + sm * 0.5 + wipe * 0.3, 0.0, 1.0);
	SPECULAR = 0.45;
	METALLIC = 0.0;
	EMISSION = c * energy;
}
