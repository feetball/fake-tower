extends Node3D
## Our radar position: the console desk and turret, the display rig, keyboard
## and trackball, a strip bay with flight progress strips under a desk lamp,
## headset, mug, thermos, clipboard and a small VCCS panel. Origin on the floor
## below the front edge of the desk centre; the operator sits toward +Z.

const Kit := preload("res://scenes/controller/room/mesh_kit.gd")
const DisplayRig := preload("res://scenes/controller/room/display_rig.gd")
const Look := preload("res://scenes/controller/scope/scope_theme.gd")

const DESK_Y := 0.74
const RIG_POS := Vector3(0.0, 1.17, -0.86)
const RIG_TILT_DEG := -9.0

var rig: DisplayRig
var lamp_light: SpotLight3D
var strip_callsigns: PackedStringArray = ["SKW412", "ASA277", "DAL1873", "UAL905"]

var _shell: Material
var _dark: Material
var _top: Material


func _ready() -> void:
	_shell = Kit.pbr("metal_plate_painted", 1.2, Color(0.16, 0.17, 0.19), 1.0)
	_dark = Kit.mat(Color(0.03, 0.032, 0.036), 0.6, 0.2)
	_top = Kit.mat(Color(0.13, 0.135, 0.145), 0.38, 0.0)
	_desk()
	_turret()
	rig = DisplayRig.new()
	rig.name = "DisplayRig"
	rig.position = RIG_POS
	rig.rotation.x = deg_to_rad(RIG_TILT_DEG)
	add_child(rig)
	_keyboard(Vector3(-0.04, DESK_Y + 0.012, -0.43))
	_trackball(Vector3(0.33, DESK_Y + 0.012, -0.42))
	_strip_bay(Vector3(-0.68, DESK_Y, -0.6))
	_lamp()
	_props()


func _desk() -> void:
	Kit.box(self, Vector3(2.0, 0.035, 0.82), Vector3(0.0, DESK_Y - 0.0175, -0.6), _top, 0.006)
	# Padded arm rest along the front edge.
	Kit.box(self, Vector3(2.0, 0.035, 0.075), Vector3(0.0, DESK_Y - 0.005, -0.21),
		Kit.pbr("leather_seat_02", 0.5, Color(0.12, 0.12, 0.13), 1.0), 0.015)
	# Pedestals and modesty panel with vents and screws.
	for sx: float in [-0.93, 0.93]:
		Kit.box(self, Vector3(0.12, DESK_Y - 0.035, 0.78), Vector3(sx, (DESK_Y - 0.035) * 0.5, -0.6), _shell, 0.008)
	var front := Kit.box(self, Vector3(1.74, 0.62, 0.03), Vector3(0.0, 0.38, -0.95), _shell, 0.006)
	front.name = "ModestyPanel"
	_vents(Vector3(0.0, 0.2, -0.932), 14, 0.5)
	for sx: float in [-0.84, 0.84]:
		for sy: float in [0.1, 0.66]:
			_screw(Vector3(sx, sy, -0.933))
	Kit.box(self, Vector3(2.0, 0.08, 0.06), Vector3(0.0, 0.04, -0.98), _dark, 0.004)


func _turret() -> void:
	# Housing behind the displays, slanted like the rig.
	var t := Node3D.new()
	t.position = Vector3(0.17, 1.13, -1.12)
	t.rotation.x = deg_to_rad(RIG_TILT_DEG)
	add_child(t)
	Kit.box(t, Vector3(1.6, 0.78, 0.26), Vector3.ZERO, _shell, 0.012)
	# Top cap with a speaker grille and status lamps.
	Kit.box(t, Vector3(1.64, 0.05, 0.3), Vector3(0.0, 0.41, 0.0), _dark, 0.01)
	for i in 3:
		var col := [Color(0.2, 1.0, 0.35), Color(0.2, 1.0, 0.35), Color(1.0, 0.65, 0.15)][i] as Color
		Kit.box(t, Vector3(0.012, 0.006, 0.006), Vector3(0.62 + i * 0.024, 0.37, 0.132),
			Kit.mat(col * 0.3, 0.4, 0.0, col, 1.6), 0.0)
	# Lower riser between desk and turret.
	Kit.box(self, Vector3(1.6, 0.14, 0.3), Vector3(0.17, DESK_Y + 0.07, -0.98), _shell, 0.01)
	_vents(Vector3(0.17, DESK_Y + 0.07, -0.828), 22, 0.07)


func _vents(centre: Vector3, count: int, height: float) -> void:
	var slot := Kit.mat(Color(0.01, 0.01, 0.012), 0.8, 0.0)
	for i in count:
		var x := centre.x + (i - (count - 1) * 0.5) * 0.028
		Kit.box(self, Vector3(0.012, height, 0.004), Vector3(x, centre.y, centre.z), slot, 0.0)


func _screw(p: Vector3) -> void:
	Kit.cylinder(self, 0.005, 0.005, 0.003, p, Kit.mat(Color(0.35, 0.36, 0.38), 0.35, 0.9),
		Vector3(PI * 0.5, 0.0, 0.0), 10)


func _keyboard(p: Vector3) -> void:
	var kb := Node3D.new()
	kb.position = p
	kb.rotation.x = deg_to_rad(4.0)
	add_child(kb)
	Kit.box(kb, Vector3(0.46, 0.022, 0.16), Vector3.ZERO, Kit.mat(Color(0.05, 0.052, 0.058), 0.5, 0.1), 0.006)
	var cap := Kit.chamfer_box(Vector3(0.0165, 0.008, 0.0165), 0.002)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cap
	var keys: Array[Transform3D] = []
	for row in 5:
		var cols := 21 if row < 4 else 9
		for col in cols:
			var x := -0.205 + col * 0.0198 + (0.004 * row)
			if row == 4:
				x = -0.205 + col * 0.045
			keys.append(Transform3D(Basis.IDENTITY.scaled(Vector3(2.4 if row == 4 else 1.0, 1.0, 1.0)),
				Vector3(x, 0.014, -0.055 + row * 0.024)))
	mm.instance_count = keys.size()
	for i in keys.size():
		mm.set_instance_transform(i, keys[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Kit.mat(Color(0.085, 0.088, 0.095), 0.55, 0.0)
	kb.add_child(mmi)


func _trackball(p: Vector3) -> void:
	var tb := Node3D.new()
	tb.position = p
	add_child(tb)
	Kit.box(tb, Vector3(0.13, 0.03, 0.15), Vector3.ZERO, Kit.mat(Color(0.05, 0.052, 0.058), 0.5, 0.1), 0.012)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.028
	sm.height = 0.056
	ball.mesh = sm
	ball.material_override = Kit.mat(Color(0.1, 0.13, 0.17), 0.18, 0.0)
	ball.position = Vector3(0.0, 0.016, 0.005)
	tb.add_child(ball)
	for sx: float in [-0.04, 0.04]:
		Kit.box(tb, Vector3(0.035, 0.008, 0.03), Vector3(sx, 0.017, -0.055), Kit.mat(Color(0.12, 0.12, 0.13), 0.5), 0.003)


## Slanted rack of flight progress strips (paper in coloured plastic holders).
func _strip_bay(p: Vector3) -> void:
	var bay := Node3D.new()
	bay.name = "StripBay"
	bay.position = p
	add_child(bay)
	Kit.box(bay, Vector3(0.34, 0.05, 0.34), Vector3(0.0, 0.025, 0.0), _shell, 0.006)
	var rack := Node3D.new()
	rack.position = Vector3(0.0, 0.085, 0.0)
	rack.rotation.x = deg_to_rad(24.0)
	bay.add_child(rack)
	Kit.box(rack, Vector3(0.3, 0.012, 0.3), Vector3.ZERO, _dark, 0.004)
	var paper := Kit.mat(Color(0.78, 0.76, 0.68), 0.92, 0.0)
	var holders := [Color(0.55, 0.42, 0.1), Color(0.55, 0.42, 0.1), Color(0.15, 0.3, 0.5), Color(0.55, 0.42, 0.1),
		Color(0.15, 0.3, 0.5), Color(0.55, 0.42, 0.1), Color(0.5, 0.12, 0.1)]
	var ink := Color(0.08, 0.09, 0.14)
	var font := Look.mono(600)
	var hand := Look.sans(400)
	var types := ["CRJ9", "B738", "A321", "B739", "E175", "A320", "C56X"]
	for i in holders.size():
		var z := -0.12 + i * 0.04
		var holder := Kit.box(rack, Vector3(0.27, 0.006, 0.034), Vector3(0.0, 0.009, z),
			Kit.mat(holders[i] as Color, 0.35, 0.0), 0.002)
		holder.name = "Holder%d" % i
		Kit.box(rack, Vector3(0.25, 0.002, 0.027), Vector3(0.006, 0.0125, z), paper, 0.0)
		var cs := strip_callsigns[i] if i < strip_callsigns.size() else ["N44CT", "FFT61", "EJA12"][i % 3] as String
		var up := Vector3(-PI * 0.5, 0.0, 0.0)
		Kit.label(rack, cs, Vector3(-0.08, 0.0137, z - 0.004), 64, ink, 0.00015, font, up)
		Kit.label(rack, "%s/M  %03d" % [types[i], 180 + i * 10], Vector3(-0.08, 0.0137, z + 0.0078), 48, Color(ink, 0.85),
			0.00011, font, up)
		Kit.label(rack, ["040", "030", "ILS", "060", "050", "HOLD", "080"][i] as String, Vector3(0.03, 0.0137, z), 72,
			Color(0.1, 0.12, 0.35), 0.0001, hand, up)
		Kit.label(rack, "%02d%02d" % [21 + i / 3, (i * 7 + 12) % 60], Vector3(0.095, 0.0137, z), 52, Color(ink, 0.75),
			0.0001, font, up)


## Clamp-on arm lamp at the back-left corner reaching over the strip bay; its
## spot light sits in the shade (model space: clamp at origin, head ~0.25 m
## along -Z, 0.62 m up).
func _lamp() -> void:
	var lamp := Kit.model(self, "desk_lamp_arm_01", Vector3(-0.98, DESK_Y, -0.92), -135.0, 1.0)
	var head := Vector3(-0.8, DESK_Y + 0.6, -0.74)
	if lamp != null:
		lamp.name = "DeskLamp"
		head = lamp.transform * Vector3(0.0, 0.6, -0.25)
	lamp_light = SpotLight3D.new()
	lamp_light.name = "LampLight"
	lamp_light.light_color = Color(1.0, 0.68, 0.4)
	lamp_light.light_energy = 6.0
	lamp_light.light_volumetric_fog_energy = 2.5
	lamp_light.spot_range = 1.8
	lamp_light.spot_angle = 34.0
	lamp_light.spot_angle_attenuation = 2.2
	lamp_light.spot_attenuation = 0.8
	lamp_light.shadow_enabled = true
	lamp_light.shadow_blur = 1.2
	lamp_light.position = head
	add_child(lamp_light)
	lamp_light.look_at(Vector3(-0.62, DESK_Y, -0.52), Vector3.FORWARD)
	# Warm bulb glow inside the shade.
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.036
	bulb.mesh = sm
	bulb.material_override = Kit.mat(Color(1.0, 0.8, 0.6), 0.5, 0.0, Color(1.0, 0.72, 0.45), 6.0)
	bulb.position = head + Vector3(0.0, 0.01, 0.0)
	add_child(bulb)


func _props() -> void:
	_headset(Vector3(0.58, DESK_Y, -0.36))
	_mug(Vector3(0.66, DESK_Y, -0.66))
	Kit.model(self, "plastic_thermos", Vector3(0.93, DESK_Y, -0.86), -20.0, 0.85)
	_clipboard(Vector3(-0.47, DESK_Y + 0.003, -0.36), 14.0)
	_vccs(Vector3(0.84, DESK_Y, -0.44))


## Clipboard with the position log sheet.
func _clipboard(p: Vector3, rot_deg: float) -> void:
	var board := Node3D.new()
	board.name = "Clipboard"
	board.position = p
	board.rotation.y = deg_to_rad(rot_deg)
	add_child(board)
	Kit.model(board, "clipboard", Vector3.ZERO)
	var paper := Kit.mat(Color(0.8, 0.79, 0.74), 0.9)
	Kit.box(board, Vector3(0.205, 0.0012, 0.27), Vector3(0.0, 0.0045, 0.02), paper, 0.0)
	var ink := Color(0.1, 0.11, 0.2)
	var up := Vector3(-PI * 0.5, 0.0, 0.0)
	Kit.label(board, "POSITION LOG  APP-1", Vector3(0.0, 0.0053, -0.085), 64, ink, 0.00016, Look.sans(700), up)
	var lines := ["2110  ON  RWY 27 ILS", "2112  ATIS INFO REC", "2131  WX: FG OVC002", "2140  RELIEF BRIEF"]
	for i in lines.size():
		Kit.label(board, lines[i], Vector3(0.0, 0.0053, -0.05 + i * 0.022), 48, Color(ink, 0.8), 0.00016,
			Look.mono(500), up)


func _headset(p: Vector3) -> void:
	var hs := Node3D.new()
	hs.name = "Headset"
	hs.position = p
	hs.rotation.y = deg_to_rad(-25.0)
	add_child(hs)
	var band := Kit.mat(Color(0.05, 0.05, 0.055), 0.35, 0.6)
	var pad := Kit.pbr("leather_seat_02", 0.15, Color(0.09, 0.09, 0.095), 1.0)
	# Headband lying on its side: a smooth arc of thin segments.
	var r := 0.082
	var n := 24
	for i in n:
		var a0 := lerpf(-PI * 0.5, PI * 0.5, float(i) / n)
		var a1 := lerpf(-PI * 0.5, PI * 0.5, float(i + 1) / n)
		var mid := (a0 + a1) * 0.5
		var seg := Kit.box(hs, Vector3(r * (a1 - a0) * 1.08, 0.006, 0.012),
			Vector3(sin(mid) * r, 0.006, -cos(mid) * r), band, 0.002)
		seg.rotation.y = -mid
	# Ear cups: shell plus a leather cushion ring, lying flat.
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(sx * (r + 0.006), 0.0, 0.004)
		Kit.cylinder(hs, 0.031, 0.033, 0.018, c + Vector3(0.0, 0.009, 0.0), band, Vector3.ZERO, 28)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.016
		tm.outer_radius = 0.033
		tm.rings = 24
		tm.ring_segments = 10
		ring.mesh = tm
		ring.material_override = pad
		ring.position = c + Vector3(0.0, 0.022, 0.0)
		ring.scale = Vector3(1.0, 0.55, 1.0)
		hs.add_child(ring)
	var boom := Kit.cylinder(hs, 0.0022, 0.0022, 0.13, Vector3(r + 0.045, 0.012, 0.06), band,
		Vector3(PI * 0.5, 0.0, -0.5), 8)
	boom.name = "Boom"
	Kit.cylinder(hs, 0.005, 0.005, 0.014, Vector3(r + 0.075, 0.012, 0.115), pad, Vector3(PI * 0.5, 0.0, -0.5), 10)
	# Coiled cord running off toward the console jack.
	Kit.cylinder(hs, 0.0028, 0.0028, 0.42, Vector3(-r - 0.08, 0.003, -0.15), band, Vector3(PI * 0.5, 0.0, 0.7), 6)


func _mug(p: Vector3) -> void:
	var body := Kit.mat(Color(0.32, 0.06, 0.05), 0.3, 0.0)
	Kit.cylinder(self, 0.04, 0.037, 0.095, p + Vector3(0.0, 0.0475, 0.0), body, Vector3.ZERO, 28)
	Kit.cylinder(self, 0.034, 0.034, 0.002, p + Vector3(0.0, 0.082, 0.0), Kit.mat(Color(0.05, 0.025, 0.012), 0.15),
		Vector3.ZERO, 24)
	var handle := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.017
	tm.outer_radius = 0.025
	handle.mesh = tm
	handle.material_override = body
	handle.position = p + Vector3(0.042, 0.05, 0.0)
	handle.rotation.x = PI * 0.5
	add_child(handle)


## Voice switch panel: a small slanted touch screen with lit keys.
func _vccs(p: Vector3) -> void:
	var v := Node3D.new()
	v.name = "Vccs"
	v.position = p
	v.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(-12.0), 0.0)
	add_child(v)
	Kit.box(v, Vector3(0.2, 0.02, 0.15), Vector3(0.0, 0.03, 0.0), _dark, 0.006)
	for row in 3:
		for col in 4:
			var on := (row == 0 and col == 0) or (row == 1 and col == 2)
			var c := Color(0.25, 0.9, 0.45) if on else Color(0.45, 0.55, 0.65)
			Kit.box(v, Vector3(0.038, 0.002, 0.03), Vector3(-0.066 + col * 0.044, 0.041, -0.045 + row * 0.04),
				Kit.mat(c * 0.1, 0.3, 0.0, c, 1.2 if on else 0.35), 0.0)
