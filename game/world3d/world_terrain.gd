class_name WorldTerrain
extends Node3D
## The four mountains of World.DATA as dark rock masses at their true positions
## and elevations, plus the flat land around the field and red obstruction
## lights on the summits. Children are in World (sim) coordinates: put this node
## under whatever root carries the world (it can be translated for a floating
## origin). The sim treats each mountain as a cylinder of radius_nm up to
## elev_ft; the visual mass stays at ≥ 85 % of that height inside the radius so
## the menace on screen matches the rule.

const RINGS := 26
const SEGMENTS := 64

@export var ground_size_m := 170000.0
@export var with_ground := true

## LightPoints per mountain, with the summit height in ft MSL (for fog fading).
var summit_lights: Array[LightPoints] = []
var summit_heights_ft: Array[float] = []


func _ready() -> void:
	var field := float(World.DATA["field_elev_ft"])
	var rock := _rock_material()
	var i := 0
	for m: Dictionary in World.DATA["terrain"]:
		var node := MeshInstance3D.new()
		node.name = String(m["name"]).replace(" ", "")
		node.mesh = _mountain_mesh(float(m["radius_nm"]) * World.NM_TO_M,
			(float(m["elev_ft"]) - field) * World.FT_TO_M, 9137 + i * 31)
		node.material_override = rock
		node.position = World.to_3d(float(m["x"]), float(m["y"]), field)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_summit_lights(node, (float(m["elev_ft"]) - field) * World.FT_TO_M, float(m["elev_ft"]))
		i += 1
	if with_ground:
		var ground := MeshInstance3D.new()
		ground.name = "Land"
		var pm := PlaneMesh.new()
		pm.size = Vector2(ground_size_m, ground_size_m)
		ground.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.03, 0.035, 0.028)
		gm.roughness = 0.95
		ground.material_override = gm
		# A little below the airport's own grass so the two never z-fight.
		ground.position = World.to_3d(0.0, 0.0, field) + Vector3(0.0, -0.4, 0.0)
		add_child(ground)


func _rock_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var base := "res://assets/textures/rock_cliff/rock_cliff"
	m.albedo_color = Color(0.13, 0.13, 0.125)
	m.roughness = 0.95
	if ResourceLoader.exists(base + "_albedo_2k.jpg"):
		m.albedo_texture = load(base + "_albedo_2k.jpg") as Texture2D
		m.normal_enabled = true
		m.normal_texture = load(base + "_normal_gl_2k.jpg") as Texture2D
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3(1.0, 1.0, 1.0) / 60.0
	return m


## A radial grid: summit plateau, flanks falling to the plain, noise on top.
func _mountain_mesh(radius_m: float, height_m: float, seed_v: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.6 / radius_m
	noise.fractal_octaves = 4
	var outer := radius_m * 2.2
	var verts := PackedVector3Array()
	for r in RINGS + 1:
		var t := float(r) / RINGS
		var d := outer * t * t * 0.6 + outer * t * 0.4
		for s in SEGMENTS:
			var a := TAU * s / SEGMENTS
			var p := Vector2(cos(a), sin(a)) * d
			var rel := d / radius_m
			var shape := 1.0 - _smooth(0.7, 2.05, rel)
			var n := noise.get_noise_2d(p.x, p.y)
			var ridge := 1.0 - absf(noise.get_noise_2d(p.x * 2.3 + 500.0, p.y * 2.3))
			var h := height_m * shape * (0.9 + 0.14 * n + 0.06 * ridge)
			if r == RINGS:
				h = -2.0
			verts.append(Vector3(p.x, h, p.y))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.0, height_m * (1.0 + 0.04 * noise.get_noise_2d(0.0, 0.0)), 0.0)
	for s in SEGMENTS:
		_tri(st, top, verts[(s + 1) % SEGMENTS], verts[s])
	for r in RINGS:
		for s in SEGMENTS:
			var a := r * SEGMENTS + s
			var b := r * SEGMENTS + (s + 1) % SEGMENTS
			var c := (r + 1) * SEGMENTS + s
			var d := (r + 1) * SEGMENTS + (s + 1) % SEGMENTS
			_tri(st, verts[a], verts[b], verts[c])
			_tri(st, verts[b], verts[d], verts[c])
	st.generate_normals()
	return st.commit()


## Emit facing up (Godot front faces are clockwise seen from the front).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).y > 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _summit_lights(mountain: Node3D, height_m: float, elev_ft: float) -> void:
	var lp := LightPoints.new()
	lp.name = "Obstruction"
	lp.halo_size_m = 40.0
	lp.halo_gain = 0.3
	lp.min_halo_angle = 0.012
	lp.extinction_per_m = 0.003
	var red := Color(1.0, 0.07, 0.03)
	# A lit mast on the summit and a second one a little down the ridge.
	lp.add_point(Vector3(0.0, height_m + 40.0, 0.0), red, 14.0, 1.4, 1.5, 0.0)
	lp.add_point(Vector3(260.0, height_m * 0.97 + 30.0, -180.0), red, 10.0, 1.2)
	mountain.add_child(lp)
	lp.commit()
	summit_lights.append(lp)
	summit_heights_ft.append(elev_ft + 100.0)
