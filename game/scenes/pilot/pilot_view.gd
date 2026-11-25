class_name PilotView
extends Node3D
## The pilot's view: a procedural airliner flight deck on an instrument
## approach at night in fog. Floating origin: the aircraft (cockpit + camera)
## stays at the scene origin with its attitude, and the outside world is
## translated by minus the eye position every frame, so ±40 nm coordinates
## never reach the GPU. Runs under main's View node, or standalone
## (`--demo=pilot`), in which case it starts the demo itself if needed.
##
## Debug user args for screenshots:
##   --pilot-debug-pos=<dme_nm>,<height_ft_above_field>  freeze on the final approach
##   --pilot-view=panel|outside|pedestal   --pilot-efb=plate|atis
##   --pilot-debug-warn=TERRAIN,PULL UP    --pilot-debug-outcome=<outcome>
##   --pilot-debug-wx=<visibility_m>,<ceiling_ft>   --pilot-quality=low|medium|high
##   --pilot-debug-light (work light)      --pilot-debug-hover=<x>,<y> (fake mouse)

const COCKPIT_LAYER := 2 ## render layer bit for the flight deck (exterior lights skip it)
const LANDED_CAPTION_KT := 40.0

## Quality hook: volumetric fog on/off, display resolution, SSR.
@export_enum("low", "medium", "high") var quality := "high":
	set(v):
		quality = v
		if is_node_ready():
			_apply_quality()

@onready var flight: PilotFlightState = $FlightState
@onready var autopilot: PilotAutopilot = $Autopilot
@onready var bus: PilotAvionicsBus = $AvionicsBus
@onready var outside: PilotOutside = $Outside
@onready var aircraft: Node3D = $Aircraft
@onready var cockpit: PilotCockpit = $Aircraft/Cockpit
@onready var rig: PilotCameraRig = $Aircraft/CameraRig
@onready var ext_lights: PilotAircraftLights = $Aircraft/ExteriorLights
@onready var interaction: PilotInteraction = $Interaction
@onready var audio: PilotCockpitAudio = $Audio
@onready var efb: PilotEfb = $Overlay/Efb
@onready var outcome_overlay: PilotOutcomeOverlay = $Overlay/Outcome
@onready var hint: PilotViewHint = $Overlay/Hint
@onready var tooltip: Label = $Overlay/Tooltip

var _landed_t := -1.0
var _fuel_cut_t := -1.0


func _ready() -> void:
	bus.flight = flight
	bus.ap = autopilot
	cockpit.setup(bus, autopilot, quality)
	_assign_layers(cockpit)
	interaction.camera = rig.camera
	interaction.controls = cockpit.controls()
	interaction.tooltip = tooltip
	audio.avionics = bus
	audio.flight = flight
	_style_tooltip()
	autopilot.commanded.connect(func(k: String) -> void: audio.click(k in ["app", "gear", "flaps"]))
	flight.touchdown.connect(_on_touchdown)
	flight.crashed.connect(_on_crashed)
	flight.sample.connect(_on_sample)
	efb.visibility_changed_to.connect(func(open: bool) -> void: interaction.enabled = not open)
	rig.view_changed.connect(func(_v: String) -> void: hint.flash(2.5))
	_apply_debug_args()
	_apply_quality()
	_apply_reserved_top.call_deferred()
	if Session.phase != "playing" and get_parent() == get_tree().root:
		_start_standalone_demo.call_deferred()


## Standalone run: Session already starts --demo itself (deferred); only start
## one if nothing did.
func _start_standalone_demo() -> void:
	if Session.phase == "playing":
		return
	var role := _arg("--demo=")
	Session.start_demo(role if role != "" else "pilot")


func _process(delta: float) -> void:
	aircraft.transform = Transform3D(flight.attitude(), Vector3.ZERO)
	outside.set_eye(flight.eye_position())
	var cloud := outside.in_cloud
	rig.turbulence = 0.12 + cloud * 0.7 if not flight.on_ground else clampf(flight.gs / 140.0, 0.0, 1.0) * 0.5
	rig.update_motion(delta, flight.bank)
	var wet := 0.22 + 0.78 * cloud
	cockpit.windshield.set_conditions(wet, bus.ias)
	audio.wetness = wet
	ext_lights.gear_down = bus.gear_pos > 0.5
	_check_landed(delta)


func _on_sample(own: Dictionary) -> void:
	if String(own.get("status", "")) == "crashed" and not outcome_overlay.is_crashed():
		# Joined (or debug-forced) after the crash: no run-down, just the end.
		_on_crashed(String(own.get("outcome", "terrain")))


func _on_touchdown(sink_fpm: float) -> void:
	rig.jolt(clampf(0.012 + absf(sink_fpm) / 20000.0, 0.012, 0.04))
	audio.touchdown(sink_fpm)


func _on_crashed(outcome: String) -> void:
	audio.crash(outcome)
	var cs := String(flight.own.get("callsign", Session.my_callsign))
	if outcome == "fuel":
		# Power fails as the engines run down; then the cut.
		_fuel_cut_t = 0.0
		outcome_overlay.show_crash(outcome, cs, 2.6)
		var tw := create_tween()
		for u in [cockpit.displays.pfd, cockpit.displays.nd, cockpit.displays.eicas]:
			tw.parallel().tween_method(func(p: float) -> void: (u as PilotDisplayUnit).material.set_shader_parameter(&"power", p), 1.0, 0.0, 1.8).set_delay(0.6)
	else:
		outcome_overlay.show_crash(outcome, cs)
		ext_lights.set_powered(false)
		rig.jolt(0.08)


func _check_landed(delta: float) -> void:
	if flight.status != "landed":
		return
	if flight.on_ground:
		_landed_t = maxf(_landed_t, 0.0) + delta
	if flight.on_ground and (flight.gs < LANDED_CAPTION_KT or _landed_t > 14.0):
		outcome_overlay.show_landed(String(flight.own.get("callsign", "")))


func _apply_quality() -> void:
	outside.set_quality(quality)
	cockpit.set_quality(quality)
	ext_lights.set_volumetric(quality != "low")


## The flight deck renders on its own layer so the exterior lights (strobes,
## landing lights) do not light it through the hull, and its own lights only
## light it.
func _assign_layers(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 1 << (COCKPIT_LAYER - 1)
	if n is Light3D:
		(n as Light3D).light_cull_mask = 1 << (COCKPIT_LAYER - 1)
	for c in n.get_children():
		_assign_layers(c)
	if n == cockpit:
		for l in ext_lights.get_children():
			if l is Light3D:
				(l as Light3D).light_cull_mask = ~(1 << (COCKPIT_LAYER - 1))


## Keep the EFB and tooltip clear of the HUD strip main draws on top.
func _apply_reserved_top() -> void:
	var px := 70.0
	var hud := get_tree().get_first_node_in_group(&"radio_hud")
	if hud != null and hud.has_method(&"get_reserved_top_px"):
		px = maxf(float(hud.call(&"get_reserved_top_px")) + 12.0, 70.0)
	efb.top_reserved = px


func _style_tooltip() -> void:
	tooltip.visible = false
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.025, 0.03, 0.86)
	sb.border_color = Color(0.45, 0.75, 1.0, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	tooltip.add_theme_stylebox_override(&"normal", sb)
	tooltip.add_theme_font_override(&"font", Avionics.sans(false))
	tooltip.add_theme_font_size_override(&"font_size", 18)
	tooltip.add_theme_color_override(&"font_color", Color(0.85, 0.9, 0.95))


func _apply_debug_args() -> void:
	var q := _arg("--pilot-quality=")
	if q in ["low", "medium", "high"]:
		quality = q
	var pos := _arg("--pilot-debug-pos=")
	if pos != "":
		var p := pos.split(",")
		if p.size() >= 2:
			flight.set_debug_pose(float(p[0]), float(p[1]))
	var v := _arg("--pilot-view=")
	if v != "":
		rig.start_view = v
		rig.set_view(v, true)
	if OS.get_cmdline_user_args().has("--pilot-debug-light"):
		var o := OmniLight3D.new()
		o.light_energy = 2.0
		o.omni_range = 5.0
		o.position = Vector3(0.3, 0.1, 0.3)
		aircraft.add_child(o)
	var wx := _arg("--pilot-debug-wx=")
	if wx != "":
		var w := wx.split(",")
		if w.size() >= 2:
			outside.debug_weather(float(w[0]), float(w[1]))
	var warn := _arg("--pilot-debug-warn=")
	if warn != "":
		bus.debug_warnings = Array(warn.split(","))
	var page := _arg("--pilot-efb=")
	if page != "":
		efb.show_page.call_deferred(page)
	var oc := _arg("--pilot-debug-outcome=")
	if oc != "":
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if oc == "landed":
				outcome_overlay.show_landed(Session.my_callsign)
			else:
				outcome_overlay.force_crash(oc, Session.my_callsign))
	var hov := _arg("--pilot-debug-hover=")
	if hov != "":
		var hp := hov.split(",")
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			Input.warp_mouse(Vector2(float(hp[0]), float(hp[1]))))


static func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""
