class_name RenderCaps
extends RefCounted
## What the active renderer and platform can do, and the default quality tier.
## Views ask this instead of testing renderer names themselves.
##
## Renderer per platform (project.godot): desktop Forward+, Android/iOS Mobile,
## Web Compatibility (WebGL 2). Any of them can be forced for testing with
## `--rendering-method mobile` / `--rendering-method gl_compatibility --rendering-driver opengl3`.
##
##   Forward+       everything: volumetric fog + FogVolumes, SSR, SSAO, compute effects
##   Mobile         no volumetric fog, FogVolumes, SSR or SSAO; the 3D buffer is RGB10A2,
##                  so the rgba16f compute pass (RainGlassEffect) is not used either
##   Compatibility  as Mobile, and no RenderingDevice at all; depth-texture NDC z is
##                  -1..1 (shaders branch on CURRENT_RENDERER)
##
## Quality tiers "low" | "medium" | "high" (pilot displays resolution, rain/wisp counts,
## shadowed lights, fog). Forward+ on desktop defaults to "high"; Mobile, Compatibility,
## Web, Android and iOS default to "low". User arg `--quality=<tier>` (or the pilot's
## older `--pilot-quality=<tier>`) overrides it.
##
## Without volumetric fog, `fog_fallback()` folds the volumetric medium into the depth
## fog (denser, lit by the fog light colour) so the night-fog mood survives.

const FORWARD_PLUS := "forward_plus"
const MOBILE := "mobile"
const COMPATIBILITY := "gl_compatibility"
const TIERS: Array[String] = ["low", "medium", "high"]
## Brightness of the depth fog standing in for volumetric fog (see fog_fallback).
const FALLBACK_FOG_LIGHT := 1.6
const FALLBACK_FOG_TINT := Color(1.08, 0.98, 0.86)


## "forward_plus" | "mobile" | "gl_compatibility".
static func method() -> String:
	return RenderingServer.get_current_rendering_method()


## "web" | "android" | "ios" | "macos" | "windows" | "linux" | "other".
static func platform() -> String:
	for f: String in ["web", "android", "ios", "macos", "windows"]:
		if OS.has_feature(f):
			return f
	if OS.has_feature("linuxbsd"):
		return "linux"
	return "other"


## Phones and tablets, natively or in a mobile browser.
static func is_handheld() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") \
		or OS.has_feature("web_android") or OS.has_feature("web_ios")


static func is_forward_plus() -> bool:
	return method() == FORWARD_PLUS


static func is_compatibility() -> bool:
	return method() == COMPATIBILITY


## Software rasterizers (llvmpipe / lavapipe / SwiftShader): used for off-screen screenshots.
static func is_software() -> bool:
	var a := RenderingServer.get_video_adapter_name().to_lower()
	for s in ["llvmpipe", "lavapipe", "swiftshader", "softpipe"]:
		if a.contains(s):
			return true
	return false


## Environment.volumetric_fog_* and FogVolume nodes (FogMaterial shaders fail to compile elsewhere).
static func has_volumetric_fog() -> bool:
	return is_forward_plus()


## FogVolume nodes (their FogMaterial shaders only compile on Forward+).
static func has_fog_volumes() -> bool:
	return is_forward_plus()


## Screen-space reflections. Off on software rasterizers too: SSR plus SubViewport
## displays crashes llvmpipe.
static func has_ssr() -> bool:
	return is_forward_plus() and not is_software()


static func has_ssao() -> bool:
	return is_forward_plus()


## CompositorEffect compute passes written for the Forward+ rgba16f colour buffer.
static func has_compute_effects() -> bool:
	return is_forward_plus() and RenderingServer.get_rendering_device() != null


## The tier this device gets when nothing overrides it.
static func default_quality() -> String:
	if not is_forward_plus() or is_handheld() or OS.has_feature("web"):
		return "low"
	return "high"


## The tier in effect: `--quality=` / `--pilot-quality=` user arg, else default_quality().
static func quality() -> String:
	for a in OS.get_cmdline_user_args():
		for prefix in ["--quality=", "--pilot-quality="]:
			if a.begins_with(prefix) and a.trim_prefix(prefix) in TIERS:
				return a.trim_prefix(prefix)
	return default_quality()


## Switch volumetric fog on where the renderer has it; elsewhere fold the configured
## volumetric medium into the depth fog (fog_fallback). Call after the volumetric_fog_*
## properties are set and with volumetric fog still off: enabling it on a renderer
## without it logs a warning. `fog_gain` scales the extra depth-fog density.
static func enable_volumetric_fog(env: Environment, fog_gain: float = 1.0) -> void:
	if has_volumetric_fog():
		env.volumetric_fog_enabled = true
	else:
		fog_fallback(env, fog_gain)


## Depth fog in place of the volumetric medium: part of its density moves into the
## exponential fog, and its emission plus the ambient light it scattered brighten
## the fog light colour, so distant lights still sit in lit haze instead of black.
static func fog_fallback(env: Environment, fog_gain: float = 1.0) -> void:
	env.volumetric_fog_enabled = false
	env.fog_enabled = true
	env.fog_density = maxf(env.fog_density, 0.0) + fallback_density(env.volumetric_fog_density) * fog_gain
	var c := env.fog_light_color * env.fog_light_energy
	var e := env.volumetric_fog_emission * env.volumetric_fog_emission_energy
	var amb := env.ambient_light_color * env.ambient_light_energy * env.volumetric_fog_ambient_inject
	var a := env.volumetric_fog_albedo
	# Brighter than the depth fog alone: the volumetric medium also carried the
	# light it scattered from the lamps, which the softlight glow darkens otherwise.
	var fog := Color(
		(c.r + e.r + a.r * amb.r * 0.05) * FALLBACK_FOG_LIGHT,
		(c.g + e.g + a.g * amb.g * 0.05) * FALLBACK_FOG_LIGHT,
		(c.b + e.b + a.b * amb.b * 0.05) * FALLBACK_FOG_LIGHT)
	# That scattered lamp light is warm (incandescent / sodium): same brightness, warmer hue.
	var lum := fog.get_luminance()
	env.fog_light_color = fog.lerp(FALLBACK_FOG_TINT * lum, 0.6)
	env.fog_light_energy = 1.0


## Exponential-fog density standing in for a volumetric density: the volumetric
## range is short (volumetric_fog_length), the depth fog runs to infinity.
static func fallback_density(volumetric_density: float) -> float:
	return volumetric_density * 0.12


## Compatibility renders 3D into a low-range buffer, so little exceeds the glow
## threshold and bloom on lights all but disappears: lower the threshold and push
## the intensity there. Call after the Environment's glow is configured.
static func adapt_glow(env: Environment) -> void:
	if is_compatibility():
		env.glow_hdr_threshold *= 0.55
		env.glow_intensity *= 1.5


## Extra gain for hand-made light glows (FogGlow sprites) where bloom is weak.
static func glow_gain() -> float:
	return 1.6 if is_compatibility() else 1.0
