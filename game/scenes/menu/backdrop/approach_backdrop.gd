class_name ApproachBackdrop
extends Node3D
## Menu backdrop: the lit aerodrome in fog at night, seen from a slowly
## drifting camera low on short final, left of the approach lights.

const FRAMINGS := {
	# name: [camera base, look target] in the runway frame
	"menu": [Vector3(-24.0, 19.0, 390.0), Vector3(-40.0, 8.0, -300.0)],
	"lobby": [Vector3(-30.0, 22.0, 420.0), Vector3(-190.0, 10.0, -300.0)],
	"cockpit": [Vector3(0.0, 46.0, 900.0), Vector3(0.0, 0.0, -400.0)],
}

var camera: DriftCamera


func _ready() -> void:
	var env := NightEnvironment.new()
	env.name = "Environment"
	add_child(env)
	var airport := AirportLayout.new()
	airport.name = "Airport"
	airport.visibility_m = env.visibility_m
	add_child(airport)
	add_child(_distant_lights(env.visibility_m))
	var cam := DriftCamera.new()
	camera = cam
	cam.name = "Camera"
	cam.fov = 52.0
	cam.near = 0.2
	cam.far = 12000.0
	add_child(cam)
	cam.make_current()


## Re-frame the shot: "menu", "lobby" or "cockpit". Instant when seconds <= 0.
func set_framing(framing: String, seconds: float = 3.0) -> void:
	var f: Array = FRAMINGS.get(framing, FRAMINGS["menu"])
	if seconds <= 0.0:
		camera.base_position = f[0]
		camera.look_target = f[1]
	else:
		camera.glide_to(f[0], f[1], seconds)


## Faint sodium and white lights of a road and a village beyond the field, for
## depth. Seeded, so every launch looks the same.
func _distant_lights(visibility: float) -> LightPoints:
	var lp := LightPoints.new()
	lp.name = "DistantLights"
	lp.extinction_per_m = NightEnvironment.extinction_for(visibility) * 0.35
	lp.halo_size_m = 30.0
	lp.halo_gain = 0.25
	lp.min_halo_angle = 0.02
	var rng := RandomNumberGenerator.new()
	rng.seed = 2707
	var sodium := Color(1.0, 0.55, 0.2)
	# A road crossing behind the far end of the runway.
	for i in 26:
		var x := -2600.0 + i * 160.0
		lp.add_point(Vector3(x, 9.0, -3400.0 + x * 0.12), sodium, 5.0, 1.2)
	# Village clusters off to the right and left.
	for c: Vector3 in [Vector3(2400.0, 0.0, -2600.0), Vector3(-2600.0, 0.0, -1800.0), Vector3(900.0, 0.0, -4200.0)]:
		for i in 34:
			var p := c + Vector3(rng.randf_range(-420.0, 420.0), rng.randf_range(4.0, 14.0), rng.randf_range(-260.0, 260.0))
			var warm := rng.randf() < 0.65
			lp.add_point(p, sodium if warm else Color(0.9, 0.92, 1.0), rng.randf_range(2.0, 5.0), 1.0)
	lp.commit()
	return lp
