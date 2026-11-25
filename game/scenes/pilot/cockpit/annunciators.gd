class_name CockpitAnnunciators
extends Node3D
## Warning lights: MASTER WARNING / MASTER CAUTION on the glareshield (push to
## acknowledge) and the GPWS / configuration annunciators left of the PFD
## (PULL UP, TERRAIN, GEAR, LOW FUEL). Driven by `own.warnings`.

const L := preload("res://scenes/pilot/cockpit/cockpit_layout.gd")
const K := preload("res://scenes/pilot/cockpit/mesh_kit.gd")
const M := preload("res://scenes/pilot/cockpit/cockpit_materials.gd")

const RED := Color(1.0, 0.12, 0.08)
const AMBER := Color(1.0, 0.6, 0.08)

var bus: PilotAvionicsBus
var controls: Array[CockpitControl] = []
## warning -> {mat, label, colour}
var _lights: Dictionary = {}
var _master_warn: Dictionary
var _master_caut: Dictionary
var _acked: Array = []
var _t := 0.0


func setup(b: PilotAvionicsBus) -> void:
	bus = b
	var col := Node3D.new()
	col.name = "GpwsColumn"
	add_child(col)
	var specs := [["PULL UP", "PULL UP", RED], ["TERRAIN", "TERRAIN", AMBER], ["TOO LOW GEAR", "GEAR", RED], ["LOW FUEL", "LOW FUEL", AMBER]]
	for i in specs.size():
		var s: Array = specs[i]
		var xf := L.panel_xf(L.ANNUN_UV.x, L.ANNUN_UV.y - i * 0.034, 0.0)
		_lights[s[0]] = _light(col, xf, Vector2(0.07, 0.026), String(s[1]), s[2])
	var g := Node3D.new()
	g.name = "Masters"
	add_child(g)
	_master_warn = _light(g, L.mcp_xf(L.MASTER_CENTRE, -0.026, 0.0, 0.006), Vector2(0.044, 0.044), "MASTER\nWARN", RED)
	_master_caut = _light(g, L.mcp_xf(L.MASTER_CENTRE, 0.026, 0.0, 0.006), Vector2(0.044, 0.044), "MASTER\nCAUT", AMBER)
	for m: Dictionary in [_master_warn, _master_caut]:
		var c := CockpitControl.new().setup(Vector3(0.046, 0.046, 0.02))
		c.transform = (m["node"] as Node3D).transform
		g.add_child(c)
		c.visuals.append(m["mesh"] as GeometryInstance3D)
		c.drag_px = 0.0
		c.on_click = func() -> void: _acked = bus.warnings.duplicate()
		c.tooltip = func() -> String: return "Master warning / caution — click to acknowledge"
		controls.append(c)


func _light(parent: Node3D, xf: Transform3D, size: Vector2, txt: String, col: Color) -> Dictionary:
	var n := Node3D.new()
	n.transform = xf
	parent.add_child(n)
	K.add(n, K.rounded_box(Vector3(size.x + 0.006, size.y + 0.006, 0.012), 0.002), M.get_mat("bezel"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0)))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.025, 0.02)
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.0
	var mesh := K.add(n, K.rounded_box(Vector3(size.x, size.y, 0.004), 0.0015), mat, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.006)))
	var lbl := K.legend(n, txt, size.y * (0.2 if txt.contains("\n") else 0.32), col * 0.25, Vector3(0, 0, 0.0085))
	lbl.line_spacing = -4.0
	return {"node": n, "mat": mat, "label": lbl, "col": col, "mesh": mesh}


func _set_light(light: Dictionary, on: bool, flash: bool) -> void:
	var lit := on and (not flash or fmod(_t, 0.5) < 0.3)
	var mat := light["mat"] as StandardMaterial3D
	var col: Color = light["col"]
	mat.emission_energy_multiplier = 2.2 if lit else 0.0
	mat.albedo_color = col * 0.5 if lit else Color(0.03, 0.025, 0.02)
	(light["label"] as Label3D).modulate = Color(1.6, 1.5, 1.4) if lit else col * 0.22


func _process(delta: float) -> void:
	if bus == null:
		return
	_t += delta
	var w: Array = bus.warnings
	for k: String in _lights:
		_set_light(_lights[k], w.has(k), k == "PULL UP")
	# Acknowledgement holds until a new warning appears.
	for x: Variant in w:
		if not _acked.has(x):
			_acked = []
			break
	var red := w.has("PULL UP") or w.has("TOO LOW GEAR") or (w.has("LOW FUEL") and float(bus.own.get("fuel_min", 9.0)) < 5.0)
	var amber := w.has("TERRAIN") or w.has("LOW FUEL")
	var acked := not w.is_empty() and _acked.size() > 0
	_set_light(_master_warn, red and not acked, true)
	_set_light(_master_caut, amber and not red and not acked, false)
