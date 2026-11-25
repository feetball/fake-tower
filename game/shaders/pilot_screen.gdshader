shader_type spatial;
// Avionics LCD behind cover glass. The display image (a SubViewport texture)
// is emitted, supersampled over the pixel footprint so it stays crisp without
// mipmaps when minified (720p) and smooth when magnified. The cover glass adds
// a faint black level, viewing-angle falloff, a soft reflection and procedural
// fingerprint/smudge streaks in the roughness. No scanlines: modern LCD.
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : source_color, filter_linear, repeat_disable;
uniform float brightness = 1.35;
uniform float smudge_amount = 0.6;
uniform vec2 smudge_seed = vec2(3.1, 7.7);
uniform float power = 1.0; // 0 = display off (dark glass)

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + 17.1;
		a *= 0.5;
	}
	return s;
}

// Fingerprint-ish ridges: concentric bands warped by noise, in a few blobs.
float smudges(vec2 uv) {
	float s = 0.0;
	for (int i = 0; i < 3; i++) {
		vec2 c = vec2(hash(smudge_seed + float(i)), hash(smudge_seed * 1.7 + float(i) * 3.0));
		vec2 d = (uv - c) * vec2(1.0, 1.3);
		float r = length(d) + fbm(uv * 9.0 + float(i)) * 0.03;
		float blob = smoothstep(0.13, 0.0, r);
		float ridges = 0.5 + 0.5 * sin(r * 420.0);
		s += blob * (0.45 + 0.55 * ridges);
	}
	// Wiped streaks across the glass.
	float streak = smoothstep(0.55, 0.9, fbm(vec2(uv.x * 2.0 + uv.y * 5.0, uv.y * 1.2) * 3.0));
	return clamp(s + streak * 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);
	vec3 col = vec3(0.0);
	// 2x2 rotated-grid supersample over the pixel footprint.
	col += texture(screen_tex, UV + dx * 0.125 + dy * 0.375).rgb;
	col += texture(screen_tex, UV - dx * 0.375 + dy * 0.125).rgb;
	col += texture(screen_tex, UV + dx * 0.375 - dy * 0.125).rgb;
	col += texture(screen_tex, UV - dx * 0.125 - dy * 0.375).rgb;
	col *= 0.25;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float angle_k = mix(0.7, 1.0, smoothstep(0.2, 0.9, facing));
	// Edge falloff of the backlight.
	vec2 e = abs(UV - 0.5) * 2.0;
	float edge = 1.0 - 0.08 * pow(max(e.x, e.y), 6.0);
	vec3 black_level = vec3(0.006, 0.008, 0.012);
	EMISSION = (col * brightness * angle_k * edge + black_level) * power;
	float sm = smudges(UV) * smudge_amount;
	ALBEDO = vec3(0.004);
	ROUGHNESS = mix(0.04, 0.38, sm);
	SPECULAR = mix(0.45, 0.3, sm);
	METALLIC = 0.0;
}
