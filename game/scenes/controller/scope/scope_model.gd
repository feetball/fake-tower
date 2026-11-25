extends RefCounted
## What the scope knows: targets as of the last sweep (no interpolation), their
## history trails, landed/crashed bookkeeping, selection, leader directions,
## scratchpads, layer toggles and aural-alert state. All UI-local.

const Fmt := preload("res://scenes/controller/scope/scope_format.gd")

signal changed()
signal selection_changed(callsign: String)

const HISTORY_LEN := 5
## History keeps every Nth sweep position: 2 s sweeps would put the dots on top of each other.
const HISTORY_EVERY := 2
const LANDED_SHOW_MS := 20000
const ALERT_REPEAT_MS := 15000
const LAYER_KEYS: PackedStringArray = ["rr", "cl", "fix", "terr", "msa", "hold", "ptl", "hist"]
const LAYER_LABELS := {"rr": "RR", "cl": "CL", "fix": "FIX", "terr": "TERR", "msa": "MSA", "hold": "HOLD", "ptl": "PTL", "hist": "HIST"}

var targets: Dictionary = {} ## callsign -> latest radar target
var order: PackedStringArray = [] ## callsigns in order of first appearance
var history: Dictionary = {} ## callsign -> PackedVector2Array, oldest first
var landed_ms: Dictionary = {} ## callsign -> ticks when first seen landed
var sweep_ms := -1
var sweep_count := 0
var selected := ""
var leader_dir: Dictionary = {} ## callsign -> int degrees, set by the controller
var scratch: Dictionary = {} ## callsign -> String
var layers := {"rr": true, "cl": true, "fix": true, "terr": true, "msa": true, "hold": true, "ptl": false, "hist": true}
var _alert_played: Dictionary = {} ## "CS|CA" -> ticks last sounded
var _alert_acked: Dictionary = {} ## "CS|CA" -> true


## Takes one sweep. Returns the alert kinds ("CA"/"LA") that should sound now.
func ingest(list: Array, now_ms: int) -> PackedStringArray:
	var seen := {}
	for raw: Variant in list:
		if not raw is Dictionary:
			continue
		var t: Dictionary = raw
		var cs := String(t.get("callsign", ""))
		if cs == "":
			continue
		seen[cs] = true
		var prev: Dictionary = targets.get(cs, {})
		if not prev.is_empty() and String(prev.get("status", "")) == "flying" and sweep_count % HISTORY_EVERY == 0:
			var hist: PackedVector2Array = history.get(cs, PackedVector2Array())
			var p := Fmt.target_pos(prev)
			if hist.is_empty() or hist[hist.size() - 1].distance_to(p) > 0.001:
				hist.append(p)
			while hist.size() > HISTORY_LEN:
				hist.remove_at(0)
			history[cs] = hist
		if not order.has(cs):
			order.append(cs)
		targets[cs] = t
		if String(t.get("status", "")) == "landed" and not landed_ms.has(cs):
			landed_ms[cs] = now_ms
	for cs: String in targets.keys():
		if not seen.has(cs):
			_forget(cs)
	sweep_ms = now_ms
	sweep_count += 1
	var sound := _alerts_to_sound(now_ms)
	changed.emit()
	return sound


func _forget(cs: String) -> void:
	targets.erase(cs)
	history.erase(cs)
	landed_ms.erase(cs)
	var i := order.find(cs)
	if i >= 0:
		order.remove_at(i)
	if selected == cs:
		select("")


func _alerts_to_sound(now_ms: int) -> PackedStringArray:
	var active := {}
	var kinds := PackedStringArray()
	for cs: String in order:
		var t: Dictionary = targets[cs]
		if String(t.get("status", "")) != "flying":
			continue
		for kind: String in ["CA", "LA"]:
			var on := bool(t.get("conflict" if kind == "CA" else "msaw", false))
			if not on:
				continue
			var key := cs + "|" + kind
			active[key] = true
			if _alert_acked.has(key):
				continue
			var last := int(_alert_played.get(key, -ALERT_REPEAT_MS * 2))
			if now_ms - last >= ALERT_REPEAT_MS:
				_alert_played[key] = now_ms
				if not kinds.has(kind):
					kinds.append(kind)
	for key: String in _alert_played.keys():
		if not active.has(key):
			_alert_played.erase(key)
			_alert_acked.erase(key)
	return kinds


## Targets drawn on the scope: flying, crashed, and recently landed.
func visible_callsigns(now_ms: int) -> PackedStringArray:
	var out := PackedStringArray()
	for cs: String in order:
		var t: Dictionary = targets[cs]
		if String(t.get("status", "")) == "landed" and now_ms - int(landed_ms.get(cs, now_ms)) > LANDED_SHOW_MS:
			continue
		out.append(cs)
	return out


func has_alert() -> bool:
	for cs: String in order:
		var t: Dictionary = targets[cs]
		if String(t.get("status", "")) == "flying" and Fmt.alert_tag(t) != "":
			return true
	return false


## Seconds within the landed tag's display window, or -1 when not landed.
func landed_age(cs: String, now_ms: int) -> float:
	if not landed_ms.has(cs):
		return -1.0
	return float(now_ms - int(landed_ms[cs])) / 1000.0


func select(cs: String) -> void:
	if cs == selected:
		return
	selected = cs
	if cs != "":
		# Selecting a target acknowledges its aural alerts (the flashing stays).
		for kind: String in ["CA", "LA"]:
			_alert_acked[cs + "|" + kind] = true
	selection_changed.emit(cs)
	changed.emit()


func set_leader(cs: String, deg: int) -> void:
	if cs == "":
		return
	leader_dir[cs] = deg
	changed.emit()


func set_scratch(cs: String, text: String) -> void:
	if cs == "":
		return
	scratch[cs] = text
	changed.emit()


func toggle_layer(key: String) -> void:
	if layers.has(key):
		layers[key] = not bool(layers[key])
		changed.emit()


func sweep_age_sec(now_ms: int) -> float:
	return -1.0 if sweep_ms < 0 else float(now_ms - sweep_ms) / 1000.0
