class_name CockpitPedestal
extends Node3D
## Centre pedestal: housing, thrust levers that follow the engines, the
## speedbrake (deploys at touchdown), the flap lever with four detents (scroll
## over it, click a gate number, or F / Shift+F), engine master switches,
## parking brake, and the radio management panel with VHF and ILS frequencies.

const L := preload("res://scenes/pilot/cockpit/cockpit_layout.gd")
const K := preload("res://scenes/pilot/cockpit/mesh_kit.gd")
const M := preload("res://scenes/pilot/cockpit/cockpit_materials.gd")

const LEGEND := Color(0.62, 0.62, 0.58)
const LCD := Color(1.25, 0.62, 0.16)
const FLAP_Z0 := -0.44 ## flap gate for detent 0 (forward)
const FLAP_DZ := 0.045

var ap: PilotAutopilot
var bus: PilotAvionicsBus
var controls: Array[CockpitControl] = []

var _thrust: Array[Node3D] = []
var _flap_handle: Node3D
var _flap_z := FLAP_Z0
var _speedbrake: Node3D
var _sb_angle := 0.0
var _flap_cmd := -1
var _flap_cmd_until := -1.0
var _t := 0.0


func setup(autopilot: PilotAutopilot, b: PilotAvionicsBus) -> void:
	ap = autopilot
	bus = b
	_build_housing()
	_build_thrust()
	_build_flaps()
	_build_speedbrake()
	_build_radio()


func _top(dx: float, z: float, d: float = 0.0) -> Transform3D:
	return L.pedestal_top_xf(dx, z, d)


func _build_housing() -> void:
	var len := L.PEDESTAL_BACK_Z - L.PEDESTAL_FRONT_Z
	var w := L.PEDESTAL_HALF_W * 2.0
	var mid := (L.PEDESTAL_FRONT_Z + L.PEDESTAL_BACK_Z) * 0.5
	var top := _top(0.0, mid, -0.3)
	K.add(self, K.rounded_box(Vector3(w, 0.6, len), 0.015), M.get_mat("panel_dark"), top, "Housing")
	# Top deck panels with breaks.
	var panels := [[-0.68, -0.48], [-0.47, -0.2], [-0.19, 0.05], [0.06, 0.3]]
	for p: Array in panels:
		var z0: float = p[0]
		var z1: float = p[1]
		K.add(self, K.rounded_box(Vector3(w - 0.012, 0.012, z1 - z0), 0.003), M.get_mat("panel"), _top(0.0, (z0 + z1) * 0.5, 0.004), "Deck")
	# Screws at the deck corners.
	var screws: Array[Transform3D] = []
	for p: Array in panels:
		for z: float in [p[0] + 0.012, p[1] - 0.012]:
			for x: float in [-L.PEDESTAL_HALF_W + 0.014, L.PEDESTAL_HALF_W - 0.014]:
				screws.append(_top(x, z, 0.011))
	K.multi(self, K.cylinder(0.0032, 0.003, 10, 0.0028), M.get_mat("screw"), screws)


func _build_thrust() -> void:
	# Quadrant gate with a dark slot per lever.
	for side: float in [-1.0, 1.0]:
		K.add(self, K.rounded_box(Vector3(0.012, 0.006, 0.17), 0.002), M.get_mat("black"), _top(side * 0.045, -0.5, 0.011))
	K.add(self, K.rounded_box(Vector3(0.2, 0.04, 0.03), 0.008), M.get_mat("panel_dark"), _top(0.0, -0.62, 0.022))
	for i in 2:
		var pivot := Node3D.new()
		pivot.name = "ThrustLever%d" % (i + 1)
		pivot.transform = _top((i - 0.5) * 0.09, -0.5, -0.03)
		add_child(pivot)
		K.add(pivot, K.rounded_box(Vector3(0.01, 0.13, 0.014), 0.004), M.get_mat("switch"), Transform3D(Basis.IDENTITY, Vector3(0, 0.085, 0)))
		K.add(pivot, K.rounded_box(Vector3(0.05, 0.03, 0.034), 0.012), M.get_mat("knob"), Transform3D(Basis.IDENTITY, Vector3(0, 0.155, 0)))
		K.legend(pivot, str(i + 1), 0.008, LEGEND, Vector3(0, 0.155, 0.018))
		_thrust.append(pivot)
	# Reverser and autothrust disconnect details.
	K.legend(self, "THR LVR", 0.006, LEGEND, Vector3.ZERO).transform = _top(0.0, -0.4, 0.012) * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)
	# Engine master switches behind the levers.
	for i in 2:
		var at := _top((i - 0.5) * 0.09, -0.34, 0.012)
		K.add(self, K.rounded_box(Vector3(0.03, 0.02, 0.03), 0.006), M.get_mat("knob"), at)
		K.legend(self, "ENG %d" % (i + 1), 0.005, LEGEND, Vector3.ZERO).transform = at * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.011, 0.025))
	var pb := _top(0.0, -0.24, 0.012)
	K.add(self, K.rounded_box(Vector3(0.05, 0.03, 0.035), 0.01), M.get_mat("lever_white"), pb)
	K.legend(self, "PARK BRK", 0.005, LEGEND, Vector3.ZERO).transform = pb * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.0, 0.03))


func _build_flaps() -> void:
	var x := 0.15
	K.add(self, K.rounded_box(Vector3(0.014, 0.006, FLAP_DZ * 3.0 + 0.03), 0.002), M.get_mat("black"), _top(x, FLAP_Z0 + FLAP_DZ * 1.5, 0.011))
	for k in 4:
		var z := FLAP_Z0 + FLAP_DZ * k
		var lbl := K.legend(self, str(k) if k < 3 else "FULL", 0.007, LEGEND, Vector3.ZERO)
		lbl.transform = _top(x - 0.03, z, 0.012) * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)
		var gate := CockpitControl.new().setup(Vector3(0.03, 0.02, 0.03))
		gate.transform = _top(x - 0.03, z, 0.012)
		add_child(gate)
		gate.drag_px = 0.0
		var det := k
		gate.on_click = func() -> void: _command_flaps(det)
		gate.tooltip = func() -> String: return "Flaps %d — click to select (F / Shift+F)" % det
		controls.append(gate)
	K.legend(self, "FLAPS", 0.007, LEGEND, Vector3.ZERO).transform = _top(x, FLAP_Z0 - 0.035, 0.012) * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)
	_flap_handle = Node3D.new()
	_flap_handle.name = "FlapLever"
	add_child(_flap_handle)
	K.add(_flap_handle, K.rounded_box(Vector3(0.008, 0.06, 0.008), 0.003), M.get_mat("switch"), Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)))
	var grip := K.add(_flap_handle, K.rounded_box(Vector3(0.05, 0.022, 0.03), 0.008), M.get_mat("lever_white"), Transform3D(Basis.IDENTITY, Vector3(0, 0.065, 0)))
	var ctl := CockpitControl.new().setup(Vector3(0.06, 0.09, 0.05))
	ctl.position = Vector3(0, 0.05, 0)
	_flap_handle.add_child(ctl)
	ctl.visuals.append(grip)
	ctl.drag_px = 30.0
	ctl.on_scroll = func(dir: int, _big: bool) -> void: _command_flaps(_flap_target() - dir)
	ctl.on_click = func() -> void: _command_flaps(_flap_target() + 1 if _flap_target() < 3 else 0)
	ctl.tooltip = func() -> String: return "Flap lever %d — scroll, click or F / Shift+F" % int(bus.own.get("flaps", 0))
	controls.append(ctl)


func _command_flaps(f: int) -> void:
	f = clampi(f, 0, 3)
	_flap_cmd = f
	_flap_cmd_until = _t + 1.5
	ap.set_flaps(f)


func _flap_target() -> int:
	if _t < _flap_cmd_until and _flap_cmd >= 0:
		return _flap_cmd
	return int(bus.own.get("flaps", 0))


func _build_speedbrake() -> void:
	var x := -0.15
	K.add(self, K.rounded_box(Vector3(0.014, 0.006, 0.12), 0.002), M.get_mat("black"), _top(x, -0.38, 0.011))
	_speedbrake = Node3D.new()
	_speedbrake.transform = _top(x, -0.43, 0.0)
	add_child(_speedbrake)
	K.add(_speedbrake, K.rounded_box(Vector3(0.008, 0.05, 0.008), 0.003), M.get_mat("switch"), Transform3D(Basis.IDENTITY, Vector3(0, 0.025, 0)))
	K.add(_speedbrake, K.rounded_box(Vector3(0.022, 0.018, 0.04), 0.007), M.get_mat("knob"), Transform3D(Basis.IDENTITY, Vector3(0, 0.055, 0)))
	K.legend(self, "SPEED BRAKE", 0.0055, LEGEND, Vector3.ZERO).transform = _top(x - 0.035, -0.38, 0.012) * Transform3D(Basis(Vector3(0, 1, 0), PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)


func _build_radio() -> void:
	var panel := Node3D.new()
	panel.name = "RMP"
	panel.transform = _top(0.0, 0.05, 0.012) * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)
	add_child(panel)
	# In panel space: x right, y forward (towards the nose), +z up out of the deck.
	K.add(panel, K.rounded_box(Vector3(0.38, 0.16, 0.006), 0.004), M.get_mat("panel"), Transform3D.IDENTITY)
	K.legend(panel, "RADIO MANAGEMENT", 0.0055, LEGEND, Vector3(0.0, 0.068, 0.004))
	_freq_window(panel, Vector2(-0.085, 0.035), "119.850", "VHF1  ACTIVE")
	_freq_window(panel, Vector2(0.085, 0.035), "121.500", "STBY / CRS")
	_freq_window(panel, Vector2(-0.085, -0.035), "109.90", "ILS  IFTW")
	_freq_window(panel, Vector2(0.085, -0.035), "270", "CRS")
	K.knob(panel, Vector3(0.0, -0.06, 0.003), 0.012, 0.016)
	var names := ["VHF1", "VHF2", "VHF3", "NAV", "ILS"]
	for i in names.size():
		var at := Vector3(-0.15 + i * 0.075, -0.065, 0.0)
		if i == 2:
			continue
		K.add(panel, K.rounded_box(Vector3(0.03, 0.018, 0.008), 0.003), M.get_mat("knob"), Transform3D(Basis.IDENTITY, at + Vector3(0, 0, 0.004)))
		K.legend(panel, names[i], 0.0045, LEGEND, at + Vector3(0, -0.002, 0.0085))
		if i == 0 or i == 4:
			var lit := StandardMaterial3D.new()
			lit.albedo_color = Color(0.1, 0.3, 0.1)
			lit.emission_enabled = true
			lit.emission = Color(0.3, 1.0, 0.45)
			lit.emission_energy_multiplier = 2.5
			K.add(panel, K.rounded_box(Vector3(0.016, 0.003, 0.002), 0.0008), lit, Transform3D(Basis.IDENTITY, at + Vector3(0, 0.005, 0.0085)))


func _freq_window(panel: Node3D, at: Vector2, txt: String, title: String) -> void:
	K.add(panel, K.rounded_box(Vector3(0.12, 0.03, 0.004), 0.002), M.get_mat("bezel"), Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0.003)))
	K.add(panel, K.rounded_box(Vector3(0.112, 0.024, 0.002), 0.001), M.get_mat("window_lcd"), Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0.005)))
	K.legend(panel, txt, 0.012, LCD, Vector3(at.x, at.y, 0.0065), true)
	K.legend(panel, title, 0.0045, LEGEND, Vector3(at.x, at.y + 0.022, 0.0035))


func _process(delta: float) -> void:
	if bus == null:
		return
	_t += delta
	for i in _thrust.size():
		# Idle ~ 24 % N1 at the aft stop, TOGA ~ 95 % fully forward.
		var k := clampf((bus.n1[i] - 22.0) / 73.0, 0.0, 1.0)
		var reverse := bool(bus.own.get("on_ground", false)) and bus.ias > 60.0
		_thrust[i].rotation.x = deg_to_rad(lerpf(28.0, -22.0, k) if not reverse else 38.0)
	_flap_z = move_toward(_flap_z, FLAP_Z0 + FLAP_DZ * _flap_target(), delta * 0.25)
	_flap_handle.transform = _top(0.15, _flap_z, 0.01)
	var deployed := bool(bus.own.get("on_ground", false))
	_sb_angle = move_toward(_sb_angle, 30.0 if deployed else 0.0, delta * 120.0)
	_speedbrake.transform = _top(-0.15, -0.43 + _sb_angle / 30.0 * 0.09, 0.0) * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(_sb_angle * 0.5)), Vector3.ZERO)
