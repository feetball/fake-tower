extends Node
## Headless proof that the touch UI drives the game: injects real
## InputEventScreenTouch / InputEventScreenDrag events (Input.parse_input_event,
## so Godot's touch-to-mouse emulation runs as on a phone) into the full main
## scene in an offline demo round and checks the game state.
##
##   godot --headless --path game res://ui/touch/dev/touch_sim.tscn -- --touch --sim=pilot
##   godot --headless --path game res://ui/touch/dev/touch_sim.tscn -- --touch --sim=controller
##
## Prints PASS/FAIL per check and exits 0 only when all passed.

const MAIN := preload("res://scenes/main.tscn")
const Fmt := preload("res://scenes/controller/scope/scope_format.gd")

var _fails := 0
var _passes := 0


func _ready() -> void:
	TouchMode.force(1)
	get_window().size = Vector2i(1920, 1080)
	add_child(MAIN.instantiate())
	await _frames(3)
	var mode := "pilot"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sim="):
			mode = a.trim_prefix("--sim=")
	await _menu_fits()
	if mode == "controller":
		await _controller()
	else:
		await _pilot()
	print("SUMMARY touch_sim %s: %d passed, %d failed" % [mode, _passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


# --- main menu -----------------------------------------------------------------

## With the touch-sized items and the join form open, the whole menu column (down to
## its last item) stays on the 1080-high canvas.
func _menu_fits() -> void:
	var panel := _find(get_tree().root, "MainMenuPanel") as MainMenuPanel
	if panel == null:
		panel = _find_class_main_menu(get_tree().root)
	_check("main menu panel present", panel != null)
	if panel == null:
		return
	panel.open_join_form()
	await _frames(3)
	var items: Array = panel.get(&"_items")
	var last := items[items.size() - 1] as Button
	var bottom := last.get_global_rect().end.y
	var h := get_viewport().get_visible_rect().size.y
	_check("menu with the join form open fits: last item '%s' ends at %.0f of %.0f" % [last.text, bottom, h],
		bottom <= h - 8.0)


func _find_class_main_menu(n: Node) -> MainMenuPanel:
	if n is MainMenuPanel:
		return n as MainMenuPanel
	for c in n.get_children():
		var r := _find_class_main_menu(c)
		if r != null:
			return r
	return null


# --- pilot ---------------------------------------------------------------------

func _pilot() -> void:
	Session.start_demo("pilot")
	await _seconds(2.5)
	var hud := get_tree().get_first_node_in_group(&"radio_hud") as RadioHud
	var ptt := hud.get_node_or_null(^"TouchPtt") as TouchButton
	_check("HUD shows the touch PTT button", ptt != null and ptt.is_visible_in_tree())
	var tc := _find(get_tree().root, "TouchControls") as PilotTouchControls
	_check("pilot touch controls present", tc != null)
	if ptt == null or tc == null:
		return
	var me := Session.my_id

	# Finger 0 holds PTT.
	await _touch(0, _centre(ptt), true)
	await _seconds(0.2)
	_check("PTT finger down -> Session.radio_tx has me", Session.radio_tx.has(me))

	# Finger 1 (other hand) focuses HDG and taps + twice while PTT stays held.
	var hdg0 := int(Session.own.get("sel_hdg", 0))
	await _tap(1, _centre(tc.get(&"_tabs")["hdg"]))
	var plus := tc.get(&"_plus") as TouchButton
	await _tap(1, _centre(plus))
	await _tap(1, _centre(plus))
	await _seconds(0.6)
	var hdg1 := int(Session.own.get("sel_hdg", 0))
	_check("strip + x2 with PTT held -> own.sel_hdg %d -> %d" % [hdg0, hdg1], hdg1 == posmod(hdg0 + 2, 360))
	_check("PTT still keyed after the other finger's taps", Session.radio_tx.has(me))

	# ALT with the ×10 toggle.
	var alt0 := int(Session.own.get("sel_alt", 0))
	await _tap(1, _centre(tc.get(&"_tabs")["alt"]))
	await _tap(1, _centre(tc.get(&"_big")))
	await _tap(1, _centre(tc.get(&"_minus")))
	await _seconds(0.6)
	var alt1 := int(Session.own.get("sel_alt", 0))
	_check("ALT ×10 − -> own.sel_alt %d -> %d" % [alt0, alt1], alt1 == clampi(alt0 - 1000, 0, 20000))

	# Gear and flaps buttons.
	var gear0 := bool(Session.own.get("gear_down", false))
	await _tap(1, _centre(tc.get(&"_gear")))
	await _seconds(0.5)
	_check("GEAR button toggles own.gear_down", bool(Session.own.get("gear_down", false)) != gear0)
	var flaps0 := int(Session.own.get("flaps", 0))
	await _tap(1, _centre(tc.get(&"_flaps_dn")))
	await _seconds(0.5)
	_check("FLAPS DN -> own.flaps %d -> %d" % [flaps0, int(Session.own.get("flaps", 0))],
		int(Session.own.get("flaps", 0)) == mini(flaps0 + 1, 3))

	# Cockpit controls touched directly in the 3D panel view (no emulated mouse).
	var pv := _find(get_tree().root, "PilotView") as PilotView
	var cam := tc.rig.camera
	var app_ctl := _control_with(pv.interaction, "APPR")
	var hdg_ctl := _control_with(pv.interaction, "heading")
	_check("found the APPR button and HDG knob in the cockpit", app_ctl != null and hdg_ctl != null)
	if app_ctl != null and hdg_ctl != null:
		var armed0 := bool(Session.own.get("app_armed", false))
		await _tap(1, cam.unproject_position(app_ctl.global_position))
		await _seconds(0.5)
		_check("tap on the glareshield APPR button toggles app_armed",
			bool(Session.own.get("app_armed", false)) != armed0)
		var h0 := int(Session.own.get("sel_hdg", 0))
		var kp := cam.unproject_position(hdg_ctl.global_position)
		await _drag(1, kp, kp + Vector2(130, 0), 10) # 130 px / 26 px per step = 5 steps
		await _seconds(0.6)
		var h1 := int(Session.own.get("sel_hdg", 0))
		_check("dragging the HDG knob turns it (%d -> %d)" % [h0, h1], h1 == posmod(h0 + 5, 360))

	# View button and a look-around drag on the 3D view, still with PTT held.
	var rig := tc.rig
	await _tap(1, _centre(tc.get(&"_view_btns")["outside"]))
	_check("OUTSIDE button -> camera view 'outside'", rig.view_name == "outside")
	var yaw0: float = rig.get(&"_look_yaw")
	await _drag(1, Vector2(960, 500), Vector2(1160, 500), 6)
	_check("one-finger drag on the 3D view turns the head (yaw %.1f -> %.1f)" % [yaw0, float(rig.get(&"_look_yaw"))],
		absf(float(rig.get(&"_look_yaw")) - yaw0) > 5.0)

	await _touch(0, _centre(ptt), false)
	await _seconds(0.2)
	_check("PTT finger up -> Session.radio_tx empty", not Session.radio_tx.has(me))

	# Pinch on the 3D view (both fingers free now).
	await _touch(2, Vector2(860, 500), true)
	await _touch(3, Vector2(1060, 500), true)
	for i in 6:
		await _move(2, Vector2(860 - i * 30, 500), Vector2(-30, 0))
		await _move(3, Vector2(1060 + i * 30, 500), Vector2(30, 0))
	await _touch(2, Vector2(710, 500), false)
	await _touch(3, Vector2(1210, 500), false)
	_check("pinch out zooms in (zoom %.2f)" % float(rig.get(&"_zoom")), float(rig.get(&"_zoom")) < 0.9)

	# ATIS toggle.
	var efb := tc.efb
	await _tap(1, _centre(tc.get(&"_atis")))
	_check("ATIS button opens the EFB", efb.is_open and efb.page == "atis")
	await _tap(1, _centre(tc.get(&"_atis")))
	_check("ATIS button again closes it", not efb.is_open)


# --- controller ----------------------------------------------------------------

func _controller() -> void:
	Session.start_demo("controller")
	await _seconds(3.0)
	var view := _find(get_tree().root, "ControllerView")
	var hud := get_tree().get_first_node_in_group(&"radio_hud") as RadioHud
	var ptt := hud.get_node_or_null(^"TouchPtt") as TouchButton
	var bar := _find(get_tree().root, "TouchBar")
	_check("controller view, touch bar and PTT present", view != null and bar != null and ptt != null)
	if view == null or bar == null or ptt == null:
		return
	var scope: SubViewport = view.get(&"_scope")
	var screen: TextureRect = view.get(&"_scope_screen")
	var ctx: RefCounted = scope.get(&"ctx")
	var xf: RefCounted = ctx.get(&"xform")
	var model: RefCounted = ctx.get(&"model")
	var to_canvas := func(p: Vector2) -> Vector2:
		return screen.get_global_rect().position + p * screen.size / Vector2(scope.size)
	var plot_c: Vector2 = to_canvas.call((xf.get(&"plot") as Rect2).get_center())

	await _touch(0, _centre(ptt), true)
	await _seconds(0.2)
	_check("PTT held -> radio_tx has me", Session.radio_tx.has(Session.my_id))

	var k0 := float(xf.get(&"k"))
	await _touch(1, plot_c - Vector2(80, 0), true)
	await _touch(2, plot_c + Vector2(80, 0), true)
	for i in 6:
		await _move(1, plot_c - Vector2(80 + (i + 1) * 25, 0), Vector2(-25, 0))
		await _move(2, plot_c + Vector2(80 + (i + 1) * 25, 0), Vector2(25, 0))
	await _touch(1, plot_c - Vector2(230, 0), false)
	await _touch(2, plot_c + Vector2(230, 0), false)
	_check("pinch on scope zooms in while PTT held (k %.2f -> %.2f)" % [k0, float(xf.get(&"k"))], float(xf.get(&"k")) > k0 * 1.3)

	var c0: Vector2 = xf.get(&"center")
	await _drag(1, plot_c, plot_c + Vector2(150, 60), 6)
	_check("one-finger drag pans the scope", (xf.get(&"center") as Vector2).distance_to(c0) > 0.1)

	await _tap(1, plot_c)
	await _tap(1, plot_c)
	_check("double tap resets the view (k back to %.2f)" % k0, absf(float(xf.get(&"k")) - k0) < 0.01 * k0)

	# Tap a target to select it.
	await _seconds(2.5)
	var targets: Dictionary = model.get(&"targets")
	var cs := ""
	for c: String in targets:
		if String(targets[c].get("status", "")) == "flying":
			cs = c
			break
	_check("radar has a flying target", cs != "")
	if cs != "":
		var sp: Vector2 = xf.call(&"to_screen", Fmt.target_pos(targets[cs]))
		await _tap(1, to_canvas.call(sp))
		_check("tap on %s selects it" % cs, String(model.get(&"selected")) == cs)
		var ldr := _find_button(bar, "+45°")
		await _tap(1, _centre(ldr))
		_check("LDR +45° turns the data block", int((model.get(&"leader_dir") as Dictionary).get(cs, -1)) == 90)
		await _tap(1, _centre(_find_button(bar, "DESEL")))
		_check("DESEL deselects", String(model.get(&"selected")) == "")

	await _tap(1, _centre(_find_button(bar, "MEASURE")))
	await _drag(1, plot_c, plot_c + Vector2(200, -100), 6)
	_check("MEASURE + drag draws the range/bearing line", bool(ctx.get(&"rbl_active")))
	await _tap(1, _centre(_find_button(bar, "MEASURE")))

	var layers: Dictionary = model.get(&"layers")
	var ptl0 := bool(layers["ptl"])
	await _tap(1, _centre(_find_button(bar, "LAYERS")))
	await _tap(1, _centre(_find_button(bar, "PTL")))
	_check("LAYERS -> PTL toggles the layer", bool(layers["ptl"]) != ptl0)

	await _tap(1, _centre(_find_button(bar, "ROOM")))
	_check("ROOM toggles the room framing", bool(view.get(&"_camera").get(&"target_room")))

	await _touch(0, _centre(ptt), false)
	await _seconds(0.2)
	_check("PTT released -> radio_tx empty", not Session.radio_tx.has(Session.my_id))


# --- helpers -------------------------------------------------------------------

func _check(what: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if ok:
		_passes += 1
	else:
		_fails += 1


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = idx
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)
	await _frames(2)


func _move(idx: int, pos: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = idx
	d.position = pos
	d.relative = rel
	Input.parse_input_event(d)
	await _frames(1)


func _tap(idx: int, pos: Vector2) -> void:
	await _touch(idx, pos, true)
	await _touch(idx, pos, false)


func _drag(idx: int, from: Vector2, to: Vector2, steps: int) -> void:
	await _touch(idx, from, true)
	var prev := from
	for i in steps:
		var p := from.lerp(to, float(i + 1) / steps)
		await _move(idx, p, p - prev)
		prev = p
	await _touch(idx, to, false)


func _centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center() if c != null else Vector2(-1000, -1000)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _find(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := _find(c, nm)
		if f != null:
			return f
	return null


func _control_with(interaction: PilotInteraction, word: String) -> CockpitControl:
	for c in interaction.controls:
		if c.tooltip_text().to_lower().contains(word.to_lower()):
			return c
	return null


func _find_button(n: Node, txt: String) -> TouchButton:
	if n is TouchButton and (n as TouchButton).text == txt and (n as TouchButton).is_visible_in_tree():
		return n
	for c in n.get_children():
		var f := _find_button(c, txt)
		if f != null:
			return f
	return null
