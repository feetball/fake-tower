extends RefCounted
## Parses what a player types into the join field into a transport and endpoint.
## Pure (no engine state), unit-tested in tests/test_net.gd.
##
## Accepted forms:
##   host                 bare host name, IPv4 or IPv6 (`::1`)
##   host:port  [v6]:port explicit port
##   ws://… wss://…       WebSocket URL, used verbatim (no port = 80 / 443, as in any URL)
##   http://… https://…   treated as ws:// / wss:// (pasting a proxy's page URL works)
##   enet://host[:port]   force ENet (desktop and mobile only)
## A bare host goes over `transport` ("enet" or "ws"). A bare host over WebSocket uses
## wss:// with no port (a TLS proxy on 443) when `secure` (an https page), else
## ws://host:<ws_port>.

const ENET := "enet"
const WS := "ws"


## Returns {ok:bool, error:String, transport:"enet"|"ws", host:String, port:int, url:String}.
## `port` is 0 when a URL leaves it to the scheme default. `url` is the WebSocket URL
## ("" for ENet).
static func parse(text: String, enet_port: int, ws_port: int, transport: String = ENET,
		secure: bool = false) -> Dictionary:
	var s := text.strip_edges()
	if s == "":
		return _fail("Enter the host's address.")
	if s.contains(" ") or s.contains("\t"):
		return _fail("The address must not contain spaces.")
	var lower := s.to_lower()
	for scheme: String in ["ws://", "wss://", "http://", "https://"]:
		if lower.begins_with(scheme):
			return _parse_url(s, scheme)
	if lower.begins_with("enet://"):
		var hp := _host_port(s.substr(7), enet_port)
		if not hp["ok"]:
			return hp
		return _ok(ENET, hp["host"], hp["port"], "")
	if s.contains("/") or s.contains("://"):
		return _fail("Unrecognised address. Use host, host:port or a ws:// / wss:// URL.")
	var default_port := ws_port if transport == WS else enet_port
	var explicit := _has_port(s)
	var hp2 := _host_port(s, default_port)
	if not hp2["ok"]:
		return hp2
	var host: String = hp2["host"]
	var port: int = hp2["port"]
	if transport != WS:
		return _ok(ENET, host, port, "")
	var h := "[%s]" % host if host.contains(":") else host
	if secure:
		if explicit:
			return _ok(WS, host, port, "wss://%s:%d" % [h, port])
		return _ok(WS, host, 0, "wss://%s" % h)
	return _ok(WS, host, port, "ws://%s:%d" % [h, port])


static func _parse_url(s: String, scheme: String) -> Dictionary:
	var rest := s.substr(scheme.length())
	var tls := scheme == "wss://" or scheme == "https://"
	var cut := rest.find("/")
	var authority := rest if cut == -1 else rest.substr(0, cut)
	var path := "" if cut == -1 else rest.substr(cut)
	if authority.contains("@"):
		return _fail("User names in the address are not supported.")
	var hp := _host_port(authority, 0)
	if not hp["ok"]:
		return hp
	var url := ("wss://" if tls else "ws://") + authority + path
	return _ok(WS, hp["host"], hp["port"], url)


## True when `s` (host or host:port, no scheme) carries an explicit port.
static func _has_port(s: String) -> bool:
	if s.begins_with("["):
		return s.contains("]:")
	return s.count(":") == 1


## Splits host[:port] / [v6][:port] / bare v6. Returns {ok, error, host, port}.
static func _host_port(s: String, default_port: int) -> Dictionary:
	var host := s
	var port_s := ""
	if s.begins_with("["):
		var close := s.find("]")
		if close == -1:
			return _fail("Missing ] in IPv6 address.")
		host = s.substr(1, close - 1)
		var after := s.substr(close + 1)
		if after != "":
			if not after.begins_with(":"):
				return _fail("Unrecognised address after ].")
			port_s = after.substr(1)
	elif s.count(":") == 1:
		host = s.get_slice(":", 0)
		port_s = s.get_slice(":", 1)
	# More than one colon without brackets: a bare IPv6 address, no port.
	if host == "":
		return _fail("The address has no host.")
	var port := default_port
	if port_s != "" or (s.count(":") == 1 and not s.begins_with("[")):
		if not port_s.is_valid_int() or port_s.to_int() < 1 or port_s.to_int() > 65535:
			return _fail("Port must be a number between 1 and 65535.")
		port = port_s.to_int()
	return {"ok": true, "error": "", "host": host, "port": port}


static func _ok(transport: String, host: String, port: int, url: String) -> Dictionary:
	return {"ok": true, "error": "", "transport": transport, "host": host, "port": port, "url": url}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "transport": "", "host": "", "port": 0, "url": ""}
