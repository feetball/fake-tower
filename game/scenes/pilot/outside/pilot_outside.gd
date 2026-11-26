class_name PilotOutside
extends Node3D
## Everything outside the aircraft: the night environment with fog and cloud,
## the lit aerodrome (reused backdrop pieces), terrain, town lights and their
## glow in the haze, ragged scud under the cloud base. All world content hangs
## under `world_root`, which is translated by minus the eye position every
## frame (floating origin). Fog, cloud and light extinction follow
## PilotWeather from the ATIS visibility and ceiling.

const FIELD_FT := 512.0
const TOWN_SEED := 4127
const LIGHT_EXTINCTION := 0.6
## Airfield light tuning for the approach view (see LightPoints): lamps dim with
## distance as d^-POINT_FALLOFF once unresolved, so rows of lights recede.
const POINT_FALLOFF := 0.45
const AIRFIELD_INTENSITY := 2.6
## Without volumetric fog (Mobile, Compatibility): how much of the volumetric medium
## the depth fog takes over, and the colour of that fog below / inside the cloud
## (standing in for the medium lit by the town glow and by the aircraft's own lights).
const FALLBACK_FOG_GAIN := 1.0
const FALLBACK_FOG_CLEAR := Color(0.055, 0.053, 0.055)
const FALLBACK_FOG_CLOUD := Color(0.12, 0.12, 0.125)

var world_root: Node3D
var env: Environment
var weather := PilotWeather.new()
var terrain: WorldTerrain
var airport: AirportLayout

var _env_node: WorldEnvironment
var _airport_lights: Array[LightPoints] = []
var _town_lights: Array[LightPoints] = []
var _town_heights_ft: Array[float] = []
var _volumetric := true
var _debug_wx := false
var _eye_h_ft := 3000.0
var _last_sigma := -1.0
var _fog_banks: FogBanks
var _cloud_base: PilotCloudBase
var _sky_glow: LightPoints
## 0..1 how much of the world (beyond the cockpit) is visible: used for sound and turbulence.
var in_cloud := 0.0


func _ready() -> void:
	_read_atis()
	_env_node = WorldEnvironment.new()
	_env_node.name = "Environment"
	env = _make_environment()
	_env_node.environment = env
	add_child(_env_node)
	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)
	airport = AirportLayout.new()
	airport.name = "Airport"
	airport.visibility_m = weather.visibility_m
	world_root.add_child(airport)
	airport.place_in_world()
	terrain = WorldTerrain.new()
	terrain.name = "Terrain"
	world_root.add_child(terrain)
	_build_towns()
	_fog_banks = FogBanks.new()
	_fog_banks.name = "GroundFog"
	_fog_banks.extent = Vector3(5000.0, 60.0, 5000.0)
	_fog_banks.density = 0.01
	_fog_banks.position = World.to_3d(-0.5, 0.0, FIELD_FT) + Vector3(0.0, 18.0, 0.0)
	world_root.add_child(_fog_banks)
	_cloud_base = PilotCloudBase.new()
	_cloud_base.name = "CloudBase"
	world_root.add_child(_cloud_base)
	_build_sky_glow()
	Session.round_began.connect(_read_atis)
	_collect_airport_lights.call_deferred()


func _read_atis() -> void:
	if _debug_wx:
		return
	var a: Dictionary = Session.atis
	if a.is_empty():
		return
	weather = PilotWeather.new(float(a.get("visibility_m", 900)), float(a.get("ceiling_ft", 300)))
	_weather_changed()


## Override the weather for reproducible screenshots.
func debug_weather(vis_m: float, ceiling_ft: float) -> void:
	_debug_wx = true
	weather = PilotWeather.new(vis_m, ceiling_ft)
	_weather_changed()


func _weather_changed() -> void:
	_last_sigma = -1.0
	if _cloud_base != null:
		_cloud_base.set_ceiling_ft(FIELD_FT + weather.ceiling_ft)


func set_quality(q: String) -> void:
	_volumetric = q != "low"
	if _cloud_base != null:
		_cloud_base.multimesh.visible_instance_count = _cloud_base.count if q != "low" else _cloud_base.count / 2
	if env != null:
		# Mobile / Compatibility: no volumetric fog, _update_fog thickens the depth fog instead.
		env.volumetric_fog_enabled = _volumetric and RenderCaps.has_volumetric_fog()
		# SSR plus SubViewport displays crashes the llvmpipe software rasterizer
		# (used for off-screen screenshots); real GPUs keep it on high.
		env.ssr_enabled = q == "high" and RenderCaps.has_ssr()
		env.volumetric_fog_length = 900.0 if q == "high" else 500.0
	if _fog_banks != null:
		_fog_banks.visible = q == "high" and RenderCaps.has_fog_volumes()
	_last_sigma = -1.0


static func is_software_renderer() -> bool:
	return RenderCaps.is_software()


func set_eye(eye: Vector3) -> void:
	world_root.position = -eye
	_eye_h_ft = eye.y / World.FT_TO_M - FIELD_FT
	_update_fog()


## Extinction per metre of the air around the eye (drives the landing-light shafts).
func scatter_at_eye() -> float:
	return weather.sigma_at(maxf(_eye_h_ft, 0.0))


func _make_environment() -> Environment:
	var e := NightEnvironment.make(weather.visibility_m, 1.0, true, RenderCaps.has_ssr())
	e.background_energy_multiplier = 0.35
	e.ambient_light_energy = 0.75
	# Night fog over a lit town and airfield glows faintly warm-grey.
	e.fog_light_color = Color(0.04, 0.038, 0.04)
	e.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	e.volumetric_fog_emission = Color(0.008, 0.0085, 0.01)
	e.volumetric_fog_emission_energy = 1.0
	e.volumetric_fog_anisotropy = 0.6
	e.volumetric_fog_length = 900.0
	e.volumetric_fog_detail_spread = 1.6
	e.volumetric_fog_ambient_inject = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.2
	e.tonemap_white = 6.0
	# Soft-light bloom weighted to the small levels: bright lamps bloom, the
	# hundreds of lamps of the approach lights do not merge into one blob.
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.glow_intensity = 0.85
	e.glow_strength = 1.0
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 0.85
	e.glow_hdr_scale = 2.0
	var levels := [0.0, 1.0, 0.8, 0.55, 0.35, 0.2, 0.1]
	for i in levels.size():
		e.set_glow_level(i, levels[i])
	e.ssao_enabled = false
	RenderCaps.adapt_glow(e)
	return e


func _update_fog() -> void:
	var h := maxf(_eye_h_ft, 0.0)
	in_cloud = weather.cloudiness(h)
	var ground_sigma := weather.mean_sigma(h, 0.0)
	# Only push uniforms when something visibly changed (a few hundred lights).
	if _last_sigma > 0.0 and absf(ground_sigma - _last_sigma) / _last_sigma < 0.02:
		return
	_last_sigma = ground_sigma
	var local_sigma := weather.sigma_at(h)
	# Depth fog carries the slant-path extinction to the ground; volumetric fog
	# adds the local medium around the aircraft that the lights scatter in.
	env.fog_density = ground_sigma * 0.55
	env.volumetric_fog_density = local_sigma * 0.9
	if not env.volumetric_fog_enabled:
		env.fog_density += RenderCaps.fallback_density(local_sigma * 0.9) * FALLBACK_FOG_GAIN
		env.fog_light_color = FALLBACK_FOG_CLEAR.lerp(FALLBACK_FOG_CLOUD, in_cloud)
	# Lights are seen much further than dark objects (Allard vs Koschmieder).
	for lp in _airport_lights:
		lp.extinction_per_m = ground_sigma * LIGHT_EXTINCTION
		lp.apply_uniforms()
	if terrain != null:
		for i in terrain.summit_lights.size():
			var lp := terrain.summit_lights[i]
			lp.extinction_per_m = weather.mean_sigma(h, terrain.summit_heights_ft[i] - FIELD_FT) * LIGHT_EXTINCTION
			lp.apply_uniforms()
	for i in _town_lights.size():
		_town_lights[i].extinction_per_m = weather.mean_sigma(h, _town_heights_ft[i]) * LIGHT_EXTINCTION
		_town_lights[i].apply_uniforms()
	if _sky_glow != null:
		# The glow is light scattered in the haze near the source: it survives
		# much further than the lamps themselves, but not through cloud.
		_sky_glow.extinction_per_m = weather.mean_sigma(h, 150.0) * 0.12
		_sky_glow.apply_uniforms()


func _collect_airport_lights() -> void:
	_airport_lights.clear()
	_collect(airport, _airport_lights)
	# Seen from the approach through fog: brighter cores and wider scattering
	# halos than the menu backdrop's settings.
	for lp in _airport_lights:
		lp.intensity_scale = AIRFIELD_INTENSITY
		lp.point_falloff = POINT_FALLOFF
		lp.halo_gain *= 1.3
		lp.min_halo_angle = 0.016
		lp.min_core_angle = 0.0019
		lp.aureole_gain = 0.002
		lp.aureole_angle = 0.011
	_last_sigma = -1.0


static func _collect(n: Node, out: Array[LightPoints]) -> void:
	if n is LightPoints:
		out.append(n as LightPoints)
	for c in n.get_children():
		_collect(c, out)


## Diffuse glow of the towns and the airfield in the low haze: huge, faint,
## warm halos without a core. Gives the eye a horizon reference on a dark night.
func _build_sky_glow() -> void:
	_sky_glow = LightPoints.new()
	_sky_glow.name = "SkyGlow"
	_sky_glow.halo_size_m = 400.0
	_sky_glow.halo_gain = 0.5
	_sky_glow.min_halo_angle = 0.0
	_sky_glow.min_core_angle = 0.0
	var sodium := Color(1.0, 0.6, 0.32)
	# [x nm, y nm, intensity, glow radius m] (the soft "core" is the glow)
	var glows := [[-4.5, 3.2, 0.05, 3200.0], [6.5, -3.5, 0.03, 2200.0], [-2.0, -4.2, 0.02, 1600.0],
		[-0.7, 0.0, 0.03, 1400.0]]
	for g: Array in glows:
		_sky_glow.add_point(World.to_3d(g[0], g[1], FIELD_FT) + Vector3(0.0, 120.0, 0.0), sodium, g[2], g[3])
	world_root.add_child(_sky_glow)
	_sky_glow.commit()


## Scattered light of the town east-south-east of the field, villages and a
## road, so the murk has some structure when it thins near the ground.
func _build_towns() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED
	var sodium := Color(1.0, 0.52, 0.18)
	var white := Color(0.85, 0.9, 1.0)
	# name: [x nm, y nm, spread nm, count]
	var towns := [[-4.5, 3.2, 0.9, 160], [6.5, -3.5, 0.6, 70], [-2.0, -4.2, 0.45, 40], [3.0, 2.8, 0.35, 30]]
	for t: Array in towns:
		var lp := LightPoints.new()
		lp.name = "Town"
		lp.halo_size_m = 25.0
		lp.halo_gain = 0.22
		lp.min_halo_angle = 0.01
		var centre := World.to_3d(t[0], t[1], FIELD_FT)
		for i in int(t[3]):
			var r := float(t[2]) * World.NM_TO_M * sqrt(rng.randf())
			var a := rng.randf() * TAU
			var p := centre + Vector3(cos(a) * r, rng.randf_range(4.0, 12.0), sin(a) * r)
			lp.add_point(p, sodium if rng.randf() < 0.7 else white, rng.randf_range(2.0, 6.0), 0.9)
		world_root.add_child(lp)
		lp.commit()
		_town_lights.append(lp)
		_town_heights_ft.append(30.0)
	# A road along the valley south of the field.
	var road := LightPoints.new()
	road.name = "Road"
	road.halo_size_m = 20.0
	road.halo_gain = 0.2
	for i in 60:
		var x := -6.0 + i * 0.22
		road.add_point(World.to_3d(x, -1.6 - 0.15 * sin(x * 0.7), FIELD_FT) + Vector3(0.0, 9.0, 0.0), sodium, 4.0, 1.0)
	world_root.add_child(road)
	road.commit()
	_town_lights.append(road)
	_town_heights_ft.append(30.0)
