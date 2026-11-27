extends RefCounted
## Lobby, roles, the round loop and radio arbitration (port of src/server/rooms.ts).
## Transport-agnostic: everything leaves through `send(to_id, kind, payload)`, which
## Session wires to RPCs and the tests to a recorder. Runs only on the host.
## Message kinds: room, begin, own, radar, radio, event, end, error, dl.
##
## Text radio (core/net/datalink.gd; not in the TS version): handle_dl() queues a
## message; it goes out only once the frequency is clear (nobody keyed by voice, no
## other text on the air), occupies the frequency for its airtime (the sender is in
## `radio.dl`, never in `radio.tx`, so no microphone opens), and is "blocked" when
## anyone keys up during that time. Then everyone gets it (`dl`); dl_hook lets the
## AI controllers and pilots hear it too.

const SimRng := preload("res://core/sim/rng.gd")
const SimRound := preload("res://core/sim/round.gd")
const SimAircraft := preload("res://core/sim/aircraft.gd")
const Geo := preload("res://core/sim/geo.gd")
const WorldDef := preload("res://core/world.gd")
const Validate := preload("res://core/net/validate.gd")
const Datalink := preload("res://core/net/datalink.gd")

const MAX_PLAYERS := 8
const TICK_HZ := 10
const DT := 1.0 / TICK_HZ
const RADAR_SWEEP_SEC := 2.0
const SWEEP_TICKS := 20 ## RADAR_SWEEP_SEC * TICK_HZ
## A stalled host catches up at most this many steps per frame, then drops the rest.
const MAX_CATCHUP_STEPS := 10
## Text messages one sender may have waiting or on the air.
const DL_QUEUE_MAX := 3
## A text message waits this long for a clear frequency, then is dropped.
const DL_WAIT_MAX_SEC := 30.0
## Clear-frequency pause before the next text message, so a voice can get in.
const DL_GAP_SEC := 0.5


class Roles:
	var real_controller_id := 0 ## 0 if none
	var impostor_id := 0 ## 0 if none
	var pilots: Array[int] = []


var phase := "lobby" ## lobby | playing | ended
## Internal records {id, name, connected}, in join order.
var players: Array[Dictionary] = []
var host_id := 0
## Keying order on the frequency.
var tx: Array[int] = []
var min_players := 4
## Dedicated server: the host is not a player; `host_id` is then the lobby leader
## (first-joined player, handed on when they leave). Sent to clients in `room`.
var dedicated := false
var rng: SimRng
var sim: SimRound = null
var roles: Roles = null
## Called before every simulation sub-step (demo AI pilots).
var ai_hook := Callable()
## Called with every text message once it has aired (any status but "queued"), so AI
## players hear the frequency. Gets a copy with the full text.
var dl_hook := Callable()
var _send: Callable
var _sim_ticks := 0
var _carry := 0.0
var _dl_seq := 0
var _dl_queue: Array[Dictionary] = [] ## {msg, waited}
var _dl_air: Dictionary = {} ## {msg, left, blocked} while a text message is on the air
var _dl_gap := 0.0
var _dl_last: Dictionary = {} ## sender id -> tick their last text message ended (round robin)


func _init(send: Callable, rng_in: SimRng, min_players_in: int = 4) -> void:
	_send = send
	rng = rng_in
	min_players = clampi(min_players_in, 1, MAX_PLAYERS)


## Random roles. >= 3 players: 1 real controller, 1 impostor, rest pilots.
## Reduced test games: 2 = controller + pilot (no impostor); 1 = a lone pilot.
static func assign_roles(ids: Array[int], r: SimRng) -> Roles:
	var s: Array[int] = []
	s.assign(r.shuffle(ids))
	var out := Roles.new()
	if s.size() >= 3:
		out.real_controller_id = s[0]
		out.impostor_id = s[1]
		out.pilots = s.slice(2)
	elif s.size() == 2:
		out.real_controller_id = s[0]
		out.pilots = s.slice(1)
	else:
		out.pilots = s
	return out


# ---------------------------------------------------------------- queries

func find(id: int) -> Dictionary:
	for p in players:
		if p["id"] == id:
			return p
	return {}


func connected_ids() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if p["connected"]:
			out.append(p["id"])
	return out


func role_of(id: int) -> String:
	if roles == null:
		return ""
	if id != 0 and (id == roles.real_controller_id or id == roles.impostor_id):
		return "controller"
	return "pilot" if roles.pilots.has(id) else ""


func can_transmit(id: int) -> bool:
	var ac: SimAircraft = sim.by_player(id) if sim != null else null
	return ac == null or ac.status != "crashed"


# ---------------------------------------------------------------- payloads (contract shapes)

func state() -> Dictionary:
	var list: Array = []
	for p in players:
		list.append({"id": p["id"], "name": p["name"], "host": p["id"] == host_id, "connected": p["connected"]})
	var out := {"phase": phase, "players": list}
	if dedicated:
		out["dedicated"] = true
	return out


## Public round roster, in join order so position never hints at a role.
func round_players() -> Array:
	var list: Array = []
	for p in players:
		var id: int = p["id"]
		var ac: SimAircraft = sim.by_player(id)
		list.append({
			"id": id, "name": p["name"],
			"role": role_of(id) if role_of(id) != "" else "pilot",
			"callsign": ac.callsign if ac != null else "",
		})
	return list


## The private `begin` payload for one player: only the impostor gets impostor = true.
func begin_payload(id: int, roster: Array) -> Dictionary:
	var ac: SimAircraft = sim.by_player(id)
	return {
		"you": {
			"role": role_of(id) if role_of(id) != "" else "pilot",
			"impostor": id != 0 and id == roles.impostor_id,
			"callsign": ac.callsign if ac != null else "",
		},
		"players": roster,
		"world": WorldDef.DATA,
		"atis": sim.atis,
	}


# ---------------------------------------------------------------- sending

## Untyped copy of a typed array, for payloads.
static func plain(a: Array) -> Array:
	var out: Array = []
	out.append_array(a)
	return out


func send_to(id: int, kind: String, payload: Dictionary) -> void:
	_send.call(id, kind, payload)


func broadcast(kind: String, payload: Dictionary) -> void:
	for p in players:
		if p["connected"]:
			_send.call(int(p["id"]), kind, payload)


func broadcast_state() -> void:
	broadcast("room", state())


# ---------------------------------------------------------------- lobby

## Add a player. Returns "" or the reason they were refused.
func add(id: int, raw_name: Variant) -> String:
	if not find(id).is_empty():
		return "Already in a room"
	if phase != "lobby":
		return "Round in progress, wait for it to end"
	if players.size() >= MAX_PLAYERS:
		return "Room is full"
	if host_id != 0 and find(host_id).is_empty():
		host_id = 0
	var taken: Array[String] = []
	for p in players:
		taken.append(p["name"])
	var name := Validate.dedupe_name(Validate.sanitize_name(raw_name), taken)
	players.append({"id": id, "name": name, "connected": true})
	if host_id == 0:
		host_id = id
	broadcast_state()
	return ""


## Connection lost. In the lobby the player leaves; mid-round they stay listed
## (disconnected) and their aircraft keeps flying on its last settings.
func disconnect_player(id: int) -> void:
	var p := find(id)
	if p.is_empty():
		return
	p["connected"] = false
	set_ptt(id, false)
	_dl_drop_sender(id)
	if phase == "lobby":
		players.erase(p)
	if id == host_id:
		_hand_on_leader()
	broadcast_state()


## The leader left: the next connected player in join order leads (0 if none; the next
## to join then leads). Only reachable with a dedicated host, as a player-host leaving
## closes the session.
func _hand_on_leader() -> void:
	var ids := connected_ids()
	host_id = ids[0] if not ids.is_empty() else 0


func start(by_id: int) -> String:
	if by_id != host_id:
		return "Only the host can start"
	if phase != "lobby":
		return "Round already started"
	var ids := connected_ids()
	if ids.size() < min_players:
		return "Need at least %d players" % min_players
	if ids.size() > MAX_PLAYERS:
		return "At most %d players" % MAX_PLAYERS
	var r := assign_roles(ids, rng)
	begin_round(r, SimRound.new(rng, r.pilots))
	return ""


## Start a round with given roles and simulation (also used by the offline demo).
func begin_round(r: Roles, s: SimRound) -> void:
	roles = r
	sim = s
	_sim_ticks = 0
	_carry = 0.0
	phase = "playing"
	_dl_reset()
	_clear_ptt()
	var roster := round_players()
	for p in players:
		if p["connected"]:
			send_to(p["id"], "begin", begin_payload(p["id"], roster))
	broadcast_state()
	_broadcast_views(true)


func end_round() -> void:
	if sim == null or phase != "playing":
		return
	phase = "ended"
	var was_on_air := not _dl_air.is_empty()
	_dl_reset()
	if was_on_air and tx.is_empty():
		_broadcast_radio()
	_clear_ptt()
	broadcast("end", {"result": sim.result(roles.real_controller_id, roles.impostor_id)})
	broadcast_state()


func back_to_lobby(by_id: int) -> String:
	if by_id != host_id:
		return "Only the host can return to the lobby"
	if phase != "ended":
		return "Round not ended"
	phase = "lobby"
	sim = null
	roles = null
	var keep: Array[Dictionary] = []
	for p in players:
		if p["connected"]:
			keep.append(p)
	players = keep
	broadcast_state()
	return ""


# ---------------------------------------------------------------- round loop

## Advance real time. The sim always moves in fixed DT sub-steps; views go out
## once per call that advanced, radar once per RADAR_SWEEP_SEC of sim time.
func advance(delta: float) -> void:
	if phase != "playing" or sim == null:
		return
	_carry += delta
	@warning_ignore("integer_division")
	var sweep_before := _sim_ticks / SWEEP_TICKS
	var steps := 0
	while _carry >= DT - 1e-9 and not sim.is_finished():
		if steps >= MAX_CATCHUP_STEPS:
			_carry = 0.0
			break
		_carry -= DT
		_sub_step()
		steps += 1
	if steps > 0:
		@warning_ignore("integer_division")
		var sweep_now := _sim_ticks / SWEEP_TICKS
		_broadcast_views(sweep_now != sweep_before)
	if sim.is_finished():
		end_round()


func _sub_step() -> void:
	if ai_hook.is_valid():
		ai_hook.call()
	var events := sim.step(DT)
	_sim_ticks += 1
	for ev in events:
		broadcast("event", {"event": ev})
		# Crashed pilots lose their transmitter.
		if ev["kind"] != "landed":
			for cs: String in ev["callsigns"]:
				var ac: SimAircraft = sim.by_callsign(cs)
				if ac != null:
					set_ptt(ac.player_id, false)
					_dl_drop_sender(ac.player_id)
	_dl_step(DT)


## `own` to each pilot (only their own aircraft); `radar` to the controllers only.
func _broadcast_views(sweep: bool) -> void:
	var t := Geo.js_round(sim.time * 10.0) / 10.0
	for id in roles.pilots:
		var own := sim.own_view(id)
		if not own.is_empty() and not find(id).is_empty() and find(id)["connected"]:
			send_to(id, "own", {"time": t, "ac": own})
	if sweep:
		var msg := {"time": t, "targets": plain(sim.radar())}
		for id in [roles.real_controller_id, roles.impostor_id]:
			if id != 0 and not find(id).is_empty() and find(id)["connected"]:
				send_to(id, "radar", msg)


# ---------------------------------------------------------------- commands

## Pilot autopilot command from an untrusted client. Returns "" or an error.
func handle_ap(id: int, raw: Variant) -> String:
	if phase != "playing" or sim == null:
		return "No round in progress"
	if role_of(id) != "pilot":
		return "Only pilots fly"
	var cmd := {}
	var err := Validate.parse_ap(raw, cmd)
	if err != "":
		return err
	sim.apply_ap(id, cmd) # ignored silently once landed/crashed
	return ""


func set_ptt(id: int, on: bool) -> void:
	var keyed := tx.has(id)
	if on:
		if keyed or phase != "playing" or not can_transmit(id):
			return
		var p := find(id)
		if p.is_empty() or not p["connected"]:
			return
		tx.append(id)
	else:
		if not keyed:
			return
		tx.erase(id)
	_broadcast_radio()


func _clear_ptt() -> void:
	if tx.is_empty():
		return
	tx.clear()
	_broadcast_radio()


## `radio`: who is keyed by voice (tx) and who has a text message on the air (dl).
func _broadcast_radio() -> void:
	broadcast("radio", {"tx": plain(tx), "dl": plain(dl_tx())})


# ---------------------------------------------------------------- text radio

## Ids with a text message on the air right now (at most one).
func dl_tx() -> Array[int]:
	var out: Array[int] = []
	if not _dl_air.is_empty():
		out.append(int(_dl_air["msg"]["from"]))
	return out


## Messages `id` has waiting or on the air.
func dl_pending(id: int) -> int:
	var n := 0
	for q in _dl_queue:
		if int(q["msg"]["from"]) == id:
			n += 1
	if not _dl_air.is_empty() and int(_dl_air["msg"]["from"]) == id:
		n += 1
	return n


## A text message from a player (or an AI player) for the frequency. Returns "" or an error.
func handle_dl(id: int, raw: Variant) -> String:
	if phase != "playing" or sim == null:
		return "No round in progress"
	var role := role_of(id)
	var p := find(id)
	if role == "" or p.is_empty() or not p["connected"]:
		return "Not in this round"
	if not can_transmit(id):
		return "Your radio is dead"
	var m := {}
	var err := Datalink.parse(raw, role, m)
	if err != "":
		return err
	if m["kind"] == Datalink.KIND_CLR and sim.by_callsign(String(m["to"])) == null:
		return "No aircraft %s" % m["to"]
	if m["kind"] == Datalink.KIND_REPLY and int(m["re"]) > _dl_seq:
		return "Bad message: re"
	var accused := Datalink.find_item(m, "accuse")
	if not accused.is_empty():
		var who := int(accused["who"])
		if who == id or role_of(who) != "controller":
			return "Only a controller can be called out"
	if dl_pending(id) >= DL_QUEUE_MAX:
		return "Frequency busy: wait for your messages to go out"
	_dl_seq += 1
	var ac: SimAircraft = sim.by_player(id)
	m["id"] = _dl_seq
	m["from"] = id
	m["role"] = role
	m["from_cs"] = ac.callsign if ac != null else ""
	m["time"] = Geo.js_round(sim.time * 10.0) / 10.0
	m["text"] = ""
	m["status"] = "queued"
	_dl_queue.append({"msg": m, "waited": 0.0})
	send_to(id, "dl", {"msg": m.duplicate(true)})
	return ""


func _dl_reset() -> void:
	_dl_queue.clear()
	_dl_air = {}
	_dl_gap = 0.0
	_dl_last.clear()


## Drop what `id` has queued or on the air (left the room, crashed).
func _dl_drop_sender(id: int) -> void:
	var keep: Array[Dictionary] = []
	for q in _dl_queue:
		if int(q["msg"]["from"]) != id:
			keep.append(q)
	_dl_queue = keep
	if not _dl_air.is_empty() and int(_dl_air["msg"]["from"]) == id:
		var m: Dictionary = _dl_air["msg"]
		_dl_air = {}
		_dl_gap = DL_GAP_SEC
		_broadcast_radio()
		m["status"] = "cut"
		_dl_notify_sender(m)


func _dl_step(dt: float) -> void:
	if not _dl_air.is_empty():
		if not tx.is_empty():
			_dl_air["blocked"] = true
		_dl_air["left"] = float(_dl_air["left"]) - dt
		if float(_dl_air["left"]) > 1e-6:
			return
		var m: Dictionary = _dl_air["msg"]
		m["status"] = "blocked" if bool(_dl_air["blocked"]) else "ok"
		m["time"] = Geo.js_round(sim.time * 10.0) / 10.0
		_dl_last[int(m["from"])] = _sim_ticks
		_dl_air = {}
		_dl_gap = DL_GAP_SEC
		_broadcast_radio()
		_dl_deliver(m)
		return
	var keep: Array[Dictionary] = []
	for q in _dl_queue:
		q["waited"] = float(q["waited"]) + dt
		if float(q["waited"]) >= DL_WAIT_MAX_SEC:
			var m: Dictionary = q["msg"]
			m["status"] = "expired"
			_dl_notify_sender(m)
		else:
			keep.append(q)
	_dl_queue = keep
	_dl_gap -= dt
	if _dl_gap > 0.0 or not tx.is_empty() or _dl_queue.is_empty():
		return
	# Round robin: the sender who had the frequency least recently goes first.
	var best := 0
	for i in range(1, _dl_queue.size()):
		var a := int(_dl_last.get(int(_dl_queue[i]["msg"]["from"]), -1))
		var b := int(_dl_last.get(int(_dl_queue[best]["msg"]["from"]), -1))
		if a < b:
			best = i
	var msg: Dictionary = _dl_queue.pop_at(best)["msg"]
	msg["text"] = Datalink.render(msg, dl_context(msg))
	_dl_air = {"msg": msg, "left": Datalink.airtime(String(msg["text"])), "blocked": false}
	_broadcast_radio()


## What the phraseology needs to know, as the host sees it now.
func dl_context(m: Dictionary) -> Dictionary:
	var names := {}
	for p in players:
		names[int(p["id"])] = String(p["name"])
	var ctx := {
		"letter": String(sim.atis.get("letter", "")), "qnh": sim.qnh,
		"wind_dir": int(sim.atis.get("wind_dir", 0)), "wind_kt": int(sim.atis.get("wind_kt", 0)),
		"from_cs": String(m.get("from_cs", "")), "names": names,
	}
	var to: SimAircraft = sim.by_callsign(String(m.get("to", ""))) if String(m.get("to", "")) != "" else null
	if to != null:
		ctx["to_alt"] = to.alt
	var mine: SimAircraft = sim.by_player(int(m.get("from", 0)))
	if mine != null:
		ctx["fuel_min"] = mine.fuel_min
		ctx["ind_alt"] = int(Geo.js_round(mine.indicated_alt(sim.qnh) / 100.0)) * 100
	return ctx


## Everyone hears an aired message; a blocked one carries its text to the sender only.
func _dl_deliver(m: Dictionary) -> void:
	var blocked := String(m["status"]) == "blocked"
	for p in players:
		if not p["connected"]:
			continue
		var out := m.duplicate(true)
		if blocked and int(p["id"]) != int(m["from"]):
			out["text"] = ""
		send_to(int(p["id"]), "dl", {"msg": out})
	if dl_hook.is_valid():
		dl_hook.call(m.duplicate(true))


func _dl_notify_sender(m: Dictionary) -> void:
	var p := find(int(m["from"]))
	if not p.is_empty() and p["connected"]:
		send_to(int(m["from"]), "dl", {"msg": m.duplicate(true)})
	if dl_hook.is_valid():
		dl_hook.call(m.duplicate(true))
