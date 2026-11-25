class_name PilotCameraRig
extends Node3D
## The pilot's head: fixed eye point with three framings (panel, outside,
## pedestal), smooth mouse-look while the right mouse button is held, and small
## head motion from turbulence, bank changes and touchdown jolts.
## Keys 1 / 2 / 3 snap between the framings; the wheel over empty space zooms.

signal view_changed(view_name: String)

## name -> [head offset (aircraft frame, m), yaw deg, pitch deg, vertical fov deg]
const VIEWS := {
	"panel": [Vector3(0.22, -0.1, -0.04), 1.5, -28.5, 45.0],
	# Framed on the glass: 50° vertical (≈ 80° horizontal at 16:9) pitched so the
	# windshield fills most of the frame with the glareshield along the bottom.
	"outside": [Vector3(0.0, 0.03, 0.0), 0.0, -4.5, 50.0],
	"pedestal": [Vector3(0.3, -0.08, 0.02), -30.0, -52.0, 56.0],
}
const LOOK_YAW_LIMIT := 110.0
const LOOK_PITCH_UP := 35.0
const LOOK_PITCH_DOWN := -70.0
const MOUSE_DEG_PER_PX := 0.12
const SMOOTH := 9.0

@export var start_view := "panel"

var camera: Camera3D
var view_name := ""
## Turbulence strength 0..1 (set by the view from the weather / cloud state).
var turbulence := 0.0

var _target_off := Vector3.ZERO
var _target_yaw := 0.0
var _target_pitch := 0.0
var _target_fov := 55.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _off := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _looking := false
var _zoom := 1.0
var _jolt := Vector3.ZERO
var _jolt_v := Vector3.ZERO
var _t := 0.0
var _prev_bank := 0.0
var _bank_rate := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.03
	camera.far = 90000.0
	add_child(camera)
	camera.make_current()
	set_view(start_view, true)


func set_view(v: String, instant: bool = false) -> void:
	if not VIEWS.has(v):
		return
	view_name = v
	var spec: Array = VIEWS[v]
	_target_off = spec[0]
	_target_yaw = spec[1]
	_target_pitch = spec[2]
	_target_fov = spec[3]
	_look_yaw = 0.0
	_look_pitch = 0.0
	_zoom = 1.0
	if instant:
		_off = _target_off
		_yaw = _target_yaw
		_pitch = _target_pitch
		camera.fov = _target_fov
		_apply(Vector3.ZERO, 0.0)
	view_changed.emit(v)


## A short vertical/rotational kick (touchdown, gear thump). `strength` ~ metres.
func jolt(strength: float) -> void:
	_jolt_v += Vector3(randf_range(-0.3, 0.3), -1.0, randf_range(-0.2, 0.2)) * strength * 14.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# Wheel over empty space zooms (knobs take the wheel first).
			_zoom = clampf(_zoom * (0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88), 0.35, 1.0)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _looking:
		var mm := event as InputEventMouseMotion
		_look_yaw = clampf(_look_yaw - mm.relative.x * MOUSE_DEG_PER_PX, -LOOK_YAW_LIMIT - _target_yaw, LOOK_YAW_LIMIT - _target_yaw)
		_look_pitch = clampf(_look_pitch - mm.relative.y * MOUSE_DEG_PER_PX, LOOK_PITCH_DOWN - _target_pitch, LOOK_PITCH_UP - _target_pitch)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).keycode
		var map := {KEY_1: "panel", KEY_2: "outside", KEY_3: "pedestal"}
		if map.has(k):
			set_view(map[k])
			get_viewport().set_input_as_handled()


## Called every frame by the view with the current bank (deg) for head motion.
func update_motion(delta: float, bank_deg: float) -> void:
	_t += delta
	_bank_rate = lerpf(_bank_rate, (bank_deg - _prev_bank) / maxf(delta, 1e-3), 1.0 - exp(-delta * 3.0))
	_prev_bank = bank_deg
	var k := 1.0 - exp(-delta * SMOOTH)
	_off = _off.lerp(_target_off, k)
	_yaw = lerpf(_yaw, _target_yaw + _look_yaw, k)
	_pitch = lerpf(_pitch, _target_pitch + _look_pitch, k)
	camera.fov = lerpf(camera.fov, _target_fov * _zoom, k)
	# Damped spring for jolts.
	_jolt_v += (-_jolt * 160.0 - _jolt_v * 14.0) * delta
	_jolt += _jolt_v * delta
	# Turbulence: layered sines, incommensurate so it never loops visibly.
	var tb := turbulence
	var shake := Vector3(
		sin(_t * 7.1) * 0.6 + sin(_t * 13.3 + 1.0) * 0.4,
		sin(_t * 9.7 + 2.0) * 0.7 + sin(_t * 17.9) * 0.3,
		0.0) * 0.0025 * tb
	# The head lags the roll a little: lean against the roll rate.
	var lean := Vector3(-_bank_rate * 0.0012, 0.0, 0.0)
	_apply(shake + lean + _jolt, sin(_t * 5.3) * 0.15 * tb - _bank_rate * 0.04)


func _apply(head_off: Vector3, roll_deg: float) -> void:
	position = _off + head_off
	rotation = Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), deg_to_rad(roll_deg))
	rotation_order = EULER_ORDER_YXZ
