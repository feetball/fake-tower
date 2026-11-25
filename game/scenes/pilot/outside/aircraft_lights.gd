class_name PilotAircraftLights
extends Node3D
## The aircraft's own exterior lights, in the aircraft frame (eye = origin):
## wing-root landing lights and the nose taxi light (they light the cloud,
## then the runway), double-flash white wingtip strobes and the red beacon
## (they flash the cloud around the aircraft), steady nav lights. Real lights
## with a little volumetric-fog contribution; no shadows. The landing-light
## beams are also drawn as additive shafts (froxels are too coarse for a 17°
## beam, and the shafts work without volumetric fog), and the rain or cloud
## mist rushing past shows up as streaks inside the beams and in the strobe
## flashes (shaders/rain_streaks.gdshader).

const C := 0.53
const SPOT_FOG := 0.45
const BEAM_SHADER: Shader = preload("res://shaders/light_beam.gdshader")
const RAIN_SHADER: Shader = preload("res://shaders/rain_streaks.gdshader")
const LANDING_HALF_ANGLE := 8.5
const SHAFT_LENGTH := 260.0
const RAIN_DROPS := {"low": 1200, "medium": 2600, "high": 4200}

@export var volumetric := true

var _landing: Array[SpotLight3D] = []
var _shafts: Array[ShaderMaterial] = []
var _taxi: SpotLight3D
var _strobes: Array[OmniLight3D] = []
var _beacon: OmniLight3D
var _rain: MultiMeshInstance3D
var _rain_mat: ShaderMaterial
var _t := 0.0
var gear_down := true


func _ready() -> void:
	for side: float in [-1.0, 1.0]:
		var s := _spot(Vector3(C + side * 4.2, -2.9, 9.5), Color(1.0, 0.96, 0.9), 80.0, 900.0, LANDING_HALF_ANGLE)
		s.rotation = Vector3(deg_to_rad(-10.0), deg_to_rad(-side * 1.5), 0.0)
		_landing.append(s)
		_shafts.append(_shaft(s))
	_taxi = _spot(Vector3(C, -3.6, -1.0), Color(1.0, 0.95, 0.88), 12.0, 250.0, 16.0)
	_taxi.rotation = Vector3(deg_to_rad(-9.0), 0.0, 0.0)
	for side: float in [-1.0, 1.0]:
		var st := _omni(Vector3(C + side * 17.0, -2.2, 13.5), Color(0.9, 0.95, 1.0), 70.0)
		_strobes.append(st)
		_omni(Vector3(C + side * 16.8, -2.2, 13.0), Color(1.0, 0.1, 0.05) if side < 0.0 else Color(0.1, 1.0, 0.3), 14.0).light_energy = 1.2
	_beacon = _omni(Vector3(C, 0.9, 14.0), Color(1.0, 0.08, 0.03), 45.0)
	_build_rain()


func _spot(pos: Vector3, col: Color, energy: float, rng: float, angle: float) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.position = pos
	s.light_color = col
	s.light_energy = energy
	s.spot_range = rng
	s.spot_angle = angle
	s.spot_attenuation = 0.6
	s.spot_angle_attenuation = 1.4
	s.light_volumetric_fog_energy = SPOT_FOG if volumetric else 0.0
	s.shadow_enabled = false
	s.light_specular = 0.6
	add_child(s)
	return s


## A visible beam along the spot's −Z: an open cone with the narrow end at the lamp.
func _shaft(s: SpotLight3D) -> ShaderMaterial:
	var cone := CylinderMesh.new()
	cone.height = SHAFT_LENGTH
	cone.top_radius = 0.25
	cone.bottom_radius = tan(deg_to_rad(LANDING_HALF_ANGLE)) * SHAFT_LENGTH
	cone.radial_segments = 20
	cone.rings = 6
	cone.cap_top = false
	cone.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	mat.set_shader_parameter(&"beam_color", s.light_color)
	mat.set_shader_parameter(&"length_m", SHAFT_LENGTH)
	mat.set_shader_parameter(&"falloff", 2.2)
	mat.set_shader_parameter(&"near_fade_m", Vector2(4.0, 30.0))
	mat.set_shader_parameter(&"soft_m", 8.0)
	var mi := MeshInstance3D.new()
	mi.name = "Shaft"
	mi.mesh = cone
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.x = PI * 0.5
	mi.position.z = -SHAFT_LENGTH * 0.5
	s.add_child(mi)
	return mat


func _omni(pos: Vector3, col: Color, rng: float) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = col
	o.light_energy = 0.0
	o.omni_range = rng
	o.omni_attenuation = 1.2
	o.light_volumetric_fog_energy = 3.0 if volumetric else 0.0
	o.shadow_enabled = false
	add_child(o)
	return o


func _build_rain() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = RAIN_DROPS["high"]
	# Positions are animated in the shader; all instances sit at the origin.
	mm.custom_aabb = AABB(Vector3(-26.0, -20.0, -64.0), Vector3(52.0, 30.0, 66.0))
	_rain = MultiMeshInstance3D.new()
	_rain.name = "Rain"
	_rain.multimesh = mm
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = RAIN_SHADER
	_rain.material_override = _rain_mat
	add_child(_rain)
	var dirs: Array[Vector3] = []
	for s in _landing:
		dirs.append(s.transform.basis * Vector3.FORWARD)
	_rain_mat.set_shader_parameter(&"lamp0_pos", _landing[0].position)
	_rain_mat.set_shader_parameter(&"lamp0_dir", dirs[0])
	_rain_mat.set_shader_parameter(&"lamp1_pos", _landing[1].position)
	_rain_mat.set_shader_parameter(&"lamp1_dir", dirs[1])
	_rain_mat.set_shader_parameter(&"lamp_cos", cos(deg_to_rad(LANDING_HALF_ANGLE)))
	_rain_mat.set_shader_parameter(&"taxi_pos", _taxi.position)
	_rain_mat.set_shader_parameter(&"taxi_dir", _taxi.transform.basis * Vector3.FORWARD)
	_rain_mat.set_shader_parameter(&"taxi_cos", cos(deg_to_rad(16.0)))


func set_volumetric(on: bool) -> void:
	volumetric = on
	for c in get_children():
		if c is Light3D:
			(c as Light3D).light_volumetric_fog_energy = (SPOT_FOG if c is SpotLight3D else 3.0) if on else 0.0


func set_quality(q: String) -> void:
	set_volumetric(q != "low")
	_rain.multimesh.visible_instance_count = int(RAIN_DROPS.get(q, RAIN_DROPS["high"]))


## Weather around the aircraft: extinction per metre of the air the beams cross,
## how far into cloud (0..1), and the true airspeed (m/s) that drives the streaks.
func set_conditions(scatter_per_m: float, cloud: float, tas_ms: float) -> void:
	# Shafts: in-scattered light grows with the density of the medium; a thick
	# cloud gives a short, bright beam, thin fog a long faint one.
	for m in _shafts:
		m.set_shader_parameter(&"intensity", clampf(scatter_per_m * 9.0, 0.0, 0.22))
		m.set_shader_parameter(&"extinction_per_m", scatter_per_m * 0.8)
	# In cloud the "rain" is dense mist; below it, steady light rain.
	_rain_mat.set_shader_parameter(&"amount", lerpf(0.45, 1.0, cloud))
	_rain_mat.set_shader_parameter(&"brightness", lerpf(1.0, 0.7, cloud))
	_rain_mat.set_shader_parameter(&"velocity", Vector3(0.0, -6.5 * (1.0 - cloud), maxf(tas_ms, 1.0)))


## Lights off (crash) or on.
func set_powered(on: bool) -> void:
	visible = on


func _process(delta: float) -> void:
	_t += delta
	# Strobes: double flash every 1.2 s.
	var ph := fmod(_t, 1.2)
	var flash := 1.0 if ph < 0.05 or (ph > 0.14 and ph < 0.19) else 0.0
	for s in _strobes:
		s.light_energy = 60.0 * flash
	# Beacon: ~1 Hz soft red pulse.
	var bp := fmod(_t + 0.4, 1.0)
	_beacon.light_energy = 18.0 * exp(-bp * 14.0)
	_taxi.visible = gear_down
	_rain_mat.set_shader_parameter(&"strobe", flash)
	_rain_mat.set_shader_parameter(&"taxi_on", 1.0 if gear_down else 0.0)
