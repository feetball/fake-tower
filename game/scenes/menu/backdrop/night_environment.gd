class_name NightEnvironment
extends WorldEnvironment
## Night, low overcast, fog. ACES tonemapping, glow on lights, volumetric fog
## that the airfield lights scatter into, depth fog beyond the volumetric
## range, SSR for the wet asphalt. Without volumetric fog / SSR (Mobile,
## Compatibility) RenderCaps substitutes denser lit depth fog. Uses an HDRI from res://assets if found
## (heavily darkened — it only needs to give the cloud deck some shape).

## Meteorological visibility in metres; drives fog density.
@export var visibility_m := 1400.0
@export var exposure := 1.0
@export var use_hdri := true
@export var ssr := true


func _ready() -> void:
	environment = make(visibility_m, exposure, use_hdri, ssr)


## Extinction coefficient matching a visibility (Koschmieder: 3.0 / V).
static func extinction_for(visibility: float) -> float:
	return 3.0 / maxf(visibility, 50.0)


static func make(visibility: float, exp_mult: float = 1.0, hdri: bool = true, with_ssr: bool = true) -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	var hdr_path := AssetLookup.find_path(["night_overcast_fog", "night"], [".hdr", ".exr"]) if hdri else ""
	if hdr_path != "":
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(hdr_path) as Texture2D
		pano.energy_multiplier = 0.25
		sky.sky_material = pano
	else:
		var proc := ProceduralSkyMaterial.new()
		proc.sky_top_color = Color(0.004, 0.005, 0.008)
		proc.sky_horizon_color = Color(0.035, 0.03, 0.032)
		proc.ground_bottom_color = Color(0.003, 0.003, 0.004)
		proc.ground_horizon_color = Color(0.03, 0.026, 0.028)
		proc.sky_curve = 0.25
		proc.sun_angle_max = 0.0
		proc.energy_multiplier = 1.0
		sky.sky_material = proc
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = exp_mult
	env.tonemap_white = 6.0

	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for lvl in 7:
		env.set_glow_level(lvl, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.8)
	env.set_glow_level(5, 0.8)
	env.set_glow_level(6, 0.5)

	var sigma := extinction_for(visibility)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.05, 0.055, 0.065)
	env.fog_light_energy = 1.0
	env.fog_density = sigma * 0.4
	env.fog_sky_affect = 1.0
	env.fog_aerial_perspective = 0.0

	env.volumetric_fog_density = sigma * 10.0
	env.volumetric_fog_albedo = Color(0.85, 0.87, 0.9)
	env.volumetric_fog_emission = Color(0.045, 0.048, 0.06)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 1400.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 1.0
	env.volumetric_fog_temporal_reprojection_enabled = true

	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.4
	env.ssr_enabled = with_ssr and RenderCaps.has_ssr()
	# Last: Mobile / Compatibility get depth fog in place of the volumetric medium.
	RenderCaps.enable_volumetric_fog(env)
	RenderCaps.adapt_glow(env)
	return env
