class_name CockpitLights
extends Node3D
## Night lighting of the flight deck: dim warm flood from under the glareshield
## lip onto the main panel, a pedestal flood, a faint dome light, and a cool
## spill from the displays. None of them scatter in the volumetric fog.

const L := preload("res://scenes/pilot/cockpit/cockpit_layout.gd")

@export var flood := 1.0


func _ready() -> void:
	var warm := Color(1.0, 0.82, 0.62)
	# Glareshield flood: two spots under the lip aimed down at the panel.
	for x: float in [0.05, L.CENTRE_X + 0.5]:
		_spot(Vector3(x, -0.385, -0.69), Vector3(x, -0.67, -0.8), warm, 1.4 * flood, 1.1, 80.0)
	# Pedestal flood from the overhead.
	_spot(Vector3(L.CENTRE_X, 0.32, -0.25), Vector3(L.CENTRE_X, -0.65, -0.3), warm, 0.9 * flood, 1.6, 50.0)
	# Glareshield/MCP: a soft light from the overhead onto the panel face.
	_spot(Vector3(0.3, 0.3, -0.25), Vector3(0.3, -0.3, -0.68), warm, 0.5 * flood, 1.4, 70.0)
	# Display spill: the screens are the brightest thing in here.
	_omni(Vector3(0.1, -0.47, -0.6), Color(0.55, 0.7, 1.0), 0.06, 0.7)
	_omni(Vector3(L.CENTRE_X, -0.47, -0.6), Color(0.6, 0.75, 1.0), 0.04, 0.6)
	# Dome: just enough to read shapes overhead and on the walls.
	_omni(Vector3(L.CENTRE_X, 0.3, 0.1), Color(0.9, 0.85, 0.8), 0.12, 2.5)


func _spot(at: Vector3, target: Vector3, col: Color, energy: float, rng: float, angle: float) -> void:
	var s := SpotLight3D.new()
	s.light_color = col
	s.light_energy = energy
	s.spot_range = rng
	s.spot_angle = angle * 0.5
	s.spot_attenuation = 1.2
	s.spot_angle_attenuation = 1.6
	s.light_volumetric_fog_energy = 0.0
	s.shadow_enabled = false
	s.light_specular = 0.3
	add_child(s)
	s.look_at_from_position(at, target, Vector3.UP if absf((target - at).normalized().y) < 0.95 else Vector3.FORWARD)


func _omni(at: Vector3, col: Color, energy: float, rng: float) -> void:
	var o := OmniLight3D.new()
	o.position = at
	o.light_color = col
	o.light_energy = energy
	o.omni_range = rng
	o.omni_attenuation = 1.5
	o.light_volumetric_fog_energy = 0.0
	o.shadow_enabled = false
	o.light_specular = 0.0
	add_child(o)
