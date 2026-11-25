class_name CockpitDisplays
extends Node3D
## The display units on the main panel: captain PFD and ND, the centre
## engine/systems display, the standby instrument, and the first officer's
## PFD/ND (which reuse the captain's rendered images: same data, no extra cost).

const L := preload("res://scenes/pilot/cockpit/cockpit_layout.gd")
const PfdScript := preload("res://scenes/pilot/instruments/pfd/pfd.gd")
const NdScript := preload("res://scenes/pilot/instruments/nd.gd")
const EicasScript := preload("res://scenes/pilot/instruments/eicas.gd")
const IsisScript := preload("res://scenes/pilot/instruments/isis.gd")

var pfd: PilotDisplayUnit
var nd: PilotDisplayUnit
var eicas: PilotDisplayUnit
var isis: PilotDisplayUnit
var _units: Array[PilotDisplayUnit] = []


func setup(bus: PilotAvionicsBus, resolution: int) -> void:
	var p := PfdScript.new()
	p.setup(bus)
	pfd = _unit("PFD", L.PFD_UV, L.DU_SIZE, p, resolution, 30.0, 1.3)
	var n := NdScript.new()
	n.bus = bus
	nd = _unit("ND", L.ND_UV, L.DU_SIZE, n, resolution, 20.0, 4.2)
	var e := EicasScript.new()
	e.bus = bus
	eicas = _unit("EICAS", L.EICAS_UV, L.DU_SIZE, e, resolution, 15.0, 7.9)
	var s := IsisScript.new()
	s.bus = bus
	isis = _unit("ISIS", L.ISIS_UV, L.ISIS_SIZE, s, maxi(256, resolution / 3), 15.0, 2.2)
	isis.bezel_margin = 0.012
	_mirror("FO_PFD", L.FO_PFD_UV, pfd, 5.5)
	_mirror("FO_ND", L.FO_ND_UV, nd, 9.1)


func set_resolution(px: int) -> void:
	for u in _units:
		u.set_resolution(px if u != isis else maxi(256, px / 3))


func _unit(n: String, uv: Vector2, sz: float, inst: PilotInstrumentPart, res: int, hz: float, seed_v: float) -> PilotDisplayUnit:
	var u := PilotDisplayUnit.new()
	u.name = n
	u.screen_size = Vector2(sz, sz)
	u.update_hz = hz
	u.transform = L.panel_xf(uv.x, uv.y, 0.012)
	add_child(u)
	u.setup(inst, res, seed_v)
	_units.append(u)
	return u


## A second glass showing another unit's image.
func _mirror(n: String, uv: Vector2, src: PilotDisplayUnit, seed_v: float) -> void:
	var u := Node3D.new()
	u.name = n
	u.transform = L.panel_xf(uv.x, uv.y, 0.012)
	add_child(u)
	var bezel := src.get_node("Bezel") as MeshInstance3D
	var gasket := src.get_node("Gasket") as MeshInstance3D
	for m: MeshInstance3D in [bezel, gasket]:
		var c := m.duplicate() as MeshInstance3D
		u.add_child(c)
	var mat := src.material.duplicate() as ShaderMaterial
	mat.set_shader_parameter(&"smudge_seed", Vector2(seed_v, seed_v + 1.1))
	var scr := MeshInstance3D.new()
	scr.mesh = src.screen.mesh
	scr.material_override = mat
	scr.position = src.screen.position
	u.add_child(scr)
