class_name AirportBeacon
extends Node3D
## Rotating civil aerodrome beacon: alternating green and white beams 180°
## apart, sweeping through volumetric fog. Origin = lamp centre.

@export var rpm := 12.0
@export var elevation_deg := 4.0
@export var beam_range_m := 3500.0
@export var beam_energy := 120.0
## Volumetric-fog energy of the real SpotLights. Kept low: froxels are too coarse
## for a 4° beam, the visible shaft is the additive cone.
@export var fog_energy := 0.0
@export var spot_angle_deg := 3.5
@export var extinction_per_m := 0.0025
@export var shaft_length_m := 900.0
@export var shaft_intensity := 0.12

const BEAM_SHADER: Shader = preload("res://shaders/light_beam.gdshader")

const GREEN := Color(0.35, 1.0, 0.6)
const WHITE := Color(1.0, 0.95, 0.85)

var _pivot: Node3D


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_beam(GREEN, 0.0)
	_beam(WHITE, PI)
	_pivot.rotation.y = randf() * TAU


func _process(delta: float) -> void:
	_pivot.rotation.y = wrapf(_pivot.rotation.y + delta * rpm / 60.0 * TAU, 0.0, TAU)


## Visible beam: a long additive cone pointing along the head's −Z.
func _shaft(col: Color) -> MeshInstance3D:
	var cone := CylinderMesh.new()
	cone.height = shaft_length_m
	cone.top_radius = 0.4
	cone.bottom_radius = tan(deg_to_rad(spot_angle_deg)) * shaft_length_m
	cone.radial_segments = 24
	cone.rings = 8
	cone.cap_top = false
	cone.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	mat.set_shader_parameter(&"beam_color", col)
	mat.set_shader_parameter(&"intensity", shaft_intensity)
	mat.set_shader_parameter(&"length_m", shaft_length_m)
	mat.set_shader_parameter(&"extinction_per_m", extinction_per_m * 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "Shaft"
	mi.mesh = cone
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.x = PI * 0.5
	mi.position.z = -shaft_length_m * 0.5
	return mi


func _beam(col: Color, yaw: float) -> void:
	var head := Node3D.new()
	head.rotation = Vector3(deg_to_rad(elevation_deg), yaw, 0.0)
	_pivot.add_child(head)
	var spot := SpotLight3D.new()
	spot.light_color = col
	spot.light_energy = beam_energy
	spot.spot_range = beam_range_m
	spot.spot_angle = spot_angle_deg
	spot.spot_angle_attenuation = 0.6
	spot.spot_attenuation = 0.6
	spot.light_volumetric_fog_energy = fog_energy
	spot.light_specular = 0.2
	spot.shadow_enabled = false
	head.add_child(spot)
	head.add_child(_shaft(col))
	# The lamp itself: blinding when the beam faces you, a faint glow otherwise.
	var lamp := LightPoints.new()
	lamp.beam_dir = Vector3(0.0, 0.0, -1.0)
	lamp.beam_power = 90.0
	lamp.beam_min = 0.015
	lamp.halo_size_m = 30.0
	lamp.halo_gain = 0.35
	lamp.extinction_per_m = extinction_per_m
	head.add_child(lamp)
	lamp.add_point(Vector3(0.0, 0.0, -0.4), col, 60.0, 0.9)
	lamp.commit()
