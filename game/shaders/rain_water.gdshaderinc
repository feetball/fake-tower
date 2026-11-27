// Water on the windshield. One model for both ways the glass is drawn:
// RainGlassEffect (the compute pass, Forward+) pastes this file into its GLSL, and
// pilot_windshield.gdshader (the pane shader, Compatibility / Mobile) includes it,
// so desktop and web show the same rain. Plain functions only: no uniforms, no
// built-ins, nothing that differs between Godot's shading language and GLSL.
//
// Flow frame: x across the airflow, y along it, the way the air carries the water
// (up the glass and outboard). Units are metres on the glass (radians, about 1 m
// from the eye, in the compute pass). Every function returns (normal xy, coverage):
// the normal is what the water's surface looks like (the unit disc across a bead,
// the across-axis only for a thin trail) and coverage is how much of the pixel is wet.
//
// Three kinds of water, as on a real windscreen:
//  - pinned beads: small drops that hang where they landed, swell, and are swept off;
//  - sliding drops: a drop that lets go and runs with the air, leaving a thin trail
//    on exactly the path it took;
//  - bigger, faster runners of the same kind that cross the whole pane.
// How fast the water moves is not a clock but a distance, `adv`: the metres the air
// has carried a reference drop since the start. The game integrates it from the
// airspeed (dynamic pressure, so it grows with the square of IAS), so drops speed
// up, slow down and stop with the aircraft instead of running at one fixed rate.
// #define WATER_LIGHT before including this to skip the finest bead layer (about a third
// less work per pixel); the pane shader does, the compute pass does not.

// The share of a slot a sliding drop crosses in one run (slots are taller than that).
const float WATER_SPAN = 0.62;

float hash12(vec2 q) {
	vec3 p3 = fract(vec3(q.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 q) {
	vec3 p3 = fract(vec3(q.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Beads pinned to the glass: each one swells, hangs for a while, and shrinks away.
vec3 water_beads(vec2 g, float cell, float density, float t) {
	vec2 gv = g / cell;
	vec2 id0 = floor(gv);
	vec3 best = vec3(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = id0 + vec2(float(i), float(j));
			vec2 h = hash22(id + 3.1);
			if (h.x > density) {
				continue;
			}
			float life = fract(t * (0.05 + 0.07 * h.y) + h.x * 9.0);
			vec2 ctr = id + 0.5 + (hash22(id * 1.37 + 7.0) - 0.5) * 0.6;
			float r = mix(0.16, 0.42, hash12(id + 5.3)) * smoothstep(0.0, 0.1, life) * (1.0 - smoothstep(0.85, 1.0, life));
			vec2 d = (gv - ctr) / max(r, 1e-3);
			float m = smoothstep(1.0, 0.82, length(d));
			if (m > best.z) {
				best = vec3(d, m);
			}
		}
	}
	return best;
}

// Sideways wander of a running drop's path (in column widths), by how far along its
// slot it is. It depends on the place, not the time, so the trail is where the head has been.
float water_wander(float s, vec2 ph) {
	return 0.22 * sin(s * 11.0 + ph.x * 6.2832) + 0.1 * sin(s * 27.0 + ph.y * 6.2832);
}

// Drops that have let go and run with the air. The glass is tiled in tall slots (cw wide,
// cw * aspect tall, along the flow); each slot is one drop at a time, born low in the slot at a
// random moment, running up it at a speed of its own while swelling and shedding the thin trail
// behind it, then gone, and another is born. Slots keep their own clocks, so drops appear and
// vanish all over the glass, never in step. sf scales the run speed relative to the reference
// drop (adv); density is the chance a slot has a drop in this run.
vec3 water_sliders(vec2 g, float cw, float aspect, float sf, float adv, float density, float seed) {
	float ch = cw * aspect;
	vec2 gv = vec2(g.x / cw, g.y / ch);
	float row = floor(gv.y);
	float fy = fract(gv.y);
	float col0 = floor(gv.x);
	vec3 best = vec3(0.0);
	for (int i = -1; i <= 1; i++) {
		vec2 cell = vec2(col0 + float(i), row);
		vec2 id = cell + seed;
		vec2 h = hash22(id);
		// The slot's clock: its whole cycles count the drops it has had, the rest is how far
		// along the current one is. The speed factor makes neighbours run at different rates.
		float c = adv * sf * (0.6 + 0.8 * h.y) / (WATER_SPAN * ch) + h.x * 31.0;
		float life = fract(c);
		float e = mod(floor(c), 1024.0);
		vec2 k = hash22(vec2(id.x + e * 17.31, id.y + e * 9.77));
		if (k.x > density) {
			continue;
		}
		vec2 q = hash22(vec2(id.y + e * 5.13, id.x + e * 3.91) + 4.2);
		vec2 ph = vec2(q.x, k.y);
		// Stick and slip: the drop surges and hangs up a little as it runs (never backwards).
		float run = life + 0.03 * sin(life * 16.0 + q.y * 6.2832);
		float y0 = 0.05 + 0.2 * k.y;
		float hy = y0 + WATER_SPAN * run;
		float bx = cell.x + 0.5 + (q.x - 0.5) * 0.3;
		// A drop appears at once (an impact), gathers water for a while, then shrinks to
		// nothing as it leaves it all behind in the trail.
		float fade = smoothstep(0.0, 0.05, life) * (1.0 - smoothstep(0.9, 1.0, life));
		// The head: an egg, longer along the run.
		float rad = mix(0.3, 0.5, q.y) * (0.6 + 0.4 * smoothstep(0.0, 0.2, life)) * (1.0 - 0.75 * smoothstep(0.6, 1.0, life));
		vec2 d = vec2(gv.x - (bx + water_wander(hy, ph)), (fy - hy) * aspect) / max(rad, 1e-3);
		d.y /= 1.3;
		float head = smoothstep(1.0, 0.82, length(d));
		// The trail: a thin thread of water from where the drop started to where it is now.
		// It is never thinner than a pixel or two, and it swells into little beads along its
		// length, the way a thin thread of water breaks up.
		float along = (fy - y0) / max(hy - y0, 1e-3);
		float wt = max(rad * mix(0.3, 0.55, along), 0.2) * (1.0 + 0.3 * sin(fy * aspect * 5.0 + ph.x * 6.2832));
		float dx = gv.x - (bx + water_wander(fy, ph));
		float tail = smoothstep(wt, wt * 0.35, abs(dx)) * smoothstep(0.0, 0.2, along) * (1.0 - step(1.0, along)) * mix(0.4, 0.8, along);
		float m = max(head, tail) * fade;
		if (m > best.z) {
			vec2 n = vec2(clamp(dx / wt, -1.0, 1.0), 0.0);
			if (head >= tail) {
				n = d;
			}
			best = vec3(n, m);
		}
	}
	return best;
}

// All the water at flow-frame position fg. t: seconds. adv: metres the air has carried a
// reference drop. rain: 0..1 how wet it is. spd: airspeed / 160 kt, clamped to 0..1.4.
vec3 water_on_glass(vec2 fg, float t, float adv, float rain, float spd) {
	// Parked, the water just hangs; at approach speed it runs; far above that the glass streams.
	float run = smoothstep(0.1, 0.65, spd);
	// Running drops sweep the pinned ones off.
	float swept = 1.0 - 0.55 * run;
	vec3 w = water_beads(fg, 0.016, (0.06 + 0.6 * rain) * swept, t);
#ifndef WATER_LIGHT
	// The finest beads: left out where the shader runs on every pane pixel of a weak GPU.
	vec3 b2 = water_beads(fg * 1.8 + 11.0, 0.016, (0.05 + 0.35 * rain) * swept, t * 1.3);
	if (b2.z > w.z) {
		w = b2;
	}
#endif
	vec3 s1 = water_sliders(fg + vec2(3.7, 1.3), 0.014, 14.0, 0.35, adv, (0.18 + 0.6 * rain) * run, 3.0);
	if (s1.z > w.z) {
		w = s1;
	}
	vec3 s2 = water_sliders(fg + vec2(9.1, 5.9), 0.022, 22.0, 1.0, adv, (0.06 + 0.45 * rain) * run, 17.0);
	if (s2.z > w.z) {
		w = s2;
	}
	return w;
}
