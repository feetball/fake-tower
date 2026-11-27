extends PanelContainer
## Flight-data display beside the scope: controllers on frequency, the
## selected target's strip with a local scratchpad, the text-radio composer
## (clearance_card.gd), the traffic list, the event log, then (tabs) the
## frequency transcript, ATIS, the approach summary and the phraseology card.
## Layout is in 1080p canvas units; the view places it over the side display.

const Look := preload("res://scenes/controller/scope/scope_theme.gd")
const Fmt := preload("res://scenes/controller/scope/scope_format.gd")
const Model := preload("res://scenes/controller/scope/scope_model.gd")
const S := preload("res://scenes/controller/panel/fdd_style.gd")
const Phrases := preload("res://scenes/controller/panel/phraseology.gd")
const ClearanceCard := preload("res://scenes/controller/panel/clearance_card.gd")
const Datalink := preload("res://core/net/datalink.gd")

const LOG_LINES := 5
const FREQ_LINES := 14
const CELL_LABELS := {"ALT": "ALT FT", "GS": "GS KT", "TRK": "TRK", "DME": "DME NM", "MSA": "MSA"}

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
var _tabs: Dictionary = {} ## tab id -> Button
var _tab := "freq" ## "freq" | "atis" | "app" | "phr"
var _phr_body: VBoxContainer
var _freq: VBoxContainer
var _card: ClearanceCard
var _shown_cs := ""


var _text_scale := 1.0
var _root: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override(&"panel", S.box(Look.FDD_BG, Color.TRANSPARENT, 0, 14, 10, 0))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Session.datalink.connect(func(_m: Dictionary) -> void: _refresh_freq())


## Focus the composer's shorthand line (Enter on the scope).
func focus_command() -> void:
	if _card != null:
		_card.focus_command()


## Rebuilds with larger text when the window is small (see FddStyle.text_scale).
func set_text_scale(f: float) -> void:
	if is_equal_approx(f, _text_scale):
		return
	_text_scale = f
	if _root != null:
		_root.free()
		_cells.clear()
		_tabs.clear()
		_shown_cs = ""
		_build()


func _build() -> void:
	S.text_scale = _text_scale
	var root := S.vbox(10)
	_root = root
	add_child(root)
	root.add_child(_header())
	root.add_child(S.heading("Flight strip"))
	root.add_child(_strip_card())
	root.add_child(S.heading("Datalink clearance"))
	_card = ClearanceCard.new()
	_card.model = model
	root.add_child(_card)
	root.add_child(S.heading("Traffic"))
	_traffic = S.vbox(1)
	root.add_child(_traffic)
	root.add_child(S.heading("Events"))
	_log = S.vbox(2)
	root.add_child(_log)
	root.add_child(_tab_row())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	root.add_child(scroll)
	var lower := S.vbox(10)
	lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lower)
	_atis_text = S.label("", 14, Look.FDD_TEXT)
	_atis_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_atis_text.custom_minimum_size = Vector2(100, 0)
	lower.add_child(_atis_text)
	_freq = S.vbox(5)
	lower.add_child(_freq)
	_approach = S.vbox(4)
	lower.add_child(_approach)
	_phr_body = S.vbox(4)
	lower.add_child(_phr_body)
	refresh_static()
	refresh()


## Reference cards below the live data, one at a time so nothing needs
## scrolling: ATIS, the approach summary, and the (collapsible) phraseology.
func _tab_row() -> Control:
	var row := S.hbox(4)
	for t: Array in [["freq", "FREQUENCY"], ["atis", "ATIS"], ["app", "ILS RWY 27"], ["phr", "PHRASEOLOGY"]]:
		var id := String(t[0])
		var b := S.flat_button(String(t[1]), 13, Look.FDD_HEAD)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			# The phraseology card collapses back to the frequency when clicked again.
			_select_tab("freq" if id == "phr" and _tab == "phr" else id))
		_tabs[id] = b
		row.add_child(b)
	return row


func _select_tab(id: String) -> void:
	_tab = id
	for key: String in _tabs:
		var b: Button = _tabs[key]
		var on := key == id
		var col := Look.FDD_TEXT if on else Look.FDD_FAINT
		for st: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color"]:
			b.add_theme_color_override(st, col)
		var sb := S.box(Color(1, 1, 1, 0.06) if on else Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 6, 4)
		sb.border_color = Look.FDD_HEAD if on else Look.FDD_LINE
		sb.border_width_bottom = 2 if on else 1
		b.add_theme_stylebox_override(&"normal", sb)
		b.add_theme_stylebox_override(&"hover", sb)
	_atis_text.visible = id == "atis"
	_approach.visible = id == "app"
	_freq.visible = id == "freq"
	_refresh_phraseology()
	_refresh_freq()


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
		cell.add_child(S.label(String(CELL_LABELS[key]), 11, Look.FDD_FAINT, Look.sans(600)))
		var val := S.label("—", 17, Look.FDD_TEXT, Look.mono(600))
		cell.add_child(val)
		_cells[key] = val
		grid.add_child(cell)
	v.add_child(grid)
	_scratch = LineEdit.new()
	_scratch.placeholder_text = "Scratchpad (local) — shown in tag"
	_scratch.max_length = 32
	_scratch.context_menu_enabled = false
	_scratch.add_theme_font_override(&"font", Look.mono(600))
	_scratch.add_theme_font_size_override(&"font_size", S.fs(15))
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
	if _card != null:
		_card.refresh_calls()
	_select_tab(_tab)


func _vis_text(m: int) -> String:
	return "%d M" % m if m < 5000 else "%d KM" % (m / 1000)


func _refresh_controllers() -> void:
	var names := PackedStringArray()
	for p: Dictionary in Session.round_players:
		if String(p.get("role", "")) == "controller":
			var n := String(p.get("name", "?"))
			var me := int(p.get("id", 0)) == Session.my_id
			names.append(n + " (you)" if me and n.to_lower() != "you" else n)
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
		if _shown_cs != "":
			_card.set_target("")
		_shown_cs = ""
		return
	if cs != _shown_cs:
		_shown_cs = cs
		_scratch.text = String(model.scratch.get(cs, ""))
		_card.set_target(cs)
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
	(_cells["GS"] as Label).text = str(int(round(float(t["gs"]))))
	(_cells["TRK"] as Label).text = "%s°" % Fmt.hdg_text(float(t["track"]))
	(_cells["DME"] as Label).text = "%.1f" % p.length()
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
	_select_tab("phr" if on else "freq")


## The frequency as heard: the latest text transmissions, newest last; replies to
## us and our own messages marked.
func _refresh_freq() -> void:
	if _freq == null:
		return
	for c in _freq.get_children():
		c.queue_free()
	if _tab != "freq":
		return
	var log: Array[Dictionary] = Session.dl_log
	if log.is_empty():
		var hint := S.label("Nothing on the text radio yet. Select a target, set HDG / ALT / SPD or type a command (Enter), then SEND. Pilots reply here.", 14,
			Look.FDD_FAINT, Look.sans(400))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(80, 0)
		_freq.add_child(hint)
		return
	for i in range(maxi(0, log.size() - FREQ_LINES), log.size()):
		var m: Dictionary = log[i]
		var mine := int(m.get("from", 0)) == Session.my_id
		var status := String(m.get("status", ""))
		var h := S.hbox(8)
		var tl := S.label(Fmt.mmss(float(m.get("time", 0.0))), 13, Look.FDD_FAINT, Look.mono(500))
		tl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(tl)
		var who := S.label("YOU" if mine else Datalink.sender_label(m, _player_name(int(m.get("from", 0)))), 13,
			Look.FDD_DIM if mine else (Look.FDD_ACCENT if String(m.get("role", "")) == "controller" else Look.FDD_TEXT), Look.mono(700))
		who.custom_minimum_size = Vector2(92, 0)
		who.clip_text = true
		who.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(who)
		var text := String(m.get("text", ""))
		var col := Look.FDD_TEXT if not mine else Look.FDD_DIM
		match status:
			"queued":
				text = "waiting for a clear frequency…"
				col = Look.FDD_FAINT
			"blocked":
				text = "BLOCKED" + (": " + text if text != "" else "")
				col = Look.FDD_RED
			"expired":
				text = "NOT SENT: the frequency never cleared"
				col = Look.FDD_RED
			"cut":
				text = "CUT OFF"
				col = Look.FDD_RED
		if String(m.get("kind", "")) == Datalink.KIND_REPLY and Datalink.has_item(m, "unable"):
			col = Look.FDD_AMBER
		var l := S.label(text, 14, col, Look.sans(400))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size = Vector2(80, 0)
		h.add_child(l)
		if mine and status in ["blocked", "expired", "cut"]:
			var again := Datalink.resend_copy(m)
			var b := S.flat_button("RESEND", 12, Look.FDD_ACCENT)
			b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			b.pressed.connect(func() -> void:
				if Session.dl_refusal() == "":
					Session.send_dl(again))
			h.add_child(b)
		_freq.add_child(h)


func _player_name(id: int) -> String:
	for p: Dictionary in Session.round_players:
		if int(p.get("id", 0)) == id:
			return String(p.get("name", ""))
	return "?"


func _refresh_phraseology() -> void:
	if _phr_body == null:
		return
	for c in _phr_body.get_children():
		c.queue_free()
	_phr_body.visible = _tab == "phr"
	if _tab != "phr":
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
