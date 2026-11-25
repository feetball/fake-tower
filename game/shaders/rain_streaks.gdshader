shader_type spatial;
// Rain (or cloud mist) rushing past the aircraft, in the aircraft frame (eye at
// the origin, −Z forward). Each MultiMesh instance is one drop; its position
// is animated here (relative wind + fall speed, wrapped in a box ahead of the
// nose) and drawn as a motion-blurred streak aligned with its screen-space
// velocity. Drops are only visible where the aircraft's own lights hit them:
// the two landing-light cones, the taxi light, and the strobe flashes.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled,
	skip_vertex_transform;

uniform vec3 box_min = vec3(-24.0, -18.0, -60.0);
uniform vec3 box_size = vec3(48.0, 26.0, 58.0);
uniform vec3 velocity = vec3(0.0, -6.0, 70.0); // m/s, aircraft frame
uniform float exposure_s = 0.022; // streak length = speed * exposure
uniform float amount = 1.0; // 0..1, fraction of drops shown
uniform float brightness = 1.0;
uniform vec3 lamp0_pos = vec3(-3.7, -2.9, 9.5);
uniform vec3 lamp0_dir = vec3(0.0, -0.17, -0.98);
uniform vec3 lamp1_pos = vec3(4.7, -2.9, 9.5);
uniform vec3 lamp1_dir = vec3(0.0, -0.17, -0.98);
uniform float lamp_cos = 0.985; // cos of the cone half-angle
uniform vec3 taxi_pos = vec3(0.5, -3.6, -1.0);
uniform vec3 taxi_dir = vec3(0.0, -0.16, -0.99);
uniform float taxi_cos = 0.96;
uniform float taxi_on = 1.0;
uniform float strobe = 0.0;
uniform vec3 light_color : source_color = vec3(1.0, 0.96, 0.9);

varying float v_light;
varying vec2 v_uv;

float hash11(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float cone(vec3 p, vec3 lp, vec3 ld, float cosc) {
	vec3 d = p - lp;
	float len = length(d);
	float c = dot(d / max(len, 1e-3), ld);
	float edge = smoothstep(cosc - 0.01, cosc + 0.006, c);
	return edge * 900.0 / (len * len + 400.0);
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 seed = vec3(hash11(id + 0.13), hash11(id + 7.71), hash11(id + 3.37));
	float show = step(hash11(id + 11.9), amount);
	// Each drop also gets its own slight speed variation.
	vec3 vel = velocity * (0.9 + 0.2 * hash11(id + 5.5));
	vec3 p = box_min + mod(seed * box_size + vel * TIME, box_size);
	vec3 tail = p - vel * exposure_s;
	vec3 a = (MODELVIEW_MATRIX * vec4(p, 1.0)).xyz;
	vec3 b = (MODELVIEW_MATRIX * vec4(tail, 1.0)).xyz;
	if (a.z > -0.5 || b.z > -0.5) {
		show = 0.0;
	}
	// Screen-aligned ribbon from b to a, at least about a pixel wide.
	vec3 axis = a - b;
	vec3 side = normalize(cross(axis, (a + b) * 0.5));
	float dist = length(a);
	float w = max(0.0025, dist * 0.0011);
	vec3 base = mix(b, a, VERTEX.y + 0.5);
	VERTEX = base + side * VERTEX.x * w * 2.0;
	v_uv = vec2(UV.x * 2.0 - 1.0, UV.y);
	float l = cone(p, lamp0_pos, lamp0_dir, lamp_cos) + cone(p, lamp1_pos, lamp1_dir, lamp_cos);
	l += taxi_on * 0.5 * cone(p, taxi_pos, taxi_dir, taxi_cos);
	l += strobe * 0.35;
	// A drop is a couple of millimetres: once drawn wider than that (the pixel
	// floor), dim it accordingly, or the far drops pile up at the focus of
	// expansion into a glowing blob.
	v_light = l * show * brightness * 0.05 * min(1.0, 0.0025 / w) * min(1.0, 0.0025 / w);
}

void fragment() {
	float across = 1.0 - abs(v_uv.x);
	float along = smoothstep(0.0, 0.25, v_uv.y) * smoothstep(1.0, 0.8, v_uv.y);
	ALBEDO = light_color * v_light * across * across * along;
	ALPHA = 1.0;
}
