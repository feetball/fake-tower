extends SceneTree
## Headless test runner:
##   godot --headless --path game -s res://tests/run_tests.gd [-- --only=<substring>]
## Runs every `test_*` method of the suites below, prints PASS/FAIL per test
## and a SUMMARY line, and exits 0 when everything passed.

const T := preload("res://tests/lib/t.gd")
const SUITES: Array[String] = [
	"res://tests/test_sim.gd",
	"res://tests/test_attitude.gd",
	"res://tests/test_server.gd",
	"res://tests/test_regression.gd",
	"res://tests/test_parity.gd",
	"res://tests/test_demo.gd",
	"res://tests/test_net.gd",
	"res://tests/test_datalink.gd",
	"res://tests/test_ai.gd",
	"res://tests/test_settings.gd",
	"res://tests/test_rain_glass.gd",
]


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var passed := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL %s (could not load)" % path)
			failed += 1
			continue
		var suite: Object = script.new()
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			var full := "%s::%s" % [path.get_file().get_basename(), mname]
			if only != "" and not full.contains(only):
				continue
			var t := T.new()
			var s0 := Time.get_ticks_msec()
			suite.call(mname, t)
			var ms := Time.get_ticks_msec() - s0
			if not t.completed:
				t.failures.append("did not complete (script error?)")
			if t.failures.is_empty():
				passed += 1
				print("PASS %s (%d ms)" % [full, ms])
			else:
				failed += 1
				print("FAIL %s (%d ms)" % [full, ms])
				for f in t.failures:
					print("     - " + f)
	print("SUMMARY: %d passed, %d failed (%.1f s)" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0 if failed == 0 else 1)
