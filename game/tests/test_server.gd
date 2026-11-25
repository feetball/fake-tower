extends RefCounted
## Logic-level port of src/server/server.test.ts: validation, roles and their
## secrecy at the payload level, radio arbitration, clamping, round flow.

const T := preload("res://tests/lib/t.gd")
const SimRng := preload("res://core/sim/rng.gd")
const Room := preload("res://core/net/room.gd")
const Validate := preload("res://core/net/validate.gd")
const LaunchArgs := preload("res://core/net/launch_args.gd")
const InputSetup := preload("res://core/net/input_setup.gd")


## Records everything the room sends: [to_id, kind, payload].
class Rec:
	var msgs: Array[Array] = []

	func send(to: int, kind: String, payload: Dictionary) -> void:
		msgs.append([to, kind, payload.duplicate(true)])

	func to(id: int, kind: String = "") -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for m in msgs:
			if m[0] == id and (kind == "" or m[1] == kind):
				out.append(m[2])
		return out

	func kinds(id: int) -> Array[String]:
		var out: Array[String] = []
		for m in msgs:
			if m[0] == id:
				out.append(m[1])
		return out


func lobby(n: int, min_players: int = 4, seed_v: int = 5) -> Array:
	var rec := Rec.new()
	var room := Room.new(rec.send, SimRng.new(seed_v), min_players)
	for i in n:
		room.add(i + 1, "P%d" % i)
	return [room, rec]


## True if `v` contains a key "impostor" set to true anywhere.
static func has_impostor_true(v: Variant) -> bool:
	if typeof(v) == TYPE_DICTIONARY:
		for k: Variant in v:
			if k == "impostor" and v[k] == true:
				return true
			if has_impostor_true(v[k]):
				return true
	elif typeof(v) == TYPE_ARRAY:
		for x: Variant in v:
			if has_impostor_true(x):
				return true
	return false


static func has_key(v: Variant, key: String) -> bool:
	if typeof(v) == TYPE_DICTIONARY:
		for k: Variant in v:
			if k == key or has_key(v[k], key):
				return true
	elif typeof(v) == TYPE_ARRAY:
		for x: Variant in v:
			if has_key(x, key):
				return true
	return false


func test_validation_parses_defensively(t: T) -> void:
	var out := {}
	t.check(Validate.parse_ap(null, out) != "", "null")
	t.check(Validate.parse_ap([], out) != "", "array")
	t.check(Validate.parse_ap("ap", out) != "", "string")
	t.check(Validate.parse_ap({"hdg": "90"}, out) != "", "hdg as string")
	t.check(Validate.parse_ap({"hdg": INF}, out) != "", "Infinity")
	t.check(Validate.parse_ap({"alt": NAN}, out) != "", "NaN")
	t.check(Validate.parse_ap({"flaps": 4}, out) != "", "flaps 4")
	t.check(Validate.parse_ap({"flaps": 1.5}, out) != "", "flaps 1.5")
	t.check(Validate.parse_ap({"flaps": true}, out) != "", "flaps bool")
	t.check(Validate.parse_ap({"gear": 1}, out) != "", "gear int")
	t.check(Validate.parse_ap({"app": "yes"}, out) != "", "app string")
	t.eq(Validate.parse_ap({"hdg": 90, "gear": true, "evil": 1, 7: "x"}, out), "", "valid with junk")
	t.eq(out, {"hdg": 90.0, "gear": true}, "unknown keys dropped")
	t.eq(Validate.parse_ap({"flaps": 2.0, "alt_setting": 1013}, out), "", "integral float flaps")
	t.eq(out, {"alt_setting": 1013.0, "flaps": 2}, "flaps as int")
	t.done()


func test_names_sanitised_and_deduped(t: T) -> void:
	t.eq(Validate.sanitize_name("  Bob\u202E\u0007  the   pilot  "), "Bob the pilot", "bidi + control + spaces (Godot strings cannot hold NUL)")
	t.eq(Validate.sanitize_name("\u200B\n"), "Player", "nothing left")
	t.eq(Validate.sanitize_name("x".repeat(50)).length(), 16, "16 chars max")
	t.eq(Validate.sanitize_name(42), "Player", "not a string")
	t.eq(Validate.dedupe_name("bob", ["Bob", "Bob 2"] as Array[String]), "bob 3", "case-insensitive")
	t.eq(Validate.dedupe_name("ABCDEFGHIJKLMNOP", ["ABCDEFGHIJKLMNOP"] as Array[String]), "ABCDEFGHIJKLMN 2", "truncate for suffix")
	t.done()


func test_assigns_roles_for_every_player_count(t: T) -> void:
	var rng := SimRng.new(3)
	for n in range(1, 9):
		var ids: Array[int] = []
		for i in n:
			ids.append(i + 10)
		var r := Room.assign_roles(ids, rng)
		var all: Array[int] = []
		for id in [r.real_controller_id, r.impostor_id]:
			if id != 0:
				all.append(id)
		all.append_array(r.pilots)
		all.sort()
		t.eq(all, ids, "n=%d everyone has a role" % n)
		t.eq(r.pilots.size(), n - 2 if n >= 3 else 1, "n=%d pilots" % n)
		t.eq(r.impostor_id == 0, n < 3, "n=%d impostor exists iff n >= 3" % n)
		t.eq(r.real_controller_id == 0, n < 2, "n=%d controller exists iff n >= 2" % n)
	t.done()


func test_roles_are_secret_at_payload_level(t: T) -> void:
	var l := lobby(6)
	var room: Room = l[0]
	var rec: Rec = l[1]
	t.eq(room.start(1), "", "start")
	for i in 25:
		room.advance(0.1) # 2.5 s: radar at t = 0 and t = 2
	var begins: Array[Dictionary] = []
	for id in range(1, 7):
		var b := rec.to(id, "begin")
		t.eq(b.size(), 1, "one begin for %d" % id)
		begins.append(b[0])
	var controllers := begins.filter(func(b: Dictionary) -> bool: return b["you"]["role"] == "controller")
	t.eq(controllers.size(), 2, "two controllers")
	t.eq(controllers.filter(func(b: Dictionary) -> bool: return b["you"]["impostor"]).size(), 1, "one impostor")
	var pilot_count := 0
	for i in 6:
		var id := i + 1
		var b := begins[i]
		t.eq(b["players"], begins[0]["players"], "same public roster")
		t.eq(b["atis"]["qnh"], begins[0]["atis"]["qnh"], "same QNH")
		var roster_ids: Array = b["players"].map(func(p: Dictionary) -> int: return p["id"])
		t.eq(roster_ids, [1, 2, 3, 4, 5, 6], "roster in join order")
		for p: Dictionary in b["players"]:
			var keys: Array = p.keys()
			keys.sort()
			t.eq(keys, ["callsign", "id", "name", "role"], "no hidden-role field")
		var all_to_me: Array = rec.to(id)
		if b["you"]["role"] == "pilot":
			pilot_count += 1
			t.eq(b["you"]["impostor"], false, "pilot begin impostor=false")
			t.check(not has_impostor_true(all_to_me), "pilot %d never sees impostor=true" % id)
			t.eq(rec.to(id, "radar").size(), 0, "pilot %d gets no radar" % id)
			t.check(not has_key(all_to_me, "targets"), "pilot %d never gets targets" % id)
			var own := rec.to(id, "own")
			t.check(own.size() > 3, "pilot %d gets own at 10 Hz (%d)" % [id, own.size()])
			for o in own:
				t.eq(o["ac"]["callsign"], b["you"]["callsign"], "only their own aircraft")
		else:
			t.eq(rec.to(id, "own").size(), 0, "controller %d gets no own" % id)
			var radar := rec.to(id, "radar")
			t.eq(radar.size(), 2, "controller %d radar sweeps at 0 and 2 s" % id)
			t.eq(radar[0]["targets"].size(), 4, "4 targets")
			t.check(not var_to_str(radar).contains("fuel"), "controllers never see fuel")
			if not b["you"]["impostor"]:
				t.check(not has_impostor_true(all_to_me), "real controller never sees impostor=true")
	t.eq(pilot_count, 4, "four pilots")
	t.done()


func test_radio_arbitration_and_bad_input(t: T) -> void:
	var l := lobby(4)
	var room: Room = l[0]
	var rec: Rec = l[1]
	room.set_ptt(1, true) # lobby: open mic, ignored
	t.eq(room.start(2), "Only the host can start", "not host")
	t.eq(room.start(1), "", "start")
	for id in range(1, 5):
		t.eq(rec.to(id, "radio").size(), 0, "no radio before keying")
	room.set_ptt(1, true)
	room.set_ptt(2, true)
	room.set_ptt(2, true) # no change, no broadcast
	room.set_ptt(1, false)
	room.set_ptt(3, true)
	room.disconnect_player(2) # disconnect clears their key
	var seq: Array = rec.to(4, "radio").map(func(m: Dictionary) -> Array: return m["tx"])
	t.eq(seq, [[1], [1, 2], [2], [2, 3], [3]], "keying order and blocking")
	t.eq(rec.to(3, "radio").map(func(m: Dictionary) -> Array: return m["tx"]), seq, "everyone sees the same sequence")
	t.check(rec.to(2, "radio").size() < seq.size(), "nothing sent to the disconnected player afterwards")
	# Controllers cannot fly.
	var ctrl := 0
	for id in range(1, 5):
		if room.role_of(id) == "controller":
			ctrl = id
	t.eq(room.handle_ap(ctrl, {"hdg": 90}), "Only pilots fly", "controller ap refused")
	# Still listed, disconnected, mid-round.
	var st: Dictionary = rec.to(4, "room").back()
	t.eq(st["phase"], "playing", "phase")
	t.check(st["players"].any(func(p: Dictionary) -> bool: return p["id"] == 2 and not p["connected"]), "2 listed as disconnected")
	room.set_ptt(2, true) # disconnected players cannot key
	t.eq(room.tx, [3] as Array[int], "disconnected cannot key")
	room.set_ptt(3, false)
	t.eq(rec.to(4, "radio").back()["tx"], [], "frequency clear")
	t.done()


func test_pilot_ap_validated_and_clamped(t: T) -> void:
	var l := lobby(4)
	var room: Room = l[0]
	var rec: Rec = l[1]
	t.eq(room.handle_ap(1, {"hdg": 90}), "No round in progress", "lobby")
	room.start(1)
	var pilot: int = room.roles.pilots[0]
	t.check(room.handle_ap(pilot, {"hdg": "90"}) != "", "wrong type refused")
	t.check(room.handle_ap(pilot, "junk") != "", "not a dictionary")
	t.eq(room.handle_ap(pilot, {"hdg": 400, "alt": 3049, "spd": 100, "alt_setting": 999}), "", "accepted")
	t.eq(room.handle_ap(pilot, {"alt": 1e300, "spd": -1e300}), "", "absurd values clamp")
	room.advance(0.1)
	var ac: Dictionary = rec.to(pilot, "own").back()["ac"]
	t.eq(ac["sel_hdg"], 40, "hdg wraps")
	t.eq(ac["sel_alt"], 20000, "alt clamps")
	t.eq(ac["sel_spd"], 200, "speed clamps to the clean minimum")
	t.eq(ac["alt_setting"], 999, "baro")
	room.handle_ap(pilot, {"alt": 3049})
	room.advance(0.1)
	t.eq(rec.to(pilot, "own").back()["ac"]["sel_alt"], 3000, "alt rounds to 100")
	t.done()


func test_lobby_dedupe_full_and_mid_round(t: T) -> void:
	var rec := Rec.new()
	var room := Room.new(rec.send, SimRng.new(1), 2)
	t.eq(room.add(1, "Bob"), "", "host")
	for i in range(2, 9):
		t.eq(room.add(i, "bob"), "", "join %d" % i)
	t.eq(room.add(9, "late"), "Room is full", "full")
	t.eq(room.add(3, "again"), "Already in a room", "duplicate join")
	var names: Array = room.state()["players"].map(func(p: Dictionary) -> String: return p["name"])
	t.eq(names.slice(0, 3), ["Bob", "bob 2", "bob 3"], "deduped")
	t.eq(room.state()["players"][0]["host"], true, "first is host")
	for i in range(3, 9):
		room.disconnect_player(i)
	t.eq(room.players.size(), 2, "lobby leavers removed")
	t.eq(room.start(1), "", "2-player start")
	t.eq(room.add(9, "late"), "Round in progress, wait for it to end", "mid-round join refused")
	var big := Room.new(rec.send, SimRng.new(1), 4)
	big.add(1, "A")
	big.add(2, "B")
	t.eq(big.start(1), "Need at least 4 players", "min players")
	t.done()


func test_two_player_game_flow(t: T) -> void:
	var l := lobby(2, 2, 9)
	var room: Room = l[0]
	var rec: Rec = l[1]
	room.start(1)
	t.eq(room.phase, "playing", "playing")
	var roles: Array = [rec.to(1, "begin")[0]["you"], rec.to(2, "begin")[0]["you"]]
	var role_names: Array = roles.map(func(y: Dictionary) -> String: return y["role"])
	role_names.sort()
	t.eq(role_names, ["controller", "pilot"], "controller + pilot")
	t.check(roles.all(func(y: Dictionary) -> bool: return not y["impostor"]), "no impostor")
	var pilot: int = room.roles.pilots[0]
	room.sim.aircraft[0].alt = 0.0 # crash the only aircraft
	room.advance(0.1)
	t.eq(room.phase, "ended", "ended")
	var end: Dictionary = rec.to(1, "end")[0]["result"]
	t.eq(end["winner"], "impostor", "winner")
	t.eq(end["impostor_id"], 0, "no impostor id")
	t.eq(end["outcomes"][0]["outcome"], "terrain", "outcome")
	t.eq(end["outcomes"][0]["player_id"], pilot, "player id")
	t.check(rec.to(2, "event").any(func(e: Dictionary) -> bool: return e["event"]["kind"] == "terrain"), "event broadcast")
	var before := rec.msgs.size()
	room.set_ptt(pilot, true)
	t.eq(rec.msgs.size(), before, "crashed pilot cannot key")
	t.eq(room.back_to_lobby(2), "Only the host can return to the lobby", "not host")
	t.eq(room.phase, "ended", "still ended")
	t.eq(room.back_to_lobby(1), "", "host returns")
	t.eq(room.phase, "lobby", "lobby")
	t.done()


func test_crash_while_keying_releases_frequency(t: T) -> void:
	var l := lobby(1, 1, 2)
	var room: Room = l[0]
	var rec: Rec = l[1]
	room.start(1)
	room.set_ptt(1, true)
	t.eq(room.tx.size(), 1, "keyed")
	room.sim.aircraft[0].alt = 0.0
	room.advance(0.1)
	t.eq(room.tx.size(), 0, "released")
	t.eq(rec.to(1, "radio").map(func(m: Dictionary) -> int: return m["tx"].size()), [1, 0], "radio sequence")
	t.done()


func test_fixed_step_accumulator(t: T) -> void:
	var l := lobby(4)
	var room: Room = l[0]
	var rec: Rec = l[1]
	room.start(1)
	var pilot: int = room.roles.pilots[0]
	var n0 := rec.to(pilot, "own").size()
	room.advance(0.25)
	t.near(room.sim.time, 0.2, 1e-9, "two steps")
	t.eq(rec.to(pilot, "own").size(), n0 + 1, "one view per advance")
	room.advance(0.05)
	t.near(room.sim.time, 0.3, 1e-9, "carry used")
	room.advance(0.04)
	t.eq(rec.to(pilot, "own").size(), n0 + 2, "no view without a step")
	room.advance(5.0)
	t.near(room.sim.time, 1.3, 1e-9, "catch-up capped at 10 steps")
	t.done()


func test_launch_args_and_input_actions(t: T) -> void:
	var a := LaunchArgs.parse(PackedStringArray(["--host", "--name=Ann", "--min-players=2", "--port=4000", "--autostart", "--net-test"]))
	t.check(a.host and a.autostart and a.net_test, "flags")
	t.eq(a.name, "Ann", "name")
	t.eq(a.min_players, 2, "min players")
	t.eq(a.port, 4000, "port")
	var b := LaunchArgs.parse(PackedStringArray(["--demo=controller", "--join=10.0.0.2", "--min-players=99"]))
	t.eq(b.demo, "controller", "demo")
	t.eq(b.join, "10.0.0.2", "join")
	t.eq(b.min_players, 8, "min players clamped")
	t.eq(b.port, 27270, "default port")
	InputSetup.register()
	for action: String in InputSetup.ACTIONS:
		t.check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "action " + action)
	t.done()
