class_name PilotOutside
extends Node3D
## Everything outside the aircraft: the night environment with fog and cloud,
## the lit aerodrome (reused backdrop pieces), terrain, town lights. All world
## content hangs under `world_root`, which is translated by minus the eye
## position every frame (floating origin). Fog, cloud and light extinction
## follow PilotWeather from the ATIS visibility and ceiling.

const FIELD_FT := 512.0
const TOWN_SEED := 4127

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
	Session.round_began.connect(_read_atis)
	_collect_airport_lights.call_deferred()


func _read_atis() -> void:
	if _debug_wx:
		return
	var a: Dictionary = Session.atis
	if a.is_empty():
		return
	weather = PilotWeather.new(float(a.get("visibility_m", 900)), float(a.get("ceiling_ft", 300)))
	_last_sigma = -1.0


## Override the weather for reproducible screenshots.
func debug_weather(vis_m: float, ceiling_ft: float) -> void:
	_debug_wx = true
	weather = PilotWeather.new(vis_m, ceiling_ft)
	_last_sigma = -1.0


func set_quality(q: String) -> void:
	_volumetric = q != "low"
	if env != null:
		env.volumetric_fog_enabled = _volumetric
		env.ssr_enabled = q == "high"
		env.volumetric_fog_length = 900.0 if q == "high" else 500.0
	if _fog_banks != null:
		_fog_banks.visible = q == "high"


func set_eye(eye: Vector3) -> void:
	world_root.position = -eye
	_eye_h_ft = eye.y / World.FT_TO_M - FIELD_FT
	_update_fog()


func _make_environment() -> Environment:
	var e := NightEnvironment.make(weather.visibility_m, 1.0, true, true)
	e.background_energy_multiplier = 0.35
	e.ambient_light_energy = 0.6
	e.fog_light_color = Color(0.035, 0.038, 0.046)
	e.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	e.volumetric_fog_emission = Color(0.01, 0.011, 0.014)
	e.volumetric_fog_emission_energy = 1.0
	e.volumetric_fog_anisotropy = 0.6
	e.volumetric_fog_length = 900.0
	e.volumetric_fog_detail_spread = 1.6
	e.volumetric_fog_ambient_inject = 0.3
	e.glow_intensity = 0.8
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.0
	e.ssao_enabled = false
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
	for lp in _airport_lights:
		lp.extinction_per_m = ground_sigma
		lp.apply_uniforms()
	if terrain != null:
		for i in terrain.summit_lights.size():
			var lp := terrain.summit_lights[i]
			lp.extinction_per_m = weather.mean_sigma(h, terrain.summit_heights_ft[i] - FIELD_FT)
			lp.apply_uniforms()
	for i in _town_lights.size():
		_town_lights[i].extinction_per_m = weather.mean_sigma(h, _town_heights_ft[i])
		_town_lights[i].apply_uniforms()


func _collect_airport_lights() -> void:
	_airport_lights.clear()
	_collect(airport, _airport_lights)
	_last_sigma = -1.0


static func _collect(n: Node, out: Array[LightPoints]) -> void:
	if n is LightPoints:
		out.append(n as LightPoints)
	for c in n.get_children():
		_collect(c, out)


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
