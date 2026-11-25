extends PanelContainer
## Flight-data display beside the scope: controllers on frequency, the
## selected target's strip with a local scratchpad, the traffic list, the event
## log, then ATIS, the approach summary and a collapsible phraseology card.
## Layout is in 1080p canvas units; the view places it over the side display.

const Look := preload("res://scenes/controller/scope/scope_theme.gd")
const Fmt := preload("res://scenes/controller/scope/scope_format.gd")
const Model := preload("res://scenes/controller/scope/scope_model.gd")
const S := preload("res://scenes/controller/panel/fdd_style.gd")
const Phrases := preload("res://scenes/controller/panel/phraseology.gd")

const LOG_LINES := 7

var model: Model
var extra_events: Array[Dictionary] = []

var _ctl_label: Label
var _atis_head: Label
var _strip: PanelContainer
var _strip_empty: Label
var _cs: Label
var _pilot: Label
var _tag: Label
var _tag_box: PanelContainer
var _cells: Dictionary = {}
var _scratch: LineEdit
var _traffic: VBoxContainer
var _log: VBoxContainer
var _atis_text: Label
var _approach: VBoxContainer
var _phr_button: Button
var _phr_body: VBoxContainer
var _phr_open := false
var _shown_cs := ""


func _ready() -> void:
	add_theme_stylebox_override(&"panel", S.box(Look.FDD_BG, Color.TRANSPARENT, 0, 14, 10, 0))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var root := S.vbox(10)
	add_child(root)
	root.add_child(_header())
	root.add_child(S.heading("Flight strip"))
	root.add_child(_strip_card())
	root.add_child(S.heading("Traffic"))
	_traffic = S.vbox(1)
	root.add_child(_traffic)
	root.add_child(S.heading("Events"))
	_log = S.vbox(2)
	root.add_child(_log)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	root.add_child(scroll)
	var lower := S.vbox(10)
	lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lower)
	lower.add_child(S.heading("ATIS"))
	_atis_text = S.label("", 14, Look.FDD_TEXT)
	_atis_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_atis_text.custom_minimum_size = Vector2(100, 0)
	lower.add_child(_atis_text)
	lower.add_child(S.heading("ILS RWY 27 — approach"))
	_approach = S.vbox(3)
	lower.add_child(_approach)
	_phr_button = S.flat_button("", 13, Look.FDD_HEAD)
	_phr_button.pressed.connect(func() -> void:
		_phr_open = not _phr_open
		_refresh_phraseology())
	lower.add_child(_phr_button)
	_phr_body = S.vbox(4)
	lower.add_child(_phr_body)
	refresh_static()
	refresh()


func _header() -> Control:
	var v := S.vbox(2)
	var top := S.hbox(10)
	var fv := FontVariation.new()
	fv.base_font = Look.sans(700)
	fv.spacing_glyph = 2
	top.add_child(S.label("FLIGHT DATA", 15, Look.FDD_TEXT, fv))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	_atis_head = S.label("", 14, Look.FDD_ACCENT, Look.mono(700))
	top.add_child(_atis_head)
	v.add_child(top)
	_ctl_label = S.label("", 13, Look.FDD_DIM, Look.sans(500))
	_ctl_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ctl_label.clip_text = true
	v.add_child(_ctl_label)
	return v


func _strip_card() -> Control:
	var host := S.vbox(0)
	_strip = PanelContainer.new()
	var sb := S.box(Look.FDD_STRIP, Look.FDD_AMBER, 0, 12, 9, 2)
	sb.border_width_left = 5
	_strip.add_theme_stylebox_override(&"panel", sb)
	host.add_child(_strip)
	var v := S.vbox(8)
	_strip.add_child(v)
	var top := S.hbox(10)
	_cs = S.label("", 26, Color.WHITE, Look.mono(700))
	top.add_child(_cs)
	_pilot = S.label("", 15, Look.FDD_DIM, Look.sans(500))
	_pilot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pilot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pilot.clip_text = true
	top.add_child(_pilot)
	_tag_box = PanelContainer.new()
	_tag_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tag = S.label("", 14, Look.FDD_TEXT, Look.mono(700))
	_tag_box.add_child(_tag)
	top.add_child(_tag_box)
	v.add_child(top)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key: String in ["ALT", "GS", "TRK", "DME", "MSA"]:
		var cell := S.vbox(0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(S.label(key, 11, Look.FDD_FAINT, Look.sans(600)))
		var val := S.label("—", 17, Look.FDD_TEXT, Look.mono(600))
		cell.add_child(val)
		_cells[key] = val
		grid.add_child(cell)
	v.add_child(grid)
	_scratch = LineEdit.new()
	_scratch.placeholder_text = "Scratchpad (local) — 7 chars show in the tag"
	_scratch.max_length = 32
	_scratch.context_menu_enabled = false
	_scratch.add_theme_font_override(&"font", Look.mono(600))
	_scratch.add_theme_font_size_override(&"font_size", 15)
	_scratch.add_theme_color_override(&"font_color", Look.FDD_AMBER)
	_scratch.add_theme_color_override(&"font_placeholder_color", Look.FDD_FAINT)
	_scratch.add_theme_color_override(&"caret_color", Look.FDD_AMBER)
	_scratch.add_theme_stylebox_override(&"normal", S.box(Color(0, 0, 0, 0.35), Look.FDD_LINE, 1, 8, 5))
	_scratch.add_theme_stylebox_override(&"focus", S.box(Color(0, 0, 0, 0.5), Color(Look.FDD_AMBER, 0.6), 1, 8, 5))
	_scratch.text_changed.connect(func(t: String) -> void:
		if model != null and model.selected != "":
			model.set_scratch(model.selected, t))
	_scratch.text_submitted.connect(func(_t: String) -> void: _scratch.release_focus())
	v.add_child(_scratch)
	_strip_empty = S.label("No target selected. Click a target on the scope or in the traffic list.", 14,
		Look.FDD_FAINT, Look.sans(400))
	_strip_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_strip_empty.custom_minimum_size = Vector2(100, 0)
	host.add_child(_strip_empty)
	return host


## World/ATIS-derived text that does not change during a round.
func refresh_static() -> void:
	var atis: Dictionary = Session.atis
	var world: Dictionary = Session.world if not Session.world.is_empty() else World.DATA
	if atis.is_empty():
		_atis_head.text = "ATIS —"
		_atis_text.text = "No ATIS received."
	else:
		_atis_head.text = "INFO %s  QNH %s" % [String(atis.get("letter", "-")), str(atis.get("qnh", "----"))]
		_atis_text.text = "%s  RWY %s  WIND %03d/%dKT  VIS %s  CLG %d FT\n%s" % [
			String(atis.get("letter", "-")), String(atis.get("runway", "27")), int(atis.get("wind_dir", 0)),
			int(atis.get("wind_kt", 0)), _vis_text(int(atis.get("visibility_m", 9999))), int(atis.get("ceiling_ft", 0)),
			String(atis.get("text", "")).replace(". ", ".\n")]
	for c in _approach.get_children():
		c.queue_free()
	var ils: Dictionary = world.get("ils", {})
	var faf: Dictionary = ils.get("faf", {})
	var faf_d := Vector2(float(faf.get("x", 0.0)), float(faf.get("y", 0.0))).length()
	var msa_parts := PackedStringArray()
	for s: Dictionary in world.get("msa", []):
		msa_parts.append("%03d–%03d %d" % [int(s["from_deg"]), int(s["to_deg"]) % 360, int(s["alt_ft"])])
	var hold: Dictionary = world.get("hold", {})
	var rows: Array[Array] = [
		["CRS", "%s°  ILS / DME at threshold" % Fmt.hdg_text(float(ils.get("course_deg", 270.0)))],
		["PLATFORM", "%d ft" % int(ils.get("platform_alt_ft", 3000))],
		["FAF", "%s  %.1f NM  GS %.1f°" % [String(faf.get("name", "")), faf_d, float(ils.get("glide_deg", 3.0))]],
		["DA", "%d ft  (elev %d)" % [int(ils.get("da_ft", 0)), int(world.get("field_elev_ft", 0))]],
		["MSA 25NM", "  ".join(msa_parts)],
		["HOLD", "%s %s° %s turns  %d+" % [String(hold.get("fix", "")), Fmt.hdg_text(float(hold.get("inbound_course_deg", 0))),
			"right" if String(hold.get("turn", "R")) == "R" else "left", int(hold.get("min_alt_ft", 0))]],
		["MISSED", String(world.get("missed_approach", ""))],
	]
	for r in rows:
		var h := S.hbox(10)
		var k := S.label(String(r[0]), 12, Look.FDD_FAINT, Look.sans(600))
		k.custom_minimum_size = Vector2(84, 0)
		h.add_child(k)
		var v := S.label(String(r[1]), 14, Look.FDD_TEXT, Look.mono(500))
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.custom_minimum_size = Vector2(80, 0)
		h.add_child(v)
		_approach.add_child(h)
	_refresh_controllers()
	_refresh_phraseology()


func _vis_text(m: int) -> String:
	return "%d M" % m if m < 5000 else "%d KM" % (m / 1000)


func _refresh_controllers() -> void:
	var names := PackedStringArray()
	for p: Dictionary in Session.round_players:
		if String(p.get("role", "")) == "controller":
			var n := String(p.get("name", "?"))
			names.append(n + " (you)" if int(p.get("id", 0)) == Session.my_id else n)
	_ctl_label.text = "ON FREQ  119.850   CTL: %s" % ("  ·  ".join(names) if not names.is_empty() else "—")


## Everything that changes with sweeps, selection and events.
func refresh() -> void:
	if model == null:
		return
	_refresh_strip()
	_refresh_traffic()
	_refresh_log()


func _refresh_strip() -> void:
	var cs := model.selected
	_strip.visible = cs != ""
	_strip_empty.visible = cs == ""
	if cs == "":
		_shown_cs = ""
		return
	if cs != _shown_cs:
		_shown_cs = cs
		_scratch.text = String(model.scratch.get(cs, ""))
		_refresh_phraseology()
	_cs.text = cs
	_pilot.text = _pilot_name(cs)
	var t: Dictionary = model.targets.get(cs, {})
	if t.is_empty():
		for key: String in _cells:
			(_cells[key] as Label).text = "—"
		_set_tag("NO TGT", Look.FDD_DIM)
		return
	var p := Fmt.target_pos(t)
	(_cells["ALT"] as Label).text = Fmt.strip_alt_text(t)
	(_cells["GS"] as Label).text = "%d kt" % int(round(float(t["gs"])))
	(_cells["TRK"] as Label).text = "%s°" % Fmt.hdg_text(float(t["track"]))
	(_cells["DME"] as Label).text = "%.1f nm" % p.length()
	var msa := Fmt.msa_at(_world(), p)
	(_cells["MSA"] as Label).text = str(msa) if msa > 0 and p.length() <= 25.0 else "—"
	var status := String(t["status"])
	if status == "crashed":
		_set_tag("CRASHED", Look.FDD_RED)
	elif status == "landed":
		_set_tag("LANDED", Look.FDD_ACCENT)
	elif bool(t.get("conflict", false)):
		_set_tag("CA", Look.FDD_RED)
	elif bool(t.get("msaw", false)):
		_set_tag("LA", Look.FDD_AMBER)
	else:
		_set_tag("", Look.FDD_DIM)


func _set_tag(text: String, col: Color) -> void:
	_tag_box.visible = text != ""
	_tag.text = text
	_tag.add_theme_color_override(&"font_color", col)
	_tag_box.add_theme_stylebox_override(&"panel", S.box(Color(col, 0.12), Color(col, 0.7), 1, 8, 2))


func _pilot_name(cs: String) -> String:
	for p: Dictionary in Session.round_players:
		if String(p.get("callsign", "")) == cs:
			return String(p.get("name", ""))
	return "—"


func _world() -> Dictionary:
	return Session.world if not Session.world.is_empty() else World.DATA


func _refresh_traffic() -> void:
	for c in _traffic.get_children():
		c.queue_free()
	if model.order.is_empty():
		_traffic.add_child(S.label("No targets yet — first sweep pending.", 14, Look.FDD_FAINT, Look.sans(400)))
		return
	var hdr := S.label("CALLSIGN  ALT   GS   DME   ", 11, Look.FDD_FAINT, Look.mono(600))
	_traffic.add_child(hdr)
	for cs in model.order:
		var t: Dictionary = model.targets[cs]
		var status := String(t["status"])
		var alt := Fmt.alt_hundreds(float(t["alt"])) + Fmt.trend_arrow(int(t["vs_trend"])) if status == "flying" else status.to_upper()
		var gs := "%3d" % int(round(float(t["gs"]) / 10.0)) if status == "flying" else "   "
		var flag := Fmt.alert_tag(t) if status == "flying" else ""
		var text := "%-8s  %-5s %s  %4.1f  %s" % [cs, alt, gs, Fmt.target_pos(t).length(), flag]
		var col := Look.FDD_TEXT
		if status == "crashed":
			col = Look.FDD_RED.darkened(0.15)
		elif status == "landed":
			col = Look.FDD_FAINT
		elif flag == "CA":
			col = Look.FDD_RED
		elif flag == "LA":
			col = Look.FDD_AMBER
		var b := S.flat_button(text, 15, col)
		if cs == model.selected:
			b.add_theme_stylebox_override(&"normal", S.box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.25), 1, 6, 3))
		b.pressed.connect(func() -> void: model.select(cs))
		_traffic.add_child(b)


func _refresh_log() -> void:
	for c in _log.get_children():
		c.queue_free()
	var all: Array[Dictionary] = []
	all.append_array(extra_events)
	all.append_array(Session.events)
	if all.is_empty():
		_log.add_child(S.label("—", 14, Look.FDD_FAINT))
		return
	for i in range(maxi(0, all.size() - LOG_LINES), all.size()):
		var e: Dictionary = all[i]
		var kind := String(e.get("kind", ""))
		var col := Look.FDD_ACCENT if kind == "landed" else Look.FDD_RED
		var h := S.hbox(10)
		h.add_child(S.label(Fmt.mmss(float(e.get("time", 0.0))), 14, Look.FDD_DIM, Look.mono(500)))
		var l := S.label(Fmt.event_text(e), 14, col, Look.mono(600))
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		_log.add_child(h)


func set_phraseology_open(on: bool) -> void:
	_phr_open = on
	_refresh_phraseology()


func _refresh_phraseology() -> void:
	if _phr_button == null:
		return
	_phr_button.text = ("▾ " if _phr_open else "▸ ") + "PHRASEOLOGY"
	for c in _phr_body.get_children():
		c.queue_free()
	_phr_body.visible = _phr_open
	if not _phr_open:
		return
	var cs := model.selected if model != null and model.selected != "" else "SKW412"
	var atis: Dictionary = Session.atis
	var groups := Phrases.groups(cs, str(atis.get("qnh", 1013)), String(atis.get("letter", "A")))
	for g: Dictionary in groups:
		_phr_body.add_child(S.label(String(g["title"]).to_upper(), 11, Look.FDD_FAINT, Look.sans(600)))
		for line: String in g["lines"]:
			var l := S.label(line, 14, Look.FDD_TEXT, Look.sans(400))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(80, 0)
			_phr_body.add_child(l)
