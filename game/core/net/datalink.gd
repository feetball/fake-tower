extends RefCounted
## The text radio ("datalink"): structured messages on the one frequency, for players
## who would rather not talk, and for the AI controllers and pilots. A message is a
## short list of standard items (a heading, an altitude, "cleared ILS approach"...),
## never free text, so the host renders the same phraseology for everyone and an AI
## can act on it. Pure: validation of untrusted client messages, rendering, airtime,
## and the controller's typed shorthand (parse_command).
##
## Client -> host (Session.send_dl), checked by parse():
##   controller clearance  {kind: "clr", to: <callsign>, items: [{t: "hdg", v: 240, turn: "L"}, ...]}
##   controller call       {kind: "call", items: [{t: "atis"}]} or [{t: "accuse", who: <player id>}]
##   pilot reply           {kind: "reply", re: <message id>, items: [{t: "wilco"}]}
##                         (also unable {why}, standby, say_again)
##   pilot call            {kind: "call", items: [{t: "min_fuel"}]} ... (PILOT_CALLS)
## Host -> every player (`dl` message, see Room): the parsed message plus
##   id, time, from (player id), role, from_cs (pilot's callsign or ""), text,
##   status: "queued" (sender only) | "ok" | "blocked" (text "" except for the sender)
##           | "expired" (sender only: the frequency never cleared) | "cut" (sender's radio died).

const Validate := preload("res://core/net/validate.gd")
const Geo := preload("res://core/sim/geo.gd")

const KIND_CLR := "clr"
const KIND_CALL := "call"
const KIND_REPLY := "reply"
## Clearance items, in the order they are read out.
const CLR_ORDER: Array[String] = [
	"disregard", "traffic", "low_alt", "contact", "cancel", "hdg", "orbit", "alt", "spd", "qnh",
	"app", "expect", "land", "ga", "roger",
]
const CTL_CALLS: Array[String] = ["atis", "accuse"]
const PILOT_CALLS: Array[String] = [
	"checkin", "req_vectors", "established", "min_fuel", "mayday_fuel", "going_around", "accuse",
]
const REPLIES: Array[String] = ["wilco", "unable", "standby", "say_again"]
const UNABLE_WHY: Array[String] = ["", "msa", "qnh", "terrain", "fuel"]
## Clearance items that cannot go together in one message.
const EXCLUSIVE: Array[Array] = [["hdg", "orbit"], ["app", "cancel"], ["app", "ga"], ["land", "ga"], ["land", "cancel"]]

const MAX_ITEMS := 7
const MAX_CALLSIGN := 8
const ALT_MIN := 1000
const ALT_MAX := 20000
const SPD_MIN := 140
const SPD_MAX := 250
const QNH_MIN := 950
const QNH_MAX := 1050
## Airtime: roughly the time it takes to say the message (VHF phraseology pace).
const AIRTIME_BASE := 0.8
const AIRTIME_PER_WORD := 0.25
const AIRTIME_MIN := 1.5
const AIRTIME_MAX := 6.0
const STATION := "Fallow Approach"
const PHONETIC := ["Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliett",
	"Kilo", "Lima", "Mike", "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform",
	"Victor", "Whiskey", "X-ray", "Yankee", "Zulu"]


# ---------------------------------------------------------------- builders (AI and UI)

static func clr(to: String, items: Array) -> Dictionary:
	return {"kind": KIND_CLR, "to": to, "items": items}


static func radio_call(t: String, who: int = 0) -> Dictionary:
	var it := {"t": t}
	if t == "accuse":
		it["who"] = who
	return {"kind": KIND_CALL, "items": [it]}


static func reply(re: int, t: String, why: String = "") -> Dictionary:
	var it := {"t": t}
	if t == "unable":
		it["why"] = why
	return {"kind": KIND_REPLY, "re": re, "items": [it]}


static func hdg(v: int, turn: String = "") -> Dictionary:
	return {"t": "hdg", "v": norm_hdg(v), "turn": turn}


static func alt(v: int) -> Dictionary:
	return {"t": "alt", "v": v}


static func spd(v: int) -> Dictionary:
	return {"t": "spd", "v": v}


static func qnh(v: int) -> Dictionary:
	return {"t": "qnh", "v": v}


static func orbit(turn: String) -> Dictionary:
	return {"t": "orbit", "turn": turn}


static func item(t: String) -> Dictionary:
	return {"t": t}


## Heading as said on the radio: 1..360 (north is 360, never 000).
static func norm_hdg(v: int) -> int:
	var h := posmod(v, 360)
	return 360 if h == 0 else h


## "L", "R" or "" (no turn worth naming) for a turn from `track` onto `target`.
static func turn_dir(track: float, target: float) -> String:
	var d := Geo.angle_diff(track, target)
	if absf(d) < 5.0:
		return ""
	return "L" if d < 0.0 else "R"


## The item of type `t` in a message's items, or {}.
static func find_item(m: Dictionary, t: String) -> Dictionary:
	for it: Variant in m.get("items", []):
		if it is Dictionary and String((it as Dictionary).get("t", "")) == t:
			return it
	return {}


static func has_item(m: Dictionary, t: String) -> bool:
	return not find_item(m, t).is_empty()


# ---------------------------------------------------------------- validation (untrusted)

## Parse a client message for a player of `role` ("controller" | "pilot"). Fills `out`
## with {kind, to, re, items} (items normalised, clearances in reading order) and
## returns "" when valid, else the reason. Context checks (does the callsign exist,
## is `who` a controller) are the Room's.
static func parse(raw: Variant, role: String, out: Dictionary) -> String:
	out.clear()
	if typeof(raw) != TYPE_DICTIONARY:
		return "Bad message"
	var d: Dictionary = raw
	var kind: Variant = d.get("kind")
	if typeof(kind) != TYPE_STRING:
		return "Bad message: kind"
	var raw_items: Variant = d.get("items")
	if typeof(raw_items) != TYPE_ARRAY or (raw_items as Array).is_empty() or (raw_items as Array).size() > MAX_ITEMS:
		return "Bad message: items"
	var allowed: Array[String] = []
	var single := true
	match [role, String(kind)]:
		["controller", KIND_CLR]:
			allowed = CLR_ORDER
			single = false
		["controller", KIND_CALL]:
			allowed = CTL_CALLS
		["pilot", KIND_CALL]:
			allowed = PILOT_CALLS
		["pilot", KIND_REPLY]:
			allowed = REPLIES
		_:
			return "%s cannot send a %s message" % ["Controllers" if role == "controller" else "Pilots", kind]
	if single and (raw_items as Array).size() != 1:
		return "Bad message: one item expected"
	var items: Array = []
	var seen := {}
	for r: Variant in raw_items:
		var it := {}
		var err := _parse_item(r, allowed, it)
		if err != "":
			return err
		if seen.has(it["t"]):
			return "Bad message: %s twice" % it["t"]
		seen[it["t"]] = true
		items.append(it)
	for pair: Array in EXCLUSIVE:
		if seen.has(pair[0]) and seen.has(pair[1]):
			return "Bad message: %s with %s" % [pair[0], pair[1]]
	var to := ""
	var re := 0
	if kind == KIND_CLR:
		var t: Variant = d.get("to")
		if typeof(t) != TYPE_STRING or not _valid_callsign(String(t)):
			return "Bad message: to"
		to = String(t)
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return CLR_ORDER.find(String(a["t"])) < CLR_ORDER.find(String(b["t"])))
	elif kind == KIND_REPLY:
		var rv: Variant = d.get("re")
		if not _is_int(rv) or int(rv) < 1:
			return "Bad message: re"
		re = int(rv)
	out.merge({"kind": String(kind), "to": to, "re": re, "items": items})
	return ""


static func _parse_item(raw: Variant, allowed: Array[String], out: Dictionary) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "Bad message: item"
	var d: Dictionary = raw
	var t: Variant = d.get("t")
	if typeof(t) != TYPE_STRING or not allowed.has(String(t)):
		return "Bad message: item %s" % (str(t) if typeof(t) == TYPE_STRING else "?")
	var ts := String(t)
	out["t"] = ts
	match ts:
		"hdg":
			var v: Variant = d.get("v")
			if not _is_int(v) or int(v) < 0 or int(v) > 360:
				return "Bad message: heading"
			out["v"] = norm_hdg(int(v))
			var turn: Variant = d.get("turn", "")
			if typeof(turn) != TYPE_STRING or not ["", "L", "R"].has(turn):
				return "Bad message: turn"
			out["turn"] = String(turn)
		"alt":
			var v: Variant = d.get("v")
			if not _is_int(v) or int(v) < ALT_MIN or int(v) > ALT_MAX or int(v) % 100 != 0:
				return "Bad message: altitude"
			out["v"] = int(v)
		"spd":
			var v: Variant = d.get("v")
			if not _is_int(v) or int(v) < SPD_MIN or int(v) > SPD_MAX:
				return "Bad message: speed"
			out["v"] = int(v)
		"qnh":
			var v: Variant = d.get("v")
			if not _is_int(v) or int(v) < QNH_MIN or int(v) > QNH_MAX:
				return "Bad message: QNH"
			out["v"] = int(v)
		"orbit":
			var turn: Variant = d.get("turn")
			if typeof(turn) != TYPE_STRING or not ["L", "R"].has(turn):
				return "Bad message: orbit"
			out["turn"] = String(turn)
		"accuse":
			var who: Variant = d.get("who")
			if not _is_int(who) or int(who) == 0:
				return "Bad message: who"
			out["who"] = int(who)
		"unable":
			var why: Variant = d.get("why", "")
			if typeof(why) != TYPE_STRING or not UNABLE_WHY.has(why):
				return "Bad message: reason"
			out["why"] = String(why)
	return ""


static func _is_int(v: Variant) -> bool:
	return Validate.is_finite_num(v) and float(v) == floorf(float(v)) and absf(float(v)) < 1e9


static func _valid_callsign(cs: String) -> bool:
	if cs.length() < 2 or cs.length() > MAX_CALLSIGN:
		return false
	for i in cs.length():
		var c := cs.unicode_at(i)
		if not ((c >= 65 and c <= 90) or (c >= 48 and c <= 57)):
			return false
	return true


# ---------------------------------------------------------------- rendering

## The message as said on the radio. `ctx` (all optional):
##   letter, qnh, wind_dir, wind_kt   the current ATIS
##   from_cs                          the sending pilot's callsign
##   to_alt                           the addressed aircraft's altitude (climb / descend), -1 unknown
##   names                            {player id: name} for accusations
##   fuel_min, ind_alt                the sending pilot's fuel and indicated altitude
static func render(m: Dictionary, ctx: Dictionary = {}) -> String:
	match String(m.get("kind", "")):
		KIND_CLR:
			return _render_clr(m, ctx)
		KIND_REPLY:
			return _render_reply(m, ctx)
		KIND_CALL:
			return _render_call(m, ctx)
	return ""


static func phonetic(letter: String) -> String:
	var i := letter.to_upper().unicode_at(0) - 65 if letter != "" else -1
	return PHONETIC[i] if i >= 0 and i < PHONETIC.size() else letter


static func _render_clr(m: Dictionary, ctx: Dictionary) -> String:
	var parts := PackedStringArray()
	var cleared := has_item(m, "app")
	var to_alt := float(ctx.get("to_alt", -1.0))
	for it: Dictionary in m.get("items", []):
		match String(it["t"]):
			"disregard":
				parts.append("disregard previous instructions")
			"traffic":
				parts.append("traffic alert")
			"low_alt":
				parts.append("low altitude alert, check your altitude immediately")
			"contact":
				parts.append("%s, radar contact, information %s is current" % [STATION, phonetic(String(ctx.get("letter", "")))])
			"cancel":
				parts.append("cancel approach clearance")
			"hdg":
				var h := "%03d" % int(it["v"])
				match String(it.get("turn", "")):
					"L":
						parts.append("turn left heading " + h)
					"R":
						parts.append("turn right heading " + h)
					_:
						parts.append("fly heading " + h)
			"orbit":
				parts.append("make a %s three-sixty for spacing" % ("left" if it["turn"] == "L" else "right"))
			"alt":
				var a := int(it["v"])
				if cleared:
					parts.append("maintain %d until established on the localizer" % a)
				elif to_alt >= 0.0 and float(a) < to_alt - 150.0:
					parts.append("descend and maintain %d" % a)
				elif to_alt >= 0.0 and float(a) > to_alt + 150.0:
					parts.append("climb and maintain %d" % a)
				else:
					parts.append("maintain %d" % a)
			"spd":
				parts.append("speed %d knots" % int(it["v"]))
			"qnh":
				parts.append("QNH %d" % int(it["v"]))
			"app":
				parts.append("cleared ILS approach runway 27")
			"expect":
				parts.append("expect ILS approach runway 27")
			"land":
				var wind := ""
				if ctx.has("wind_dir"):
					wind = ", wind %03d degrees %d knots" % [int(ctx["wind_dir"]), int(ctx.get("wind_kt", 0))]
				parts.append("runway 27, cleared to land" + wind)
			"ga":
				parts.append("go around, fly the published missed approach")
			"roger":
				parts.append("roger")
	return "%s, %s." % [String(m.get("to", "")), ", ".join(parts)]


static func _render_reply(m: Dictionary, ctx: Dictionary) -> String:
	var cs := String(ctx.get("from_cs", ""))
	var it: Dictionary = (m.get("items", [{}]) as Array)[0]
	match String(it.get("t", "")):
		"wilco":
			return "Wilco, %s." % cs
		"standby":
			return "Standby, %s." % cs
		"say_again":
			return "Say again, %s." % cs
		"unable":
			match String(it.get("why", "")):
				"msa":
					return "Unable, %s, that is below the minimum safe altitude." % cs
				"qnh":
					return "Unable, %s, the ATIS gives QNH %d." % [cs, int(ctx.get("qnh", 0))]
				"terrain":
					return "Unable, %s, that heading takes us into terrain." % cs
				"fuel":
					return "Unable, %s, not enough fuel for that." % cs
			return "Unable, %s." % cs
	return ""


static func _render_call(m: Dictionary, ctx: Dictionary) -> String:
	var cs := String(ctx.get("from_cs", ""))
	var it: Dictionary = (m.get("items", [{}]) as Array)[0]
	var names: Dictionary = ctx.get("names", {})
	match String(it.get("t", "")):
		"atis":
			return "All stations, %s, information %s is current, QNH %d." % [
				STATION, phonetic(String(ctx.get("letter", ""))), int(ctx.get("qnh", 0))]
		"accuse":
			var who := String(names.get(int(it.get("who", 0)), "the other controller"))
			if cs == "":
				return "All stations, disregard all instructions from %s, that is not %s." % [who, STATION]
			return "All stations, %s, do not trust %s, that is the impostor." % [cs, who]
		"checkin":
			var letter := String(ctx.get("letter", ""))
			var info := ", information %s" % phonetic(letter) if letter != "" else ""
			return "%s, %s, with you at %d%s." % [STATION, cs, int(ctx.get("ind_alt", 0)), info]
		"req_vectors":
			return "%s, %s, request vectors for the ILS runway 27." % [STATION, cs]
		"established":
			return "%s, established localizer runway 27." % cs
		"min_fuel":
			return "%s, %s, minimum fuel." % [STATION, cs]
		"mayday_fuel":
			return "MAYDAY MAYDAY MAYDAY, %s, fuel emergency, %d minutes of fuel remaining." % [
				cs, maxi(0, int(floor(float(ctx.get("fuel_min", 0.0)))))]
		"going_around":
			return "%s, going around." % cs
	return ""


## Seconds the message occupies the frequency.
static func airtime(text: String) -> float:
	var words := text.split(" ", false).size()
	return clampf(AIRTIME_BASE + AIRTIME_PER_WORD * words, AIRTIME_MIN, AIRTIME_MAX)


## Short label for a message's sender in a transcript ("Ann", "DAL123").
static func sender_label(m: Dictionary, name: String) -> String:
	var cs := String(m.get("from_cs", ""))
	return cs if cs != "" else name


# ---------------------------------------------------------------- controller shorthand

## Turns typed shorthand into clearance items. Tokens (case-insensitive, any order):
##   h270 fly heading · l270 / r270 turn left / right · a55 or a5500 altitude (also c / d)
##   s180 speed · q1009 QNH (q alone: the ATIS QNH) · app (ils) cleared ILS · land (ctl)
##   ga go around · rc radar contact · exp expect ILS · la low altitude alert
##   ta traffic alert · ol / or 360 for spacing · x cancel approach · dis disregard · rog roger
## Returns {items: Array, error: String}.
static func parse_command(text: String, atis_qnh: int = 0) -> Dictionary:
	var items: Array = []
	var seen := {}
	for raw_tok in text.strip_edges().to_lower().replace(",", " ").split(" ", false):
		var tok := String(raw_tok)
		var it := _command_token(tok, atis_qnh)
		if it.is_empty():
			return {"items": [], "error": "Unknown: %s" % tok}
		if it.has("error"):
			return {"items": [], "error": String(it["error"])}
		if seen.has(it["t"]):
			return {"items": [], "error": "Twice: %s" % tok}
		seen[it["t"]] = true
		items.append(it)
	if items.is_empty():
		return {"items": [], "error": "Nothing to send"}
	return {"items": items, "error": ""}


static func _command_token(tok: String, atis_qnh: int) -> Dictionary:
	const WORDS := {
		"app": "app", "ils": "app", "land": "land", "ctl": "land", "ga": "ga", "rc": "contact",
		"contact": "contact", "exp": "expect", "la": "low_alt", "ta": "traffic", "x": "cancel",
		"cancel": "cancel", "dis": "disregard", "rog": "roger", "roger": "roger",
	}
	if WORDS.has(tok):
		return item(WORDS[tok])
	if tok == "ol" or tok == "or":
		return orbit("L" if tok == "ol" else "R")
	if tok == "q":
		return qnh(atis_qnh) if atis_qnh > 0 else {"error": "No ATIS QNH yet"}
	var head := tok.substr(0, 1)
	var num := tok.substr(1)
	if not num.is_valid_int():
		return {}
	var n := num.to_int()
	match head:
		"h", "l", "r":
			if n < 0 or n > 360:
				return {"error": "Heading 1-360: %s" % tok}
			return hdg(n, "" if head == "h" else head.to_upper())
		"a", "c", "d":
			var v := n * 100 if n < 200 else n
			if v < ALT_MIN or v > ALT_MAX or v % 100 != 0:
				return {"error": "Altitude %d-%d: %s" % [ALT_MIN, ALT_MAX, tok]}
			return alt(v)
		"s":
			if n < SPD_MIN or n > SPD_MAX:
				return {"error": "Speed %d-%d: %s" % [SPD_MIN, SPD_MAX, tok]}
			return spd(n)
		"q":
			if n < QNH_MIN or n > QNH_MAX:
				return {"error": "QNH %d-%d: %s" % [QNH_MIN, QNH_MAX, tok]}
			return qnh(n)
	return {}
