class_name ControlTower
extends Node3D
## Procedural control tower silhouette: tapered concrete shaft, octagonal
## glass cab with a dim console glow, roof with antenna mast, red obstruction
## lights and an AirportBeacon on top. Origin = base of the shaft on the ground.

@export var height_m := 42.0
@export var with_beacon := true
@export var cab_glow := Color(0.12, 0.3, 0.26)
@export var extinction_per_m := 0.0025

var beacon: AirportBeacon


func _ready() -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.16, 0.16, 0.155)
	concrete.roughness = 0.85
	var tex := AssetLookup.find_texture(["concrete"], ["diff", "albedo", "color", "col"])
	if tex:
		concrete.albedo_texture = tex
		concrete.albedo_color = Color(0.5, 0.5, 0.5)
		concrete.uv1_triplanar = true
		concrete.uv1_scale = Vector3(0.25, 0.25, 0.25)
	var shaft_h := height_m - 7.0
	_cyl("Shaft", 3.2, 4.2, shaft_h, 12, shaft_h * 0.5, concrete)
	_cyl("Gallery", 7.0, 5.0, 1.6, 8, shaft_h + 0.8, concrete)

	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.02, 0.03, 0.035)
	glass.metallic = 0.2
	glass.roughness = 0.05
	glass.emission_enabled = true
	glass.emission = cab_glow
	glass.emission_energy_multiplier = 1.2
	_cyl("Cab", 7.6, 6.6, 4.4, 8, shaft_h + 1.6 + 2.2, glass)
	_cyl("Roof", 8.4, 8.4, 0.7, 8, shaft_h + 6.15, concrete)
	_cyl("Mast", 0.12, 0.18, 9.0, 6, shaft_h + 6.5 + 4.5, concrete)

	var cab_light := OmniLight3D.new()
	cab_light.light_color = Color(0.4, 0.9, 0.75)
	cab_light.light_energy = 0.6
	cab_light.omni_range = 14.0
	cab_light.light_volumetric_fog_energy = 1.5
	cab_light.position = Vector3(0.0, shaft_h + 3.5, 0.0)
	add_child(cab_light)

	var obstruction := LightPoints.new()
	obstruction.name = "Obstruction"
	obstruction.extinction_per_m = extinction_per_m
	obstruction.halo_size_m = 10.0
	add_child(obstruction)
	var red := Color(1.0, 0.08, 0.04)
	obstruction.add_point(Vector3(0.0, shaft_h + 15.2, 0.0), red, 6.0, 0.4)
	for a in 4:
		var ang := a * PI * 0.5 + PI * 0.25
		obstruction.add_point(Vector3(cos(ang) * 8.2, shaft_h + 6.6, sin(ang) * 8.2), red, 3.5, 0.3)
	obstruction.commit()

	if with_beacon:
		beacon = AirportBeacon.new()
		beacon.name = "Beacon"
		beacon.extinction_per_m = extinction_per_m
		beacon.position = Vector3(0.0, shaft_h + 7.4, 2.5)
		add_child(beacon)


func _cyl(n: String, top_r: float, bottom_r: float, h: float, segs: int, center_y: float, mat: Material) -> void:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = m
	mi.material_override = mat
	mi.position.y = center_y
	add_child(mi)
