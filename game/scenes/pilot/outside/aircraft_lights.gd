class_name PilotAircraftLights
extends Node3D
## The aircraft's own exterior lights, in the aircraft frame (eye = origin):
## wing-root landing lights and the nose taxi light (they light the cloud,
## then the runway), double-flash white wingtip strobes and the red beacon
## (they flash the cloud around the aircraft), steady nav lights. Real lights
## with volumetric-fog contribution; no shadows.

const C := 0.53
const SPOT_FOG := 1.6

@export var volumetric := true

var _landing: Array[SpotLight3D] = []
var _taxi: SpotLight3D
var _strobes: Array[OmniLight3D] = []
var _beacon: OmniLight3D
var _t := 0.0
var gear_down := true


func _ready() -> void:
	for side: float in [-1.0, 1.0]:
		var s := _spot(Vector3(C + side * 4.2, -2.9, 9.5), Color(1.0, 0.96, 0.9), 55.0, 900.0, 8.5)
		s.rotation = Vector3(deg_to_rad(-10.0), deg_to_rad(-side * 1.5), 0.0)
		_landing.append(s)
	_taxi = _spot(Vector3(C, -3.6, -1.0), Color(1.0, 0.95, 0.88), 12.0, 250.0, 16.0)
	_taxi.rotation = Vector3(deg_to_rad(-9.0), 0.0, 0.0)
	for side: float in [-1.0, 1.0]:
		var st := _omni(Vector3(C + side * 17.0, -2.2, 13.5), Color(0.9, 0.95, 1.0), 70.0)
		_strobes.append(st)
		_omni(Vector3(C + side * 16.8, -2.2, 13.0), Color(1.0, 0.1, 0.05) if side < 0.0 else Color(0.1, 1.0, 0.3), 14.0).light_energy = 1.2
	_beacon = _omni(Vector3(C, 0.9, 14.0), Color(1.0, 0.08, 0.03), 45.0)


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


func set_volumetric(on: bool) -> void:
	volumetric = on
	for c in get_children():
		if c is Light3D:
			(c as Light3D).light_volumetric_fog_energy = (SPOT_FOG if c is SpotLight3D else 3.0) if on else 0.0


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
