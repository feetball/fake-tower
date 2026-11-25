class_name LightPoints
extends MultiMeshInstance3D
## A set of airfield light points (lamp core + fog halo) drawn in one call.
## Usage: add_point(...) as often as needed, then commit(). Strobes run in the
## shader, so there is no per-frame CPU cost. Positions are in this node's space.

const SHADER: Shader = preload("res://shaders/light_point.gdshader")

## Local direction the lamps shine towards; zero = omnidirectional.
@export var beam_dir := Vector3.ZERO
## Higher = narrower beam (cos^power falloff).
@export var beam_power := 2.0
## Fraction of intensity seen from behind / outside the beam.
@export var beam_min := 0.05
## Atmospheric extinction applied to the lamps (≈ 3 / visibility in metres).
@export var extinction_per_m := 0.0025
@export var halo_size_m := 9.0
@export var halo_gain := 0.18
@export var intensity_scale := 1.0

var _pos: PackedVector3Array = []
var _col: PackedColorArray = []
var _custom: PackedColorArray = []
var _material: ShaderMaterial


func add_point(pos: Vector3, color: Color, intensity: float = 4.0, core_m: float = 0.35,
		flash_period: float = 0.0, flash_phase: float = 0.0) -> void:
	_pos.append(pos)
	_col.append(color)
	_custom.append(Color(core_m, flash_period, flash_phase, intensity))


func clear_points() -> void:
	_pos.clear()
	_col.clear()
	_custom.clear()


func point_count() -> int:
	return _pos.size()


func commit() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = _pos.size()
	for i in _pos.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _pos[i]))
		mm.set_instance_color(i, _col[i])
		mm.set_instance_custom_data(i, _custom[i])
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Billboards extend beyond the instance AABB; keep them from being culled early.
	extra_cull_margin = 40.0
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	material_override = _material
	apply_uniforms()


## Re-apply exported parameters to the shader (call after changing them at runtime).
func apply_uniforms() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"beam_dir", beam_dir)
	_material.set_shader_parameter(&"beam_power", beam_power)
	_material.set_shader_parameter(&"beam_min", beam_min)
	_material.set_shader_parameter(&"extinction_per_m", extinction_per_m)
	_material.set_shader_parameter(&"halo_size_m", halo_size_m)
	_material.set_shader_parameter(&"halo_gain", halo_gain)
	_material.set_shader_parameter(&"intensity_scale", intensity_scale)
