extends Node
## The `Session` autoload: the only thing views talk to (contract in ARCHITECTURE.md).
## Host-authoritative over Godot high-level multiplayer (ENet). The host runs a
## Room (core/net/room.gd) with the simulation; every peer, the host included,
## receives only its own messages through _deliver(), so the host's views see
## exactly what a client would. Clients are untrusted: every RPC they can call
## re-validates sender, phase, role and argument types.

const Room := preload("res://core/net/room.gd")
const Demo := preload("res://core/net/demo.gd")
const SimRng := preload("res://core/sim/rng.gd")
const InputSetup := preload("res://core/net/input_setup.gd")
const LaunchArgs := preload("res://core/net/launch_args.gd")

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

const DEFAULT_PORT := 27270
const MAX_PLAYERS := Room.MAX_PLAYERS
const CHANNEL_RELIABLE := 0
const CHANNEL_OWN := 1
const ENET_CHANNELS := 4 ## Voice uses channel 2
## ENet slots beyond MAX_PLAYERS so a full or running room can still refuse politely.
const MAX_CLIENTS := 15
const RATE_WINDOW_MS := 1000
const RATE_MAX := 120 ## messages per second per peer; excess is dropped
const RAW_NAME_MAX := 200
const REFUSE_KICK_SEC := 0.5

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
var events: Array[Dictionary] = []
var result: Dictionary = {}
var round_time := 0.0
var min_players := 4
var is_demo := false

var _room: Room = null
var _demo: Demo = null
var _peer: ENetMultiplayerPeer = null
var _pending_name := ""
var _ptt_on := false
var _autostart := false
var _local: Array[Array] = [] # queued [kind, payload] for this peer
var _flushing := false
var _rate: Dictionary = {} # peer id -> PackedInt64Array [window start ms, count]


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
		round_time += delta
		if _room != null:
			_room.advance(delta)
	_flush_local()


# ---------------------------------------------------------------- public API

func host_game(player_name: String, port: int = DEFAULT_PORT) -> Error:
	_teardown()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS, ENET_CHANNELS)
	if err != OK:
		error.emit("Could not host on port %d: %s" % [port, error_string(err)])
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	is_host = true
	my_id = multiplayer.get_unique_id()
	_room = Room.new(_send, SimRng.from_entropy(), min_players)
	_room.add(my_id, player_name)
	my_name = String(_room.find(my_id)["name"])
	_set_phase("lobby")
	_flush_local()
	return OK


func join_game(player_name: String, address: String, port: int = DEFAULT_PORT) -> Error:
	_teardown()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, ENET_CHANNELS)
	if err != OK:
		error.emit("Could not connect to %s:%d: %s" % [address, port, error_string(err)])
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_pending_name = player_name.substr(0, RAW_NAME_MAX)
	my_name = player_name
	return OK


func leave() -> void:
	_teardown()
	_set_phase("menu")


func start_round() -> void:
	if not is_host or _room == null or is_demo:
		return
	_report(_room.start(my_id))
	_flush_local()


func return_to_lobby() -> void:
	if not is_host or _room == null:
		return
	if is_demo:
		leave()
		return
	_report(_room.back_to_lobby(my_id))
	_flush_local()


func send_ap(changes: Dictionary) -> void:
	if phase != "playing" or my_role != "pilot":
		return
	if is_host:
		_report(_room.handle_ap(my_id, changes))
		_flush_local()
	elif _peer != null:
		_s_ap.rpc_id(1, changes)


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
	_room.begin_round(demo.roles, demo.sim)
	_flush_local()


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
			radio_changed.emit(radio_tx)
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
	var room_phase := String(p.get("phase", "lobby"))
	var me := players.filter(func(q: Dictionary) -> bool: return int(q["id"]) == my_id)
	if not me.is_empty():
		my_name = String(me[0]["name"])
	if phase == "menu" or (room_phase == "lobby" and phase != "lobby"):
		_clear_round()
		_set_phase("lobby")
	lobby_changed.emit()
	if _autostart and is_host and phase == "lobby" and _room.connected_ids().size() >= min_players:
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
	round_time = 0.0
	_ptt_on = false
	round_began.emit()
	_set_phase("playing")


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
	events.clear()
	result = {}
	round_time = 0.0
	_ptt_on = false


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
	var a := LaunchArgs.parse(OS.get_cmdline_user_args())
	min_players = a.min_players
	if a.name != "":
		my_name = a.name
	_autostart = a.autostart
	if a.net_test:
		add_child(load("res://core/net/net_test.gd").new())
	if a.demo != "":
		start_demo(a.demo)
	elif a.host:
		host_game(my_name if my_name != "" else "Host", a.port)
	elif a.join != "":
		join_game(my_name if my_name != "" else "Player", a.join, a.port)
