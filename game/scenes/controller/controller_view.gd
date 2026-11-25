extends Node3D
## Controller view: a dark radar room with our position's two displays.
## "At the scope" (default) the camera looks straight at the displays and the
## scope and flight-data images are drawn as 2D overlays exactly over the 3D
## panels, so text is pixel-exact and mouse input maps 1:1. In the room
## framing (Tab) or while looking around (hold RMB off the scope) the overlays
## fade out and the same images are seen on the 3D panels.
##
## Debug user args (for screenshots): --ctrl-debug-targets, --ctrl-select=<cs>,
## --ctrl-framing=room, --ctrl-rbl, --ctrl-phr, --ctrl-scratch=<text>,
## --ctrl-ca-on, --ctrl-look=<yaw_deg>,<pitch_deg>, --ctrl-view=<x_nm>,<y_nm>,<range_nm>,
## --ctrl-layers=<key,...> (toggles, e.g. ptl)

const ScopeDisplay := preload("res://scenes/controller/scope/scope_display.gd")
const SidePanel := preload("res://scenes/controller/panel/side_panel.gd")
const Camera := preload("res://scenes/controller/camera/ctrl_camera.gd")
const Room := preload("res://scenes/controller/room/room.gd")
const AlertTones := preload("res://scenes/controller/audio/alert_tones.gd")
const DebugTargets := preload("res://scenes/controller/debug/debug_targets.gd")
const Fmt := preload("res://scenes/controller/scope/scope_format.gd")

const MIN_TOP := 70.0
const SIDE_MARGIN := 14.0
const BOTTOM_MARGIN := 12.0
const OVERLAY_FADE_IN := 8.0 ## per second
const OVERLAY_FADE_OUT := 14.0

@onready var _room: Room = $Room
@onready var _camera: Camera = $Camera
@onready var _scope: ScopeDisplay = $ScopeDisplay
@onready var _panel_vp: SubViewport = $PanelViewport
@onready var _screens: Control = $Overlay/Screens
@onready var _scope_screen: TextureRect = $Overlay/Screens/ScopeScreen
@onready var _panel_host: Control = $Overlay/Screens/PanelHost
@onready var _panel_glass: ColorRect = $Overlay/Screens/PanelGlass
@onready var _tones: AlertTones = $Alerts

var _panel: SidePanel
var _args: Dictionary = {}
var _debug := false
var _debug_last: Array = []
var _overlay_alpha := 1.0
var _reserved_top := -1.0
var _layout_timer := 0.0
var _side_rect := Rect2()
## Frames the flight-data SubViewport still has to render after a change (the
## rebuilt rows settle their layout a frame later).
var _panel_dirty := 0


func _ready() -> void:
	_parse_args()
	_debug = _args.has("ctrl-debug-targets")
	_camera.rig = _room.console.rig
	_camera.make_current()

	_panel = SidePanel.new()
	_panel.name = "SidePanel"
	_panel.model = _scope.ctx.model
	_panel_host.add_child(_panel)
	_panel_vp.disable_3d = true
	_panel_vp.transparent_bg = false
	_panel_vp.size_2d_override_stretch = true
	_panel_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

	_scope_screen.texture = _scope.get_texture()
	_room.console.rig.set_textures(_scope.get_texture(), _panel_vp.get_texture())

	_scope.alerts.connect(func(kinds: PackedStringArray) -> void:
		for k in kinds:
			_tones.alert(k))
	_scope.ctx.model.changed.connect(_panel.refresh)
	_scope.ctx.model.changed.connect(_mark_panel_dirty)
	_scope_screen.gui_input.connect(_on_scope_gui_input)
	_scope_screen.mouse_exited.connect(func() -> void: _scope.input.mouse_left())
	Session.radar_swept.connect(_on_radar)
	Session.round_event.connect(func(_e: Dictionary) -> void:
		_panel.refresh()
		_mark_panel_dirty())
	Session.round_began.connect(_on_round_began)
	get_viewport().size_changed.connect(_layout)

	_on_round_began()
	if not Session.radar.is_empty() and not _debug:
		_on_radar(Session.radar)
	_layout.call_deferred()
	if get_tree().current_scene == self:
		_start_standalone.call_deferred()
	if _debug:
		_start_debug.call_deferred()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ctrl-") or a.begins_with("--demo"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else ""


## Run on its own (no main scene): start the offline demo unless Session already did.
func _start_standalone() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if Session.phase != "playing":
		var role := String(_args.get("demo", "controller"))
		Session.start_demo(role if role != "" else "controller")


func _start_debug() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_on_round_began()
	_panel.extra_events = DebugTargets.EVENTS.duplicate()
	for sweep in DebugTargets.sweeps():
		_scope.ingest(sweep)
		_debug_last = sweep
	var sel := String(_args.get("ctrl-select", ""))
	if _args.has("ctrl-scratch") and sel != "":
		_scope.ctx.model.set_scratch(sel, String(_args["ctrl-scratch"]))
	if sel != "":
		_scope.ctx.model.select(sel)
	if _args.has("ctrl-rbl"):
		var m := _scope.ctx.model
		_scope.ctx.rbl_active = true
		_scope.ctx.rbl_a = Fmt.target_pos(m.targets["SKW412"])
		_scope.ctx.rbl_b = Fmt.target_pos(m.targets["ASA277"])
	_scope.ctx.force_flash = _args.has("ctrl-ca-on")
	if _args.has("ctrl-view"):
		var v := String(_args["ctrl-view"]).split_floats(",")
		if v.size() == 3:
			var xf := _scope.ctx.xform
			xf.center = Vector2(v[0], v[1])
			xf.k = minf(xf.plot.size.x, xf.plot.size.y) * 0.5 / maxf(v[2], 1.0)
			xf.user_moved = true
	for key in String(_args.get("ctrl-layers", "")).split(",", false):
		_scope.ctx.model.toggle_layer(key)
	if _args.has("ctrl-phr"):
		_panel.set_phraseology_open(true)
	if String(_args.get("ctrl-framing", "")) == "room":
		_camera.target_room = true
		_camera.blend = 1.0
	if _args.has("ctrl-look"):
		var parts := String(_args["ctrl-look"]).split(",")
		_camera.looking = true
		_camera.look = Vector2(deg_to_rad(float(parts[0])), deg_to_rad(float(parts[1]) if parts.size() > 1 else 0.0))
	_panel.refresh()
	_scope.redraw_all()


func _on_round_began() -> void:
	var world: Dictionary = Session.world if not Session.world.is_empty() else World.DATA
	_scope.set_world(world)
	_panel.refresh_static()
	_panel.refresh()
	_update_status()


func _on_radar(targets: Array) -> void:
	if _debug:
		return
	_scope.ingest(targets)
	_panel.refresh()


func _update_status() -> void:
	var st := _scope.ctx.status
	var world := _scope.ctx.world
	st["icao"] = String(world.get("icao", "KFTW"))
	st["time"] = Session.round_time
	st["atis_letter"] = String(Session.atis.get("letter", "-"))
	st["qnh"] = Session.atis.get("qnh", "----")


# --- layout ----------------------------------------------------------------

func _hud_top() -> float:
	var hud := get_tree().get_first_node_in_group(&"radio_hud")
	if hud != null and hud.has_method(&"get_reserved_top_px"):
		return maxf(MIN_TOP, float(hud.call(&"get_reserved_top_px")) + 10.0)
	return MIN_TOP


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	if view.x < 16.0 or view.y < 16.0:
		return
	_reserved_top = _hud_top()
	var avail := Rect2(SIDE_MARGIN, _reserved_top, view.x - SIDE_MARGIN * 2.0, view.y - _reserved_top - BOTTOM_MARGIN)
	var lay := _camera.scope_layout(view, avail)
	var scale := float(get_tree().root.size.y) / view.y
	var main_r := _snap(lay["main"], scale)
	_side_rect = _snap(lay["side"], scale)
	_scope_screen.position = main_r.position
	_scope_screen.size = main_r.size
	_scope.resize_to(Vector2i((main_r.size * scale).round()), scale)
	_panel_host.position = _side_rect.position
	_panel_host.size = _side_rect.size
	_panel_glass.position = _side_rect.position
	_panel_glass.size = _side_rect.size
	_panel.set_text_scale(clampf(0.85 / scale, 1.0, 1.3))
	_panel.position = Vector2.ZERO
	_panel.size = _side_rect.size
	_panel_vp.size = Vector2i((_side_rect.size * scale).round())
	_panel_vp.size_2d_override = Vector2i(_side_rect.size.round())
	var glass := _scope_screen.material as ShaderMaterial
	if glass != null:
		glass.set_shader_parameter("aspect", Vector2(main_r.size.x / main_r.size.y, 1.0))


## Rect snapped to the physical pixel grid (canvas units in, canvas units out).
func _snap(r: Rect2, scale: float) -> Rect2:
	var p := (r.position * scale).round()
	var e := (r.end * scale).round()
	return Rect2(p / scale, (e - p) / scale)


# --- per frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	_update_status()
	_layout_timer += delta
	if _layout_timer > 0.5:
		_layout_timer = 0.0
		if not is_equal_approx(_hud_top(), _reserved_top):
			_layout()
	# Wall clock, not delta: frame deltas are clamped when rendering is very slow.
	if _debug and not _debug_last.is_empty() \
			and _scope.ctx.model.sweep_age_sec(Time.get_ticks_msec()) >= DebugTargets.SWEEP_SEC:
		_scope.ingest(_debug_last)
	_update_presentation(delta)


## Overlay when exactly at the scope, 3D panels otherwise. The flight-data
## panel moves into its SubViewport while the 3D panel is what is seen.
func _update_presentation(delta: float) -> void:
	var want := _camera.at_scope()
	if want:
		_overlay_alpha = move_toward(_overlay_alpha, 1.0, delta * OVERLAY_FADE_IN)
	else:
		_overlay_alpha = move_toward(_overlay_alpha, 0.0, delta * OVERLAY_FADE_OUT)
	_screens.visible = _overlay_alpha > 0.0
	_screens.modulate.a = _overlay_alpha
	var in_overlay := _panel.get_parent() == _panel_host
	if want and not in_overlay:
		_move_panel(_panel_host)
	elif not want and in_overlay and _overlay_alpha <= 0.0:
		_move_panel(_panel_vp)
		_mark_panel_dirty()
	if _panel_dirty > 0 and _panel.get_parent() == _panel_vp:
		_panel_dirty -= 1
		_panel_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _mark_panel_dirty() -> void:
	_panel_dirty = 3


func _move_panel(to: Node) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and _panel.is_ancestor_of(focus):
		focus.release_focus()
	_panel.get_parent().remove_child(_panel)
	to.add_child(_panel)
	_panel.position = Vector2.ZERO
	_panel.size = _side_rect.size


# --- input -----------------------------------------------------------------

func _on_scope_gui_input(e: InputEvent) -> void:
	if not e is InputEventMouse:
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		get_viewport().gui_release_focus()
	var local := (e as InputEventMouse).position
	var p := local * Vector2(_scope.size) / _scope_screen.size
	if _scope.input.pointer(e, p):
		_scope_screen.accept_event()


func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mb.pressed:
			var over_scope := _screens.visible and _scope_screen.get_global_rect().has_point(mb.position)
			if over_scope or mb.position.y < _reserved_top - 8.0:
				return
			_camera.looking = true
			get_viewport().set_input_as_handled()
		elif _camera.looking:
			_camera.looking = false
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion and _camera.looking:
		_camera.look_by((e as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_TAB:
		if _typing():
			return
		if not (e as InputEventKey).echo:
			_camera.toggle_framing()
		get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if not e is InputEventKey or _typing():
		return
	if _scope.input.key(e as InputEventKey):
		get_viewport().set_input_as_handled()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit
