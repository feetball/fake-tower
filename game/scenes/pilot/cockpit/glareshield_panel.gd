class_name CockpitGlareshieldPanel
extends Node3D
## The autopilot control panel (MCP/FCU) on the glareshield and the captain's
## EFIS panel beside it: SPD / HDG / ALT windows with knobs, V/S window, AP1 /
## A/THR / LOC / APPR push buttons with light bars, and the baro knob with its
## window and STD push. Windows show the commanded value immediately (from
## PilotAutopilot), which then reconciles with the server.

const L := preload("res://scenes/pilot/cockpit/cockpit_layout.gd")
const K := preload("res://scenes/pilot/cockpit/mesh_kit.gd")
const M := preload("res://scenes/pilot/cockpit/cockpit_materials.gd")

const LCD := Color(1.25, 0.62, 0.16)
const LEGEND := Color(0.62, 0.62, 0.58)
const LIGHT_ON := Color(0.3, 1.0, 0.45)

var ap: PilotAutopilot
var bus: PilotAvionicsBus
var controls: Array[CockpitControl] = []

var _windows: Dictionary = {} ## knob -> Label3D
var _knobs: Dictionary = {} ## knob -> spinning Node3D
var _last: Dictionary = {}
var _app_light: StandardMaterial3D
var _loc_light: StandardMaterial3D
var _baro_label: Label3D
var _std_label: Label3D
var _last_body: MeshInstance3D


func setup(autopilot: PilotAutopilot, b: PilotAvionicsBus) -> void:
	ap = autopilot
	bus = b
	_build_mcp()
	_build_efis()


func _build_mcp() -> void:
	var mcp := Node3D.new()
	mcp.name = "MCP"
	mcp.transform = L.mcp_xf(L.MCP_CENTRE, 0.0, 0.0)
	add_child(mcp)
	var w := L.MCP_SIZE.x
	var h := L.MCP_SIZE.y
	K.add(mcp, K.rounded_box(Vector3(w, h, 0.05), 0.006), M.get_mat("panel"), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.025)), "Body")
	# Sub-panel breaks.
	for u: float in [-0.13, 0.05, 0.245]:
		K.add(mcp, K.rounded_box(Vector3(0.002, h - 0.01, 0.002), 0.0005), M.get_mat("black"), Transform3D(Basis.IDENTITY, Vector3(u, 0, 0.0005)))
	# Left to right: SPD, A/THR, HDG, LOC/APPR, ALT, V/S, AP1/AP2 (the
	# approach controls sit next to HDG so the panel view frames them).
	_knob_unit(mcp, "spd", "SPD", -0.255, "Selected speed", "kt")
	_knob_unit(mcp, "hdg", "HDG", -0.085, "Selected heading", "°")
	_knob_unit(mcp, "alt", "ALT", 0.1, "Selected altitude", "ft")
	# V/S window: dashed (managed by ALT / G/S), wheel is not used in this aircraft.
	_window(mcp, Vector2(0.2, 0.018), 0.064, "-----", "V/S", true)
	K.add(mcp, K.rounded_box(Vector3(0.012, 0.03, 0.012), 0.004), M.get_mat("knob"), Transform3D(Basis.IDENTITY, Vector3(0.2, -0.022, 0.006)))
	# Push buttons.
	_button(mcp, Vector2(-0.17, 0.012), "A/THR", true)
	_button(mcp, Vector2(0.28, 0.02), "AP1", true)
	_button(mcp, Vector2(0.28, -0.022), "AP2", false)
	_loc_light = _button(mcp, Vector2(0.008, 0.02), "LOC", false)
	_app_light = _button(mcp, Vector2(0.008, -0.022), "APPR", false)
	var app_body := _last_body
	var app_ctl := _control(mcp, Vector3(0.008, -0.022, 0.006), Vector3(0.04, 0.03, 0.02))
	app_ctl.on_click = func() -> void: ap.toggle_app()
	app_ctl.on_scroll = Callable()
	app_ctl.drag_px = 0.0
	app_ctl.tooltip = func() -> String:
		return "APPR — arm the ILS approach (A)   " + ("ARMED" if bool(bus.own.get("app_armed", false)) else "off")
	app_ctl.visuals.append(app_body)


func _knob_unit(parent: Node3D, k: String, title: String, u: float, desc: String, unit: String) -> void:
	_windows[k] = _window(parent, Vector2(u, 0.018), 0.075, "---", title)
	var spin := K.knob(parent, Vector3(u, -0.024, 0.0), 0.0155, 0.022)
	_knobs[k] = spin
	var ctl := _control(parent, Vector3(u, -0.024, 0.012), Vector3(0.042, 0.042, 0.03))
	ctl.on_scroll = func(dir: int, big: bool) -> void: ap.nudge(k, dir, big)
	ctl.tooltip = func() -> String:
		return "%s %d %s — scroll or drag (Shift: ×10)" % [desc, ap.display_value(k), unit]
	for c in spin.get_children():
		if c is GeometryInstance3D:
			ctl.visuals.append(c as GeometryInstance3D)


## LCD window with a legend above it; returns the digits label.
func _window(parent: Node3D, at: Vector2, width: float, txt: String, title: String, small: bool = false) -> Label3D:
	K.add(parent, K.rounded_box(Vector3(width + 0.006, 0.03, 0.004), 0.002), M.get_mat("bezel"), Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0.0005)))
	K.add(parent, K.rounded_box(Vector3(width, 0.024, 0.002), 0.001), M.get_mat("window_lcd"), Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0.0025)))
	K.legend(parent, title, 0.0065, LEGEND, Vector3(at.x, at.y + 0.025, 0.001))
	return K.legend(parent, txt, 0.011 if small else 0.0135, LCD, Vector3(at.x, at.y, 0.004), true)


## Square push button with a light bar; returns the bar's material.
func _button(parent: Node3D, at: Vector2, title: String, lit: bool) -> StandardMaterial3D:
	_last_body = K.add(parent, K.rounded_box(Vector3(0.036, 0.03, 0.01), 0.003), M.get_mat("knob"), Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0.005)))
	var bar := StandardMaterial3D.new()
	bar.albedo_color = Color(0.05, 0.06, 0.05)
	bar.emission_enabled = true
	_set_light(bar, lit)
	K.add(parent, K.rounded_box(Vector3(0.022, 0.004, 0.002), 0.0008), bar, Transform3D(Basis.IDENTITY, Vector3(at.x, at.y + 0.006, 0.0105)))
	K.legend(parent, title, 0.0048, LEGEND, Vector3(at.x, at.y - 0.006, 0.0106))
	return bar


static func _set_light(m: StandardMaterial3D, on: bool) -> void:
	m.emission = LIGHT_ON if on else Color(0.0, 0.0, 0.0)
	m.emission_energy_multiplier = 3.0 if on else 0.0


func _control(parent: Node3D, pos: Vector3, extents: Vector3) -> CockpitControl:
	var c := CockpitControl.new().setup(extents)
	c.position = pos
	parent.add_child(c)
	controls.append(c)
	return c


func _build_efis() -> void:
	var efis := Node3D.new()
	efis.name = "EFIS"
	efis.transform = L.mcp_xf(L.EFIS_CENTRE, 0.0, 0.0)
	add_child(efis)
	K.add(efis, K.rounded_box(Vector3(L.EFIS_SIZE.x, L.EFIS_SIZE.y, 0.045), 0.006), M.get_mat("panel"), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.0225)), "Body")
	# Baro window and knob (pull = QNH, push = STD).
	K.add(efis, K.rounded_box(Vector3(0.076, 0.03, 0.004), 0.002), M.get_mat("bezel"), Transform3D(Basis.IDENTITY, Vector3(-0.07, 0.018, 0.0005)))
	K.add(efis, K.rounded_box(Vector3(0.07, 0.024, 0.002), 0.001), M.get_mat("window_lcd"), Transform3D(Basis.IDENTITY, Vector3(-0.07, 0.018, 0.0025)))
	K.legend(efis, "BARO  hPa", 0.0055, LEGEND, Vector3(-0.07, 0.042, 0.001))
	_baro_label = K.legend(efis, "1013", 0.0135, LCD, Vector3(-0.07, 0.018, 0.004), true)
	_std_label = K.legend(efis, "PUSH STD", 0.0045, LEGEND, Vector3(-0.07, -0.046, 0.001))
	var spin := K.knob(efis, Vector3(-0.07, -0.022, 0.0), 0.0145, 0.02)
	_knobs["baro"] = spin
	var ctl := _control(efis, Vector3(-0.07, -0.022, 0.012), Vector3(0.04, 0.04, 0.03))
	ctl.on_scroll = func(dir: int, big: bool) -> void: ap.nudge("baro", dir, big)
	ctl.on_click = func() -> void: ap.toggle_std()
	ctl.tooltip = func() -> String:
		var v := ap.display_value("baro")
		return "Altimeter %s — scroll or drag to set, click = STD ([ ] B)" % ("STD 1013" if v == 1013 else "QNH %d" % v)
	for c in spin.get_children():
		if c is GeometryInstance3D:
			ctl.visuals.append(c as GeometryInstance3D)
	# ND mode / range selectors and the LS / CSTR buttons (not used, for the look).
	K.knob(efis, Vector3(0.04, -0.008, 0.0), 0.0105, 0.016)
	K.legend(efis, "MODE", 0.0045, LEGEND, Vector3(0.04, 0.022, 0.001))
	K.knob(efis, Vector3(0.088, -0.008, 0.0), 0.0105, 0.016)
	K.legend(efis, "RANGE", 0.0045, LEGEND, Vector3(0.088, 0.022, 0.001))
	_button(efis, Vector2(-0.012, 0.02), "LS", true)
	_button(efis, Vector2(-0.012, -0.022), "CSTR", false)


func _process(_delta: float) -> void:
	if ap == null:
		return
	for k: String in _windows:
		var v := ap.display_value(k)
		var s := ("%03d" % v) if k == "hdg" else str(v)
		_update_knob(k, v)
		var lbl := _windows[k] as Label3D
		if lbl.text != s:
			lbl.text = s
	var baro := ap.display_value("baro")
	_update_knob("baro", baro)
	var bs := "STD" if baro == 1013 else str(baro)
	if _baro_label.text != bs:
		_baro_label.text = bs
	var own := bus.own
	var armed := bool(own.get("app_armed", false))
	_set_light(_app_light, armed)
	_set_light(_loc_light, armed or String(own.get("ap_mode", "HDG")) != "HDG")


## Turn the knob a detent whenever its value moves.
func _update_knob(k: String, v: int) -> void:
	if not _last.has(k):
		_last[k] = v
		return
	var prev: int = _last[k]
	if prev != v:
		var d := v - prev
		if k == "hdg":
			d = wrapi(d + 180, 0, 360) - 180
		var step: int = PilotAutopilot.LIMITS[k][2]
		var spin := _knobs[k] as Node3D
		spin.rotation.z -= signf(d) * minf(absf(d) / step, 6.0) * deg_to_rad(12.0)
		_last[k] = v
