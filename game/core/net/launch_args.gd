extends RefCounted
## Launch options. Desktop/mobile: command-line user args (after `--`). Web: the page
## URL's query string as well (`?demo=pilot&name=X&join=wss://host`), see from_query().
##   --demo=<role> --host --join=<addr> --name=<n> --port=<p> --ws-port=<p>
##   --autostart --min-players=<n> --net-test
##   --server [--autostart-at=<n>] [--lobby-after=<sec>]   dedicated server (SERVER.md)
##   --time-scale=<k>   with --net-test only: speed up the host's simulation
## --port is the ENet (UDP) port; the WebSocket (TCP) port defaults to 27271, or to
## --port + 1 when only --port is given.

const Self := preload("res://core/net/launch_args.gd")
const DEFAULT_PORT := 27270
const DEFAULT_WS_PORT := 27271
## Query keys honoured on the web. Hosting and the dedicated server cannot run in a browser.
const WEB_KEYS: Array[String] = ["demo", "join", "name", "port", "ws-port", "autostart", "min-players"]

var demo := ""
var host := false
var join := ""
var name := ""
var port := DEFAULT_PORT
var ws_port := DEFAULT_WS_PORT
var autostart := false
var min_players := 4
var net_test := false
var server := false
var autostart_at := 0 ## dedicated server: start the round when this many players are in (0 = leader starts)
var lobby_after := 15.0 ## dedicated server with autostart_at: seconds from round end back to lobby
var time_scale := 1.0


static func parse(args: PackedStringArray) -> Self:
	var a := Self.new()
	var ws_given := false
	for s in args:
		if s.begins_with("--demo="):
			a.demo = s.trim_prefix("--demo=")
		elif s == "--host":
			a.host = true
		elif s.begins_with("--join="):
			a.join = s.trim_prefix("--join=")
		elif s.begins_with("--name="):
			a.name = s.trim_prefix("--name=")
		elif s.begins_with("--port="):
			a.port = clampi(s.trim_prefix("--port=").to_int(), 1, 65535)
		elif s.begins_with("--ws-port="):
			a.ws_port = clampi(s.trim_prefix("--ws-port=").to_int(), 0, 65535)
			ws_given = true
		elif s == "--autostart":
			a.autostart = true
		elif s.begins_with("--min-players="):
			a.min_players = clampi(s.trim_prefix("--min-players=").to_int(), 1, 8)
		elif s == "--net-test":
			a.net_test = true
		elif s == "--server":
			a.server = true
		elif s.begins_with("--autostart-at="):
			a.autostart_at = clampi(s.trim_prefix("--autostart-at=").to_int(), 0, 8)
		elif s.begins_with("--lobby-after="):
			a.lobby_after = clampf(s.trim_prefix("--lobby-after=").to_float(), 1.0, 3600.0)
		elif s.begins_with("--time-scale="):
			a.time_scale = clampf(s.trim_prefix("--time-scale=").to_float(), 0.1, 100.0)
	if not ws_given and a.port != DEFAULT_PORT:
		a.ws_port = mini(a.port + 1, 65535)
	return a


## `?demo=pilot&name=A%20B&autostart` -> ["--demo=pilot", "--name=A B", "--autostart"].
## Only WEB_KEYS pass; values are URL-decoded ('+' is a space).
static func from_query(query: String) -> PackedStringArray:
	var out := PackedStringArray()
	var q := query.strip_edges().trim_prefix("?")
	var hash_at := q.find("#")
	if hash_at != -1:
		q = q.substr(0, hash_at)
	for part in q.split("&", false):
		var eq := part.find("=")
		var key := (part if eq == -1 else part.substr(0, eq)).replace("+", " ").uri_decode().strip_edges()
		if not WEB_KEYS.has(key):
			continue
		if eq == -1:
			out.append("--" + key)
		else:
			out.append("--%s=%s" % [key, part.substr(eq + 1).replace("+", " ").uri_decode()])
	return out


## The launch options of this run: command-line user args, plus the page query on the web.
static func current() -> Self:
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		args.append_array(from_query(_web_query()))
	return parse(args)


static func _web_query() -> String:
	if not Engine.has_singleton("JavaScriptBridge"):
		return ""
	var jsb: Object = Engine.get_singleton("JavaScriptBridge")
	var v: Variant = jsb.call("eval", "window.location.search", true)
	return v if v is String else ""
