class_name CockpitWindshield
extends Node3D
## Glass in the four window openings with the wet-windshield shader. The view
## feeds airspeed and how wet it is (cloud, drizzle) every frame.

const SHADER: Shader = preload("res://shaders/pilot_windshield.gdshader")

var material: ShaderMaterial


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	var panes: Array = [
		CockpitShell.FRONT_LEFT, CockpitShell.mirror(CockpitShell.FRONT_LEFT),
		CockpitShell.SIDE_LEFT, CockpitShell.mirror(CockpitShell.SIDE_LEFT)]
	for i in panes.size():
		var pts: Array[Vector3] = panes[i]
		var mi := MeshInstance3D.new()
		mi.name = "Pane%d" % i
		mi.mesh = _quad(pts)
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var w := (pts[0].distance_to(pts[1]) + pts[3].distance_to(pts[2])) * 0.5
		var h := (pts[0].distance_to(pts[3]) + pts[1].distance_to(pts[2])) * 0.5
		add_child(mi)
		mi.set_instance_shader_parameter(&"glass_size", Vector2(w, h))
		mi.set_instance_shader_parameter(&"glass_seed", float(i) * 3.7 + 1.0)


## Corners: bottom-outer, bottom-inner, top-inner, top-outer. UV x runs
## outer→inner, y bottom→top (the direction the airflow blows the water).
static func _quad(pts: Array[Vector3]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var n := (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized()
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uvs[idx])
		st.add_vertex(pts[idx])
	return st.commit()


func set_conditions(wetness: float, airspeed_kt: float) -> void:
	material.set_shader_parameter(&"rain", clampf(wetness, 0.0, 1.0))
	material.set_shader_parameter(&"airspeed", airspeed_kt)
