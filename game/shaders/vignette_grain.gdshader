shader_type canvas_item;
// Full-screen finishing pass for menu screens, multiplied over the 3D image:
// a soft vignette plus fine animated grain that also breaks up banding in the
// dark fog gradients.
render_mode blend_mul, unshaded;

uniform float vignette_strength = 0.55;
uniform float vignette_radius = 0.75;
uniform float grain_amount = 0.035;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float v = smoothstep(vignette_radius * 0.45, vignette_radius * 1.2, length(uv));
	float g = hash(FRAGCOORD.xy + floor(TIME * 24.0) * 17.0) - 0.5;
	float f = (1.0 - v * vignette_strength) * (1.0 + g * grain_amount * 2.0);
	COLOR = vec4(vec3(f), 1.0);
}
