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
