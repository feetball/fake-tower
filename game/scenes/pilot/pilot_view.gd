class_name PilotView
extends Node3D
## The pilot's view: a procedural airliner flight deck on an instrument
## approach at night in fog. Floating origin: the aircraft (cockpit + camera)
## stays at the scene origin with its attitude, and the outside world is
## translated by minus the eye position every frame, so ±40 nm coordinates
## never reach the GPU. Runs standalone (--demo=pilot) or under main's View.
##
## Debug user args (screenshots): --pilot-debug-pos=<dme_nm>,<height_ft_above_field>
## --pilot-view=panel|outside|pedestal  --pilot-efb=plate|atis
## --pilot-debug-warn=TERRAIN,PULL UP  --pilot-debug-outcome=<outcome>
## --pilot-debug-wx=<visibility_m>,<ceiling_ft>  --pilot-quality=low|medium|high

@export_enum("low", "medium", "high") var quality := "high":
	set(v):
		quality = v
		if is_node_ready():
			_apply_quality()

@onready var flight: PilotFlightState = $FlightState
@onready var aircraft: Node3D = $Aircraft
@onready var cockpit: PilotCockpit = $Aircraft/Cockpit
@onready var rig: PilotCameraRig = $Aircraft/CameraRig
@onready var outside: PilotOutside = $Outside


func _ready() -> void:
	_apply_debug_args()
	_apply_quality()
	if Session.phase != "playing" and get_parent() == get_tree().root:
		# Standalone run: Session handles --demo itself (deferred); only start one
		# if nothing else will.
		_start_standalone_demo.call_deferred()


func _start_standalone_demo() -> void:
	if Session.phase == "playing":
		return
	var role := _arg("--demo=")
	Session.start_demo(role if role != "" else "pilot")


func _process(delta: float) -> void:
	var eye := flight.eye_position()
	aircraft.transform = Transform3D(flight.attitude(), Vector3.ZERO)
	outside.set_eye(eye)
	rig.update_motion(delta, flight.bank)


func _apply_quality() -> void:
	outside.set_quality(quality)
	cockpit.set_quality(quality)


func _apply_debug_args() -> void:
	var q := _arg("--pilot-quality=")
	if q in ["low", "medium", "high"]:
		quality = q
	var pos := _arg("--pilot-debug-pos=")
	if pos != "":
		var p := pos.split(",")
		if p.size() >= 2:
			flight.set_debug_pose(float(p[0]), float(p[1]))
	var v := _arg("--pilot-view=")
	if v != "":
		rig.start_view = v
		rig.set_view(v, true)
	var wx := _arg("--pilot-debug-wx=")
	if wx != "":
		var w := wx.split(",")
		if w.size() >= 2:
			outside.debug_weather(float(w[0]), float(w[1]))


static func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""
