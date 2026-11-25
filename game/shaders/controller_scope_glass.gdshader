shader_type canvas_item;
// "At the scope" presentation of the radar SubViewport, drawn 1:1 over the 3D
// display: the image stays pixel-exact; on top come a faint phosphor bloom
// (bright pixels bleed a few pixels), a very low glass sheen with smudges,
// and a slight edge falloff. Kept subtle: legibility first.
render_mode blend_mix, unshaded;

uniform float bloom = 0.32;
uniform float bloom_threshold = 0.22;
uniform float sheen = 0.022;
uniform float smudge = 0.6;
uniform vec2 aspect = vec2(1.25, 1.0);
uniform vec3 lamp_tint = vec3(1.0, 0.72, 0.45);
uniform float fade = 1.0;

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
	vec3 c = texture(TEXTURE, UV).rgb;
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 g = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398 + 0.39;
		vec2 d = vec2(cos(a), sin(a)) * px;
		g += max(texture(TEXTURE, UV + d * 2.0).rgb - bloom_threshold, vec3(0.0)) * 0.6;
		g += max(texture(TEXTURE, UV + d * 5.0).rgb - bloom_threshold, vec3(0.0)) * 0.4;
	}
	c += g * (bloom / 8.0);
	vec2 sp = UV * aspect * 5.0;
	float sm = smoothstep(0.45, 0.85, fbm(sp)) * smudge;
	// Broad diagonal sheen from the room, and a warm reflection of the desk lamp.
	float diag = smoothstep(1.3, 0.0, UV.x + UV.y * 0.8);
	float lamp = exp(-dot((UV - vec2(1.02, 0.08)) * aspect, (UV - vec2(1.02, 0.08)) * aspect) * 9.0);
	c += vec3(0.55, 0.65, 0.7) * sheen * diag * (0.35 + sm);
	c += lamp_tint * sheen * 1.4 * lamp * (0.3 + sm);
	vec2 e = abs(UV - 0.5) * 2.0;
	float edge = 1.0 - 0.18 * pow(max(e.x, e.y), 6.0);
	COLOR = vec4(c * edge, fade);
}
