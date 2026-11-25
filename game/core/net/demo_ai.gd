extends RefCounted
## A scripted AI pilot for offline demos: optional orbit delay, a few waypoints,
## then a 30° intercept with APP armed, configuring on LOC and GS capture.
## Flies through the same autopilot commands a human pilot uses.

const SimAircraft := preload("res://core/sim/aircraft.gd")
const Geo := preload("res://core/sim/geo.gd")

const WAYPOINT_NM := 1.5
## Inside this distance a waypoint also counts as passed once the distance grows
## again (the turn radius at 250 kt is about 1.5 nm, so it could otherwise orbit it).
const WAYPOINT_PASS_NM := 4.0

var ac: SimAircraft
## Waypoints as (x nm, y nm, indicated altitude ft).
var route: Array[Vector3] = []
var intercept_hdg := 240.0
var intercept_alt := 3000
var cruise_spd := 220
var delay_s := 0.0
var _stage := "delay" # delay, route, intercept, loc, gs
var _wp := 0
var _last_dist := INF
var _t := 0.0


func _init(aircraft: SimAircraft, qnh: int) -> void:
	ac = aircraft
	ac.apply({"alt_setting": qnh})


func stage() -> String:
	return _stage


func tick(dt: float) -> void:
	if not ac.is_flying():
		return
	_t += dt
	match _stage:
		"delay":
			if _t < delay_s:
				ac.apply({"hdg": ac.hdg + 30.0, "spd": cruise_spd}) # keep orbiting right
			else:
				_stage = "route"
		"route":
			if _wp >= route.size():
				ac.apply({"hdg": intercept_hdg, "alt": intercept_alt, "app": true, "flaps": 1, "spd": 180})
				_stage = "intercept"
				return
			var p := route[_wp]
			ac.apply({"hdg": Geo.bearing(ac.x, ac.y, p.x, p.y), "alt": p.z, "spd": cruise_spd})
			var d := Geo.dist(ac.x, ac.y, p.x, p.y)
			if d < WAYPOINT_NM or (d < WAYPOINT_PASS_NM and d > _last_dist):
				_wp += 1
				d = INF
			_last_dist = d
		"intercept":
			if ac.loc_captured:
				ac.apply({"flaps": 2, "spd": 160})
				_stage = "loc"
		"loc":
			if ac.gs_captured:
				ac.apply({"gear": true, "flaps": 3, "spd": 140})
				_stage = "gs"
