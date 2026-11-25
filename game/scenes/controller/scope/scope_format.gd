extends RefCounted
## Scope geometry and text helpers, ported from src/client/geo.ts, format.ts
## and text.ts. World points are Vector2(x nm east, y nm north); bearings are
## degrees true, clockwise from north.

const UP_ARROW := "↑"
const DOWN_ARROW := "↓"


static func norm360(d: float) -> float:
	return fposmod(d, 360.0)


## Heading for display: 001..360.
static func hdg_text(d: float) -> String:
	var v := int(round(norm360(d))) % 360
	return "%03d" % (360 if v == 0 else v)


static func bearing_to(a: Vector2, b: Vector2) -> float:
	return norm360(rad_to_deg(atan2(b.x - a.x, b.y - a.y)))


static func point_at(p: Vector2, brg: float, dist: float) -> Vector2:
	var r := deg_to_rad(brg)
	return p + Vector2(sin(r), cos(r)) * dist


static func mmss(sec: float) -> String:
	var s := maxi(0, int(floor(sec)))
	return "%02d:%02d" % [s / 60, s % 60]


static func target_pos(t: Dictionary) -> Vector2:
	return Vector2(float(t.get("x", 0.0)), float(t.get("y", 0.0)))


static func fix_pos(world: Dictionary, fix_name: String) -> Variant:
	for f: Dictionary in world.get("fixes", []):
		if String(f["name"]) == fix_name:
			return Vector2(float(f["x"]), float(f["y"]))
	return null


## MSA for a position (sector by bearing from the field), or -1.
static func msa_at(world: Dictionary, p: Vector2) -> int:
	var b := bearing_to(Vector2.ZERO, p)
	for s: Dictionary in world.get("msa", []):
		var a0 := float(s["from_deg"])
		var a1 := float(s["to_deg"])
		var inside := (b >= a0 and b < a1) if a0 <= a1 else (b >= a0 or b < a1)
		if inside:
			return int(s["alt_ft"])
	return -1


## Racetrack hold polyline: 1-minute legs at `speed_kt`, standard-rate turns.
static func hold_path(world: Dictionary, speed_kt: float = 210.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var hold: Dictionary = world.get("hold", {})
	if hold.is_empty():
		return pts
	var fix: Variant = fix_pos(world, String(hold["fix"]))
	if fix == null:
		return pts
	var f: Vector2 = fix
	var inb := float(hold["inbound_course_deg"])
	var r := speed_kt / (60.0 * PI)
	var leg := speed_kt / 60.0
	var side := 90.0 if String(hold["turn"]) == "R" else -90.0
	var dir := 1.0 if side > 0.0 else -1.0
	var start := point_at(f, inb + 180.0, leg)
	pts.append(start)
	pts.append(f)
	var c1 := point_at(f, inb + side, r)
	var a0 := norm360(inb - side)
	for i in range(1, 25):
		pts.append(point_at(c1, a0 + dir * 180.0 * i / 24.0, r))
	pts.append(point_at(start, inb + side, 2.0 * r))
	var c2 := point_at(start, inb + side, r)
	var b0 := norm360(inb + side)
	for i in range(1, 25):
		pts.append(point_at(c2, b0 + dir * 180.0 * i / 24.0, r))
	return pts


static func alert_tag(t: Dictionary) -> String:
	if bool(t.get("conflict", false)):
		return "CA"
	if bool(t.get("msaw", false)):
		return "LA"
	return ""


static func trend_arrow(vs_trend: int) -> String:
	if vs_trend > 0:
		return UP_ARROW
	if vs_trend < 0:
		return DOWN_ARROW
	return " "


static func alt_hundreds(alt: float) -> String:
	return "%03d" % maxi(0, int(round(alt / 100.0)))


## Data block lines below the alert line: callsign, "AAA↑ GG", [scratchpad].
static func block_lines(t: Dictionary, scratch: String) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(String(t.get("callsign", "")))
	var gs_tens := "%02d" % maxi(0, int(round(float(t.get("gs", 0.0)) / 10.0)))
	out.append("%s%s %s" % [alt_hundreds(float(t.get("alt", 0.0))), trend_arrow(int(t.get("vs_trend", 0))), gs_tens])
	var sp := scratch.strip_edges().to_upper().substr(0, 7)
	if sp != "":
		out.append(sp)
	return out


static func strip_alt_text(t: Dictionary) -> String:
	var vs := int(t.get("vs_trend", 0))
	var arrow := UP_ARROW if vs > 0 else (DOWN_ARROW if vs < 0 else "=")
	return "%d ft %s" % [int(round(float(t.get("alt", 0.0)))), arrow]


static func event_text(e: Dictionary) -> String:
	var cs := " and ".join(PackedStringArray(e.get("callsigns", [])))
	match String(e.get("kind", "")):
		"landed":
			return "%s landed runway 27" % cs
		"terrain":
			return "%s impacted terrain" % cs
		"collision":
			return "MID-AIR COLLISION: %s" % cs
		"fuel":
			return "%s ran out of fuel" % cs
		"runway":
			return "%s crashed on the runway" % cs
		"flying":
			return "%s still airborne" % cs
	return "%s %s" % [cs, String(e.get("kind", ""))]
