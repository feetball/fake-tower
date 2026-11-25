class_name PilotCloudBase
extends MultiMeshInstance3D
## Ragged scud under the cloud base along the final approach: a few hundred lit
## noise billboards (shaders/cloud_wisps.gdshader) in World coordinates, hung
## around the ceiling height so that breaking out the aircraft streams past
## them and the first approach lights show through the gaps. The whole layer
## moves with the ceiling (set_ceiling_ft). Put it under the world root.

const SHADER: Shader = preload("res://shaders/cloud_wisps.gdshader")
const SEED := 9017

@export var count := 420
## Along-track extent (nm east of the threshold) and half-width (nm).
@export var from_nm := 0.15
@export var to_nm := 4.5
@export var half_width_nm := 0.22

var material: ShaderMaterial


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	for i in count:
		var x := rng.randf_range(from_nm, to_nm)
		var y := rng.randf_range(-half_width_nm, half_width_nm) * (0.4 + 0.6 * rng.randf())
		# Mostly at and just above the base; a few ragged fragments hang lower.
		var dh := rng.randf_range(-15.0, 70.0) if rng.randf() < 0.8 else rng.randf_range(-75.0, -15.0)
		var p := World.to_3d(x, y, 0.0) + Vector3(0.0, dh * World.FT_TO_M, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
		var low := dh < -15.0
		mm.set_instance_custom_data(i, Color(rng.randf_range(35.0, 110.0) * (0.6 if low else 1.0),
			rng.randf(), rng.randf_range(0.35, 0.8) * (0.7 if low else 1.0), 0.0))
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 120.0
	material = ShaderMaterial.new()
	material.shader = SHADER
	material_override = material


## Height of the base, ft MSL.
func set_ceiling_ft(base_msl_ft: float) -> void:
	position.y = base_msl_ft * World.FT_TO_M
