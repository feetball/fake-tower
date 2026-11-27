shader_type spatial;
// Wet windshield film. When RainGlassEffect is unavailable it also draws the
// water itself (fallback): procedural drops refracting the scene behind, from
// the same model as the compute pass (rain_water.gdshaderinc): beads that hang
// on the glass, and drops that run up it with the airflow leaving trails.
// Mostly transparent: only the water and a faint film are drawn, so the airfield
// lights (additive, drawn later in the transparent pass) stay visible, and their
// bloom spreads over the drops. Glass coordinates come from UV scaled by the
// pane size in metres.
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

#define WATER_LIGHT
#include "res://shaders/rain_water.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float rain : hint_range(0.0, 1.0) = 0.5;
uniform float airspeed = 150.0; // kt
uniform float water_travel = 0.0; // m of glass the airflow has carried a reference drop
uniform float film = 0.06;
uniform vec3 interior_glow : source_color = vec3(0.025, 0.03, 0.04);
// Off when RainGlassEffect draws the water (it can see the light sprites).
uniform bool drops = true;
instance uniform vec2 glass_size = vec2(0.9, 0.6);
instance uniform float glass_seed = 0.0;

void fragment() {
	// UV runs up the glass, the way the airflow blows the water: that is the flow frame.
	vec2 p = UV * glass_size + vec2(glass_seed * 13.1, glass_seed * 7.3);
	float spd = clamp(airspeed / 160.0, 0.0, 1.4);
	vec3 w = water_on_glass(p, TIME, water_travel, rain, spd);
	float mask = drops ? w.z : 0.0;
	// Inverted lens: the drop shows the scene around it, flipped and blurred.
	vec2 offs = -w.xy * vec2(0.025, 0.035) * mask;
#if CURRENT_RENDERER != RENDERER_FORWARD_PLUS
	// Compatibility (GLES3 / WebGL 2) and Mobile have no screen-texture mipmaps (higher
	// levels read black, drops turn into dark specks): sample level 0 and blur the haze
	// with a few taps instead.
	vec3 seen = textureLod(screen_tex, SCREEN_UV + offs, 0.0).rgb;
	vec2 r = vec2(0.012, 0.02);
	vec3 haze = (textureLod(screen_tex, SCREEN_UV + vec2(r.x, 0.0), 0.0).rgb
		+ textureLod(screen_tex, SCREEN_UV - vec2(r.x, 0.0), 0.0).rgb
		+ textureLod(screen_tex, SCREEN_UV + vec2(0.0, r.y), 0.0).rgb
		+ textureLod(screen_tex, SCREEN_UV - vec2(0.0, r.y), 0.0).rgb) * 0.25;
#else
	vec3 seen = textureLod(screen_tex, SCREEN_UV + offs, 1.0 + mask).rgb;
	vec3 haze = textureLod(screen_tex, SCREEN_UV, 3.5).rgb;
#endif
	float rim = pow(clamp(length(w.xy), 0.0, 1.0), 4.0) * mask;
	float film_a = film * (0.4 + rain);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// GLES3 hands this pass the picture already tone-mapped and tone-maps the pass again,
	// so a copy comes out much darker: opaque drops read as dark specks on the haze.
	// Here the drops are faint lenses instead: what they show is lifted and only partly
	// blended in, so they glint over the lights and all but vanish over the dark haze.
	vec3 col = seen * 1.8 + haze * 0.4 + interior_glow * (0.5 + rim * 6.0) + seen * rim * 3.0;
	ALBEDO = mix(haze * 1.6 + interior_glow, col, step(0.001, mask));
	ALPHA = clamp(max(mask * (0.18 + 0.5 * rim), film_a * 0.5), 0.0, 1.0);
#else
	vec3 col = seen * 1.15 + haze * 0.35 + interior_glow * (0.5 + rim * 3.0);
	ALBEDO = mix(haze * 1.2 + interior_glow, col, step(0.001, mask));
	ALPHA = clamp(max(mask * 0.92, film_a), 0.0, 1.0);
#endif
}
