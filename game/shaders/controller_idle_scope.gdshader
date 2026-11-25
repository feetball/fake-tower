shader_type spatial;
// Distant scopes at the other positions: a procedural radar picture (map
// lines, range rings, a few targets that jump every sweep) as emission behind
// dark glass. Only meant to read as "a working scope" from metres away.
render_mode blend_mix, cull_back, specular_schlick_ggx;

uniform float energy = 1.0;
uniform float seed = 1.0;
uniform vec2 aspect = vec2(1.25, 1.0);
uniform vec3 tint : source_color = vec3(0.4, 1.0, 0.55);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float line_seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return smoothstep(w, w * 0.3, length(pa - ba * h));
}

void fragment() {
	vec2 p = (UV - 0.5) * aspect;
	vec2 o = vec2(hash(vec2(seed, 1.0)) - 0.5, hash(vec2(seed, 2.0)) - 0.5) * 0.2;
	float r = length(p - o);
	float rings = smoothstep(0.006, 0.0, abs(fract(r * 7.0 + 0.5) - 0.5) / 7.0) * 0.18;
	float map = 0.0;
	for (int i = 0; i < 7; i++) {
		vec2 a = vec2(hash(vec2(seed + float(i), 3.0)), hash(vec2(seed + float(i), 4.0))) - 0.5;
		vec2 b = vec2(hash(vec2(seed + float(i), 5.0)), hash(vec2(seed + float(i), 6.0))) - 0.5;
		map += line_seg(p, a * aspect, b * aspect, 0.004) * 0.25;
	}
	float tgt = 0.0;
	float sweep = floor(TIME / 2.0);
	for (int i = 0; i < 6; i++) {
		vec2 base = vec2(hash(vec2(seed * 3.1 + float(i), 7.0)), hash(vec2(seed * 3.1 + float(i), 8.0))) - 0.5;
		vec2 vel = (vec2(hash(vec2(float(i), seed)), hash(vec2(seed, float(i)))) - 0.5) * 0.004;
		vec2 tp = (base + vel * mod(sweep + float(i) * 13.0, 120.0)) * aspect * 0.9;
		float d = length(p - tp);
		tgt += smoothstep(0.012, 0.004, d);
		tgt += smoothstep(0.004, 0.0, abs(p.y - tp.y - 0.03)) * step(tp.x + 0.02, p.x) * step(p.x, tp.x + 0.09) * 0.7;
	}
	vec3 bg = vec3(0.004, 0.016, 0.01);
	vec3 col = bg + tint * (rings + map) * 0.5 + tint * tgt * 0.9;
	ALBEDO = vec3(0.004);
	ROUGHNESS = 0.12;
	SPECULAR = 0.4;
	EMISSION = col * energy;
}
