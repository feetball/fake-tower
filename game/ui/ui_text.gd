class_name UiText
extends RefCounted
## Player-facing wording shared by the HUD, lobby and end screen
## (mirrors src/client/text.ts and roundbar.ts of the browser version).

const OUTCOME_TEXT := {
	"landed": "Landed safely",
	"terrain": "Flew into terrain",
	"collision": "Mid-air collision",
	"fuel": "Ran out of fuel",
	"runway": "Crashed on the runway",
	"flying": "Still airborne",
	"": "Still airborne",
}

const EVENT_TEXT := {
	"landed": "%s landed runway 27",
	"terrain": "%s flew into terrain",
	"collision": "Mid-air collision: %s",
	"fuel": "%s ran out of fuel",
	"runway": "%s crashed on the runway",
}


static func outcome_text(outcome: String) -> String:
	return OUTCOME_TEXT.get(outcome, outcome.capitalize())


static func outcome_color(outcome: String) -> Color:
	if outcome == "landed":
		return UiTheme.ACCENT
	if outcome == "" or outcome == "flying":
		return UiTheme.DIM
	return UiTheme.RED


static func event_text(e: Dictionary) -> String:
	var cs := " and ".join(PackedStringArray(e.get("callsigns", [])))
	var kind := str(e.get("kind", ""))
	return EVENT_TEXT.get(kind, "%s: " + kind) % cs


static func mmss(sec: float) -> String:
	var s := maxi(0, int(floor(sec)))
	return "%02d:%02d" % [s / 60, s % 60]


## {text, kind} for the radio indicator. kind: idle | rx | tx | blocked | dead.
static func radio_state(tx: Array, my_id: int, local_ptt: bool, radio_dead: bool) -> Dictionary:
	if tx.size() >= 2:
		return {"text": "BLOCKED", "kind": "blocked"}
	if tx.size() == 1:
		var id := int(tx[0])
		if id == my_id:
			return {"text": "TX", "kind": "tx"}
		var rp := Sess.round_player(id)
		var nm := Sess.player_name(id)
		var tag := nm
		if str(rp.get("role", "")) == "pilot" and str(rp.get("callsign", "")) != "":
			tag = str(rp["callsign"])
		elif str(rp.get("role", "")) == "controller":
			tag = "%s · CTL" % nm
		return {"text": "RX  " + tag, "kind": "rx"}
	if local_ptt:
		if radio_dead:
			return {"text": "RADIO DEAD", "kind": "dead"}
		return {"text": "TX", "kind": "tx"}
	return {"text": "IDLE", "kind": "idle"}


static func controller_names() -> PackedStringArray:
	var out := PackedStringArray()
	for p: Variant in Sess.round_players():
		if p is Dictionary and str(p.get("role", "")) == "controller":
			out.append(str(p.get("name", "")))
	return out


## {text, kind} for the role line. kind: pilot | real | impostor | none.
static func role_line() -> Dictionary:
	match Sess.my_role():
		"pilot":
			var ctl := controller_names()
			if ctl.is_empty():
				return {"text": "%s  ·  Practice flight — no controllers on frequency." % Sess.my_callsign(),
					"kind": "pilot"}
			return {"text": "%s  ·  Two controllers on frequency: %s. One is the impostor." % [
				Sess.my_callsign(), " and ".join(ctl)], "kind": "pilot"}
		"controller":
			if Sess.i_am_impostor():
				return {"text": "YOU ARE THE IMPOSTOR — the tower wins only if more than half the aircraft land.",
					"kind": "impostor"}
			return {"text": "YOU ARE THE REAL TOWER — get them down safely.", "kind": "real"}
	return {"text": "", "kind": "none"}
