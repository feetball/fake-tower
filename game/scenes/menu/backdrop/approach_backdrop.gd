extends Node3D
## Menu backdrop: the lit aerodrome in fog at night, seen from a slowly
## drifting camera low on short final, left of the approach lights.


func _ready() -> void:
	var env := NightEnvironment.new()
	env.name = "Environment"
	add_child(env)
	var airport := AirportLayout.new()
	airport.name = "Airport"
	airport.visibility_m = env.visibility_m
	add_child(airport)
	var cam := DriftCamera.new()
	cam.name = "Camera"
	cam.fov = 52.0
	cam.near = 0.2
	cam.far = 12000.0
	add_child(cam)
	cam.make_current()
