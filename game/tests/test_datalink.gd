extends RefCounted
## The text radio: message validation and phraseology (core/net/datalink.gd), the
## Room's queue / airtime / blocking, and Session.send_dl in an offline round.

const T := preload("res://tests/lib/t.gd")
const SimRng := preload("res://core/sim/rng.gd")
const Room := preload("res://core/net/room.gd")
const Datalink := preload("res://core/net/datalink.gd")


class Rec:
	var msgs: Array[Array] = []

	func send(to: int, kind: String, payload: Dictionary) -> void:
		msgs.append([to, kind, payload.duplicate(true)])

	func to(id: int, kind: String) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for m in msgs:
			if m[0] == id and m[1] == kind:
				out.append(m[2])
		return out

	## The `dl` messages `id` received with this status.
	func dl(id: int, status: String) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for p in to(id, "dl"):
			if String(p["msg"]["status"]) == status:
				out.append(p["msg"])
		return out


## A started 4-player round: [room, rec, controller id, pilot id, pilot callsign, other controller].
func round4(seed_v: int = 5) -> Array:
	var rec := Rec.new()
	var room := Room.new(rec.send, SimRng.new(seed_v), 4)
	for i in 4:
		room.add(i + 1, "P%d" % i)
	room.start(1)
	var ctl := room.roles.real_controller_id
	var pilot := room.roles.pilots[0]
	return [room, rec, ctl, pilot, room.sim.by_player(pilot).callsign, room.roles.impostor_id]


func steps(room: Room, n: int) -> void:
	for i in n:
		room.advance(Room.DT)


# ---------------------------------------------------------------- parse

func test_parse_valid_messages(t: T) -> void:
	var out := {}
	var raw := {"kind": "clr", "to": "DAL12", "items": [
		{"t": "app"}, {"t": "alt", "v": 5500.0}, {"t": "hdg", "v": 0, "turn": "L"}, {"t": "junk_key_ignored", "x": 1},
	]}
	t.check(Datalink.parse(raw, "controller", out) != "", "unknown item refused")
	raw["items"].pop_back()
	t.eq(Datalink.parse(raw, "controller", out), "", "clearance")
	t.eq(out["items"].map(func(i: Dictionary) -> String: return i["t"]), ["hdg", "alt", "app"], "reading order")
	t.eq(out["items"][0]["v"], 360, "heading 0 is said 360")
	t.eq(typeof(out["items"][1]["v"]), TYPE_INT, "altitude normalised to int")
	t.eq(Datalink.parse({"kind": "reply", "re": 3, "items": [{"t": "unable", "why": "msa"}]}, "pilot", out), "", "reply")
	t.eq(out["re"], 3, "re")
	t.eq(Datalink.parse({"kind": "call", "items": [{"t": "min_fuel"}]}, "pilot", out), "", "pilot call")
	t.eq(Datalink.parse({"kind": "call", "items": [{"t": "accuse", "who": 2}]}, "controller", out), "", "accuse")
	t.done()


func test_parse_refuses_bad_input(t: T) -> void:
	var out := {}
	var bad: Array = [
		[null, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": []}, "controller"],
		[{"kind": "clr", "to": "dal12", "items": [{"t": "app"}]}, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": [{"t": "app"}]}, "pilot"],
		[{"kind": "reply", "re": 1, "items": [{"t": "wilco"}]}, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": [{"t": "alt", "v": 5550}]}, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": [{"t": "alt", "v": INF}]}, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": [{"t": "hdg", "v": 400}]}, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": [{"t": "hdg", "v": 90, "turn": "X"}]}, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": [{"t": "spd", "v": 90}]}, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": [{"t": "qnh", "v": "1013"}]}, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": [{"t": "app"}, {"t": "app"}]}, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": [{"t": "hdg", "v": 90}, {"t": "orbit", "turn": "L"}]}, "controller"],
		[{"kind": "clr", "to": "DAL12", "items": [{"t": "app"}, {"t": "ga"}]}, "controller"],
		[{"kind": "reply", "re": 0, "items": [{"t": "wilco"}]}, "pilot"],
		[{"kind": "reply", "re": 2, "items": [{"t": "wilco"}, {"t": "standby"}]}, "pilot"],
		[{"kind": "reply", "re": 2, "items": [{"t": "unable", "why": "bored"}]}, "pilot"],
		[{"kind": "call", "items": [{"t": "accuse", "who": 0}]}, "pilot"],
		[{"kind": "call", "items": [{"t": "atis"}]}, "pilot"],
	]
	for b: Array in bad:
		t.check(Datalink.parse(b[0], String(b[1]), out) != "", "refused: %s as %s" % [var_to_str(b[0]), b[1]])
		t.check(out.is_empty(), "nothing parsed")
	t.done()


# ---------------------------------------------------------------- render

func test_render_phraseology(t: T) -> void:
	var ctx := {"letter": "B", "qnh": 1009, "wind_dir": 250, "wind_kt": 8, "to_alt": 8000.0}
	var m := Datalink.clr("DAL12", [Datalink.item("contact"), Datalink.hdg(265, "L"), Datalink.alt(5500),
		Datalink.qnh(1009), Datalink.item("expect")])
	t.eq(Datalink.render(m, ctx),
		"DAL12, Fallow Approach, radar contact, information Bravo is current, turn left heading 265, descend and maintain 5500, QNH 1009, expect ILS approach runway 27.",
		"first contact")
	ctx["to_alt"] = 3000.0
	t.eq(Datalink.render(Datalink.clr("DAL12", [Datalink.alt(5500)]), ctx), "DAL12, climb and maintain 5500.", "climb")
	ctx["to_alt"] = 5500.0
	t.eq(Datalink.render(Datalink.clr("DAL12", [Datalink.alt(5500)]), ctx), "DAL12, maintain 5500.", "maintain")
	t.eq(Datalink.render(Datalink.clr("DAL12", [Datalink.hdg(240, "R"), Datalink.alt(5500), Datalink.item("app")]), ctx),
		"DAL12, turn right heading 240, maintain 5500 until established on the localizer, cleared ILS approach runway 27.",
		"approach clearance")
	t.eq(Datalink.render(Datalink.clr("DAL12", [Datalink.item("land")]), ctx),
		"DAL12, runway 27, cleared to land, wind 250 degrees 8 knots.", "landing")
	t.eq(Datalink.render(Datalink.clr("DAL12", [Datalink.hdg(90)]), ctx), "DAL12, fly heading 090.", "fly heading")
	var pilot := {"from_cs": "DAL12", "qnh": 1009, "ind_alt": 7000, "fuel_min": 3.7, "letter": "B",
		"names": {4: "Bob"}}
	t.eq(Datalink.render(Datalink.reply(3, "wilco"), pilot), "Wilco, DAL12.", "wilco")
	t.eq(Datalink.render(Datalink.reply(3, "unable", "qnh"), pilot), "Unable, DAL12, the ATIS gives QNH 1009.", "unable qnh")
	t.eq(Datalink.render(Datalink.radio_call("checkin"), pilot), "Fallow Approach, DAL12, with you at 7000, information Bravo.", "checkin")
	t.eq(Datalink.render(Datalink.radio_call("mayday_fuel"), pilot),
		"MAYDAY MAYDAY MAYDAY, DAL12, fuel emergency, 3 minutes of fuel remaining.", "mayday")
	t.eq(Datalink.render(Datalink.radio_call("accuse", 4), pilot), "All stations, DAL12, do not trust Bob, that is the impostor.", "pilot accuses")
	t.eq(Datalink.render(Datalink.radio_call("accuse", 4), {"names": {4: "Bob"}}),
		"All stations, disregard all instructions from Bob, that is not Fallow Approach.", "controller accuses")
	t.check(Datalink.airtime("Wilco, DAL12.") >= Datalink.AIRTIME_MIN, "short airtime floor")
	t.check(Datalink.airtime(" ".repeat(0) + "a ".repeat(60)) <= Datalink.AIRTIME_MAX, "long airtime cap")
	t.done()


func test_parse_command(t: T) -> void:
	var r := Datalink.parse_command("l240 a55 s180 app", 1009)
	t.eq(r["error"], "", "no error")
	t.eq(r["items"], [Datalink.hdg(240, "L"), Datalink.alt(5500), Datalink.spd(180), Datalink.item("app")], "items")
	t.eq(Datalink.parse_command("rc h270 d6000 q", 1009)["items"],
		[Datalink.item("contact"), Datalink.hdg(270), Datalink.alt(6000), Datalink.qnh(1009)], "contact, ft, ATIS QNH")
	t.eq(Datalink.parse_command("OR", 0)["items"], [Datalink.orbit("R")], "orbit right, case-insensitive")
	t.check(Datalink.parse_command("h400", 0)["error"] != "", "bad heading")
	t.check(Datalink.parse_command("a55 a60", 0)["error"] != "", "twice")
	t.check(Datalink.parse_command("hello", 0)["error"] != "", "unknown")
	t.check(Datalink.parse_command("  ", 0)["error"] != "", "empty")
	t.done()


# ---------------------------------------------------------------- room

func test_room_airs_after_clear_frequency(t: T) -> void:
	var r := round4()
	var room: Room = r[0]
	var rec: Rec = r[1]
	var ctl: int = r[2]
	var pilot: int = r[3]
	var cs: String = r[4]
	t.eq(room.handle_dl(ctl, Datalink.clr(cs, [Datalink.hdg(240, "L")])), "", "queued")
	t.eq(rec.dl(ctl, "queued").size(), 1, "sender told it is queued")
	t.eq(rec.dl(pilot, "queued").size(), 0, "others are not")
	steps(room, 1)
	t.eq(room.dl_tx(), [ctl] as Array[int], "on the air at once on a clear frequency")
	t.eq(room.tx, [] as Array[int], "but never keyed by voice (no microphone opens)")
	t.eq(rec.to(pilot, "radio").back()["dl"], [ctl], "everyone told who is on the air")
	steps(room, 60)
	var got := rec.dl(pilot, "ok")
	t.eq(got.size(), 1, "delivered")
	t.eq(String(got[0]["text"]), "%s, turn left heading 240." % cs, "text")
	t.eq(int(got[0]["from"]), ctl, "from")
	t.eq(room.dl_tx(), [] as Array[int], "off the air")
	# A reply to it, from the pilot.
	t.eq(room.handle_dl(pilot, Datalink.reply(int(got[0]["id"]), "wilco")), "", "reply")
	t.eq(room.handle_dl(pilot, Datalink.reply(99, "wilco")), "Bad message: re", "reply to nothing")
	steps(room, 60)
	t.eq(String(rec.dl(ctl, "ok").back()["text"]), "Wilco, %s." % cs, "readback text")
	t.eq(String(rec.dl(ctl, "ok").back()["from_cs"]), cs, "from_cs")
	t.done()


func test_room_blocking_waiting_and_limits(t: T) -> void:
	var r := round4()
	var room: Room = r[0]
	var rec: Rec = r[1]
	var ctl: int = r[2]
	var pilot: int = r[3]
	var cs: String = r[4]
	var other: int = r[5]
	# Someone keys up during the airtime: blocked, text only for the sender.
	room.handle_dl(ctl, Datalink.clr(cs, [Datalink.alt(6000)]))
	steps(room, 8)
	room.set_ptt(pilot, true)
	steps(room, 3)
	room.set_ptt(pilot, false)
	steps(room, 60)
	t.eq(rec.dl(pilot, "blocked").size(), 1, "blocked")
	t.eq(String(rec.dl(pilot, "blocked")[0]["text"]), "", "others get no text")
	t.eq(rec.dl(pilot, "blocked")[0]["items"], [], "nor its items")
	t.eq(String(rec.dl(pilot, "blocked")[0]["to"]), "", "nor who it was for")
	t.check(String(rec.dl(ctl, "blocked")[0]["text"]) != "", "the sender sees what was lost")
	# A voice on the frequency: text waits, then goes once it is clear.
	room.set_ptt(other, true)
	room.handle_dl(ctl, Datalink.clr(cs, [Datalink.spd(200)]))
	steps(room, 50)
	t.eq(room.dl_tx(), [] as Array[int], "waits while someone talks")
	room.set_ptt(other, false)
	steps(room, 60)
	t.eq(rec.dl(pilot, "ok").size(), 1, "then airs")
	# Held mic for the whole wait: expired, sender told.
	room.set_ptt(other, true)
	room.handle_dl(ctl, Datalink.clr(cs, [Datalink.spd(210)]))
	steps(room, int(Room.DL_WAIT_MAX_SEC * 10) + 5)
	t.eq(rec.dl(ctl, "expired").size(), 1, "expired")
	room.set_ptt(other, false)
	# Per-sender limit.
	for i in Room.DL_QUEUE_MAX:
		t.eq(room.handle_dl(ctl, Datalink.clr(cs, [Datalink.spd(200 + i)])), "", "queue %d" % i)
	t.check(room.handle_dl(ctl, Datalink.clr(cs, [Datalink.spd(240)])).begins_with("Frequency busy"), "limit")
	# Round robin: a pilot's call goes before the controller's backlog.
	var n0 := rec.dl(ctl, "ok").size()
	t.eq(room.handle_dl(pilot, Datalink.radio_call("min_fuel")), "", "pilot call")
	steps(room, 120)
	var order: Array = rec.dl(ctl, "ok").slice(n0).map(func(m: Dictionary) -> int: return int(m["from"]))
	t.eq(order, [pilot, ctl, ctl, ctl], "the sender who spoke least recently goes first")
	# Context checks.
	t.check(room.handle_dl(ctl, Datalink.clr("NOPE1", [Datalink.spd(200)])).begins_with("No aircraft"), "unknown callsign")
	t.eq(room.handle_dl(pilot, Datalink.radio_call("accuse", pilot)), "Only a controller can be called out", "accuse a pilot")
	t.eq(room.handle_dl(pilot, Datalink.radio_call("accuse", ctl)), "", "accuse a controller")
	t.check(room.handle_dl(pilot, Datalink.clr(cs, [Datalink.spd(200)])) != "", "pilots cannot clear")
	room.end_round()
	t.eq(room.handle_dl(ctl, Datalink.clr(cs, [Datalink.spd(200)])), "No round in progress", "after the round")
	t.eq(room.dl_tx(), [] as Array[int], "frequency clear at the end")
	t.done()


func test_room_dead_radio(t: T) -> void:
	var r := round4()
	var room: Room = r[0]
	var rec: Rec = r[1]
	var pilot: int = r[3]
	room.handle_dl(pilot, Datalink.radio_call("min_fuel"))
	steps(room, 7)
	t.eq(room.dl_tx(), [pilot] as Array[int], "on the air")
	room.sim.by_player(pilot).finish("terrain")
	t.eq(room.handle_dl(pilot, Datalink.radio_call("min_fuel")), "Your radio is dead", "crashed: no transmitter")
	room.disconnect_player(pilot)
	t.eq(room.dl_tx(), [] as Array[int], "leaving cuts the transmission")
	t.eq(rec.dl(pilot, "cut").size(), 0, "nothing sent to someone who left")
	t.done()


# ---------------------------------------------------------------- session

func _session() -> Node:
	var root := (Engine.get_main_loop() as SceneTree).root
	var s := root.get_node_or_null("Session")
	if s == null:
		s = load("res://core/session.gd").new()
		s.name = "Session"
		root.add_child(s)
	return s


func test_session_send_dl_to_ai_pilot(t: T) -> void:
	var s := _session()
	var seen: Array[Dictionary] = []
	var cb := func(m: Dictionary) -> void: seen.append(m)
	s.datalink.connect(cb)
	s.start_demo("solo_controller")
	t.eq(s.my_role, "controller", "you are the tower")
	t.eq(s.round_players.filter(func(p: Dictionary) -> bool: return p["role"] == "pilot").size(), 4, "4 AI pilots")
	var cs := String(s.radar[0]["callsign"])
	s.send_dl(Datalink.clr(cs, [Datalink.alt(9000)]))
	t.eq(String(seen.back()["status"]), "queued", "queued")
	var mid := int(seen.back()["id"])
	var aired := false
	var readback := false
	for i in 200:
		s._process(0.1)
		for m in seen:
			if int(m["id"]) == mid and String(m["status"]) == "ok":
				aired = true
			if String(m["kind"]) == "reply" and int(m["re"]) == mid:
				readback = true
		if readback:
			break
	t.check(aired, "aired")
	t.check(readback, "the AI pilot read it back")
	var logged: Array = s.dl_log.filter(func(m: Dictionary) -> bool: return int(m["id"]) == mid)
	t.eq(logged.size(), 1, "one log entry per message id")
	t.eq(String(logged[0]["status"]), "ok", "status replaced in place")
	t.eq(s.on_air().size(), s.radio_tx.size() + s.dl_tx.size(), "on_air is voice + text")
	s.datalink.disconnect(cb)
	s.leave()
	t.eq(s.dl_log.size(), 0, "log cleared on leave")
	t.done()
