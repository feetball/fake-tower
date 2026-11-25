class_name RunwaySurface
extends Node3D
## Wet asphalt runway with painted markings, in the runway frame (origin =
## threshold centre, landing direction −Z). Also lays the surrounding grass.
## Asphalt and paint use shaders/runway_surface.gdshader (rubber deposits,
## standing water, grazing backscatter so the landing lights pick them out);
## the asphalt texture is the CC0 set from res://assets when present.

const FT := 0.3048
const SURFACE_SHADER: Shader = preload("res://shaders/runway_surface.gdshader")
const PAINT := Color(0.72, 0.72, 0.7)

@export var length_m := 1.4 * 1852.0
@export var width_m := 45.0
@export var designator := "27"
@export var grass_size_m := 9000.0
## 0 = dry, 1 = soaked (lower roughness, more mirror-like streaks).
@export var wetness := 0.85


func _ready() -> void:
	build()


func build() -> void:
	for c in get_children():
		c.queue_free()
	_add_plane("Asphalt", Vector2(width_m + 7.0, length_m + 60.0), Vector3(0, 0.0, -length_m * 0.5), _asphalt_material(-length_m * 0.5))
	_add_plane("Grass", Vector2(grass_size_m, grass_size_m), Vector3(0, -0.05, -length_m * 0.5), _grass_material())
	_build_markings()


func _add_plane(n: String, size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _asphalt_material(origin_z: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter(&"origin_z", origin_z)
	m.set_shader_parameter(&"wetness", wetness)
	var base := "res://assets/textures/asphalt_runway/asphalt_runway"
	if ResourceLoader.exists(base + "_albedo_2k.jpg"):
		m.set_shader_parameter(&"albedo_tex", load(base + "_albedo_2k.jpg"))
		m.set_shader_parameter(&"normal_tex", load(base + "_normal_gl_2k.jpg"))
		m.set_shader_parameter(&"arm_tex", load(base + "_arm_2k.jpg"))
		m.set_shader_parameter(&"has_arm", true)
		m.set_shader_parameter(&"tint", Color(0.42, 0.42, 0.43))
	else:
		m.set_shader_parameter(&"tint", Color(0.07, 0.07, 0.072))
		m.set_shader_parameter(&"normal_tex", _noise_tex(0.05, 512, true))
		m.set_shader_parameter(&"tile_m", 20.0)
	return m


func _grass_material() -> StandardMaterial3D:
	var m := AssetLookup.pbr_material("grass_field", Vector2(grass_size_m, grass_size_m), 2.0)
	if m:
		m.albedo_color = Color(0.3, 0.32, 0.26)
	else:
		m = StandardMaterial3D.new()
		m.albedo_color = Color(0.035, 0.042, 0.03)
		m.roughness = 0.92
	return m


func _noise_tex(freq: float, size: int, normal: bool) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.as_normal_map = normal
	t.bump_strength = 4.0
	t.generate_mipmaps = true
	return t


func _paint_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter(&"paint", true)
	m.set_shader_parameter(&"tint", PAINT)
	m.set_shader_parameter(&"wetness", wetness)
	return m


func _build_markings() -> void:
	var rects: Array[Rect2] = [] # x = lateral, y = along (positive = down the runway)
	# Threshold "piano keys": 6 stripes each side of the centreline.
	var stripe_w := 1.8
	for side in [-1.0, 1.0]:
		for k in 6:
			var x: float = side * (3.0 + k * (stripe_w + 1.6) + stripe_w * 0.5)
			rects.append(Rect2(x - stripe_w * 0.5, 6.0, stripe_w, 30.0))
	# Centreline: 120 ft stripes, 80 ft gaps, starting after the designator.
	var y := 80.0
	while y < length_m - 60.0:
		rects.append(Rect2(-0.45, y, 0.9, 120.0 * FT))
		y += 200.0 * FT
	# Side stripes along both edges, the full length.
	for side in [-1.0, 1.0]:
		rects.append(Rect2(side * (width_m * 0.5 - 0.6) - 0.45, 0.0, 0.9, length_m))
	# Aiming point blocks at 1000 ft and touchdown zone pairs.
	for side in [-1.0, 1.0]:
		rects.append(Rect2(side * 9.0 - 4.5, 1000.0 * FT, 9.0, 45.0))
		for d in [500.0, 1500.0, 2000.0]:
			for k in 3 if d < 1000.0 else 2:
				rects.append(Rect2(side * (5.0 + k * 3.0) - 0.9, d * FT, 1.8, 22.5))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.02, 1.0)
	box.material = _paint_material()
	mm.mesh = box
	mm.instance_count = rects.size()
	for i in rects.size():
		var r := rects[i]
		var b := Basis.from_scale(Vector3(r.size.x, 1.0, r.size.y))
		mm.set_instance_transform(i, Transform3D(b, Vector3(r.position.x + r.size.x * 0.5, 0.005, -(r.position.y + r.size.y * 0.5))))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Markings"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var lbl := Label3D.new()
	lbl.name = "Designator"
	lbl.text = designator
	lbl.font_size = 512
	lbl.pixel_size = 0.04
	lbl.modulate = PAINT
	lbl.shaded = true
	lbl.double_sided = false
	lbl.outline_size = 0
	lbl.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	# Flat on the surface, readable from the approach (+Z side).
	lbl.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	lbl.position = Vector3(0.0, 0.03, -58.0)
	lbl.scale = Vector3(1.0, 2.2, 1.0)
	add_child(lbl)
