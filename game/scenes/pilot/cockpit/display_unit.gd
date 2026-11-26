class_name PilotDisplayUnit
extends Node3D
## A display unit on the panel: bezel, cover glass and a SubViewport that
## renders an instrument (1000 x 1000 logical units) at `resolution` pixels.
## The viewport only renders when this unit asks, `update_hz` times a second.
## Origin = centre of the glass, local +Z = towards the pilot.

const K := preload("res://scenes/pilot/cockpit/mesh_kit.gd")
const M := preload("res://scenes/pilot/cockpit/cockpit_materials.gd")
const SCREEN_SHADER: Shader = preload("res://shaders/pilot_screen.gdshader")

@export var screen_size := Vector2(0.205, 0.205)
@export var bezel_margin := 0.016
@export var update_hz := 30.0

var viewport: SubViewport
var instrument: PilotInstrumentPart
var material: ShaderMaterial
var screen: MeshInstance3D

var _acc := 0.0


func setup(inst: PilotInstrumentPart, resolution: int, seed_v: float) -> void:
	instrument = inst
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.disable_3d = true
	viewport.transparent_bg = false
	# 2D MSAA is not available in Compatibility (GLES3 / WebGL 2).
	viewport.msaa_2d = Viewport.MSAA_DISABLED if RenderCaps.is_compatibility() else Viewport.MSAA_4X
	viewport.size_2d_override_stretch = true
	viewport.size_2d_override = Vector2i(1000, int(1000.0 * screen_size.y / screen_size.x))
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	set_resolution(resolution)
	add_child(viewport)
	inst.size = Vector2(viewport.size_2d_override)
	viewport.add_child(inst)

	var bezel_size := Vector3(screen_size.x + bezel_margin * 2.0, screen_size.y + bezel_margin * 2.0, 0.03)
	K.add(self, K.rounded_box(bezel_size, 0.006), M.get_mat("bezel"), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.012)), "Bezel")
	# A thin dark gasket between bezel and glass gives the screen a recessed edge.
	K.add(self, K.rounded_box(Vector3(screen_size.x + 0.006, screen_size.y + 0.006, 0.004), 0.001), M.get_mat("black"),
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.002)), "Gasket")
	var quad := QuadMesh.new()
	quad.size = screen_size
	material = ShaderMaterial.new()
	material.shader = SCREEN_SHADER
	material.set_shader_parameter(&"screen_tex", viewport.get_texture())
	material.set_shader_parameter(&"smudge_seed", Vector2(seed_v, seed_v * 1.37 + 2.0))
	screen = K.add(self, quad, material, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0045)), "Screen")
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_resolution(px: int) -> void:
	if viewport != null:
		viewport.size = Vector2i(px, int(px * screen_size.y / screen_size.x))


func _process(delta: float) -> void:
	if instrument == null:
		return
	_acc += delta
	if _acc >= 1.0 / update_hz:
		_acc = 0.0
		instrument.refresh()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
