class_name CockpitGearPanel
extends Node3D
## Landing gear lever on the centre panel with the three gear lights (green
## down and locked, red in transit) and a brake pressure / autobrake strip.
## Click the lever (or G) to move it; it moves at once and the lights follow
## the actuation.

const L := preload("res://scenes/pilot/cockpit/cockpit_layout.gd")
const K := preload("res://scenes/pilot/cockpit/mesh_kit.gd")
const M := preload("res://scenes/pilot/cockpit/cockpit_materials.gd")

const LEVER_UP_DEG := 28.0
const LEVER_DOWN_DEG := -28.0

var ap: PilotAutopilot
var bus: PilotAvionicsBus
var controls: Array[CockpitControl] = []

var _pivot: Node3D
var _lights: Array[StandardMaterial3D] = []
var _lever_angle := LEVER_UP_DEG
var _cmd_down := false
var _cmd_until := -1.0
var _t := 0.0


func setup(autopilot: PilotAutopilot, b: PilotAvionicsBus) -> void:
	ap = autopilot
	bus = b
	var base := Node3D.new()
	base.name = "Gear"
	base.transform = L.panel_xf(L.GEAR_UV.x, L.GEAR_UV.y, 0.0)
	add_child(base)
	# Slotted plate.
	K.add(base, K.rounded_box(Vector3(0.07, 0.15, 0.008), 0.004), M.get_mat("panel_dark"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.004)))
	K.add(base, K.rounded_box(Vector3(0.012, 0.1, 0.004), 0.002), M.get_mat("black"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.008)))
	K.legend(base, "UP", 0.006, Color(0.62, 0.62, 0.58), Vector3(0.022, 0.05, 0.009))
	K.legend(base, "DN", 0.006, Color(0.62, 0.62, 0.58), Vector3(0.022, -0.05, 0.009))
	K.legend(base, "L/G", 0.007, Color(0.62, 0.62, 0.58), Vector3(0.0, 0.068, 0.009))
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0, 0.006)
	base.add_child(_pivot)
	# Arm and the wheel-shaped knob at its end.
	K.add(_pivot, K.rounded_box(Vector3(0.008, 0.008, 0.07), 0.003), M.get_mat("switch"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.035)))
	var wheel := K.add(_pivot, K.cylinder(0.017, 0.012, 32), M.get_mat("lever_white"),
		Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0, 0.074)))
	var ctl := CockpitControl.new().setup(Vector3(0.05, 0.16, 0.09))
	ctl.position = Vector3(0, 0, 0.04)
	base.add_child(ctl)
	ctl.visuals.append(wheel)
	ctl.drag_px = 0.0
	ctl.on_click = _toggle
	ctl.on_scroll = func(dir: int, _big: bool) -> void: _command(dir < 0)
	ctl.tooltip = func() -> String:
		return "Landing gear — click (G)   " + ("DOWN" if bool(bus.own.get("gear_down", false)) else "UP")
	controls.append(ctl)
	# Gear lights: nose above, mains below, to the left of the lever.
	var spots: Array[Vector2] = [Vector2(-0.065, 0.045), Vector2(-0.085, 0.012), Vector2(-0.045, 0.012)]
	for s in spots:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.02, 0.03, 0.02)
		mat.emission_enabled = true
		K.add(base, K.rounded_box(Vector3(0.018, 0.018, 0.006), 0.002), M.get_mat("bezel"), Transform3D(Basis.IDENTITY, Vector3(s.x, s.y, 0.003)))
		K.add(base, K.rounded_box(Vector3(0.014, 0.014, 0.003), 0.0015), mat, Transform3D(Basis.IDENTITY, Vector3(s.x, s.y, 0.0065)))
		_lights.append(mat)
	K.legend(base, "LDG GEAR", 0.0055, Color(0.62, 0.62, 0.58), Vector3(-0.065, -0.018, 0.009))
	# Autobrake strip to the right.
	var labels := ["LO", "MED", "MAX"]
	for i in 3:
		var at := Vector3(0.075 + i * 0.04, 0.03, 0.0)
		K.add(base, K.rounded_box(Vector3(0.032, 0.024, 0.01), 0.003), M.get_mat("knob"), Transform3D(Basis.IDENTITY, at + Vector3(0, 0, 0.005)))
		K.legend(base, labels[i], 0.005, Color(0.62, 0.62, 0.58), at + Vector3(0, -0.004, 0.0105))
		if i == 1:
			var lit := StandardMaterial3D.new()
			lit.albedo_color = Color(0.1, 0.3, 0.1)
			lit.emission_enabled = true
			lit.emission = Color(0.3, 1.0, 0.45)
			lit.emission_energy_multiplier = 2.5
			K.add(base, K.rounded_box(Vector3(0.02, 0.004, 0.002), 0.0008), lit, Transform3D(Basis.IDENTITY, at + Vector3(0, 0.006, 0.0105)))
	K.legend(base, "AUTO BRK", 0.0055, Color(0.62, 0.62, 0.58), Vector3(0.115, 0.058, 0.009))
	K.knob(base, Vector3(0.115, -0.03, 0.0), 0.012, 0.016)
	K.legend(base, "BRK PRESS", 0.005, Color(0.62, 0.62, 0.58), Vector3(0.115, -0.058, 0.009))


func _toggle() -> void:
	_command(not _lever_down())


func _command(down: bool) -> void:
	_cmd_down = down
	_cmd_until = _t + 1.5
	ap.set_gear(down)


func _lever_down() -> bool:
	if _t < _cmd_until:
		return _cmd_down
	return bool(bus.own.get("gear_down", false))


func _process(delta: float) -> void:
	if bus == null:
		return
	_t += delta
	var target := LEVER_DOWN_DEG if _lever_down() else LEVER_UP_DEG
	_lever_angle = move_toward(_lever_angle, target, delta * 160.0)
	_pivot.rotation.x = deg_to_rad(-_lever_angle)
	var g := bus.gear_pos
	for i in 3:
		var leg := clampf((g - i * 0.04) / 0.92, 0.0, 1.0) if bus.gear_target > 0.5 else clampf((g - 0.08 + i * 0.04) / 0.92, 0.0, 1.0)
		var m := _lights[i]
		if leg >= 0.999:
			m.emission = Color(0.25, 1.0, 0.35)
			m.emission_energy_multiplier = 2.5
		elif leg > 0.001:
			m.emission = Color(1.0, 0.12, 0.08)
			m.emission_energy_multiplier = 2.5
		else:
			m.emission_energy_multiplier = 0.0
