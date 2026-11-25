class_name HowToPlay
extends RefCounted
## The two-column rules summary used by the lobby and the How to Play overlay.

const CONTROLLER_LINES := [
	"Two players get the radar scope. Both claim to be Fallow Approach.",
	"One is the real tower: vector everyone onto the ILS 27 and land them safely.",
	"The other is the impostor: wins unless more than half the aircraft land. Below the MSA, a wrong QNH, two on the approach at once, endless holding…",
	"Everyone knows who the two controllers are. Only they know which one is real.",
]
const PILOT_LINES := [
	"You fly a twin jet in fog through the autopilot panel. No traffic display.",
	"Check every instruction against the ATIS and the approach plate: QNH, MSA, platform altitude 3000.",
	"Only you see your fuel. Declare \"minimum fuel\" by voice.",
	"To land: established on localizer and glideslope, gear down, flaps 3, 155 kt or less.",
]
## Controls reference for the full overlay: [key or input, what it does].
const PILOT_KEYS := [
	["1 / 2 / 3", "Panel / outside / pedestal view"],
	["Hold RMB", "Look around (wheel over empty space zooms)"],
	["I / P", "ATIS / approach plate (press again to close)"],
	["← / →", "Heading −1 / +1  (Shift ×10)"],
	["↑ / ↓", "Altitude +100 / −100 ft  (Shift ×10)"],
	["PgUp / PgDn", "Speed +1 / −1 kt  (Shift ×10)"],
	["[ / ]", "Altimeter −1 / +1 hPa  (Shift ×5)"],
	["B", "Altimeter STD 1013 / back to QNH"],
	["A", "Arm / disarm approach (APPR)"],
	["G", "Gear up / down"],
	["F / Shift+F", "Flaps down / up one step"],
	["Wheel, drag", "Turn the knob under the cursor (Shift: big steps)"],
	["Click", "Gear lever, flap lever, APPR, baro knob (STD), master warning"],
	["Space", "Push-to-talk (hold)"],
]
const CONTROLLER_KEYS := [
	["Wheel", "Zoom the scope at the cursor"],
	["Drag", "Pan (middle button also pans)"],
	["Double-click", "Reset the view (also Home)"],
	["Click", "Select a target (also in the traffic list)"],
	["Ctrl+click", "Select and turn its data block 45°"],
	["RMB / Shift+drag", "Measure range and bearing; a click clears it"],
	["1–4, 6–9", "Data block direction for the selected target (5 = auto)"],
	["F1–F8", "Layers: RR CL FIX TERR MSA HOLD PTL HIST"],
	["+ / −", "Zoom in / out (also PgUp / PgDn)"],
	["Del / Backspace", "Deselect and clear the measuring line"],
	["Tab", "Switch between scope and room view"],
	["Hold RMB off scope", "Look around the room"],
	["CA / LA", "Conflict (under 3 nm and 1000 ft) / below MSA, not on the localizer"],
	["Space", "Push-to-talk (hold)"],
]
const RADIO_LINE := "One frequency, push-to-talk on Space. Two people keying at once block it — nobody hears anything but a squeal."


static func build(compact: bool = false) -> VBoxContainer:
	var text_var := &"Small" if compact else &"Dim"
	var cols := UiKit.hbox(48 if not compact else 36)
	for spec: Array in [["Controllers · 2", CONTROLLER_LINES, UiTheme.ACCENT], ["Pilots · 2–6", PILOT_LINES, UiTheme.BLUE]]:
		var col := UiKit.vbox(12)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := UiKit.heading(spec[0])
		h.add_theme_color_override(&"font_color", (spec[2] as Color).lerp(UiTheme.DIM, 0.3))
		col.add_child(h)
		col.add_child(UiKit.bullets(spec[1], text_var))
		cols.add_child(col)
	var radio := UiKit.label(RADIO_LINE, text_var, true)
	radio.add_theme_color_override(&"font_color", UiTheme.TEXT)
	return UiKit.vbox(18 if not compact else 12, [cols, UiKit.hsep(), radio])


## Pilot and controller key tables, side by side. Full overlay only.
static func build_controls() -> VBoxContainer:
	var cols := UiKit.hbox(48)
	for spec: Array in [["Pilot controls", PILOT_KEYS, UiTheme.BLUE], ["Controller controls", CONTROLLER_KEYS, UiTheme.ACCENT]]:
		var col := UiKit.vbox(10)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := UiKit.heading(spec[0])
		h.add_theme_color_override(&"font_color", (spec[2] as Color).lerp(UiTheme.DIM, 0.3))
		col.add_child(h)
		col.add_child(_key_table(spec[1], spec[2]))
		cols.add_child(col)
	var note := UiKit.label("Full manual: HOW_TO_PLAY.md next to the game.", &"Small", true)
	return UiKit.vbox(14, [cols, note])


static func _key_table(rows: Array, tint: Color) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 7)
	for r: Array in rows:
		var k := UiKit.label(r[0], &"MonoSmall")
		k.add_theme_color_override(&"font_color", tint.lerp(UiTheme.TEXT, 0.45))
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		k.custom_minimum_size = Vector2(118.0, 0.0)
		var a := UiKit.label(r[1], &"Small", true)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		a.custom_minimum_size = Vector2(120.0, 0.0)
		grid.add_child(k)
		grid.add_child(a)
	return grid
