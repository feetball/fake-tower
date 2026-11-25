shader_type spatial;
// Wet windshield film. When RainGlassEffect is unavailable it also draws the
// water itself (fallback): procedural drops refracting the scene behind:
// beading drops that grow and, with airspeed, are blown up the glass as
// streaks, plus fast mist streaks in cloud. Mostly transparent: only the water
// and a faint film are drawn, so the airfield lights (additive, drawn later
// in the transparent pass) stay visible, and their bloom spreads over the
// drops. Glass coordinates come from UV scaled by the pane size in metres.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float rain : hint_range(0.0, 1.0) = 0.5;
uniform float airspeed = 150.0; // kt
uniform float film = 0.06;
uniform vec3 interior_glow : source_color = vec3(0.025, 0.03, 0.04);
// Off when RainGlassEffect draws the water (it can see the light sprites).
uniform bool drops = true;
instance uniform vec2 glass_size = vec2(0.9, 0.6);
instance uniform float glass_seed = 0.0;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Beading drops in a grid; each lives a while and, at speed, slides upward.
// Returns (refraction normal xy, coverage).
vec3 beads(vec2 p, float cell, float t, float blow, float density) {
	vec2 gv = p / cell;
	vec2 id0 = floor(gv);
	vec3 acc = vec3(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = id0 + vec2(float(i), float(j));
			vec2 h = hash22(id + glass_seed * 17.0);
			if (h.x > density) {
				continue;
			}
			float life = fract(t * (0.07 + 0.08 * h.y) + h.x * 7.0);
			vec2 c = id + 0.5 + (hash22(id * 1.7 + 3.0) - 0.5) * 0.7;
			// Airflow pushes the drop up the glass, faster the longer it has grown.
			c.y += blow * life * life * 2.5;
			c.x += blow * life * 0.4 * (h.y - 0.5);
			float r = mix(0.12, 0.36, hash12(id + 9.1)) * smoothstep(0.0, 0.15, life);
			vec2 d = gv - c;
			// Stretch along the motion when blown.
			d.y /= 1.0 + blow * life * 2.0;
			float l = length(d) / max(r, 1e-3);
			float m = smoothstep(1.0, 0.75, l) * (1.0 - smoothstep(0.8, 1.0, life));
			if (m > acc.z) {
				acc = vec3(d / max(r, 1e-3), m);
			}
		}
	}
	return acc;
}

// Thin streaks racing up the glass (mist impacting at speed).
vec3 streaks(vec2 p, float t, float spd) {
	float colw = 0.012;
	float x = p.x / colw;
	float id = floor(x);
	float fx = fract(x) - 0.5;
	float h = hash12(vec2(id, glass_seed));
	float h2 = hash12(vec2(id * 3.1, 7.0 + glass_seed));
	float len = 0.04 + 0.12 * h2;
	float y = fract((p.y / len) * 0.25 - t * spd * (0.6 + h) - h * 13.0);
	float head = smoothstep(0.0, 0.03, y) * smoothstep(1.0, 0.55, y);
	float w = smoothstep(0.18, 0.0, abs(fx + (h - 0.5) * 0.3));
	float on = step(0.72, hash12(vec2(id, floor((p.y / len) * 0.25 - t * spd * (0.6 + h) - h * 13.0))));
	float m = head * w * on;
	return vec3(fx * 2.0, 0.0, m * 0.8);
}

void fragment() {
	vec2 p = UV * glass_size;
	float spd = clamp(airspeed / 160.0, 0.0, 1.5);
	float blow = smoothstep(0.15, 0.6, spd);
	vec3 b = beads(p, 0.016, TIME, blow, 0.32 * rain + 0.05);
	vec3 s = streaks(p, TIME, spd * 2.5) * smoothstep(0.3, 0.8, rain) * blow;
	vec3 w = b.z >= s.z ? b : s;
	float mask = drops ? max(b.z, s.z) : 0.0;
	// Inverted lens: the drop shows the scene around it, flipped and blurred.
	vec2 offs = -w.xy * vec2(0.025, 0.035) * mask;
	vec3 seen = textureLod(screen_tex, SCREEN_UV + offs, 1.0 + mask).rgb;
	vec3 haze = textureLod(screen_tex, SCREEN_UV, 3.5).rgb;
	float rim = pow(clamp(length(w.xy), 0.0, 1.0), 4.0) * mask;
	vec3 col = seen * 1.15 + haze * 0.35 + interior_glow * (0.5 + rim * 3.0);
	float film_a = film * (0.4 + rain);
	ALBEDO = mix(haze * 1.2 + interior_glow, col, step(0.001, mask));
	ALPHA = clamp(max(mask * 0.92, film_a), 0.0, 1.0);
}
