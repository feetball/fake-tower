extends RefCounted
## Command-line user args (after `--`): --demo=<role> --host --join=<ip>
## --name=<n> --port=<p> --autostart --min-players=<n> --net-test.

const Self := preload("res://core/net/launch_args.gd")
const DEFAULT_PORT := 27270

var demo := ""
var host := false
var join := ""
var name := ""
var port := DEFAULT_PORT
var autostart := false
var min_players := 4
var net_test := false


static func parse(args: PackedStringArray) -> Self:
	var a := Self.new()
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
		elif s == "--autostart":
			a.autostart = true
		elif s.begins_with("--min-players="):
			a.min_players = clampi(s.trim_prefix("--min-players=").to_int(), 1, 8)
		elif s == "--net-test":
			a.net_test = true
	return a
