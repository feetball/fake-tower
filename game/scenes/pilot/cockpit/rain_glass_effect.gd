class_name RainGlassEffect
extends CompositorEffect
## Water on the windshield as a compute pass after the transparent pass, so
## the drops refract the full HDR scene including the additive airfield light
## sprites (a spatial shader's screen texture is captured before them, which
## turned every drop over a light into a dark speck) and bloom acts on the
## result. Pixels nearer than the glass (the cockpit interior) are left alone,
## using the depth buffer. Drop positions are fixed in the aircraft frame
## (azimuth/elevation of the view ray), so they stay on the glass when the
## pilot looks around. The water itself (beads, drops running up the glass with their
## trails) is shaders/rain_water.gdshaderinc, shared with the pane shader. Forward+
## only (RenderCaps.has_compute_effects): inert without a RenderingDevice (headless,
## Compatibility), and not used on Mobile, whose 3D buffer is not the rgba16f image
## this pass binds.

const WATER: ShaderInclude = preload("res://shaders/rain_water.gdshaderinc")
const CONTEXT := &"rain_glass"
const COPY := &"copy"
const GROUP := 8
## Anything nearer than this (m) is the flight deck, not the view through the glass.
const INTERIOR_M := 2.2

const GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform image2D copy_image;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;

layout(push_constant, std430) uniform Params {
	vec4 bx;   // camera -> aircraft basis, column x
	vec4 by;
	vec4 bz;
	vec4 a;    // width, height, time, rain 0..1
	vec4 b;    // airspeed kt, mode (0 copy, 1 apply), projection z.z, projection w.z
	vec4 c;    // tan half fov x, tan half fov y, px per radian, water travel (m of glass)
} p;

vec3 fetch(vec2 pos) {
	vec2 size = p.a.xy;
	pos = clamp(pos - 0.5, vec2(0.0), size - 2.0);
	ivec2 i = ivec2(floor(pos));
	vec2 f = fract(pos);
	vec3 c00 = imageLoad(copy_image, i).rgb;
	vec3 c10 = imageLoad(copy_image, i + ivec2(1, 0)).rgb;
	vec3 c01 = imageLoad(copy_image, i + ivec2(0, 1)).rgb;
	vec3 c11 = imageLoad(copy_image, i + ivec2(1, 1)).rgb;
	return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

vec3 soft(vec2 pos, float r) {
	return (fetch(pos) * 2.0 + fetch(pos + vec2(r, 0.0)) + fetch(pos - vec2(r, 0.0))
		+ fetch(pos + vec2(0.0, r)) + fetch(pos - vec2(0.0, r))) / 6.0;
}

%WATER%

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	vec2 size = p.a.xy;
	if (px.x >= int(size.x) || px.y >= int(size.y)) {
		return;
	}
	if (p.b.y < 0.5) {
		imageStore(copy_image, px, imageLoad(color_image, px));
		return;
	}
	vec2 uv = (vec2(px) + 0.5) / size;
	float depth = textureLod(depth_tex, uv, 0.0).r;
	// Depth to linear view distance, from the projection actually used
	// (reverse Z): depth = (P.z.z * z + P.w.z) / -z.
	float z = abs(p.b.w / (depth + p.b.z));
	if (depth <= 0.0) {
		z = 1e9;
	}
	if (z < %INTERIOR%) {
		return;
	}
	vec3 dir_c = normalize(vec3((uv.x * 2.0 - 1.0) * p.c.x, (1.0 - uv.y * 2.0) * p.c.y, -1.0));
	vec3 d = mat3(p.bx.xyz, p.by.xyz, p.bz.xyz) * dir_c;
	// Glass coordinates (m at ~1 m from the eye): azimuth right, elevation up.
	vec2 g = vec2(atan(d.x, -d.z), asin(clamp(d.y, -1.0, 1.0)));
	float rain = p.a.w;
	float t = p.a.z;
	float spd = clamp(p.b.x / 160.0, 0.0, 1.4);
	// Airflow drives the water up the front panes and back along the side ones.
	vec2 flow = normalize(vec2(sign(g.x) * (0.25 + 1.6 * smoothstep(0.35, 0.95, abs(g.x))), 1.0));
	vec2 fg = vec2(dot(g, vec2(flow.y, -flow.x)), dot(g, flow));
	vec3 w = water_on_glass(fg, t, p.c.w, rain, spd);
	vec3 orig = imageLoad(copy_image, px).rgb;
	if (w.z <= 0.001) {
		return;
	}
	vec2 n = w.xy;
	float nl = clamp(length(n), 0.0, 1.0);
	float ppr = p.c.z;
	// The surface normal is in the flow frame: turn it back to the glass (azimuth, elevation).
	vec2 ng = n.x * vec2(flow.y, -flow.x) + n.y * flow;
	// A drop is a tiny fisheye: it shows a wide, inverted, slightly blurred view
	// of what is behind it, gathering nearby lights into bright sparkles.
	vec2 offs = vec2(-ng.x, ng.y) * ppr * 0.028;
	vec3 refr = soft(vec2(px) + 0.5 + offs, 1.6);
	vec3 refr2 = soft(vec2(px) + 0.5 + offs * 1.8, 2.5);
	refr = max(refr, refr2 * 0.6) * 1.08;
	// Dark rim (total internal reflection) and a faint glint from the cockpit.
	float rim = smoothstep(0.6, 1.0, nl);
	refr *= 1.0 - 0.18 * rim;
	refr += vec3(0.010, 0.012, 0.016) * smoothstep(0.55, 0.75, nl) * (1.0 - smoothstep(0.75, 0.95, nl));
	vec3 col = mix(orig, refr, w.z * 0.9);
	imageStore(color_image, px, vec4(col, 1.0));
}
"""

var rain := 0.3
var airspeed_kt := 140.0
## The aircraft's global basis (drops are fixed to the glass, i.e. to it).
var aircraft_basis := Basis.IDENTITY
var time_s := 0.0
## Metres of glass the airflow has carried a reference drop since the start: the clock the
## running drops move by (CockpitWindshield integrates it from the airspeed).
var water_travel := 0.0

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	_rd = RenderingServer.get_rendering_device()
	if _rd != null:
		RenderingServer.call_on_render_thread(_create)


static func is_supported() -> bool:
	return RenderCaps.has_compute_effects()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		if _shader.is_valid():
			_rd.free_rid(_shader)
		if _sampler.is_valid():
			_rd.free_rid(_sampler)


func _create() -> void:
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = GLSL.replace("%WATER%", WATER.code).replace("%INTERIOR%", "%.2f" % INTERIOR_M)
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("RainGlassEffect: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(ss)


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not _pipeline.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var data := render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or data == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	if not buffers.has_texture(CONTEXT, COPY):
		buffers.create_texture(CONTEXT, COPY, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT,
			RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)
	var proj := data.get_cam_projection()
	var cam := data.get_cam_transform()
	var b := aircraft_basis.inverse() * cam.basis.orthonormalized()
	var tan_y := 1.0 / absf(proj.y.y)
	var pc := PackedFloat32Array([
		b.x.x, b.x.y, b.x.z, 0.0,
		b.y.x, b.y.y, b.y.z, 0.0,
		b.z.x, b.z.y, b.z.z, 0.0,
		float(size.x), float(size.y), time_s, rain,
		airspeed_kt, 0.0, proj.z.z, proj.w.z,
		1.0 / absf(proj.x.x), tan_y, float(size.y) * 0.5 / tan_y, water_travel,
	])
	var groups := Vector2i(ceili(size.x / float(GROUP)), ceili(size.y / float(GROUP)))
	for view in buffers.get_view_count():
		var uniforms: Array[RDUniform] = []
		uniforms.append(_image_uniform(0, buffers.get_color_layer(view)))
		uniforms.append(_image_uniform(1, buffers.get_texture_slice(CONTEXT, COPY, view, 0, 1, 1)))
		var du := RDUniform.new()
		du.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		du.binding = 2
		du.add_id(_sampler)
		du.add_id(buffers.get_depth_layer(view))
		uniforms.append(du)
		var set_rid := UniformSetCacheRD.get_cache(_shader, 0, uniforms)
		for mode in 2:
			pc[17] = float(mode)
			var bytes := pc.to_byte_array()
			var cl := _rd.compute_list_begin()
			_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
			_rd.compute_list_bind_uniform_set(cl, set_rid, 0)
			_rd.compute_list_set_push_constant(cl, bytes, bytes.size())
			_rd.compute_list_dispatch(cl, groups.x, groups.y, 1)
			_rd.compute_list_end()


static func _image_uniform(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u
