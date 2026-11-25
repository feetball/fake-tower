extends Camera3D
## Controller camera. Two framings: "scope" looks straight at the display rig
## from a distance chosen so both panels fill the screen below the HUD strip
## (scope_layout() returns their exact on-screen rects), "room" is a seated,
## pulled-back view of the position. Holding RMB looks around (springs back on
## release); a slow breathing drift runs in the room framing only.

const SCOPE_FOV := 32.0
const ROOM_FOV := 62.0
const BLEND_SPEED := 2.6 ## framing transitions per second
const LOOK_SENS := 0.0042 ## radians per canvas pixel
const LOOK_YAW_MAX := 1.9
const LOOK_PITCH_MIN := -0.75
const LOOK_PITCH_MAX := 0.6

var rig: Node3D ## display_rig.gd
var room_eye := Vector3(0.48, 1.4, 1.15)
var room_target := Vector3(-0.2, 1.0, -0.85)
var target_room := false
var blend := 0.0 ## 0 = scope framing, 1 = room framing
var look := Vector2.ZERO ## yaw, pitch
var looking := false

var _scope_xf := Transform3D.IDENTITY
var _t := 0.0


## Fits the rig into `avail` (canvas units) of a viewport `view` big and
## returns {"main": Rect2, "side": Rect2} in canvas units.
func scope_layout(view: Vector2, avail: Rect2) -> Dictionary:
	var b: Rect2 = rig.call("bounds")
	var ppm := minf(avail.size.x / b.size.x, avail.size.y / b.size.y)
	var size := b.size * ppm
	var r := Rect2(avail.get_center() - size * 0.5, size)
	var d := view.y / (2.0 * tan(deg_to_rad(SCOPE_FOV) * 0.5) * ppm)
	# Point of the panel plane that must appear at the viewport centre.
	var cx := b.get_center().x + (view.x * 0.5 - r.get_center().x) / ppm
	var cy := b.get_center().y + (r.get_center().y - view.y * 0.5) / ppm
	var local := Transform3D(Basis.IDENTITY, Vector3(cx, cy, d))
	_scope_xf = rig.global_transform * local
	var to_screen := func(lr: Rect2) -> Rect2:
		return Rect2(r.position.x + (lr.position.x - b.position.x) * ppm,
			r.position.y + (b.end.y - lr.end.y) * ppm, lr.size.x * ppm, lr.size.y * ppm)
	return {"main": to_screen.call(rig.call("main_rect")), "side": to_screen.call(rig.call("side_rect"))}


func at_scope() -> bool:
	return blend <= 0.0001 and look.length() < 0.001 and not target_room


func toggle_framing() -> void:
	target_room = not target_room


func look_by(rel: Vector2) -> void:
	look.x = clampf(look.x - rel.x * LOOK_SENS, -LOOK_YAW_MAX, LOOK_YAW_MAX)
	look.y = clampf(look.y - rel.y * LOOK_SENS, LOOK_PITCH_MIN, LOOK_PITCH_MAX)


func _process(delta: float) -> void:
	_t += delta
	blend = move_toward(blend, 1.0 if target_room else 0.0, delta * BLEND_SPEED)
	if not looking:
		look = look.lerp(Vector2.ZERO, 1.0 - exp(-delta * 7.0))
		if look.length() < 0.0005:
			look = Vector2.ZERO
	_apply()


func _apply() -> void:
	var e := smoothstep(0.0, 1.0, blend)
	var room_xf := Transform3D.IDENTITY.looking_at(room_target - room_eye, Vector3.UP)
	room_xf.origin = room_eye
	var xf := _scope_xf.interpolate_with(room_xf, e)
	# Breathing: a few millimetres and a fraction of a degree, room framing only.
	var br := Vector3(sin(_t * 0.31) * 0.004, sin(_t * 0.23 + 1.0) * 0.003, 0.0) * e
	xf.origin += xf.basis * br
	var yaw := look.x + sin(_t * 0.17) * 0.0025 * e
	var pitch := look.y + sin(_t * 0.27 + 2.0) * 0.002 * e
	xf.basis = Basis(Vector3.UP, yaw) * xf.basis * Basis(Vector3.RIGHT, pitch)
	global_transform = xf
	fov = lerpf(SCOPE_FOV, ROOM_FOV, e)
