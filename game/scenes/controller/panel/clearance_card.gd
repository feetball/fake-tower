extends VBoxContainer
## The controller's text-radio composer (core/net/datalink.gd), under the flight
## strip: for the selected target, HDG / ALT / SPD / QNH values with steppers
## (a value is included once touched; turn direction from the radar track), the
## one-shot items (radar contact, cleared ILS, cleared to land, go around, 360s,
## alerts...), a typed shorthand line ("l240 a55 app", Enter sends), the text that
## will go out, and SEND. Below it the calls to all stations: the ATIS, and calling
## the other controller out. The impostor uses the very same card (a wrong QNH is
## one − away). Everything leaves through Session.send_dl.

const Look := preload("res://scenes/controller/scope/scope_theme.gd")
const Model := preload("res://scenes/controller/scope/scope_model.gd")
const S := preload("res://scenes/controller/panel/fdd_style.gd")
const Datalink := preload("res://core/net/datalink.gd")

## value item -> [label, step, big step, min, max]
const VALUES := {
	"hdg": ["HDG", 5, 30, 5, 360],
	"alt": ["ALT", 500, 1000, 1000, 20000],
	"spd": ["SPD", 10, 20, 140, 250],
	"qnh": ["QNH", 1, 5, 950, 1050],
}
const VALUE_ORDER: Array[String] = ["hdg", "alt", "spd", "qnh"]
## One-shot items: [item, label].
const FLAGS: Array[Array] = [
	["contact", "RADAR CONTACT"], ["expect", "EXPECT ILS"], ["app", "CLEARED ILS"], ["land", "CLEARED LAND"],
	["ga", "GO AROUND"], ["cancel", "CANCEL APP"], ["orbit_L", "360 LEFT"], ["orbit_R", "360 RIGHT"],
	["low_alt", "LOW ALT ALERT"], ["traffic", "TRAFFIC ALERT"], ["disregard", "DISREGARD"], ["roger", "ROGER"],
]

var model: Model

var _target := ""
var _vals := {} ## item -> int
var _on := {} ## item -> bool (values and flags)
var _val_labels := {} ## item -> Button
var _flag_btns := {} ## flag -> Button
var _cmd: LineEdit
var _preview: Label
var _send_btn: Button
var _calls: HFlowContainer
var _for: Label


func _ready() -> void:
	add_theme_constant_override(&"separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	_for = S.label("", 13, Look.FDD_DIM, Look.sans(500))
	add_child(_for)
	var vals := S.hbox(6)
	for k in VALUE_ORDER:
		vals.add_child(_value_box(k))
	add_child(vals)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 4)
	flow.add_theme_constant_override(&"v_separation", 4)
	for f: Array in FLAGS:
		var key := String(f[0])
		var b := _chip(String(f[1]))
		b.toggled.connect(func(on: bool) -> void:
			_on[key] = on
			if on:
				_untoggle_exclusive(key)
			_update_preview())
		_flag_btns[key] = b
		flow.add_child(b)
	add_child(flow)
	var row := S.hbox(6)
	_cmd = LineEdit.new()
	_cmd.placeholder_text = "or type: l240 a55 s180 app   (Enter)"
	_cmd.max_length = 64
	_cmd.context_menu_enabled = false
	_cmd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cmd.add_theme_font_override(&"font", Look.mono(600))
	_cmd.add_theme_font_size_override(&"font_size", S.fs(15))
	_cmd.add_theme_color_override(&"font_color", Look.FDD_ACCENT)
	_cmd.add_theme_color_override(&"font_placeholder_color", Look.FDD_FAINT)
	_cmd.add_theme_color_override(&"caret_color", Look.FDD_ACCENT)
	_cmd.add_theme_stylebox_override(&"normal", S.box(Color(0, 0, 0, 0.35), Look.FDD_LINE, 1, 8, 5))
	_cmd.add_theme_stylebox_override(&"focus", S.box(Color(0, 0, 0, 0.5), Color(Look.FDD_ACCENT, 0.6), 1, 8, 5))
	_cmd.text_changed.connect(func(_t: String) -> void: _update_preview())
	_cmd.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
			_cmd.release_focus()
			_cmd.accept_event())
	_cmd.text_submitted.connect(func(_t: String) -> void: send())
	row.add_child(_cmd)
	_send_btn = _chip("SEND ⏎", false)
	_send_btn.custom_minimum_size = Vector2(96, 0)
	_send_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_send_btn.pressed.connect(send)
	row.add_child(_send_btn)
	add_child(row)
	_preview = S.label("", 14, Look.FDD_TEXT, Look.sans(400))
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.custom_minimum_size = Vector2(80, 0)
	add_child(_preview)
	add_child(S.heading("All stations"))
	_calls = HFlowContainer.new()
	_calls.add_theme_constant_override(&"h_separation", 4)
	_calls.add_theme_constant_override(&"v_separation", 4)
	add_child(_calls)
	refresh_calls()
	set_target("")


func _value_box(k: String) -> Control:
	var spec: Array = VALUES[k]
	var v := S.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := S.hbox(2)
	var minus := _chip("−", false)
	minus.pressed.connect(func() -> void: nudge(k, -1, Input.is_key_pressed(KEY_SHIFT)))
	var val := _chip("%s —" % spec[0])
	val.alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.tooltip_text = "Click to include or leave out; wheel or −/+ to change (Shift: big steps)"
	val.toggled.connect(func(on: bool) -> void:
		_on[k] = on
		if on:
			_untoggle_exclusive(k)
		_update_preview())
	val.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			var mb := e as InputEventMouseButton
			if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				nudge(k, 1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1, mb.shift_pressed)
				val.accept_event())
	var plus := _chip("+", false)
	plus.pressed.connect(func() -> void: nudge(k, 1, Input.is_key_pressed(KEY_SHIFT)))
	for b: Button in [minus, plus]:
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(26, 0)
	h.add_child(minus)
	h.add_child(val)
	h.add_child(plus)
	v.add_child(h)
	_val_labels[k] = val
	return v


func _chip(text: String, toggle: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override(&"font", Look.mono(600))
	b.add_theme_font_size_override(&"font_size", S.fs(12))
	for st: StringName in [&"font_color", &"font_hover_color", &"font_focus_color"]:
		b.add_theme_color_override(st, Look.FDD_DIM)
	b.add_theme_color_override(&"font_pressed_color", Color.BLACK)
	b.add_theme_color_override(&"font_hover_pressed_color", Color.BLACK)
	b.add_theme_stylebox_override(&"normal", S.box(Color(1, 1, 1, 0.03), Look.FDD_LINE, 1, 6, 3))
	b.add_theme_stylebox_override(&"hover", S.box(Color(1, 1, 1, 0.08), Color(Look.FDD_ACCENT, 0.5), 1, 6, 3))
	b.add_theme_stylebox_override(&"pressed", S.box(Look.FDD_ACCENT, Look.FDD_ACCENT, 1, 6, 3))
	b.add_theme_stylebox_override(&"hover_pressed", S.box(Look.FDD_ACCENT.lightened(0.15), Look.FDD_ACCENT, 1, 6, 3))
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	return b


# ---------------------------------------------------------------- state

## A new selection: values start from what the radar shows, nothing included.
func set_target(cs: String) -> void:
	_target = cs
	var t: Dictionary = model.targets.get(cs, {}) if model != null else {}
	var atis: Dictionary = Session.atis
	_vals["hdg"] = Datalink.norm_hdg(int(round(float(t.get("track", 270)) / 5.0)) * 5)
	_vals["alt"] = clampi(int(round(float(t.get("alt", 6000)) / 500.0)) * 500, 1000, 20000)
	_vals["spd"] = clampi(int(round(float(t.get("gs", 220)) / 10.0)) * 10, 140, 250)
	_vals["qnh"] = int(atis.get("qnh", 1013))
	_clear_toggles()
	_cmd.text = ""
	_for.text = "TO %s" % cs if cs != "" else "Select a target to send it instructions."
	_update_preview()


func nudge(k: String, dir: int, big: bool) -> void:
	var spec: Array = VALUES[k]
	var step: int = spec[2] if big else spec[1]
	var v := int(_vals.get(k, spec[3])) + dir * step
	if k == "hdg":
		v = Datalink.norm_hdg(v)
	else:
		v = clampi(v, spec[3], spec[4])
	_vals[k] = v
	_on[k] = true
	(_val_labels[k] as Button).set_pressed_no_signal(true)
	_untoggle_exclusive(k)
	_update_preview()


func _clear_toggles() -> void:
	_on.clear()
	for k: String in _val_labels:
		(_val_labels[k] as Button).set_pressed_no_signal(false)
	for k: String in _flag_btns:
		(_flag_btns[k] as Button).set_pressed_no_signal(false)


func _untoggle_exclusive(key: String) -> void:
	var t := "orbit" if key.begins_with("orbit") else key
	if key == "orbit_L" or key == "orbit_R":
		var other := "orbit_R" if key == "orbit_L" else "orbit_L"
		_on[other] = false
		(_flag_btns[other] as Button).set_pressed_no_signal(false)
	for pair: Array in Datalink.EXCLUSIVE:
		var other := ""
		if pair[0] == t:
			other = String(pair[1])
		elif pair[1] == t:
			other = String(pair[0])
		if other == "hdg" or other == "orbit":
			if other == "hdg":
				_on["hdg"] = false
				(_val_labels["hdg"] as Button).set_pressed_no_signal(false)
			else:
				for o in ["orbit_L", "orbit_R"]:
					_on[o] = false
					(_flag_btns[o] as Button).set_pressed_no_signal(false)
		elif other != "" and _flag_btns.has(other):
			_on[other] = false
			(_flag_btns[other] as Button).set_pressed_no_signal(false)


## The items to send: the typed shorthand if there is any, else the toggles; checked
## with the host's own rules (Datalink.parse), so SEND never offers what it would refuse.
func items() -> Dictionary:
	var r := _raw_items()
	if String(r["error"]) == "" and _target != "":
		var out := {}
		var err := Datalink.parse(Datalink.clr(_target, r["items"]), "controller", out)
		if err != "":
			return {"items": [], "error": _readable(err.trim_prefix("Bad message: "))}
	return r


## "hdg with orbit" -> "A heading and a 360 cannot go in one message."
static func _readable(err: String) -> String:
	const NAMES := {"hdg": "a heading", "orbit": "a 360", "app": "CLEARED ILS", "cancel": "CANCEL APP",
		"ga": "GO AROUND", "land": "CLEARED LAND"}
	var pair := err.split(" with ")
	if pair.size() == 2 and NAMES.has(pair[0]) and NAMES.has(pair[1]):
		var msg := "%s and %s cannot go in one message." % [NAMES[pair[0]], NAMES[pair[1]]]
		return msg.left(1).to_upper() + msg.substr(1)
	if err == "items":
		return "Too many items for one message (at most %d)." % Datalink.MAX_ITEMS
	return err


func _raw_items() -> Dictionary:
	if _cmd.text.strip_edges() != "":
		return Datalink.parse_command(_cmd.text, int(Session.atis.get("qnh", 0)))
	var out: Array = []
	var track := float(model.targets.get(_target, {}).get("track", 0.0)) if model != null else 0.0
	for k in VALUE_ORDER:
		if bool(_on.get(k, false)):
			match k:
				"hdg":
					out.append(Datalink.hdg(int(_vals[k]), Datalink.turn_dir(track, float(_vals[k]))))
				"alt":
					out.append(Datalink.alt(int(_vals[k])))
				"spd":
					out.append(Datalink.spd(int(_vals[k])))
				"qnh":
					out.append(Datalink.qnh(int(_vals[k])))
	for f: Array in FLAGS:
		var key := String(f[0])
		if bool(_on.get(key, false)):
			out.append(Datalink.orbit(key.substr(6)) if key.begins_with("orbit") else Datalink.item(key))
	return {"items": out, "error": "" if not out.is_empty() else "Nothing to send"}


func _update_preview() -> void:
	for k in VALUE_ORDER:
		var spec: Array = VALUES[k]
		var v := int(_vals.get(k, 0))
		(_val_labels[k] as Button).text = "%s %s" % [spec[0], "%03d" % v if k == "hdg" else str(v)]
	var r := items()
	var ok := _target != "" and String(r["error"]) == ""
	_send_btn.disabled = not ok
	if _target == "":
		_preview.text = ""
		return
	if String(r["error"]) != "":
		var nothing := String(r["error"]) == "Nothing to send" and _cmd.text.strip_edges() == ""
		_preview.text = "" if nothing else String(r["error"])
		_preview.add_theme_color_override(&"font_color", Look.FDD_AMBER)
		return
	var t: Dictionary = model.targets.get(_target, {})
	var ctx := {"letter": String(Session.atis.get("letter", "")), "wind_dir": int(Session.atis.get("wind_dir", 0)),
		"wind_kt": int(Session.atis.get("wind_kt", 0)), "to_alt": float(t.get("alt", -1.0))}
	_preview.text = Datalink.render(Datalink.clr(_target, r["items"]), ctx)
	var wrong_qnh := false
	for it: Dictionary in r["items"]:
		if String(it["t"]) == "qnh" and int(it["v"]) != int(Session.atis.get("qnh", 0)):
			wrong_qnh = true
	_preview.add_theme_color_override(&"font_color", Look.FDD_AMBER if wrong_qnh else Look.FDD_TEXT)


func send() -> void:
	if _target == "":
		return
	var r := items()
	if String(r["error"]) != "":
		_update_preview()
		return
	var why := Session.dl_refusal()
	if why != "":
		# Keep what was composed: it can go once the frequency has room.
		_preview.text = why
		_preview.add_theme_color_override(&"font_color", Look.FDD_AMBER)
		return
	Session.send_dl(Datalink.clr(_target, r["items"]))
	_clear_toggles()
	_cmd.text = ""
	_cmd.release_focus()
	_update_preview()


func focus_command() -> void:
	if _target != "":
		_cmd.grab_focus()


## The ATIS broadcast and one "call out" per other controller.
func refresh_calls() -> void:
	if _calls == null:
		return
	for c in _calls.get_children():
		c.queue_free()
	var atis := _chip("BROADCAST ATIS + QNH", false)
	atis.pressed.connect(func() -> void: Session.send_dl(Datalink.radio_call("atis")))
	_calls.add_child(atis)
	for p: Dictionary in Session.round_players:
		if String(p.get("role", "")) == "controller" and int(p.get("id", 0)) != Session.my_id:
			var who := int(p["id"])
			var b := _chip("CALL OUT %s" % String(p.get("name", "?")).to_upper(), false)
			b.add_theme_color_override(&"font_color", Look.FDD_RED)
			b.pressed.connect(func() -> void: Session.send_dl(Datalink.radio_call("accuse", who)))
			_calls.add_child(b)
