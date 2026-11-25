extends Control
## On-glass chrome: the menu bar (layer toggles, range, reset), the system
## status area, the alert list, the range/bearing line, the cursor readout and
## a one-line help. Fills ctx.dcb_rects for hit testing.

const Ctx := preload("res://scenes/controller/scope/scope_ctx.gd")
const Look := preload("res://scenes/controller/scope/scope_theme.gd")
const Fmt := preload("res://scenes/controller/scope/scope_format.gd")
const DU := preload("res://scenes/controller/scope/draw_util.gd")
const Model := preload("res://scenes/controller/scope/scope_model.gd")

const HELP := "WHEEL zoom · DRAG pan · DBL-CLICK reset · RMB/SHIFT-DRAG measure · CLICK select · 1-9 leader · F1-F8 maps · TAB room"

var ctx: Ctx


func _draw() -> void:
	if ctx == null:
		return
	_dcb()
	if ctx.world.is_empty():
		return
	var y := _status()
	_alert_list(y)
	_rbl()
	_footer()


func _dcb() -> void:
	ctx.dcb_rects.clear()
	var h := ctx.dcb_h
	draw_rect(Rect2(0, 0, ctx.size.x, h), Look.DCB_BG)
	draw_line(Vector2(0, h - 0.5), Vector2(ctx.size.x, h - 0.5), Look.DCB_EDGE, ctx.px(1.0))
	var font := ctx.mono(700)
	var fsz := ctx.fs(13.0)
	var pad := ctx.px(5.0)
	var bw := ctx.px(62.0)
	var x := ctx.px(8.0)
	for key in Model.LAYER_KEYS:
		var on := bool(ctx.model.layers[key])
		_button(Rect2(x, pad, bw, h - pad * 2.0), "layer:" + key, String(Model.LAYER_LABELS[key]), on, font, fsz)
		x += bw + ctx.px(4.0)
	x += ctx.px(18.0)
	_button(Rect2(x, pad, bw, h - pad * 2.0), "rng_in", "RNG−", false, font, fsz)
	x += bw + ctx.px(4.0)
	var rng_r := Rect2(x, pad, bw * 1.1, h - pad * 2.0)
	DU.text(self, font, rng_r.get_center(), "%d NM" % int(round(ctx.xform.range_nm())), fsz, Look.DCB_TEXT, 0, 0)
	x += rng_r.size.x + ctx.px(4.0)
	_button(Rect2(x, pad, bw, h - pad * 2.0), "rng_out", "RNG+", false, font, fsz)
	x += bw + ctx.px(4.0)
	_button(Rect2(x, pad, bw, h - pad * 2.0), "reset", "RST", false, font, fsz)
	x += bw + ctx.px(4.0)
	_button(Rect2(x, pad, bw * 1.2, h - pad * 2.0), "ldr_auto", "LDR A", false, font, fsz)
	var ident := "%s APP" % String(ctx.status.get("icao", ""))
	DU.text(self, ctx.mono(700), Vector2(ctx.size.x - ctx.px(14.0), h * 0.5), ident, ctx.fs(14.0), Look.DCB_TEXT, 1, 0)


func _button(r: Rect2, id: String, label: String, on: bool, font: Font, fsz: int) -> void:
	var hover := r.has_point(ctx.mouse)
	draw_rect(r, Look.DCB_ON if on else (Look.DCB_BG.lerp(Look.DCB_ON, 0.4) if hover else Look.DCB_BG))
	draw_rect(r, Look.DCB_EDGE if on or hover else Look.DCB_EDGE.darkened(0.4), false, ctx.px(1.0))
	DU.text(self, font, r.get_center(), label, fsz, Look.DCB_TEXT if on or not id.begins_with("layer:") else Look.DCB_TEXT_OFF, 0, 0)
	ctx.dcb_rects.append({"id": id, "rect": r})


## System status block under the menu bar. Returns the y below it.
func _status() -> float:
	var font := ctx.mono(600)
	var fsz := ctx.fs(14.0)
	var lh := font.get_height(fsz) * 1.08
	var age := ctx.model.sweep_age_sec(ctx.now_ms)
	var sep := ctx.sep()
	print("DBG chrome age ", age, " now ", ctx.now_ms)
	var lines: Array[Array] = [
		["%s   %s" % [String(ctx.status.get("icao", "")), Fmt.mmss(float(ctx.status.get("time", 0.0)))], Look.HUD],
		["ATIS %s  QNH %s" % [String(ctx.status.get("atis_letter", "-")), str(ctx.status.get("qnh", "----"))], Look.HUD],
		["RNG %d  TA %d" % [int(round(ctx.xform.range_nm())), int(ctx.world.get("transition_alt_ft", 6000))], Look.HUD],
		["SEP %dNM/%dFT" % [int(sep["lateral_nm"]), int(sep["vertical_ft"])], Look.HUD],
		["NO RADAR DATA" if age < 0.0 else "SWEEP %.1fs" % age, Look.LA if age < 0.0 or age > 4.5 else Look.HUD],
	]
	var x := ctx.px(14.0)
	var y := ctx.dcb_h + ctx.px(12.0)
	var w := ctx.px(196.0)
	draw_rect(Rect2(x - ctx.px(6.0), y - ctx.px(5.0), w, lh * lines.size() + ctx.px(10.0)), Color(Look.BG, 0.75))
	for l in lines:
		DU.text(self, font, Vector2(x, y), String(l[0]), fsz, l[1])
		y += lh
	return y + ctx.px(10.0)


func _alert_list(y0: float) -> void:
	var ca := PackedStringArray()
	var la := PackedStringArray()
	for cs in ctx.model.order:
		var t: Dictionary = ctx.model.targets[cs]
		if String(t["status"]) != "flying":
			continue
		if bool(t.get("conflict", false)):
			ca.append(cs)
		if bool(t.get("msaw", false)):
			la.append(cs)
	if ca.is_empty() and la.is_empty():
		return
	var font := ctx.mono(700)
	var fsz := ctx.fs(14.0)
	var lh := font.get_height(fsz) * 1.08
	var x := ctx.px(14.0)
	var y := y0
	var flash := ctx.flash_on or ctx.force_flash
	for row: Array in [["CA", ca, Look.CA], ["LA", la, Look.LA]]:
		var names: PackedStringArray = row[1]
		if names.is_empty():
			continue
		var col: Color = row[2]
		DU.text(self, font, Vector2(x, y), String(row[0]), fsz, col if flash else col.darkened(0.4), -1, -1, ctx.px(4.0), Look.BG)
		DU.text(self, font, Vector2(x + ctx.px(36.0), y), " ".join(names), fsz, col, -1, -1, ctx.px(4.0), Look.BG)
		y += lh


func _rbl() -> void:
	if not ctx.rbl_active:
		return
	var a := ctx.xform.to_screen(ctx.rbl_a)
	var b := ctx.xform.to_screen(ctx.rbl_b)
	draw_line(a, b, Look.RBL, ctx.px(1.3), true)
	draw_circle(a, ctx.px(3.0), Look.RBL)
	draw_circle(b, ctx.px(3.0), Look.RBL)
	var dist := ctx.rbl_a.distance_to(ctx.rbl_b)
	if dist < 0.05:
		return
	var label := "BRG %s° / %.1f NM" % [Fmt.hdg_text(Fmt.bearing_to(ctx.rbl_a, ctx.rbl_b)), dist]
	var font := ctx.mono(700)
	var fsz := ctx.fs(14.0)
	var mid := (a + b) * 0.5 + Vector2(ctx.px(12.0), -ctx.px(12.0))
	var w := DU.text_width(font, label, fsz)
	var h := font.get_height(fsz)
	draw_rect(Rect2(mid.x - ctx.px(5.0), mid.y - h * 0.5 - ctx.px(3.0), w + ctx.px(10.0), h + ctx.px(6.0)), Look.BLOCK_BACK)
	DU.text(self, font, mid, label, fsz, Look.RBL, -1, 0)


func _footer() -> void:
	var top := ctx.size.y - ctx.foot_h
	draw_rect(Rect2(0, top, ctx.size.x, ctx.foot_h), Look.DCB_BG)
	draw_line(Vector2(0, top + 0.5), Vector2(ctx.size.x, top + 0.5), Look.DCB_EDGE.darkened(0.3), ctx.px(1.0))
	var mid := top + ctx.foot_h * 0.5
	DU.text(self, ctx.mono(500), Vector2(ctx.size.x - ctx.px(12.0), mid), HELP, ctx.fs(11.0), Look.HUD_DIM, 1, 0)
	if ctx.mouse.x < 0.0 or not ctx.xform.plot.has_point(ctx.mouse):
		return
	var w := ctx.xform.to_world(ctx.mouse)
	var d := w.length()
	var txt := "%s %s°/%.1fNM" % [String(ctx.status.get("icao", "")).substr(1), Fmt.hdg_text(Fmt.bearing_to(Vector2.ZERO, w)), d]
	var msa := Fmt.msa_at(ctx.world, w)
	if msa > 0 and d <= 25.0:
		txt += "   MSA %d" % msa
	DU.text(self, ctx.mono(600), Vector2(ctx.px(14.0), mid), txt, ctx.fs(13.0), Look.HUD, -1, 0)
