class_name PilotMeshKit
extends RefCounted
## Procedural mesh helpers for the cockpit: rounded (bevelled) boxes, extruded
## profiles with smoothed curves, slabs between arbitrary corners. Sizes in metres.
## Every triangle goes through _tri(), which orders it to face along its normal
## (Godot treats clockwise winding as the front face).

const _ROUND_STEPS: Array[float] = [0.0, 0.38, 0.71, 0.92, 1.0]


## A box with rounded edges of radius r and smooth normals across the bevels.
static func rounded_box(size: Vector3, r: float) -> ArrayMesh:
	var h := size * 0.5
	r = clampf(r, 0.0005, minf(h.x, minf(h.y, h.z)) * 0.98)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var coords: Array[PackedFloat32Array] = [_axis_coords(h.x, r), _axis_coords(h.y, r), _axis_coords(h.z, r)]
	var inner_h := h - Vector3(r, r, r)
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var ua := (axis + 1) % 3
			var va := (axis + 2) % 3
			var uc := coords[ua]
			var vc := coords[va]
			for i in uc.size() - 1:
				for j in vc.size() - 1:
					var pts: Array[Vector3] = []
					var nrm: Array[Vector3] = []
					for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
						var v := Vector3.ZERO
						v[axis] = h[axis] * sgn
						v[ua] = uc[i + k.x]
						v[va] = vc[j + k.y]
						var inner := v.clamp(-inner_h, inner_h)
						var n := (v - inner).normalized()
						pts.append(inner + n * r)
						nrm.append(n)
					_tri(st, pts[0], pts[1], pts[2], nrm[0], nrm[1], nrm[2])
					_tri(st, pts[0], pts[2], pts[3], nrm[0], nrm[2], nrm[3])
	st.generate_tangents()
	return st.commit()


static func _axis_coords(h: float, r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var inner := h - r
	for s in _ROUND_STEPS:
		out.append(-inner - r * cos(s * PI * 0.5))
	for k in range(_ROUND_STEPS.size() - 1, -1, -1):
		out.append(inner + r * cos(_ROUND_STEPS[k] * PI * 0.5))
	var dedup := PackedFloat32Array()
	for v in out:
		if dedup.is_empty() or absf(v - dedup[dedup.size() - 1]) > 1e-6:
			dedup.append(v)
	return dedup


## Extrude a closed 2D profile given as Vector2(z, y) along X from x0 to x1.
## Neighbouring edges meeting at less than `smooth_deg` share normals.
static func extrude_x(profile: PackedVector2Array, x0: float, x1: float, smooth_deg: float = 35.0, caps: bool = true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pr := profile.duplicate()
	var n := pr.size()
	var area := 0.0
	for i in n:
		var a := pr[i]
		var b := pr[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		pr.reverse()
	var centroid := Vector2.ZERO
	for p in pr:
		centroid += p
	centroid /= n
	var edge_n: Array[Vector3] = []
	for i in n:
		var d := (pr[(i + 1) % n] - pr[i]).normalized()
		# CCW polygon in (z, y): outward normal is (d.y, -d.x) in (z, y).
		edge_n.append(Vector3(0.0, -d.x, d.y).normalized())
	var cos_lim := cos(deg_to_rad(smooth_deg))
	for i in n:
		var a := pr[i]
		var b := pr[(i + 1) % n]
		var en := edge_n[i]
		var pn := edge_n[(i - 1 + n) % n]
		var nn := edge_n[(i + 1) % n]
		var na := (en + pn).normalized() if en.dot(pn) > cos_lim else en
		var nb := (en + nn).normalized() if en.dot(nn) > cos_lim else en
		var pa0 := Vector3(x0, a.y, a.x)
		var pa1 := Vector3(x1, a.y, a.x)
		var pb0 := Vector3(x0, b.y, b.x)
		var pb1 := Vector3(x1, b.y, b.x)
		_tri(st, pa0, pb0, pb1, na, nb, nb)
		_tri(st, pa0, pb1, pa1, na, nb, na)
	if caps:
		var tris := Geometry2D.triangulate_polygon(pr)
		for side in 2:
			var x := x0 if side == 0 else x1
			var cn := Vector3(-1.0 if side == 0 else 1.0, 0.0, 0.0)
			for t in range(0, tris.size(), 3):
				var p0 := pr[tris[t]]
				var p1 := pr[tris[t + 1]]
				var p2 := pr[tris[t + 2]]
				_tri(st, Vector3(x, p0.y, p0.x), Vector3(x, p1.y, p1.x), Vector3(x, p2.y, p2.x), cn, cn, cn)
	st.generate_tangents()
	return st.commit()


## Points along a quadratic Bezier from a to c with control b (inclusive).
static func bezier(a: Vector2, b: Vector2, c: Vector2, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out


## A slab whose front face spans the corners a, b, c, d (in order around the
## face), pushed back by thickness t against the front normal `facing`.
static func slab(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float, facing: Vector3) -> ArrayMesh:
	var n := (b - a).cross(d - a).normalized()
	if n.dot(facing) < 0.0:
		n = -n
	var back := -n * t
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var f: Array[Vector3] = [a, b, c, d]
	var r: Array[Vector3] = [a + back, b + back, c + back, d + back]
	var centre := (a + b + c + d) * 0.25 + back * 0.5
	_quad(st, f[0], f[1], f[2], f[3], n)
	_quad(st, r[0], r[1], r[2], r[3], -n)
	for i in 4:
		var j := (i + 1) % 4
		var mid := (f[i] + f[j]) * 0.5 + back * 0.5
		var en := (f[j] - f[i]).cross(back).normalized()
		if en.dot(mid - centre) < 0.0:
			en = -en
		_quad(st, f[i], r[i], r[j], f[j], en)
	st.generate_tangents()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n, n, n)
	_tri(st, a, c, d, n, n, n)


## Emit one triangle ordered so its front face points along the vertex normals.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var geo := (b - a).cross(c - a)
	if geo.dot(na + nb + nc) > 0.0:
		var tp := b
		b = c
		c = tp
		var tn := nb
		nb = nc
		nc = tn
	for k in 3:
		var p: Vector3 = [a, b, c][k]
		var nn: Vector3 = [na, nb, nc][k]
		st.set_normal(nn)
		st.set_uv(Vector2(p.x + p.z * 0.7, p.y + p.z * 0.3))
		st.add_vertex(p)


## A MeshInstance3D for `mesh` with `mat`, added to `parent` at `xf`.
static func add(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D = Transform3D.IDENTITY, node_name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if node_name != "":
		mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	parent.add_child(mi)
	return mi


## Transform whose local Z axis runs from a to b, positioned at their midpoint.
static func between(a: Vector3, b: Vector3, up_hint: Vector3 = Vector3.UP) -> Transform3D:
	var z := (b - a).normalized()
	var x := up_hint.cross(z).normalized()
	if x.length() < 0.01:
		x = Vector3.RIGHT
	var y := z.cross(x).normalized()
	return Transform3D(Basis(x, y, z), (a + b) * 0.5)


static func cylinder(radius: float, height: float, segs: int = 24, top_radius: float = -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top_radius < 0.0 else top_radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return c


## MultiMesh of `mesh` at `xfs`, as a MultiMeshInstance3D under parent.
static func multi(parent: Node3D, mesh: Mesh, mat: Material, xfs: Array[Transform3D], node_name: String = "") -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	if node_name != "":
		mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi
