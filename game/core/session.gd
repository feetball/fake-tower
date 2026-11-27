extends Node
## The `Session` autoload: the only thing views talk to (contract in ARCHITECTURE.md).
## Host-authoritative over Godot high-level multiplayer. The host runs a Room
## (core/net/room.gd) with the simulation; every peer, the host included, receives
## only its own messages through _deliver(), so the host's views see exactly what a
## client would. Clients are untrusted: every RPC they can call re-validates sender,
## phase, role and argument types.
## Transports: a host listens on ENet (UDP) and WebSocket (TCP) at once through
## core/net/multi_server_peer.gd; a client joins over one of them (core/net/address.gd).
## A dedicated server (start_server, `--server`) runs the room without being a player;
## its first-joined player is the lobby leader.

const Room := preload("res://core/net/room.gd")
const Demo := preload("res://core/net/demo.gd")
const SimRng := preload("res://core/sim/rng.gd")
const InputSetup := preload("res://core/net/input_setup.gd")
const LaunchArgs := preload("res://core/net/launch_args.gd")
const Address := preload("res://core/net/address.gd")
const MultiServerPeer := preload("res://core/net/multi_server_peer.gd")

signal lobby_changed()
signal round_began()
signal own_updated(ac: Dictionary)
signal radar_swept(targets: Array)
signal radio_changed(tx: Array)
signal round_event(event: Dictionary)
signal round_ended(result: Dictionary)
signal phase_changed(phase: String)
signal error(msg: String)
signal connection_lost()
## A text-radio message arrived or changed status (core/net/datalink.gd for the shape).
signal datalink(msg: Dictionary)

const DEFAULT_PORT := 27270 ## ENet, UDP
const DEFAULT_WS_PORT := 27271 ## WebSocket, TCP
const MAX_PLAYERS := Room.MAX_PLAYERS
const CHANNEL_RELIABLE := 0
const CHANNEL_OWN := 1
const ENET_CHANNELS := 4 ## Voice uses channel 2
const WS_HANDSHAKE_TIMEOUT_SEC := 20.0 ## client; Godot's default is 3 s
## A tab that stalls for a while (background, shader compile, slow device) must
## not drop queued state: Godot's 64 KB / 2048-packet defaults overflow in seconds.
const WS_BUFFER_BYTES := 4 * 1024 * 1024
const WS_MAX_QUEUED_PACKETS := 16384
## ENet slots beyond MAX_PLAYERS so a full or running room can still refuse politely.
const MAX_CLIENTS := 15
const RATE_WINDOW_MS := 1000
const RATE_MAX := 120 ## messages per second per peer; excess is dropped
const RAW_NAME_MAX := 200
const REFUSE_KICK_SEC := 0.5
const SERVER_SCENE := "res://core/net/server.tscn"
const SERVER_MAX_FPS := 30 ## dedicated server frame cap (the sim runs at 10 Hz)
const DL_LOG_MAX := 200
## Solo rounds: once the human's own flight is over, the rest plays out this much faster.
const FAST_FORWARD := 8.0

var phase := "menu"
var my_id := 0
var my_name := ""
var is_host := false
var players: Array[Dictionary] = []
var round_players: Array[Dictionary] = []
var my_role := ""
var i_am_impostor := false
var my_callsign := ""
var world: Dictionary = {}
var atis: Dictionary = {}
var own: Dictionary = {}
var radar: Array[Dictionary] = []
var radio_tx: Array[int] = []
## Ids with a text message on the air (not keyed by voice: their microphone stays shut).
## The frequency is busy when radio_tx and dl_tx hold anyone, blocked with two or more.
var dl_tx: Array[int] = []
## This round's text messages in arrival order; a status change replaces the entry.
var dl_log: Array[Dictionary] = []
var events: Array[Dictionary] = []
var result: Dictionary = {}
var round_time := 0.0
var min_players := 4
var is_demo := false
## May start the round and return to the lobby: a player-host, or the first-joined
## player of a dedicated server (handed on when they leave).
var is_leader := false
## This instance is a dedicated server: it runs the room but is not a player.
var is_dedicated := false
## Client: the host we joined is a dedicated server (no host player).
var server_dedicated := false
## "enet" or "ws" for a client, "enet+ws" (or one of them) for a host, "" offline.
var transport := ""
## Client: what we connected to ("host:port" or the ws:// URL). Host: "".
var server_address := ""
## Host: the ports listened on (0 = transport off).
var listen_port := 0
var listen_ws_port := 0
## Dedicated server: start when this many players are in (0 = the leader starts).
var autostart_at := 0
## Dedicated server with autostart_at: seconds from round end back to the lobby.
var lobby_after := 15.0
## Offline round running FAST_FORWARD times faster (our own aircraft is done).
var fast_forward := false

var _room: Room = null
var _demo: Demo = null
var _peer: MultiplayerPeer = null
var _pending_name := ""
var _ptt_on := false
var _autostart := false
var _local: Array[Array] = [] # queued [kind, payload] for this peer
var _flushing := false
var _rate: Dictionary = {} # peer id -> PackedInt64Array [window start ms, count]
var _ended_t := 0.0 # dedicated: seconds since the round ended
var _mirror_sig := ""


func _ready() -> void:
	InputSetup.register()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_apply_launch_args.call_deferred()


func _process(delta: float) -> void:
	if phase == "playing":
		fast_forward = _demo_flight_over()
		var k := FAST_FORWARD if fast_forward else 1.0
		round_time += delta * k
		if _room != null:
			_room.advance(delta * k)
	if is_dedicated:
		_server_tick(delta)
	_flush_local()


# ---------------------------------------------------------------- public API

## Host and play. Listens on ENet UDP `port` and WebSocket TCP `ws_port` at once;
## 0 turns a transport off. Not available on the web (browsers cannot listen).
func host_game(player_name: String, port: int = DEFAULT_PORT, ws_port: int = DEFAULT_WS_PORT) -> Error:
	_teardown()
	var err := _listen(port, ws_port)
	if err != OK:
		return err
	is_host = true
	my_id = multiplayer.get_unique_id()
	_room = Room.new(_send, SimRng.from_entropy(), min_players)
	_room.add(my_id, player_name)
	my_name = String(_room.find(my_id)["name"])
	_set_phase("lobby")
	_flush_local()
	return OK


## Dedicated server: run the lobby and the simulation without being a player
## (no role, no aircraft, no voice). Same ports as host_game.
func start_server(port: int = DEFAULT_PORT, ws_port: int = DEFAULT_WS_PORT) -> Error:
	_teardown()
	var err := _listen(port, ws_port)
	if err != OK:
		return err
	is_host = true
	is_dedicated = true
	my_id = multiplayer.get_unique_id()
	_room = _new_server_room()
	_log("listening: ENet UDP %s, WebSocket TCP %s; min players %d; %s" % [
		listen_port if listen_port > 0 else "off", listen_ws_port if listen_ws_port > 0 else "off",
		min_players, "autostart at %d" % autostart_at if autostart_at > 0 else "the first player to join leads"])
	_set_phase("lobby")
	_mirror_room()
	return OK


## Join a game. `address` is host, host:port, [v6]:port, ws://… or wss://… (see
## core/net/address.gd); `port` is used when the address has none. A bare host goes over
## ENet (`port`, default 27270) on desktop/mobile and over WebSocket on the web (port
## 27271 when `port` is left at DEFAULT_PORT; wss:// via the page's host TLS on https
## pages). `transport_pref`: "auto", "enet" or "ws".
func join_game(player_name: String, address: String, port: int = DEFAULT_PORT, transport_pref: String = "auto") -> Error:
	_teardown()
	var web := OS.has_feature("web")
	var want := Address.WS if web or transport_pref == "ws" else Address.ENET
	var ws_port := port if port != DEFAULT_PORT else DEFAULT_WS_PORT
	var a := Address.parse(address, port, ws_port, want, web and _page_is_https())
	if not a["ok"]:
		error.emit(String(a["error"]))
		return ERR_INVALID_PARAMETER
	var target := String(a["url"]) if a["transport"] == Address.WS else "%s:%d" % [a["host"], a["port"]]
	var err := OK
	var peer: MultiplayerPeer = null
	if a["transport"] == Address.ENET:
		if web:
			error.emit("Browsers can only join over WebSocket (ws:// or wss://).")
			return ERR_UNAVAILABLE
		var enet := ENetMultiplayerPeer.new()
		err = enet.create_client(String(a["host"]), int(a["port"]), ENET_CHANNELS)
		peer = enet
	else:
		var ws := WebSocketMultiplayerPeer.new()
		# The default 3 s is too short for a page still compiling shaders on its first
		# frames (phones, software WebGL): the handshake completes, but is only polled late.
		ws.handshake_timeout = WS_HANDSHAKE_TIMEOUT_SEC
		_ws_buffers(ws)
		err = ws.create_client(target)
		peer = ws
	if err != OK:
		error.emit("Could not connect to %s: %s" % [target, error_string(err)])
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	transport = String(a["transport"])
	server_address = target
	_pending_name = player_name.substr(0, RAW_NAME_MAX)
	my_name = player_name
	return OK


func leave() -> void:
	_teardown()
	_set_phase("menu")


## Leader only: a player-host starts locally, a dedicated server's leader asks the server.
func start_round() -> void:
	if is_demo or is_dedicated:
		return
	if is_host and _room != null:
		_report(_room.start(my_id))
		_flush_local()
	elif is_leader and _peer != null and my_id != 0:
		_s_start.rpc_id(1)


func return_to_lobby() -> void:
	if is_demo and _room != null:
		leave()
		return
	if is_dedicated:
		return
	if is_host and _room != null:
		_report(_room.back_to_lobby(my_id))
		_flush_local()
	elif is_leader and _peer != null and my_id != 0:
		_s_lobby.rpc_id(1)


func send_ap(changes: Dictionary) -> void:
	if phase != "playing" or my_role != "pilot":
		return
	if is_host:
		_report(_room.handle_ap(my_id, changes))
		_flush_local()
	elif _peer != null:
		_s_ap.rpc_id(1, changes)


## Text radio: a clearance, call or reply (core/net/datalink.gd). The host queues it
## until the frequency is clear; the result comes back through `datalink`.
func send_dl(msg: Dictionary) -> void:
	if phase != "playing" or my_role == "":
		return
	if is_host:
		if _room != null:
			_report(_room.handle_dl(my_id, msg))
			_flush_local()
	elif _peer != null and my_id != 0:
		_s_dl.rpc_id(1, msg)


## Everyone on the frequency, voice and text: the ids keyed right now.
func on_air() -> Array[int]:
	var out: Array[int] = []
	out.append_array(radio_tx)
	for id in dl_tx:
		if not out.has(id):
			out.append(id)
	return out


func set_ptt(on: bool) -> void:
	if on == _ptt_on:
		return
	_ptt_on = on
	if is_host and _room != null:
		_room.set_ptt(my_id, on)
		_flush_local()
	elif _peer != null and my_id != 0:
		_s_ptt.rpc_id(1, on)


func start_demo(role: String) -> void:
	_teardown()
	var rng := SimRng.from_entropy()
	var demo := Demo.build(role, 1, rng)
	if demo == null:
		error.emit("Unknown demo role: %s" % role)
		return
	is_demo = true
	is_host = true
	my_id = 1
	if my_name == "":
		my_name = "You"
	_demo = demo
	_room = Room.new(_send, rng, 1)
	_room.add(my_id, my_name)
	for id: int in demo.ai_names:
		_room.add(id, demo.ai_names[id])
	_room.ai_hook = demo.tick
	_room.dl_hook = demo.hear
	demo.attach(_room.handle_dl)
	_room.begin_round(demo.roles, demo.sim)
	_flush_local()


## Offline, flying: our aircraft has crashed, or landed and stopped, while others still fly.
func _demo_flight_over() -> bool:
	if not is_demo or my_role != "pilot" or own.is_empty():
		return false
	var st := String(own.get("status", "flying"))
	return st == "crashed" or (st == "landed" and float(own.get("gs", 1.0)) <= 0.0)


func player_name(id: int) -> String:
	for p in players:
		if int(p["id"]) == id:
			return String(p["name"])
	for p in round_players:
		if int(p["id"]) == id:
			return String(p["name"])
	return ""


func callsign_of(id: int) -> String:
	for p in round_players:
		if int(p["id"]) == id:
			return String(p["callsign"])
	return ""


# ---------------------------------------------------------------- outbound (host)

## Room sink: queue for this peer, RPC to remote peers, drop AI (id <= 0).
func _send(to_id: int, kind: String, payload: Dictionary) -> void:
	if to_id == my_id:
		_local.append([kind, payload.duplicate(true)])
	elif to_id > 0 and _peer != null and not is_demo:
		if kind == "own":
			_c_own.rpc_id(to_id, payload)
		else:
			_c_msg.rpc_id(to_id, kind, payload)


## Deliver queued local messages outside Room calls, so signal handlers may call back in.
func _flush_local() -> void:
	if _flushing:
		return
	_flushing = true
	while not _local.is_empty():
		var m: Array = _local.pop_front()
		_deliver(m[0], m[1])
	_flushing = false
	if is_dedicated:
		_mirror_room()


func _report(err: String) -> void:
	if err != "":
		error.emit(err)


# ---------------------------------------------------------------- RPC: host -> client

@rpc("authority", "call_remote", "reliable", CHANNEL_RELIABLE)
func _c_msg(kind: Variant, payload: Variant) -> void:
	if typeof(kind) == TYPE_STRING and typeof(payload) == TYPE_DICTIONARY and kind != "own":
		_deliver(kind, payload)


@rpc("authority", "call_remote", "unreliable_ordered", CHANNEL_OWN)
func _c_own(payload: Variant) -> void:
	if typeof(payload) == TYPE_DICTIONARY:
		_deliver("own", payload)


# ---------------------------------------------------------------- RPC: client -> host (untrusted)

@rpc("any_peer", "call_remote", "reliable", CHANNEL_RELIABLE)
func _s_hello(raw_name: Variant) -> void:
	var id := _client_sender()
	if id == 0:
		return
	if typeof(raw_name) != TYPE_STRING or String(raw_name).length() > RAW_NAME_MAX:
		_refuse(id, "Bad name")
		return
	var err := _room.add(id, raw_name)
	if err == "Already in a room":
		_send(id, "error", {"msg": err})
	elif err != "":
		_refuse(id, err)
	_flush_local()


@rpc("any_peer", "call_remote", "reliable", CHANNEL_RELIABLE)
func _s_start() -> void:
	var id := _client_sender()
	if id != 0:
		_reply(id, _room.start(id))


@rpc("any_peer", "call_remote", "reliable", CHANNEL_RELIABLE)
func _s_lobby() -> void:
	var id := _client_sender()
	if id != 0:
		_reply(id, _room.back_to_lobby(id))


@rpc("any_peer", "call_remote", "reliable", CHANNEL_RELIABLE)
func _s_ap(changes: Variant) -> void:
	var id := _client_sender()
	if id != 0:
		_reply(id, _room.handle_ap(id, changes))


@rpc("any_peer", "call_remote", "reliable", CHANNEL_RELIABLE)
func _s_ptt(on: Variant) -> void:
	var id := _client_sender()
	if id == 0:
		return
	if typeof(on) != TYPE_BOOL:
		_reply(id, "Bad ptt: on")
		return
	_room.set_ptt(id, on)
	_flush_local()


@rpc("any_peer", "call_remote", "reliable", CHANNEL_RELIABLE)
func _s_dl(msg: Variant) -> void:
	var id := _client_sender()
	if id != 0:
		_reply(id, _room.handle_dl(id, msg))


## The remote sender if this is the host and the message is within the rate limit, else 0.
## Messages from peers that never joined the room are dropped except the hello.
func _client_sender() -> int:
	if not is_host or _room == null or is_demo:
		return 0
	var id := multiplayer.get_remote_sender_id()
	if id <= 0 or id == my_id:
		return 0
	var now := Time.get_ticks_msec()
	var w: PackedInt64Array = _rate.get(id, PackedInt64Array([now, 0]))
	if now - w[0] >= RATE_WINDOW_MS:
		w = PackedInt64Array([now, 0])
	w[1] += 1
	_rate[id] = w
	return id if w[1] <= RATE_MAX else 0


func _reply(id: int, err: String) -> void:
	if err != "":
		_send(id, "error", {"msg": err})
	_flush_local()


## Tell a peer why it cannot join, then drop it once the message had time to leave.
func _refuse(id: int, msg: String) -> void:
	_send(id, "error", {"msg": msg})
	var peer := _peer
	get_tree().create_timer(REFUSE_KICK_SEC).timeout.connect(func() -> void:
		if peer != null and peer == _peer and _room != null and _room.find(id).is_empty():
			peer.disconnect_peer(id))


# ---------------------------------------------------------------- inbound (every peer)

func _deliver(kind: String, p: Dictionary) -> void:
	match kind:
		"room":
			_on_room(p)
		"begin":
			_on_begin(p)
		"own":
			own = p.get("ac", {})
			round_time = float(p.get("time", round_time))
			own_updated.emit(own)
		"radar":
			radar.assign(p.get("targets", []))
			round_time = float(p.get("time", round_time))
			radar_swept.emit(radar)
		"radio":
			radio_tx.assign(p.get("tx", []))
			dl_tx.assign(p.get("dl", []))
			radio_changed.emit(radio_tx)
		"dl":
			var m: Dictionary = p.get("msg", {})
			if not m.is_empty() and phase == "playing":
				_log_dl(m)
				datalink.emit(m)
		"event":
			var ev: Dictionary = p.get("event", {})
			events.append(ev)
			round_event.emit(ev)
		"end":
			result = p.get("result", {})
			_ptt_on = false
			round_ended.emit(result)
			_set_phase("ended")
		"error":
			error.emit(String(p.get("msg", "")))


func _on_room(p: Dictionary) -> void:
	players.assign(p.get("players", []))
	server_dedicated = bool(p.get("dedicated", false))
	var room_phase := String(p.get("phase", "lobby"))
	var me := players.filter(func(q: Dictionary) -> bool: return int(q["id"]) == my_id)
	if not me.is_empty():
		my_name = String(me[0]["name"])
		is_leader = bool(me[0].get("host", false))
	if phase == "menu" or (room_phase == "lobby" and phase != "lobby"):
		_clear_round()
		_set_phase("lobby")
	lobby_changed.emit()
	var connected := players.filter(func(q: Dictionary) -> bool: return bool(q.get("connected", true))).size()
	if _autostart and is_leader and phase == "lobby" and connected >= min_players:
		_autostart = false
		start_round.call_deferred()


func _on_begin(p: Dictionary) -> void:
	var you: Dictionary = p.get("you", {})
	my_role = String(you.get("role", ""))
	i_am_impostor = bool(you.get("impostor", false))
	my_callsign = String(you.get("callsign", ""))
	round_players.assign(p.get("players", []))
	world = p.get("world", {})
	atis = p.get("atis", {})
	own = {}
	radar.clear()
	events.clear()
	result = {}
	radio_tx.clear()
	dl_tx.clear()
	dl_log.clear()
	round_time = 0.0
	_ptt_on = false
	round_began.emit()
	_set_phase("playing")


## Keep one entry per message id (a later status replaces the earlier one in place).
func _log_dl(m: Dictionary) -> void:
	var mid := int(m.get("id", 0))
	for i in range(dl_log.size() - 1, maxi(-1, dl_log.size() - 40), -1):
		if int(dl_log[i].get("id", -1)) == mid:
			dl_log[i] = m
			return
	dl_log.append(m)
	if dl_log.size() > DL_LOG_MAX:
		dl_log.pop_front()


# ---------------------------------------------------------------- connection events

func _on_connected_to_server() -> void:
	my_id = multiplayer.get_unique_id()
	_s_hello.rpc_id(1, _pending_name)


func _on_connection_failed() -> void:
	_teardown()
	error.emit("Could not connect")
	_set_phase("menu")


func _on_server_disconnected() -> void:
	_teardown()
	connection_lost.emit()
	_set_phase("menu")


func _on_peer_connected(_id: int) -> void:
	pass # nothing until the peer says hello


func _on_peer_disconnected(id: int) -> void:
	_rate.erase(id)
	if is_host and _room != null and not is_demo:
		_room.disconnect_player(id)
		_flush_local()


# ---------------------------------------------------------------- hosting / dedicated server

## Listen on ENet `port` and WebSocket `ws_port` (0 = off) behind one MultiServerPeer.
func _listen(port: int, ws_port: int) -> Error:
	if OS.has_feature("web"):
		error.emit("Browsers cannot host a game: join one instead.")
		return ERR_UNAVAILABLE
	if port <= 0 and ws_port <= 0:
		error.emit("No port to host on.")
		return ERR_INVALID_PARAMETER
	var multi := MultiServerPeer.new()
	if port > 0:
		var enet := ENetMultiplayerPeer.new()
		var err := enet.create_server(port, MAX_CLIENTS, ENET_CHANNELS)
		if err != OK:
			multi.close()
			error.emit("Could not host on UDP port %d: %s" % [port, error_string(err)])
			return err
		multi.add(enet)
	if ws_port > 0:
		var ws := WebSocketMultiplayerPeer.new()
		_ws_buffers(ws)
		var err2 := ws.create_server(ws_port)
		if err2 != OK:
			multi.close()
			error.emit("Could not host on TCP port %d (WebSocket): %s" % [ws_port, error_string(err2)])
			return err2
		multi.add(ws)
	_peer = multi
	multiplayer.multiplayer_peer = multi
	listen_port = maxi(port, 0)
	listen_ws_port = maxi(ws_port, 0)
	transport = "enet+ws" if port > 0 and ws_port > 0 else ("enet" if port > 0 else "ws")
	return OK


func _new_server_room() -> Room:
	var r := Room.new(_send, SimRng.from_entropy(), min_players)
	r.dedicated = true
	return r


## Dedicated server: mirror the room into the public state (phase, players, radio_tx,
## round_players, result) so Voice's relay rule and the server log see it, and emit
## the usual signals. The server is never in the room, so it gets no messages itself.
func _mirror_room() -> void:
	if _room == null:
		return
	var st := _room.state()
	var sig := JSON.stringify(st)
	var room_dl := _room.dl_tx()
	if _room.tx != radio_tx or room_dl != dl_tx:
		radio_tx.assign(_room.tx)
		dl_tx.assign(room_dl)
		radio_changed.emit(radio_tx)
	if sig == _mirror_sig:
		return
	_mirror_sig = sig
	players.assign(st["players"])
	if _room.phase != phase:
		match _room.phase:
			"playing":
				_clear_round()
				round_players.assign(_room.round_players())
				var who := PackedStringArray()
				for q in round_players:
					who.append("%s (%s %s)" % [q["name"], q["role"], q["callsign"]])
				_log("round started: " + ", ".join(who))
				_set_phase("playing")
				round_began.emit()
			"ended":
				result = _room.sim.result(_room.roles.real_controller_id, _room.roles.impostor_id)
				_ended_t = 0.0
				_log("round ended after %d s: %s wins" % [result["duration_sec"], result["winner"]])
				_set_phase("ended")
				round_ended.emit(result)
			_:
				_clear_round()
				_set_phase(_room.phase)
	var names := PackedStringArray()
	for q in players:
		names.append("%s%s" % [q["name"], "*" if q["host"] else ""])
	_log("%s: %d player(s) %s" % [phase, players.size(), ", ".join(names)])
	lobby_changed.emit()


func _server_tick(delta: float) -> void:
	if _room == null:
		return
	var connected := _room.connected_ids().size()
	if connected == 0 and (_room.phase != "lobby" or not _room.players.is_empty()):
		_log("everyone left: room reset")
		_room = _new_server_room()
		_mirror_room()
		return
	if autostart_at <= 0:
		return
	if _room.phase == "lobby" and _room.host_id != 0 and connected >= maxi(autostart_at, _room.min_players):
		_report(_room.start(_room.host_id))
	elif _room.phase == "ended":
		_ended_t += delta
		if _ended_t >= lobby_after and _room.host_id != 0:
			_report(_room.back_to_lobby(_room.host_id))


func _log(msg: String) -> void:
	if is_dedicated:
		print("[server] %s" % msg)


static func _page_is_https() -> bool:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return false
	var v: Variant = Engine.get_singleton("JavaScriptBridge").call("eval", "window.location.protocol", true)
	return v is String and v == "https:"


# ---------------------------------------------------------------- state

func _set_phase(p: String) -> void:
	if p == phase:
		return
	phase = p
	phase_changed.emit(p)


func _clear_round() -> void:
	round_players.clear()
	my_role = ""
	i_am_impostor = false
	my_callsign = ""
	own = {}
	radar.clear()
	radio_tx.clear()
	dl_tx.clear()
	dl_log.clear()
	events.clear()
	result = {}
	round_time = 0.0
	_ptt_on = false
	fast_forward = false


## Drop any session (closing the peer ends it for every client if we host).
func _teardown() -> void:
	var peer := _peer
	_room = null
	_demo = null
	_peer = null
	_local.clear()
	_rate.clear()
	is_host = false
	is_demo = false
	is_leader = false
	is_dedicated = false
	server_dedicated = false
	transport = ""
	server_address = ""
	listen_port = 0
	listen_ws_port = 0
	_mirror_sig = ""
	my_id = 0
	players.clear()
	world = {}
	atis = {}
	_clear_round()
	if is_inside_tree():
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if peer != null:
		peer.close()


func _apply_launch_args() -> void:
	var a := LaunchArgs.current()
	min_players = a.min_players
	if a.name != "":
		my_name = a.name
	_autostart = a.autostart
	autostart_at = a.autostart_at
	lobby_after = a.lobby_after
	if a.net_test:
		Engine.time_scale = a.time_scale
		add_child(load("res://core/net/net_test.gd").new())
	if a.server or OS.has_feature("dedicated_server"):
		_run_dedicated(a)
	elif a.demo != "":
		start_demo(a.demo)
	elif a.host:
		host_game(my_name if my_name != "" else "Host", a.port, a.ws_port)
	elif a.join != "":
		join_game(my_name if my_name != "" else "Player", a.join, a.port)


func _run_dedicated(a: LaunchArgs) -> void:
	if Engine.max_fps == 0:
		Engine.max_fps = SERVER_MAX_FPS
	# Leave the game's main scene (menu, 3D backdrop) before the server state exists, so no
	# view ever reacts to it. Launching with the server scene as the scene arg skips this.
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != SERVER_SCENE:
		if scene != null:
			# Free it now (not queued) so its pending coroutines are dropped, not resumed
			# outside the tree.
			scene.get_parent().remove_child(scene)
			scene.free()
		get_tree().change_scene_to_file(SERVER_SCENE)
		await get_tree().scene_changed
	if start_server(a.port, a.ws_port) != OK:
		push_error("Dedicated server could not start")
		get_tree().quit(1)


func _ws_buffers(ws: WebSocketMultiplayerPeer) -> void:
	ws.inbound_buffer_size = WS_BUFFER_BYTES
	ws.outbound_buffer_size = WS_BUFFER_BYTES
	ws.max_queued_packets = WS_MAX_QUEUED_PACKETS
