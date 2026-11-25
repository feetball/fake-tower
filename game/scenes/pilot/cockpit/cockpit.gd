class_name PilotCockpit
extends Node3D
## Assembles the flight deck: shell, windshield, display units, glareshield
## controls, gear panel, pedestal, annunciators and the interior lighting,
## and lists every mouse-operable control for the view's picker.

const L := preload("res://scenes/pilot/cockpit/cockpit_layout.gd")

var shell: CockpitShell
var windshield: CockpitWindshield
var lights: CockpitLights
var displays: CockpitDisplays
var glareshield: CockpitGlareshieldPanel
var annunciators: CockpitAnnunciators
var gear: CockpitGearPanel
var pedestal: CockpitPedestal


func _ready() -> void:
	shell = _add(CockpitShell.new(), "Shell") as CockpitShell
	windshield = _add(CockpitWindshield.new(), "Windshield") as CockpitWindshield
	displays = _add(CockpitDisplays.new(), "Displays") as CockpitDisplays
	glareshield = _add(CockpitGlareshieldPanel.new(), "Glareshield") as CockpitGlareshieldPanel
	annunciators = _add(CockpitAnnunciators.new(), "Annunciators") as CockpitAnnunciators
	gear = _add(CockpitGearPanel.new(), "GearPanel") as CockpitGearPanel
	pedestal = _add(CockpitPedestal.new(), "Pedestal") as CockpitPedestal
	lights = _add(CockpitLights.new(), "Lights") as CockpitLights
	# Keep the cloud out of the flight deck: subtract the volumetric fog in here.
	var clear := FogVolume.new()
	clear.name = "NoFogInside"
	clear.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	clear.size = Vector3(2.6, 2.0, 2.4)
	clear.position = Vector3(L.CENTRE_X, -0.3, -0.25)
	var fm := FogMaterial.new()
	fm.density = -1.0
	fm.edge_fade = 0.05
	clear.material = fm
	add_child(clear)


func _add(n: Node3D, node_name: String) -> Node3D:
	n.name = node_name
	add_child(n)
	return n


## Wire the parts to the data bus and the autopilot (call once, after _ready).
func setup(bus: PilotAvionicsBus, ap: PilotAutopilot, quality: String) -> void:
	displays.setup(bus, resolution_for(quality))
	windshield.add_display_reflections([displays.pfd, displays.nd, displays.eicas])
	glareshield.setup(ap, bus)
	annunciators.setup(bus)
	gear.setup(ap, bus)
	pedestal.setup(ap, bus)


func controls() -> Array[CockpitControl]:
	var out: Array[CockpitControl] = []
	out.append_array(glareshield.controls)
	out.append_array(annunciators.controls)
	out.append_array(gear.controls)
	out.append_array(pedestal.controls)
	return out


func set_quality(q: String) -> void:
	if displays.pfd != null:
		displays.set_resolution(resolution_for(q))


static func resolution_for(q: String) -> int:
	match q:
		"low":
			return 512
		"medium":
			return 768
	return 1024
