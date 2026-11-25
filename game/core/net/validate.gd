extends RefCounted
## Defensive checks on everything a client sends (port of src/server/validate.ts).
## Nothing here trusts types: RPC arguments arrive as arbitrary Variants.

const NAME_MAX := 16
const RAW_NAME_MAX := 200
const AP_NUM_KEYS: Array[String] = ["hdg", "alt", "spd", "alt_setting"]
const AP_BOOL_KEYS: Array[String] = ["app", "gear"]


static func is_finite_num(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	return typeof(v) == TYPE_FLOAT and is_finite(float(v))


## Parse an `ap` command. Fills `out` with the accepted fields (unknown keys are
## dropped) and returns "" when valid, else the reason.
static func parse_ap(raw: Variant, out: Dictionary) -> String:
	out.clear()
	if typeof(raw) != TYPE_DICTIONARY:
		return "Bad ap: not a dictionary"
	var d: Dictionary = raw
	for k in AP_NUM_KEYS:
		if d.has(k):
			if not is_finite_num(d[k]):
				return "Bad ap: " + k
			out[k] = float(d[k])
	for k in AP_BOOL_KEYS:
		if d.has(k):
			if typeof(d[k]) != TYPE_BOOL:
				return "Bad ap: " + k
			out[k] = bool(d[k])
	if d.has("flaps"):
		var f: Variant = d["flaps"]
		if not is_finite_num(f) or float(f) != floorf(float(f)) or float(f) < 0.0 or float(f) > 3.0:
			out.clear()
			return "Bad ap: flaps"
		out["flaps"] = int(f)
	return ""


## Control, format (bidi overrides, zero-width), line/paragraph separators,
## surrogates and private use: the \p{C}\p{Zl}\p{Zp} set of the TS version.
static func _is_hidden(c: int) -> bool:
	return c < 0x20 or (c >= 0x7F and c <= 0x9F) or c == 0xAD or c == 0x061C or c == 0x180E \
		or (c >= 0x200B and c <= 0x200F) or (c >= 0x2028 and c <= 0x202E) \
		or (c >= 0x2060 and c <= 0x206F) or c == 0xFEFF or (c >= 0xFFF9 and c <= 0xFFFB) \
		or (c >= 0xD800 and c <= 0xF8FF) or (c >= 0xE0000 and c <= 0xE007F) or c >= 0xF0000


static func _is_space(c: int) -> bool:
	return c == 0x20 or c == 0xA0 or c == 0x1680 or (c >= 0x2000 and c <= 0x200A) \
		or c == 0x202F or c == 0x205F or c == 0x3000


## Display name: printable, single-spaced, 1-16 characters ("Player" if nothing is left).
static func sanitize_name(raw: Variant) -> String:
	var src := String(raw) if typeof(raw) == TYPE_STRING else ""
	src = src.substr(0, RAW_NAME_MAX)
	var out := ""
	var pending_space := false
	for i in src.length():
		var c := src.unicode_at(i)
		if _is_hidden(c):
			continue
		if _is_space(c):
			pending_space = true
			continue
		if pending_space and out != "":
			out += " "
		pending_space = false
		out += String.chr(c)
	out = out.substr(0, NAME_MAX).strip_edges()
	return out if out != "" else "Player"


## Append " 2", " 3"... until the name is unique (case-insensitive) among `taken`.
static func dedupe_name(name: String, taken: Array[String]) -> String:
	var lower := {}
	for n in taken:
		lower[n.to_lower()] = true
	if not lower.has(name.to_lower()):
		return name
	var i := 2
	while true:
		var suffix := " %d" % i
		var candidate := name.substr(0, NAME_MAX - suffix.length()).strip_edges(false, true) + suffix
		if not lower.has(candidate.to_lower()):
			return candidate
		i += 1
	return name
