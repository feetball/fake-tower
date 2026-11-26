extends RefCounted
## Transport-level logic: join address parsing, launch args (command line and web
## query string), dedicated-server room behaviour (leader, handover), and the
## multi-transport server peer's bookkeeping.

const T := preload("res://tests/lib/t.gd")
const Address := preload("res://core/net/address.gd")
const LaunchArgs := preload("res://core/net/launch_args.gd")
const Room := preload("res://core/net/room.gd")
const SimRng := preload("res://core/sim/rng.gd")
const MultiServerPeer := preload("res://core/net/multi_server_peer.gd")

const EP := 27270
const WP := 27271


static func p(text: String, transport: String = "enet", secure: bool = false) -> Dictionary:
	return Address.parse(text, EP, WP, transport, secure)


func _expect(t: T, d: Dictionary, transport: String, host: String, port: int, url: String, label: String) -> void:
	t.check(d["ok"], "%s: ok (error: %s)" % [label, d["error"]])
	t.eq(d["transport"], transport, label + " transport")
	t.eq(d["host"], host, label + " host")
	t.eq(d["port"], port, label + " port")
	t.eq(d["url"], url, label + " url")


func test_address_bare_and_port_enet(t: T) -> void:
	_expect(t, p("192.168.1.20"), "enet", "192.168.1.20", EP, "", "bare ip")
	_expect(t, p("  tower.lan  "), "enet", "tower.lan", EP, "", "trimmed name")
	_expect(t, p("tower.lan:4000"), "enet", "tower.lan", 4000, "", "host:port")
	_expect(t, p("::1"), "enet", "::1", EP, "", "bare ipv6")
	_expect(t, p("[fe80::1]:4000"), "enet", "fe80::1", 4000, "", "[v6]:port")
	_expect(t, p("[::1]"), "enet", "::1", EP, "", "[v6] no port")
	_expect(t, p("enet://10.0.0.2:5000", "ws"), "enet", "10.0.0.2", 5000, "", "enet:// forces enet")
	_expect(t, p("ENET://10.0.0.2"), "enet", "10.0.0.2", EP, "", "enet:// default port, any case")
	t.done()


func test_address_bare_over_websocket(t: T) -> void:
	_expect(t, p("10.0.0.2", "ws"), "ws", "10.0.0.2", WP, "ws://10.0.0.2:27271", "bare -> ws default port")
	_expect(t, p("10.0.0.2:9000", "ws"), "ws", "10.0.0.2", 9000, "ws://10.0.0.2:9000", "host:port -> ws")
	_expect(t, p("::1", "ws"), "ws", "::1", WP, "ws://[::1]:27271", "v6 bracketed in url")
	# https page: wss, and no port means the TLS proxy on 443.
	_expect(t, p("tower.example.org", "ws", true), "ws", "tower.example.org", 0, "wss://tower.example.org", "secure bare")
	_expect(t, p("tower.example.org:8443", "ws", true), "ws", "tower.example.org", 8443, "wss://tower.example.org:8443", "secure host:port")
	t.done()


func test_address_urls(t: T) -> void:
	_expect(t, p("ws://10.0.0.2:27271"), "ws", "10.0.0.2", 27271, "ws://10.0.0.2:27271", "ws url")
	_expect(t, p("wss://tower.example.org/play"), "ws", "tower.example.org", 0, "wss://tower.example.org/play", "wss url with path, no port")
	_expect(t, p("WSS://Tower.example.org:443"), "ws", "Tower.example.org", 443, "wss://Tower.example.org:443", "scheme any case")
	_expect(t, p("https://tower.example.org/"), "ws", "tower.example.org", 0, "wss://tower.example.org/", "https -> wss")
	_expect(t, p("http://10.0.0.2:27271"), "ws", "10.0.0.2", 27271, "ws://10.0.0.2:27271", "http -> ws")
	_expect(t, p("ws://[::1]:27271/x"), "ws", "::1", 27271, "ws://[::1]:27271/x", "ws v6")
	t.done()


func test_address_errors(t: T) -> void:
	for bad: String in ["", "   ", "host:", "host:0", "host:70000", "host:abc", "ws://", "ws://:80",
			"wss://user@host", "[::1", "[::1]x", "a b", "host/path", "ftp://host"]:
		var d := p(bad)
		t.check(not d["ok"], "should fail: '%s'" % bad)
		t.check(String(d["error"]) != "", "error text for '%s'" % bad)
	t.done()


func test_launch_args_server_and_ports(t: T) -> void:
	var a := LaunchArgs.parse(PackedStringArray(["--server", "--min-players=3", "--autostart-at=5", "--lobby-after=7"]))
	t.check(a.server, "server")
	t.eq(a.min_players, 3, "min players")
	t.eq(a.autostart_at, 5, "autostart at")
	t.eq(a.lobby_after, 7.0, "lobby after")
	t.eq(a.port, 27270, "default enet port")
	t.eq(a.ws_port, 27271, "default ws port")
	var b := LaunchArgs.parse(PackedStringArray(["--port=4000"]))
	t.eq(b.ws_port, 4001, "ws port follows --port")
	var c := LaunchArgs.parse(PackedStringArray(["--port=4000", "--ws-port=0"]))
	t.eq(c.ws_port, 0, "ws off")
	var d := LaunchArgs.parse(PackedStringArray(["--ws-port=8080", "--time-scale=500"]))
	t.eq(d.ws_port, 8080, "explicit ws port")
	t.eq(d.port, 27270, "enet port unchanged")
	t.eq(d.time_scale, 100.0, "time scale clamped")
	t.check(not d.server and d.autostart_at == 0, "defaults")
	t.done()


func test_launch_args_from_web_query(t: T) -> void:
	var q := LaunchArgs.from_query("?demo=pilot&name=Ann%20Lee&join=wss%3A%2F%2Ftower.example.org%2Fplay&autostart&server&host&net-test&x=1#frag")
	t.eq(Array(q), ["--demo=pilot", "--name=Ann Lee", "--join=wss://tower.example.org/play", "--autostart"], "query -> args (host/server/test keys dropped)")
	var a := LaunchArgs.parse(q)
	t.eq(a.demo, "pilot", "demo")
	t.eq(a.name, "Ann Lee", "name")
	t.eq(a.join, "wss://tower.example.org/play", "join url")
	t.check(a.autostart and not a.host and not a.server, "flags")
	t.eq(Array(LaunchArgs.from_query("")), [], "empty")
	t.eq(Array(LaunchArgs.from_query("name=A+B&port=9000")), ["--name=A B", "--port=9000"], "plus is space, no leading ?")
	t.done()


class Rec:
	var msgs: Array[Array] = []

	func send(to: int, kind: String, payload: Dictionary) -> void:
		msgs.append([to, kind, payload.duplicate(true)])

	func last_room(id: int) -> Dictionary:
		for i in range(msgs.size() - 1, -1, -1):
			if msgs[i][0] == id and msgs[i][1] == "room":
				return msgs[i][2]
		return {}


func test_dedicated_room_leader_and_handover(t: T) -> void:
	var rec := Rec.new()
	var room := Room.new(rec.send, SimRng.new(3), 4)
	room.dedicated = true
	for id in [11, 22, 33, 44]:
		room.add(id, "P%d" % id)
	var st := rec.last_room(22)
	t.eq(st.get("dedicated"), true, "clients learn the host is dedicated")
	t.eq(room.host_id, 11, "first joined leads")
	t.check(room.find(1).is_empty(), "server (id 1) is not a player")
	t.eq(room.start(22), "Only the host can start", "non-leader cannot start")
	# Leader leaves in the lobby: next in join order leads.
	room.disconnect_player(11)
	t.eq(room.host_id, 22, "handover in lobby")
	var hosts := (rec.last_room(33)["players"] as Array).filter(func(q: Dictionary) -> bool: return q["host"])
	t.eq(hosts.size(), 1, "one leader flagged")
	t.eq(int(hosts[0]["id"]), 22, "new leader flagged")
	room.add(55, "P55")
	t.eq(room.start(22), "", "new leader starts")
	t.eq(room.roles.real_controller_id != 0 and room.roles.impostor_id != 0, true, "full roles without a host player")
	var everyone: Array[int] = [room.roles.real_controller_id, room.roles.impostor_id]
	everyone.append_array(room.roles.pilots)
	everyone.sort()
	t.eq(everyone, [22, 33, 44, 55] as Array[int], "roles cover exactly the players")
	# Leader drops mid-round: handed on; disconnected leader stays listed.
	room.disconnect_player(22)
	t.eq(room.host_id, 33, "handover mid-round")
	room.end_round()
	t.eq(room.back_to_lobby(33), "", "new leader returns to lobby")
	t.check(room.find(22).is_empty(), "disconnected player dropped on return")
	for id in [33, 44, 55]:
		room.disconnect_player(id)
	t.eq(room.host_id, 0, "no leader when empty")
	room.add(66, "P66")
	t.eq(room.host_id, 66, "next to join leads")
	t.done()


func test_player_host_room_unchanged(t: T) -> void:
	var rec := Rec.new()
	var room := Room.new(rec.send, SimRng.new(3), 2)
	room.add(1, "Host")
	room.add(7, "C")
	t.check(not rec.last_room(7).has("dedicated"), "no dedicated flag for a player-host")
	t.eq(room.host_id, 1, "host leads")
	room.disconnect_player(7)
	t.eq(room.host_id, 1, "host keeps leading")
	t.done()


func test_multi_server_peer_bookkeeping(t: T) -> void:
	var m := MultiServerPeer.new()
	t.eq(m.get_connection_status(), MultiplayerPeer.CONNECTION_DISCONNECTED, "closed before add")
	var enet := ENetMultiplayerPeer.new()
	var ws := WebSocketMultiplayerPeer.new()
	var port := 30000 + randi() % 20000
	t.eq(enet.create_server(port, 4), OK, "enet listens")
	t.eq(ws.create_server(port + 1), OK, "ws listens")
	m.add(enet)
	m.add(ws)
	t.eq(m.get_connection_status(), MultiplayerPeer.CONNECTION_CONNECTED, "open")
	t.eq(m.get_unique_id(), 1, "server id")
	t.check(m.is_server_relay_supported(), "relay supported")
	var seen: Array[int] = []
	m.peer_connected.connect(func(id: int) -> void: seen.append(id))
	m.peer_disconnected.connect(func(id: int) -> void: seen.append(-id))
	enet.peer_connected.emit(1234)
	ws.peer_connected.emit(1234) # id clash across transports: refused, not reported
	ws.peer_connected.emit(5678)
	t.eq(seen, [1234, 5678] as Array[int], "connections reported once")
	t.check(m.peer_transport(1234) == enet and m.peer_transport(5678) == ws, "owner per id")
	ws.peer_disconnected.emit(1234) # not ws's peer
	enet.peer_disconnected.emit(1234)
	t.eq(seen, [1234, 5678, -1234] as Array[int], "disconnect only from the owner")
	m.refuse_new_connections = true
	t.check(enet.refuse_new_connections and ws.refuse_new_connections, "refuse propagates")
	m.close()
	t.eq(m.get_connection_status(), MultiplayerPeer.CONNECTION_DISCONNECTED, "closed")
	t.done()
