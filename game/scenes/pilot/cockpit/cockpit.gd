class_name PilotCockpit
extends Node3D
## Assembles the flight deck: shell, windshield, display units, glareshield
## controls, pedestal, annunciators and the interior lighting. Exposes the
## parts the view wires to data and input.

const L := preload("res://scenes/pilot/cockpit/cockpit_layout.gd")

var shell: CockpitShell
var lights: CockpitLights


func _ready() -> void:
	shell = CockpitShell.new()
	shell.name = "Shell"
	add_child(shell)
	lights = CockpitLights.new()
	lights.name = "Lights"
	add_child(lights)
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


func set_quality(_q: String) -> void:
	pass
