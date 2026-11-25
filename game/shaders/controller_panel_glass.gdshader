shader_type canvas_item;
// Glass over the flight-data display in the "at the scope" framing: added on
// top of the UI, only a faint sheen and smudges (no change to the text).
render_mode blend_add, unshaded;

uniform float sheen = 0.018;
uniform float smudge = 0.6;
uniform vec2 aspect = vec2(0.57, 1.0);
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

void fragment() {
	vec2 sp = UV * aspect * 6.0 + 11.0;
	float n = noise(sp) * 0.6 + noise(sp * 2.1) * 0.3 + noise(sp * 4.3) * 0.1;
	float sm = smoothstep(0.45, 0.85, n) * smudge;
	float diag = smoothstep(1.4, 0.0, (1.0 - UV.x) * 0.7 + UV.y);
	vec3 c = vec3(0.6, 0.68, 0.75) * sheen * diag * (0.4 + sm);
	COLOR = vec4(c * fade, 1.0);
}
