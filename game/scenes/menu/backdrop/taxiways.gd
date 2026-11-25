class_name Taxiways
extends Node3D
## Parallel taxiway north of runway 27 with stub connectors, blue taxiway edge
## lights, lit runway distance-remaining signs along the left edge, red
## mandatory hold signs at the connectors and a terminal with a lit window
## band beside the apron. Runway frame (origin = threshold centre, landing
## direction −Z, +X = right of the landing direction).

const FT := 0.3048
const BLUE := Color(0.12, 0.28, 1.0)

@export var length_m := 1.4 * 1852.0
@export var runway_width_m := 45.0
@export var offset_m := 75.0
@export var width_m := 23.0
@export var extinction_per_m := 0.0025
@export var terminal_position := Vector3(200.0, 0.0, -390.0)

var edge_lights: LightPoints


func _ready() -> void:
	var surface := _surface_material()
	_slab(Vector3(offset_m, 0.0, -length_m * 0.5), Vector2(width_m, length_m + 40.0), surface)
	edge_lights = LightPoints.new()
	edge_lights.name = "TaxiwayEdge"
	edge_lights.extinction_per_m = extinction_per_m
	edge_lights.halo_size_m = 2.0
	edge_lights.halo_gain = 0.12
	add_child(edge_lights)
	# Parallel taxiway edges, with gaps where the connectors join.
	var connectors: Array[float] = [-40.0, -620.0, -1500.0, -length_m + 40.0]
	for side: float in [-1.0, 1.0]:
		var x := offset_m + side * (width_m * 0.5 + 0.8)
		var z := 0.0
		while z > -length_m:
			var near_gap := false
			for c in connectors:
				if side < 0.0 and absf(z - c) < 20.0:
					near_gap = true
			if not near_gap:
				edge_lights.add_point(Vector3(x, 0.35, z), BLUE, 1.8, 0.18)
			z -= 30.0
	for c in connectors:
		_connector(c, surface)
	edge_lights.commit()
	_distance_signs()
	_terminal()


func _surface_material() -> StandardMaterial3D:
	var m := AssetLookup.pbr_material("asphalt_worn", Vector2(width_m, length_m), 4.0)
	if m == null:
		m = StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.16, 0.165)
	m.roughness = 0.4
	return m


func _slab(center: Vector3, size: Vector2, mat: Material) -> void:
	var pm := PlaneMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = center + Vector3(0.0, 0.015, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A stub from the runway edge to the parallel taxiway at z, edge-lit, with a
## red mandatory hold sign on each side at the holding position.
func _connector(z: float, mat: Material) -> void:
	var x0 := runway_width_m * 0.5 + 2.0
	var x1 := offset_m - width_m * 0.5
	_slab(Vector3((x0 + x1) * 0.5, 0.0, z), Vector2(x1 - x0, 18.0), mat)
	var x := x0 + 6.0
	while x < x1:
		for side: float in [-1.0, 1.0]:
			edge_lights.add_point(Vector3(x, 0.35, z + side * 9.8), BLUE, 1.8, 0.18)
		x += 15.0
	var hold_x := runway_width_m * 0.5 + 45.0
	for side: float in [-1.0, 1.0]:
		_sign(Vector3(hold_x, 0.0, z + side * 13.0), Basis(Vector3.UP, -PI * 0.5),
			"27-09", Color(0.75, 0.04, 0.03), Color(1.0, 0.97, 0.92), 2.4)


## Runway distance-remaining signs (thousands of feet) along the left edge,
## facing the landing aircraft.
func _distance_signs() -> void:
	var total_kft := int(floor(length_m / FT / 1000.0))
	for n in range(total_kft, 0, -1):
		var z := -(length_m - n * 1000.0 * FT)
		if z > -150.0:
			continue
		_sign(Vector3(-(runway_width_m * 0.5 + 16.0), 0.0, z), Basis.IDENTITY,
			str(n), Color(0.02, 0.02, 0.02), Color(1.0, 1.0, 0.98), 1.2)


func _sign(pos: Vector3, basis: Basis, text: String, bg: Color, fg: Color, width: float) -> void:
	var root := Node3D.new()
	root.name = "Sign"
	root.transform = Transform3D(basis, pos)
	add_child(root)
	var housing := StandardMaterial3D.new()
	housing.albedo_color = Color(0.05, 0.05, 0.05)
	var face := StandardMaterial3D.new()
	face.albedo_color = bg
	face.emission_enabled = true
	face.emission = bg
	face.emission_energy_multiplier = 1.4
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 1.0, 0.3)
	box.mesh = bm
	box.material_override = housing
	box.position = Vector3(0.0, 0.9, 0.0)
	root.add_child(box)
	for s: float in [1.0, -1.0]:
		var panel := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(width - 0.1, 0.9)
		panel.mesh = qm
		panel.material_override = face
		panel.position = Vector3(0.0, 0.9, s * 0.152)
		panel.rotation.y = 0.0 if s > 0.0 else PI
		root.add_child(panel)
		var lbl := Label3D.new()
		lbl.text = text
		lbl.font_size = 96
		lbl.pixel_size = 0.0075
		lbl.modulate = fg * 0.8
		# Mipmapped so the far signs fade to a soft glow instead of sparkling.
		lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		lbl.visibility_range_end = 1500.0
		lbl.visibility_range_end_margin = 300.0
		lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		lbl.outline_size = 0
		lbl.double_sided = false
		lbl.position = Vector3(0.0, 0.9, s * 0.16)
		lbl.rotation.y = 0.0 if s > 0.0 else PI
		root.add_child(lbl)


## Low terminal building with a warm window band towards the runway, and
## sodium lamps on its landside.
func _terminal() -> void:
	var t := Node3D.new()
	t.name = "Terminal"
	t.position = terminal_position
	add_child(t)
	var wall := AssetLookup.pbr_material("concrete_apron", Vector2(30.0, 140.0), 4.0)
	if wall == null:
		wall = StandardMaterial3D.new()
	wall.albedo_color = Color(0.22, 0.22, 0.22)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30.0, 12.0, 140.0)
	body.mesh = bm
	body.material_override = wall
	body.position = Vector3(0.0, 6.0, 0.0)
	t.add_child(body)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.05, 0.05)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.78, 0.5)
	glass.emission_energy_multiplier = 1.6
	var band := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(132.0, 3.2)
	band.mesh = qm
	band.material_override = glass
	# Facing the runway (−X in this frame).
	band.position = Vector3(-15.05, 7.0, 0.0)
	band.rotation.y = -PI * 0.5
	t.add_child(band)
	var lamps := LightPoints.new()
	lamps.name = "TerminalLamps"
	lamps.extinction_per_m = extinction_per_m
	lamps.halo_size_m = 12.0
	lamps.halo_gain = 0.2
	t.add_child(lamps)
	for k in 6:
		lamps.add_point(Vector3(-17.0, 13.0, -60.0 + k * 24.0), Color(1.0, 0.6, 0.25), 3.0, 0.4)
	lamps.commit()
