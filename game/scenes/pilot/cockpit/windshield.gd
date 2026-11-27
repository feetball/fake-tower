class_name CockpitWindshield
extends Node3D
## Glass in the four window openings. The water on it is drawn by
## RainGlassEffect (a compositor pass on the pilot camera) when a
## RenderingDevice is available; otherwise the pane shader draws the older
## screen-texture drops. The panes always add a faint wet film, and the lit
## displays reflect faintly in the front panes. The view feeds airspeed and
## how wet it is (cloud, drizzle) every frame.
##
## The drops run with the airflow. How far it has carried water since the start
## (water_travel) is integrated here from the airspeed and handed to both
## drawing paths, so the drops speed up, slow down and stop with the aircraft.

const SHADER: Shader = preload("res://shaders/pilot_windshield.gdshader")
const REFLECTION_SHADER: Shader = preload("res://shaders/pilot_glass_reflection.gdshader")
## The airflow's pull on water on the glass is its dynamic pressure, which goes with
## IAS squared: FLOW_REF_MPS metres of glass per second at FLOW_REF_KT (a reference
## drop; the shaders run bigger and smaller drops faster and slower). Below the
## pinning share of that pressure the drops hold where they are.
const FLOW_REF_KT := 140.0
const FLOW_REF_MPS := 0.45
const FLOW_PIN := 0.06

var material: ShaderMaterial
## Null where compute effects are unavailable.
var effect: RainGlassEffect
## Metres of glass the airflow has carried a reference drop so far (see flow_speed).
var water_travel := 0.0
var _t := 0.0
var _ias := 0.0


## How fast the airflow carries a reference drop over the glass (m/s) at this indicated airspeed.
static func flow_speed(ias_kt: float) -> float:
	var q := ias_kt * ias_kt / (FLOW_REF_KT * FLOW_REF_KT)
	return FLOW_REF_MPS * maxf(q - FLOW_PIN, 0.0)


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
	if RainGlassEffect.is_supported():
		effect = RainGlassEffect.new()
	material.set_shader_parameter(&"drops", effect == null)


## Put the water pass on the camera that looks through this glass.
func attach(camera: Camera3D) -> void:
	if effect == null:
		return
	var comp := Compositor.new()
	comp.compositor_effects = [effect]
	camera.compositor = comp


## Keep the drops fixed to the glass: they live in the aircraft frame.
func update_view(aircraft_basis: Basis, delta: float) -> void:
	_t += delta
	water_travel += flow_speed(_ias) * delta
	material.set_shader_parameter(&"water_travel", water_travel)
	if effect != null:
		effect.aircraft_basis = aircraft_basis
		effect.time_s = _t
		effect.water_travel = water_travel


## Virtual images of the displays in the front pane on their side: each
## display's picture on a quad mirrored across that pane's plane.
func add_display_reflections(units: Array) -> void:
	for u: PilotDisplayUnit in units:
		if u == null or u.screen == null:
			continue
		var pts: Array[Vector3] = CockpitShell.FRONT_LEFT
		if u.position.x > CockpitShell.C + 0.1:
			pts = CockpitShell.mirror(CockpitShell.FRONT_LEFT)
		var n := (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized()
		var o: Vector3 = pts[0]
		var r := Basis(Vector3.RIGHT - 2.0 * n.x * n, Vector3.UP - 2.0 * n.y * n, Vector3.BACK - 2.0 * n.z * n)
		var xf := get_global_transform().affine_inverse() * u.screen.global_transform
		var p := xf.origin - 2.0 * (xf.origin - o).dot(n) * n
		var mi := MeshInstance3D.new()
		mi.name = "Reflection" + u.name
		mi.mesh = u.screen.mesh
		var m := ShaderMaterial.new()
		m.shader = REFLECTION_SHADER
		m.set_shader_parameter(&"screen_tex", u.viewport.get_texture())
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(r * xf.basis, p)
		add_child(mi)


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
	_ias = airspeed_kt
	material.set_shader_parameter(&"rain", clampf(wetness, 0.0, 1.0))
	material.set_shader_parameter(&"airspeed", airspeed_kt)
	if effect != null:
		effect.rain = clampf(wetness, 0.0, 1.0)
		effect.airspeed_kt = airspeed_kt
