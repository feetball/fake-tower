shader_type spatial;
// Wet runway asphalt and runway paint. GGX + Lambert by hand so a grazing
// backscatter lobe can be added: rough asphalt, and far more so paint with glass
// beads, throws light back towards a source near the eye (the landing lights),
// which is why a runway lights up in front of a landing aircraft although plain
// Lambert shading at a 5-10° grazing angle would leave it black.
// Asphalt mode: CC0 texture set tiled in metres, rubber deposits in the
// touchdown zone, standing-water patches (smoother, darker) and wetness.
// Coordinates come from the mesh-local vertex (runway frame), so they do not
// swim with the floating origin.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform bool paint = false;
uniform vec3 tint : source_color = vec3(0.32, 0.32, 0.33);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_arm = false;
uniform float tile_m = 3.0;
uniform float normal_strength = 0.6;
uniform float wetness : hint_range(0.0, 1.0) = 0.85;
uniform float origin_z = 0.0; // mesh position along the runway (runway frame z)
uniform float rubber_from_m = 120.0;
uniform float rubber_to_m = 900.0;
uniform float backscatter = 1.2;
uniform float specular_scale = 1.0;
uniform float backscatter_power = 18.0;

varying vec2 v_rw; // x = metres right of the centreline, y = metres from the threshold

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
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_rw = vec2(VERTEX.x, -(VERTEX.z + origin_z));
}

void fragment() {
	if (paint) {
		ALBEDO = tint;
		ROUGHNESS = mix(0.55, 0.18, wetness);
		SPECULAR = 0.5;
	} else {
		vec2 uv = v_rw / tile_m;
		vec3 base = texture(albedo_tex, uv).rgb * tint;
		float rough = has_arm ? texture(arm_tex, uv).g : 0.8;
		// Large-scale patchiness so the surface is not a uniform repeat.
		float patch = fbm(v_rw * vec2(0.08, 0.02));
		base *= 0.8 + 0.4 * patch;
		// Rubber: black deposits along the main-gear tracks in the touchdown zone.
		float along = smoothstep(rubber_from_m, rubber_from_m + 120.0, v_rw.y)
			* (1.0 - smoothstep(rubber_to_m - 300.0, rubber_to_m, v_rw.y));
		float lat = abs(v_rw.x);
		float tracks = smoothstep(11.0, 5.0, lat) * (0.55 + 0.45 * smoothstep(0.3, 2.5, lat));
		float streaks = fbm(vec2(v_rw.x * 1.7, v_rw.y * 0.035)) * fbm(v_rw * vec2(0.6, 0.012));
		float rubber = clamp(along * tracks * (0.35 + 1.4 * streaks), 0.0, 1.0);
		base = mix(base, base * 0.22, rubber);
		// Standing water in shallow dips: darker, mirror-smooth.
		float puddle = smoothstep(0.58, 0.68, fbm(v_rw * vec2(0.14, 0.05) + 3.7)) * wetness;
		float wet_rough = mix(rough, rough * 0.35, wetness);
		ROUGHNESS = clamp(mix(wet_rough, 0.04, puddle) * (1.0 - 0.25 * rubber), 0.03, 1.0);
		ALBEDO = base * mix(1.0, 0.6, max(puddle, wetness * 0.4));
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength * (1.0 - puddle * 0.9);
		SPECULAR = 0.5 * specular_scale;
	}
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float ndv = max(dot(NORMAL, VIEW), 1e-4);
	vec3 h = normalize(LIGHT + VIEW + vec3(0.0, 1e-4, 0.0));
	float ndh = max(dot(NORMAL, h), 0.0);
	// Floor the roughness: a mirror-sharp lobe from a point light overflows the
	// half-float buffer (inf -> NaN -> black specks after the post passes).
	float a = max(ROUGHNESS * ROUGHNESS, 0.01);
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float d = a2 / (PI * dd * dd);
	float k = a * 0.5;
	float g = (ndl / (ndl * (1.0 - k) + k)) * (ndv / (ndv * (1.0 - k) + k));
	float f = 0.04 + 0.96 * pow(1.0 - max(dot(LIGHT, h), 0.0), 5.0);
	vec3 lc = LIGHT_COLOR * ATTENUATION;
	DIFFUSE_LIGHT += lc * ndl / PI;
	SPECULAR_LIGHT += min(lc * d * g * f / (4.0 * ndv) * SPECULAR_AMOUNT * specular_scale, vec3(12.0));
	// Backscatter towards the light source (opposition effect / retroreflection).
	float back = pow(max(dot(LIGHT, VIEW), 0.0), backscatter_power);
	DIFFUSE_LIGHT += lc * back * sqrt(ndl) * backscatter / PI * (paint ? 3.0 : 1.0);
}
