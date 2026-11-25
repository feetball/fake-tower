extends RefCounted
## Procedural building blocks for the radar room: chamfered boxes, materials,
## CC0 model instancing.

static var _mats: Dictionary = {}
static var _box_cache: Dictionary = {}


## Box centred on the origin with all edges chamfered by `c` metres.
static func chamfer_box(size: Vector3, c: float) -> ArrayMesh:
	var key := "%s|%s" % [size, c]
	if _box_cache.has(key):
		return _box_cache[key]
	var h := size * 0.5
	c = minf(c, minf(h.x, minf(h.y, h.z)) * 0.95)
	# Per corner: points on its X, Y and Z faces.
	var corner := func(s: Vector3i, axis: int) -> Vector3:
		var p := Vector3(s.x * (h.x - c), s.y * (h.y - c), s.z * (h.z - c))
		p[axis] = s[axis] * h[axis]
		return p
	var polys: Array[PackedVector3Array] = []
	# 6 faces
	for axis in 3:
		for sgn: int in [-1, 1]:
			var poly := PackedVector3Array()
			for a: int in [-1, 1]:
				for b: int in ([-1, 1] if a < 0 else [1, -1]):
					var s := Vector3i.ZERO
					s[axis] = sgn
					s[(axis + 1) % 3] = a
					s[(axis + 2) % 3] = b
					poly.append(corner.call(s, axis))
			polys.append(poly)
	# 12 edge chamfers (between faces of axes i and j, running along axis k)
	for i in 3:
		var j := (i + 1) % 3
		var k := (i + 2) % 3
		for si: int in [-1, 1]:
			for sj: int in [-1, 1]:
				var poly := PackedVector3Array()
				for sk: int in [-1, 1]:
					var s := Vector3i.ZERO
					s[i] = si
					s[j] = sj
					s[k] = sk
					poly.append(corner.call(s, i))
				for sk: int in [1, -1]:
					var s := Vector3i.ZERO
					s[i] = si
					s[j] = sj
					s[k] = sk
					poly.append(corner.call(s, j))
				polys.append(poly)
	# 8 corner triangles
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var s := Vector3i(sx, sy, sz)
				polys.append(PackedVector3Array([corner.call(s, 0), corner.call(s, 1), corner.call(s, 2)]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for poly in polys:
		var centre := Vector3.ZERO
		for p in poly:
			centre += p
		centre /= poly.size()
		var n := (poly[1] - poly[0]).cross(poly[2] - poly[0]).normalized()
		if n.dot(centre) < 0.0:
			poly.reverse()
			n = -n
		for t in range(1, poly.size() - 1):
			# Godot front faces wind clockwise seen from the front.
			for p: Vector3 in [poly[0], poly[t + 1], poly[t]]:
				st.set_normal(n)
				st.set_uv(_box_uv(p, n))
				st.add_vertex(p)
	st.generate_tangents()
	var mesh := st.commit()
	_box_cache[key] = mesh
	return mesh


static func _box_uv(p: Vector3, n: Vector3) -> Vector2:
	var a := n.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector2(p.z, -p.y)
	if a.y >= a.z:
		return Vector2(p.x, p.z)
	return Vector2(p.x, -p.y)


static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, chamfer: float = 0.004,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = chamfer_box(size, chamfer) if chamfer > 0.0 else _plain_box(size)
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _plain_box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cylinder(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, mat: Material,
		rot: Vector3 = Vector3.ZERO, segments: int = 24) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segments
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## Plain PBR material, cached by its parameters.
static func mat(albedo: Color, roughness: float = 0.7, metallic: float = 0.0, emission: Color = Color.BLACK,
		emission_energy: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [albedo, roughness, metallic, emission, emission_energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = metallic
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_mats[key] = m
	return m


## Triplanar PBR material from res://assets/textures/<set>/ (falls back to a flat colour).
static func pbr(set_name: String, tile_m: float, tint: Color, roughness_scale: float = 1.0) -> StandardMaterial3D:
	var key := "pbr|%s|%s|%s|%s" % [set_name, tile_m, tint, roughness_scale]
	if _mats.has(key):
		return _mats[key]
	var base := "res://assets/textures/%s/%s" % [set_name, set_name]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	if ResourceLoader.exists(base + "_albedo_2k.jpg"):
		m.albedo_texture = load(base + "_albedo_2k.jpg") as Texture2D
		m.normal_enabled = true
		m.normal_texture = load(base + "_normal_gl_2k.jpg") as Texture2D
		var arm := load(base + "_arm_2k.jpg") as Texture2D
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = arm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.roughness = roughness_scale
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / tile_m
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		m.roughness = 0.7
	_mats[key] = m
	return m


## Instances res://assets/models/<name>/<name>.gltf, or returns null if missing.
static func model(parent: Node3D, model_name: String, pos: Vector3, rot_y_deg: float = 0.0, scale: float = 1.0) -> Node3D:
	var path := "res://assets/models/%s/%s.gltf" % [model_name, model_name]
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.position = pos
	n.rotation.y = deg_to_rad(rot_y_deg)
	n.scale = Vector3.ONE * scale
	parent.add_child(n)
	return n


static func label(parent: Node3D, text: String, pos: Vector3, px: int, col: Color, pixel_m: float,
		font: Font = null, rot: Vector3 = Vector3.ZERO, emissive: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = px
	l.pixel_size = pixel_m
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.rotation = rot
	l.shaded = not emissive
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if font != null:
		l.font = font
	parent.add_child(l)
	return l
