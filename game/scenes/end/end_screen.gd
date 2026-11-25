class_name EndScreen
extends Control
## Round result over the frozen view: winner, the reveal of the real tower and
## the impostor, each aircraft's outcome, timeline, and the host's
## "Back to lobby" (everyone else waits for the host).

var _banner: Label
var _sub: Label
var _reveal: HBoxContainer
var _table: GridContainer
var _timeline: VBoxContainer
var _back: Button
var _wait: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.005, 0.01, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var body := UiKit.vbox(22)
	body.custom_minimum_size = Vector2(1040.0, 0.0)
	center.add_child(UiKit.panel(&"Glass", body))

	body.add_child(UiKit.heading("Round over"))
	_banner = UiKit.label("", &"Title")
	_banner.add_theme_font_override(&"font", UiTheme.display(300, 14))
	_banner.add_theme_font_size_override(&"font_size", 76)
	body.add_child(_banner)
	_sub = UiKit.label("", &"Tagline", true)
	_sub.add_theme_font_size_override(&"font_size", 21)
	body.add_child(_sub)

	_reveal = UiKit.hbox(14)
	body.add_child(_reveal)

	_table = GridContainer.new()
	_table.columns = 3
	_table.add_theme_constant_override(&"h_separation", 40)
	_table.add_theme_constant_override(&"v_separation", 10)
	body.add_child(UiKit.panel(&"Inset", _table))

	_timeline = UiKit.vbox(4)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 118.0)
	scroll.add_child(_timeline)
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(UiKit.vbox(8, [UiKit.heading("Timeline"), scroll]))

	body.add_child(UiKit.hsep())
	_back = UiKit.button("Back to lobby", &"Primary", func() -> void: Sess.invoke(&"return_to_lobby"))
	_wait = UiKit.label("", &"Dim", true)
	_wait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(UiKit.hbox(16, [_wait, _back]))
	Sess.connect_signal(&"round_ended", func(_r: Dictionary) -> void: refresh())


func refresh() -> void:
	var r := Sess.result()
	var tower := str(r.get("winner", "")) == "tower"
	var col := UiTheme.ACCENT if tower else UiTheme.RED
	_banner.text = "TOWER WINS" if tower else "IMPOSTOR WINS"
	_banner.add_theme_color_override(&"font_color", col.lerp(Color.WHITE, 0.15))
	var outcomes: Array = r.get("outcomes", [])
	var landed := 0
	for o: Variant in outcomes:
		if o is Dictionary and str(o.get("outcome", "")) == "landed":
			landed += 1
	_sub.text = "%d of %d aircraft landed — %s  Round time %s." % [landed, outcomes.size(),
		"more than half made it down." if tower else "not more than half made it down.",
		UiText.mmss(float(r.get("duration_sec", Sess.round_time())))]

	var me := Sess.my_id()
	var imp := int(r.get("impostor_id", 0))
	var real := int(r.get("real_controller_id", 0))
	var you_won := (tower and me != imp) or (not tower and me == imp)
	for c in _reveal.get_children():
		c.queue_free()
	_reveal.add_child(_card("Real tower", Sess.player_name(real), UiTheme.ACCENT))
	_reveal.add_child(_card("Impostor", Sess.player_name(imp), UiTheme.RED))
	_reveal.add_child(_card("You", "WON" if you_won else "LOST", UiTheme.ACCENT if you_won else UiTheme.DIM))

	for c in _table.get_children():
		c.queue_free()
	for h in ["Callsign", "Pilot", "Outcome"]:
		_table.add_child(UiKit.heading(h))
	for o: Variant in outcomes:
		if not o is Dictionary:
			continue
		var pid := int(o.get("player_id", 0))
		var cs := UiKit.label(str(o.get("callsign", "")), &"Mono")
		var nm := UiKit.label(Sess.player_name(pid) + ("  (you)" if pid == me else ""), &"")
		var oc := str(o.get("outcome", ""))
		var out := UiKit.label(UiText.outcome_text(oc), &"")
		out.add_theme_color_override(&"font_color", UiText.outcome_color(oc))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_table.add_child(cs)
		_table.add_child(nm)
		_table.add_child(out)

	for c in _timeline.get_children():
		c.queue_free()
	var evs := Sess.events()
	if evs.is_empty():
		_timeline.add_child(UiKit.label("No events recorded.", &"Small"))
	for e: Variant in evs:
		if e is Dictionary:
			var t := UiKit.label(UiText.mmss(float(e.get("time", 0.0))), &"MonoSmall")
			var txt := UiKit.label(UiText.event_text(e), &"Small")
			txt.add_theme_color_override(&"font_color", UiText.outcome_color(str(e.get("kind", ""))).lerp(UiTheme.TEXT, 0.35))
			_timeline.add_child(UiKit.hbox(14, [t, txt]))

	var host := Sess.is_host()
	_back.visible = host
	_wait.text = "Open mic is live again." if host \
		else "Open mic is live again. Waiting for the host to return everyone to the lobby."
	if host:
		_back.grab_focus.call_deferred()


func _card(title: String, value: String, col: Color) -> PanelContainer:
	var v := UiKit.vbox(4, [UiKit.heading(title)])
	var l := UiKit.label(value, &"Big")
	l.add_theme_color_override(&"font_color", col.lerp(Color.WHITE, 0.2))
	v.add_child(l)
	var p := UiKit.panel(&"Inset", v)
	p.add_theme_stylebox_override(&"panel", UiTheme.flat(Color(col, 0.06), Color(col, 0.35), 1, 2, 20, 14))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p
