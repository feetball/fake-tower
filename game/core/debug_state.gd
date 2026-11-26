class_name DebugState
extends Node
## Test hook for browser tests (game/tests/web): with the user arg `--debug-state`
## (on the web: `?debug-state=1` in the page URL) a compact snapshot of the game
## state is published whenever it changes: as `window.ftState` (a JSON string) on
## the web and as a `[ft-state] {...}` line on stdout / the browser console.
## Read-only: it never changes the game.

var _last := ""
var _t := 0.0


static func wanted() -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--debug-state" or (a.begins_with("--debug-state=") and a != "--debug-state=0"):
			return true
	return false


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.1:
		return
	_t = 0.0
	var own: Dictionary = Session.own
	var s := {
		"phase": Session.phase,
		"role": Session.my_role,
		"my_id": Session.my_id,
		"players": Session.players.size(),
		"transport": Session.transport,
		"ptt": Session.radio_tx.has(Session.my_id),
		"touch": TouchMode.active(),
		"sel_hdg": int(own.get("sel_hdg", -1)),
		"sel_alt": int(own.get("sel_alt", -1)),
		"sel_spd": int(own.get("sel_spd", -1)),
		"app_armed": bool(own.get("app_armed", false)),
		"gear_down": bool(own.get("gear_down", false)),
		"flaps": int(own.get("flaps", -1)),
	}
	s["targets"] = _targets()
	var j := JSON.stringify(s)
	if j == _last:
		return
	_last = j
	print("[ft-state] ", j)
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var jsb: Object = Engine.get_singleton("JavaScriptBridge")
		jsb.call("eval", "window.ftState = %s;" % JSON.stringify(j), true)


## Window-pixel rects [x, y, w, h, held] of the visible touch controls a test may tap
## (the browser maps them to CSS pixels with the canvas scale).
func _targets() -> Dictionary:
	var out := {}
	var hud := get_tree().get_first_node_in_group(&"radio_hud")
	if hud != null:
		_add_rect(out, "ptt", hud.get_node_or_null(^"TouchPtt") as Control)
	var tc := get_tree().root.find_child("TouchControls", true, false)
	if tc != null:
		var tabs: Variant = tc.get(&"_tabs")
		if tabs is Dictionary:
			for k: String in (tabs as Dictionary):
				_add_rect(out, "tab_" + k, (tabs as Dictionary)[k] as Control)
		for p: String in ["_plus", "_minus", "_big", "_app", "_gear"]:
			_add_rect(out, p.trim_prefix("_"), tc.get(StringName(p)) as Control)
	return out


static func _add_rect(out: Dictionary, key: String, c: Control) -> void:
	if c == null or not c.is_visible_in_tree():
		return
	var xf := c.get_viewport().get_final_transform() * c.get_global_transform_with_canvas()
	var p := xf * Vector2.ZERO
	var e := xf * c.size
	out[key] = [roundi(p.x), roundi(p.y), roundi(e.x - p.x), roundi(e.y - p.y), 1 if c.get(&"held") else 0]
