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
@export var halo_size_m := 3.0
@export var halo_gain := 0.08
@export var intensity_scale := 1.0
## Also draw wet-pavement reflections (mirrored streaks below this node's y = 0).
@export var reflections := false
@export var reflection_gain := 0.3
## Minimum apparent halo size (radians) so distant lights keep a soft glow.
@export var min_halo_angle := 0.03
## Minimum apparent core size (radians) so distant lights never alias away.
@export var min_core_angle := 0.0022
## Dimming exponent for lamps smaller than min_core_angle (2 = inverse square,
## 0 = every lamp equally bright whatever its distance).
@export var point_falloff := 0.0
## Fog aureole (forward scattering) strength and angular radius at optical depth 1.
@export var aureole_gain := 0.0
@export var aureole_angle := 0.018
## PAPI boxes: the colour comes from the eye's elevation angle seen from each
## box; add_papi_box() stores the box's setting angle.
@export var papi := false

var _pos: PackedVector3Array = []
var _col: PackedColorArray = []
var _custom: PackedColorArray = []
var _material: ShaderMaterial
var _refl_material: ShaderMaterial
var _refl: MultiMeshInstance3D


func add_point(pos: Vector3, color: Color, intensity: float = 4.0, core_m: float = 0.35,
		flash_period: float = 0.0, flash_phase: float = 0.0) -> void:
	_pos.append(pos)
	_col.append(color)
	_custom.append(Color(core_m, flash_period, flash_phase, intensity))


## One PAPI light unit (needs `papi`): white when the eye is above setting_deg, red below.
func add_papi_box(pos: Vector3, setting_deg: float, intensity: float = 6.0, core_m: float = 0.4) -> void:
	add_point(pos, Color(1.0, 1.0, 1.0, setting_deg / 10.0), intensity, core_m)


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
	if reflections:
		if _refl == null:
			_refl = MultiMeshInstance3D.new()
			_refl.name = "Reflections"
			_refl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_refl.extra_cull_margin = 80.0
			_refl_material = ShaderMaterial.new()
			_refl_material.shader = SHADER
			_refl.material_override = _refl_material
			add_child(_refl)
		_refl.multimesh = mm
	set_notify_transform(true)
	apply_uniforms()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_sync_reflection_transform()


func _sync_reflection_transform() -> void:
	if _refl == null or not is_inside_tree():
		return
	_refl_material.set_shader_parameter(&"ground_y", global_position.y)


## Re-apply exported parameters to the shader (call after changing them at runtime).
func apply_uniforms() -> void:
	if _material == null:
		return
	for m: ShaderMaterial in [_material, _refl_material]:
		if m != null:
			_apply_to(m)
	if _refl_material != null:
		_refl_material.set_shader_parameter(&"reflection", true)
		_refl_material.set_shader_parameter(&"reflection_gain", reflection_gain)
		# Mirrored streaks are not fog aureoles.
		_refl_material.set_shader_parameter(&"aureole_gain", 0.0)
		_sync_reflection_transform()


func _apply_to(m: ShaderMaterial) -> void:
	if m == null:
		return
	m.set_shader_parameter(&"beam_dir", beam_dir)
	m.set_shader_parameter(&"beam_power", beam_power)
	m.set_shader_parameter(&"beam_min", beam_min)
	m.set_shader_parameter(&"extinction_per_m", extinction_per_m)
	m.set_shader_parameter(&"halo_size_m", halo_size_m)
	m.set_shader_parameter(&"halo_gain", halo_gain)
	m.set_shader_parameter(&"intensity_scale", intensity_scale)
	m.set_shader_parameter(&"min_halo_angle", min_halo_angle)
	m.set_shader_parameter(&"min_core_angle", min_core_angle)
	m.set_shader_parameter(&"point_falloff", point_falloff)
	m.set_shader_parameter(&"aureole_gain", aureole_gain)
	m.set_shader_parameter(&"aureole_angle", aureole_angle)
	m.set_shader_parameter(&"papi", papi)
