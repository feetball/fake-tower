class_name PilotDatalink
extends Control
## The pilot's text radio (core/net/datalink.gd): the latest transmissions on the
## frequency, top right under the radio strip, clearances for our callsign marked;
## reply buttons for the newest one (W WILCO, U UNABLE, S STANDBY, R SAY AGAIN; the
## ▾ next to UNABLE gives a reason) and a CALLS row (C): check in, request vectors,
## established, minimum fuel, mayday, going around, and calling a controller out.
## T shows more lines. Our own message shows "waiting" until the frequency is clear;
## a blocked or unsent one gets a RESEND button. Hidden when nobody is on frequency.
## Everything goes through Session.send_dl; nothing here decides what is said.

const Datalink := preload("res://core/net/datalink.gd")

const WIDTH := 700.0
const MARGIN := 22.0
const ROWS_SHORT := 3
const ROWS_LONG := 8
const ROWS_TOUCH_MAX := 5
const NOTICE_MS := 3000
## Each controller keeps one colour, so the two "Fallow Approach" voices stay apart.
const CTL_COLORS: Array[Color] = [Color(0.56, 0.93, 0.76), Color(0.8, 0.66, 1.0), Color(1.0, 0.82, 0.5)]
const PILOT_COLOR := Color(0.55, 0.78, 1.0)
const UNABLE_REASONS: Array[Array] = [
	["msa", "Below the MSA"], ["qnh", "QNH is not the ATIS"], ["terrain", "Terrain"], ["fuel", "Fuel"],
]
const CALLS: Array[Array] = [
	["checkin", "CHECK IN"], ["req_vectors", "REQUEST VECTORS"], ["established", "ESTABLISHED"],
	["min_fuel", "MIN FUEL"], ["mayday_fuel", "MAYDAY FUEL"], ["going_around", "GOING AROUND"],
]

var top_reserved := 70.0:
	set(v):
		top_reserved = v
		if is_node_ready():
			_layout()
## Hidden for good (not used by the pilot view: a crashed pilot still listens).
var suppressed := false:
	set(v):
		suppressed = v
		if is_node_ready():
			refresh()
## More lines (T).
var long := false
## Fewer lines while the EFB is open, so the chart stays readable.
var compact := false:
	set(v):
		compact = v
		if is_node_ready():
			refresh()

var _box: PanelContainer
var _rows: VBoxContainer
var _head_status: Label
var _reply_bar: HBoxContainer
var _reply_label: Label
var _unable_bar: HFlowContainer
var _calls_bar: HFlowContainer
var _calls_btn: Button
var _more_btn: Button
var _reply_to: Dictionary = {}
var _notice: Array = [] ## [text, until ticks msec]: a refused send, shown in the header
var _answered: Dictionary = {} ## message id -> true once we replied
var _touch := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	_touch = TouchMode.active()
	_build()
	Sess.connect_signal(&"datalink", func(_m: Dictionary) -> void: refresh())
	Sess.connect_signal(&"round_began", func() -> void:
		_answered.clear()
		refresh())
	Sess.connect_signal(&"radio_changed", func(_tx: Array) -> void: _refresh_status())
	get_viewport().size_changed.connect(_layout)
	refresh()
	_layout.call_deferred()


## Something to show: a controller on frequency (or anything said already).
func wanted() -> bool:
	if not UiText.controller_names().is_empty():
		return true
	return not (Sess.val(&"dl_log", []) as Array).is_empty()


func _build() -> void:
	_box = PanelContainer.new()
	_box.name = "DatalinkBox"
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.add_theme_stylebox_override(&"panel", UiTheme.flat(Color(0.012, 0.016, 0.02, 0.84), Color(1, 1, 1, 0.09), 1, 3, 14, 10))
	add_child(_box)
	var col := UiKit.vbox(8)
	_box.add_child(col)

	var head := UiKit.hbox(10)
	var title := UiKit.label("DATALINK  119.850", &"MonoSmall")
	title.add_theme_color_override(&"font_color", UiTheme.DIM)
	head.add_child(title)
	_head_status = UiKit.label("", &"MonoSmall")
	_head_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head_status.clip_text = true
	head.add_child(_head_status)
	_calls_btn = _small("CALLS  C", func() -> void: _toggle_calls())
	head.add_child(_calls_btn)
	_more_btn = _small("MORE  T", func() -> void: _toggle_more())
	head.add_child(_more_btn)
	col.add_child(head)

	_rows = UiKit.vbox(4)
	col.add_child(_rows)

	_reply_bar = UiKit.hbox(8)
	_reply_label = UiKit.label("", &"MonoSmall")
	_reply_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_reply_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reply_label.clip_text = true
	_reply_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_reply_bar.add_child(_reply_label)
	_reply_bar.add_child(_reply_button("WILCO  W", UiTheme.ACCENT, func() -> void: _reply("wilco", "")))
	_reply_bar.add_child(_reply_button("UNABLE  U", UiTheme.RED, func() -> void: _reply("unable", "")))
	var why := _reply_button("WHY ▾", UiTheme.RED, func() -> void:
		_unable_bar.visible = not _unable_bar.visible
		_box.reset_size.call_deferred())
	why.tooltip_text = "Unable, with a reason"
	_reply_bar.add_child(why)
	_reply_bar.add_child(_reply_button("STANDBY  S", UiTheme.TEXT, func() -> void: _reply("standby", "")))
	_reply_bar.add_child(_reply_button("SAY AGAIN  R", UiTheme.TEXT, func() -> void: _reply("say_again", "")))
	col.add_child(_reply_bar)

	_unable_bar = HFlowContainer.new()
	_unable_bar.add_theme_constant_override(&"h_separation", 8)
	_unable_bar.add_theme_constant_override(&"v_separation", 6)
	for r: Array in UNABLE_REASONS:
		var reason := String(r[0])
		_unable_bar.add_child(_small("UNABLE: " + String(r[1]), func() -> void: _reply("unable", reason)))
	_unable_bar.visible = false
	col.add_child(_unable_bar)

	_calls_bar = HFlowContainer.new()
	_calls_bar.add_theme_constant_override(&"h_separation", 8)
	_calls_bar.add_theme_constant_override(&"v_separation", 6)
	_calls_bar.visible = false
	col.add_child(_calls_bar)
	if _touch:
		TouchMode.enlarge_targets(_box, TouchMode.TARGET_PX * 0.5)


## Wrapping rows settle their height a frame after a width change: keep the box tight.
func _process(_delta: float) -> void:
	if visible and _box.size.y > _box.get_combined_minimum_size().y + 1.0:
		_box.reset_size()


func _small(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text, &"Ghost", cb)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override(&"font", UiTheme.mono(600))
	b.add_theme_font_size_override(&"font_size", 15)
	return b


func _reply_button(text: String, col: Color, cb: Callable) -> Button:
	var b := UiKit.button(text, &"", cb)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override(&"font", UiTheme.mono(600))
	b.add_theme_font_size_override(&"font_size", 15)
	b.add_theme_color_override(&"font_color", col)
	for st: StringName in [&"normal", &"hover", &"pressed"]:
		var sb := UiTheme.flat(Color(col, 0.08 if st == &"normal" else 0.2), Color(col, 0.45 if st == &"normal" else 0.9), 1, 2, 10, 5)
		b.add_theme_stylebox_override(st, sb)
	return b


func _layout() -> void:
	var vs := get_viewport_rect().size
	var w := minf(WIDTH, vs.x * 0.46)
	if _touch:
		var safe := TouchMode.safe_rect(get_viewport())
		w = minf(WIDTH * 1.1, safe.size.x - 2.0 * (PilotTouchControls.COL_W + TouchMode.EDGE * 3.0))
		_box.position = Vector2(safe.end.x - w - TouchMode.EDGE * 2.0, top_reserved + 8.0)
	else:
		_box.position = Vector2(vs.x - w - MARGIN, top_reserved + 8.0)
	_box.custom_minimum_size = Vector2(w, 0.0)
	_box.size = Vector2(w, 0.0)
	_box.reset_size()


# ---------------------------------------------------------------- content

func refresh() -> void:
	if not is_node_ready():
		return
	visible = wanted() and not suppressed
	if not visible:
		return
	for c in _rows.get_children():
		_rows.remove_child(c) # out of the layout now, so the box can shrink
		c.queue_free()
	var log: Array = Sess.val(&"dl_log", [])
	var n := ROWS_LONG if long else ROWS_SHORT
	if compact:
		n = 1
	if _touch:
		n = mini(n, ROWS_TOUCH_MAX)
	_reply_to = _awaiting_reply()
	if log.is_empty():
		_rows.add_child(_dim_line("Nothing said yet. Instructions to you appear here, highlighted."))
	var first := maxi(0, log.size() - n)
	# The clearance waiting for our reply stays on screen, pinned above the newer lines.
	if not _reply_to.is_empty() and first > 0 and log.find(_reply_to) < first:
		_rows.add_child(_row(_reply_to, false))
		first += 1
	for i in range(first, log.size()):
		_rows.add_child(_row(log[i], i == log.size() - 1))
	_reply_bar.visible = not _reply_to.is_empty()
	if _reply_bar.visible:
		_reply_label.text = "REPLY"
		_reply_label.tooltip_text = "Reply to %s" % _sender_name(_reply_to)
	else:
		_unable_bar.visible = false
	_more_btn.text = "LESS  T" if long else "MORE  T"
	_rebuild_calls()
	_refresh_status()
	_box.reset_size.call_deferred()


func _refresh_status() -> void:
	if _head_status == null:
		return
	var air: Array = Sess.val(&"dl_tx", [])
	var voice: Array = Sess.radio_tx()
	var me := Sess.my_id()
	var on_air := voice.duplicate()
	for id: Variant in air:
		if not on_air.has(id):
			on_air.append(id)
	var txt := ""
	if not _notice.is_empty() and Time.get_ticks_msec() < int(_notice[1]):
		txt = String(_notice[0])
	elif on_air.size() >= 2:
		txt = "BLOCKED"
	elif air.has(me):
		txt = "sending…"
	elif not air.is_empty():
		txt = "receiving %s…" % _name_of(int(air[0]))
	_head_status.text = txt
	_head_status.add_theme_color_override(&"font_color", UiTheme.RED if txt == "BLOCKED" else UiTheme.AMBER)


func _row(m: Dictionary, newest: bool) -> Control:
	var me := Sess.my_id()
	var mine := int(m.get("from", 0)) == me
	var to_me := String(m.get("to", "")) == Sess.my_callsign() and Sess.my_callsign() != ""
	var status := String(m.get("status", ""))
	var h := UiKit.hbox(10)
	var time := UiKit.label(UiText.mmss(float(m.get("time", 0.0))), &"MonoSmall")
	time.custom_minimum_size = Vector2(54.0, 0.0)
	time.add_theme_color_override(&"font_color", UiTheme.FAINT)
	time.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(time)
	var who := UiKit.label("YOU" if mine else _sender_name(m), &"Mono")
	who.custom_minimum_size = Vector2(136.0, 0.0)
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	who.add_theme_font_size_override(&"font_size", 16)
	who.add_theme_color_override(&"font_color", UiTheme.DIM if mine else _sender_color(m))
	h.add_child(who)
	var text := UiKit.label(_row_text(m), &"", true)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(120.0, 0.0)
	text.add_theme_font_size_override(&"font_size", 18 if to_me else 17)
	var col := UiTheme.TEXT if newest else UiTheme.TEXT.darkened(0.2)
	if to_me and status == "ok":
		col = Color.WHITE
	elif mine:
		col = UiTheme.DIM
	if status == "blocked" or status == "expired" or status == "cut":
		col = UiTheme.RED
	text.add_theme_color_override(&"font_color", col)
	h.add_child(text)
	if mine and status in ["blocked", "expired", "cut"] and not _dead():
		var again := Datalink.resend_copy(m)
		h.add_child(_small("RESEND", func() -> void: _send(again)))
	if not (to_me and status == "ok"):
		return h
	var mark := PanelContainer.new()
	var sb := UiTheme.flat(Color(UiTheme.AMBER, 0.08), Color(UiTheme.AMBER, 0.85), 0, 2, 8, 4)
	sb.border_width_left = 3
	mark.add_theme_stylebox_override(&"panel", sb)
	mark.mouse_filter = Control.MOUSE_FILTER_PASS
	mark.add_child(h)
	return mark


func _row_text(m: Dictionary) -> String:
	var status := String(m.get("status", ""))
	var text := String(m.get("text", ""))
	match status:
		"queued":
			return "%s   (waiting for a clear frequency)" % Datalink.render(m, _local_ctx(m))
		"blocked":
			return "BLOCKED: %s" % text if text != "" else "— blocked transmission —"
		"expired":
			return "NOT SENT, the frequency never cleared."
		"cut":
			return "CUT OFF."
	return text


func _dim_line(t: String) -> Label:
	var l := UiKit.label(t, &"Small", true)
	l.add_theme_color_override(&"font_color", UiTheme.FAINT)
	return l


## What our own queued message will say (the host renders the real text when it airs).
func _local_ctx(m: Dictionary) -> Dictionary:
	var atis: Dictionary = Sess.val(&"atis", {})
	var own: Dictionary = Sess.val(&"own", {})
	return {"letter": String(atis.get("letter", "")), "qnh": int(atis.get("qnh", 0)),
		"from_cs": String(m.get("from_cs", Sess.my_callsign())), "names": _names(),
		"ind_alt": int(round(float(own.get("ind_alt", 0)) / 100.0)) * 100, "fuel_min": float(own.get("fuel_min", 0.0))}


## The newest clearance for our callsign that we have not answered, or {}.
func _awaiting_reply() -> Dictionary:
	var cs := Sess.my_callsign()
	var log: Array = Sess.val(&"dl_log", [])
	if cs == "" or Sess.my_role() != "pilot":
		return {}
	var own: Dictionary = Sess.val(&"own", {})
	if String(own.get("status", "flying")) == "crashed":
		return {}
	var replied := {}
	for m: Dictionary in log:
		if String(m.get("kind", "")) == Datalink.KIND_REPLY and int(m.get("from", 0)) == Sess.my_id():
			replied[int(m.get("re", 0))] = true
	for i in range(log.size() - 1, -1, -1):
		var m: Dictionary = log[i]
		if String(m.get("kind", "")) != Datalink.KIND_CLR or String(m.get("to", "")) != cs:
			continue
		if String(m.get("status", "")) != "ok":
			continue
		var mid := int(m.get("id", 0))
		if replied.has(mid) or _answered.has(mid):
			return {}
		return m
	return {}


func _rebuild_calls() -> void:
	for c in _calls_bar.get_children():
		c.queue_free()
	if Sess.my_role() != "pilot" or _dead():
		_calls_btn.visible = false
		_calls_bar.visible = false
		return
	_calls_btn.visible = true
	for c: Array in CALLS:
		var t := String(c[0])
		_calls_bar.add_child(_small(String(c[1]), func() -> void:
			if _send(Datalink.radio_call(t)):
				_calls_bar.visible = false))
	for p: Variant in Sess.round_players():
		if p is Dictionary and String((p as Dictionary).get("role", "")) == "controller" and UiText.controller_names().size() >= 2:
			var who := int((p as Dictionary)["id"])
			var b := _small("CALL OUT %s" % String((p as Dictionary).get("name", "?")).to_upper(), func() -> void:
				if _send(Datalink.radio_call("accuse", who)):
					_calls_bar.visible = false)
			b.add_theme_color_override(&"font_color", UiTheme.RED)
			_calls_bar.add_child(b)
	if _touch:
		TouchMode.enlarge_targets(_calls_bar, TouchMode.TARGET_PX * 0.5)


func _names() -> Dictionary:
	var out := {}
	for p: Variant in Sess.round_players():
		if p is Dictionary:
			out[int((p as Dictionary).get("id", 0))] = String((p as Dictionary).get("name", ""))
	return out


func _name_of(id: int) -> String:
	var rp := Sess.round_player(id)
	if String(rp.get("role", "")) == "pilot" and String(rp.get("callsign", "")) != "":
		return String(rp["callsign"])
	return Sess.player_name(id)


func _sender_name(m: Dictionary) -> String:
	return Datalink.sender_label(m, Sess.player_name(int(m.get("from", 0))))


func _sender_color(m: Dictionary) -> Color:
	if String(m.get("role", "")) != "controller":
		return PILOT_COLOR
	var i := 0
	for p: Variant in Sess.round_players():
		if p is Dictionary and String((p as Dictionary).get("role", "")) == "controller":
			if int((p as Dictionary).get("id", 0)) == int(m.get("from", 0)):
				return CTL_COLORS[i % CTL_COLORS.size()]
			i += 1
	return CTL_COLORS[0]


# ---------------------------------------------------------------- actions

## Answered only once it really went to the host (a full queue keeps the reply bar up).
func _reply(t: String, why: String) -> void:
	if _reply_to.is_empty():
		return
	var mid := int(_reply_to.get("id", 0))
	if _send(Datalink.reply(mid, t, why)):
		_answered[mid] = true
		_unable_bar.visible = false
		refresh()


## Hand a message to Session; false (and a note in the header) when it would be refused.
func _send(msg: Dictionary) -> bool:
	var why: Variant = Sess.invoke(&"dl_refusal")
	if why is String and String(why) != "":
		_notice = [String(why), Time.get_ticks_msec() + NOTICE_MS]
		_refresh_status()
		return false
	Sess.invoke(&"send_dl", [msg])
	refresh()
	return true


func _dead() -> bool:
	var own: Dictionary = Sess.val(&"own", {})
	return String(own.get("status", "flying")) == "crashed"


func _toggle_calls() -> void:
	_calls_bar.visible = not _calls_bar.visible
	_box.reset_size.call_deferred()


func _toggle_more() -> void:
	long = not long
	refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	if (event as InputEventKey).shift_pressed or (event as InputEventKey).ctrl_pressed:
		return
	if UiKit.is_text_input_focused(get_viewport()):
		return
	var handled := true
	if event.is_action("dl_calls") and Sess.my_role() == "pilot":
		_toggle_calls()
	elif event.is_action("dl_more"):
		_toggle_more()
	elif _reply_to.is_empty():
		handled = false
	elif event.is_action("dl_wilco"):
		_reply("wilco", "")
	elif event.is_action("dl_unable"):
		_reply("unable", "")
	elif event.is_action("dl_standby"):
		_reply("standby", "")
	elif event.is_action("dl_say_again"):
		_reply("say_again", "")
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
