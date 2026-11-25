extends Node3D
## The two flat panels of our position, coplanar so that a camera looking
## straight at them sees both as axis-aligned rectangles: the main radar
## display (5:4) and the narrow flight-data display to its right. Local frame:
## origin = centre of the main screen, +X right, +Y up, +Z toward the operator.

const Kit := preload("res://scenes/controller/room/mesh_kit.gd")
const DISPLAY_SHADER: Shader = preload("res://shaders/controller_display.gdshader")

const MAIN := Vector2(0.66, 0.528) ## active area, metres
const SIDE := Vector2(0.30, 0.528)
const GAP := 0.052 ## between the two active areas
const BORDER := 0.022 ## bezel width around an active area
const DEPTH := 0.05

var main_screen: MeshInstance3D
var side_screen: MeshInstance3D
var main_material: ShaderMaterial
var side_material: ShaderMaterial
var main_light: SpotLight3D
var side_light: OmniLight3D


func _ready() -> void:
	var bezel := Kit.mat(Color(0.045, 0.048, 0.052), 0.55, 0.15)
	var inner := Kit.mat(Color(0.008, 0.009, 0.01), 0.18, 0.0)
	main_material = _screen_material(MAIN, 0.0)
	side_material = _screen_material(SIDE, 7.0)
	main_screen = _panel(Vector3.ZERO, MAIN, bezel, inner, main_material, "RDR-1")
	side_screen = _panel(Vector3(side_center_x(), 0.0, 0.0), SIDE, bezel, inner, side_material, "FDD-1")
	# Spine joining the two panels at the back.
	Kit.box(self, Vector3(GAP + 0.1, 0.12, 0.05), Vector3(MAIN.x * 0.5 + GAP * 0.5, 0.0, -0.075), bezel, 0.006)

	main_light = SpotLight3D.new()
	main_light.name = "ScopeLight"
	main_light.light_color = Color(0.55, 0.95, 0.72)
	main_light.light_energy = 0.55
	main_light.spot_range = 2.6
	main_light.spot_angle = 72.0
	main_light.spot_attenuation = 1.4
	main_light.light_volumetric_fog_energy = 0.4
	main_light.light_specular = 0.25
	main_light.position = Vector3(0.0, 0.0, 0.06)
	add_child(main_light)
	side_light = OmniLight3D.new()
	side_light.name = "FddLight"
	side_light.light_color = Color(0.7, 0.8, 0.95)
	side_light.light_energy = 0.12
	side_light.omni_range = 1.2
	side_light.light_specular = 0.1
	side_light.position = Vector3(side_center_x(), 0.0, 0.12)
	add_child(side_light)


func side_center_x() -> float:
	return MAIN.x * 0.5 + GAP + SIDE.x * 0.5


## Both active areas in local metres (x right, y up).
func main_rect() -> Rect2:
	return Rect2(-MAIN.x * 0.5, -MAIN.y * 0.5, MAIN.x, MAIN.y)


func side_rect() -> Rect2:
	return Rect2(side_center_x() - SIDE.x * 0.5, -SIDE.y * 0.5, SIDE.x, SIDE.y)


func bounds() -> Rect2:
	return main_rect().merge(side_rect())


func set_textures(main_tex: Texture2D, side_tex: Texture2D) -> void:
	main_material.set_shader_parameter("screen_tex", main_tex)
	side_material.set_shader_parameter("screen_tex", side_tex)


func _screen_material(sz: Vector2, seed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DISPLAY_SHADER
	m.set_shader_parameter("aspect", Vector2(sz.x / sz.y, 1.0))
	m.set_shader_parameter("seed", seed)
	return m


func _panel(centre: Vector3, active: Vector2, bezel: Material, inner: Material, screen_mat: Material, tag: String) -> MeshInstance3D:
	var outer := Vector3(active.x + BORDER * 2.0, active.y + BORDER * 2.0 + 0.018, DEPTH)
	Kit.box(self, outer, centre + Vector3(0.0, -0.009, -DEPTH * 0.5 - 0.001), bezel, 0.007)
	# Black glass margin inside the bezel.
	var margin := QuadMesh.new()
	margin.size = active + Vector2(0.012, 0.012)
	var mm := MeshInstance3D.new()
	mm.mesh = margin
	mm.material_override = inner
	mm.position = centre + Vector3(0.0, 0.0, -0.0006)
	add_child(mm)
	var q := QuadMesh.new()
	q.size = active
	var mi := MeshInstance3D.new()
	mi.name = tag
	mi.mesh = q
	mi.material_override = screen_mat
	mi.position = centre
	add_child(mi)
	# Power LED and a faint model plate on the chin.
	var chin_y := -active.y * 0.5 - BORDER - 0.006
	Kit.box(self, Vector3(0.004, 0.002, 0.002), centre + Vector3(active.x * 0.5 - 0.01, chin_y, 0.0),
		Kit.mat(Color(0.1, 0.4, 0.15), 0.4, 0.0, Color(0.2, 1.0, 0.35), 2.5), 0.0)
	Kit.label(self, tag, centre + Vector3(-active.x * 0.5 + 0.03, chin_y, 0.0005), 32, Color(0.35, 0.37, 0.4),
		0.00022, null, Vector3.ZERO, false)
	# Rear housing taper.
	Kit.box(self, Vector3(active.x * 0.7, active.y * 0.6, 0.06), centre + Vector3(0.0, 0.0, -DEPTH - 0.03),
		bezel, 0.02)
	return mi
