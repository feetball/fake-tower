class_name AirportLayout
extends Node3D
## The whole lit aerodrome around runway 27, in the runway frame: origin =
## threshold centre at field elevation, landing direction = local −Z, local +X
## = right of the landing direction. place_in_world() puts it at the real
## KFTW threshold in World coordinates (heading 270, field elevation).
## Built from RunwaySurface, RunwayLights, ApproachLights, ControlTower
## (with AirportBeacon) plus an apron with sodium floodlights and hangars.

const FT := 0.3048

@export var visibility_m := 900.0
@export var tower_position := Vector3(270.0, 0.0, -760.0)
@export var with_apron := true
@export var with_ground := true

var surface: RunwaySurface
var runway_lights: RunwayLights
var approach_lights: ApproachLights
var tower: ControlTower


func _ready() -> void:
	var length := float(World.DATA["runway"]["length_nm"]) * World.NM_TO_M
	var sigma := NightEnvironment.extinction_for(visibility_m) * 0.8
	if with_ground:
		surface = RunwaySurface.new()
		surface.name = "Surface"
		surface.length_m = length
		add_child(surface)
	runway_lights = RunwayLights.new()
	runway_lights.name = "RunwayLights"
	runway_lights.length_m = length
	runway_lights.extinction_per_m = sigma
	add_child(runway_lights)
	approach_lights = ApproachLights.new()
	approach_lights.name = "ApproachLights"
	approach_lights.extinction_per_m = sigma
	add_child(approach_lights)
	tower = ControlTower.new()
	tower.name = "Tower"
	tower.extinction_per_m = sigma
	tower.position = tower_position
	tower.rotation.y = PI * 0.25
	add_child(tower)
	if with_apron:
		_build_apron(sigma)


## Moves this node to the runway 27 threshold in World (sim) coordinates.
func place_in_world() -> void:
	transform = runway_frame_transform()


static func runway_frame_transform() -> Transform3D:
	var hdg := float(World.DATA["runway"]["heading_deg"])
	var origin := World.to_3d(0.0, 0.0, float(World.DATA["field_elev_ft"]))
	return Transform3D(Basis(Vector3.UP, World.heading_to_rot_y(hdg)), origin)


func _build_apron(sigma: float) -> void:
	var apron_center := tower_position + Vector3(-60.0, 0.0, -260.0)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.09, 0.09, 0.09)
	concrete.roughness = 0.35
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 420.0)
	var apron := MeshInstance3D.new()
	apron.name = "Apron"
	apron.mesh = plane
	apron.material_override = concrete
	apron.position = apron_center + Vector3(0.0, 0.01, 0.0)
	add_child(apron)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.11, 0.115, 0.12)
	metal.metallic = 0.5
	metal.roughness = 0.6
	for k in 2:
		var hangar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(60.0, 18.0, 70.0)
		hangar.mesh = box
		hangar.material_override = metal
		hangar.position = apron_center + Vector3(110.0, 9.0, -120.0 + k * 150.0)
		add_child(hangar)

	var sodium := Color(1.0, 0.55, 0.22)
	var lamps := LightPoints.new()
	lamps.name = "FloodLamps"
	lamps.extinction_per_m = sigma
	lamps.halo_size_m = 18.0
	lamps.halo_gain = 0.25
	add_child(lamps)
	for k in 3:
		var p := apron_center + Vector3(-70.0, 22.0, -150.0 + k * 150.0)
		lamps.add_point(p, sodium, 7.0, 0.6)
		var flood := SpotLight3D.new()
		flood.light_color = sodium
		flood.light_energy = 6.0
		flood.spot_range = 70.0
		flood.spot_angle = 55.0
		flood.light_volumetric_fog_energy = 1.2
		flood.shadow_enabled = false
		flood.position = p
		flood.rotation = Vector3(-deg_to_rad(65.0), deg_to_rad(-90.0), 0.0)
		add_child(flood)
	lamps.commit()
