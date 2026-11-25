extends RefCounted
## Lobby, roles, the round loop and radio arbitration (port of src/server/rooms.ts).
## Transport-agnostic: everything leaves through `send(to_id, kind, payload)`, which
## Session wires to RPCs and the tests to a recorder. Runs only on the host.
## Message kinds: room, begin, own, radar, radio, event, end, error.

const SimRng := preload("res://core/sim/rng.gd")
const SimRound := preload("res://core/sim/round.gd")
const SimAircraft := preload("res://core/sim/aircraft.gd")
const Geo := preload("res://core/sim/geo.gd")
const WorldDef := preload("res://core/world.gd")
const Validate := preload("res://core/net/validate.gd")

const MAX_PLAYERS := 8
const TICK_HZ := 10
const DT := 1.0 / TICK_HZ
const RADAR_SWEEP_SEC := 2.0
const SWEEP_TICKS := 20 ## RADAR_SWEEP_SEC * TICK_HZ
## A stalled host catches up at most this many steps per frame, then drops the rest.
const MAX_CATCHUP_STEPS := 10


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
var rng: SimRng
var sim: SimRound = null
var roles: Roles = null
## Called before every simulation sub-step (demo AI pilots).
var ai_hook := Callable()
var _send: Callable
var _sim_ticks := 0
var _carry := 0.0


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
	return {"phase": phase, "players": list}


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
	if phase == "lobby":
		players.erase(p)
	broadcast_state()


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
	broadcast("radio", {"tx": plain(tx)})


func _clear_ptt() -> void:
	if tx.is_empty():
		return
	tx.clear()
	broadcast("radio", {"tx": []})
