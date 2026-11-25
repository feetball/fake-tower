extends RefCounted
## QNH and ATIS generation. Port of src/shared/sim/atis.ts (same RNG call order).

const SimRng := preload("res://core/sim/rng.gd")
const SimWorld := preload("res://core/sim/sim_world.gd")
const Geo := preload("res://core/sim/geo.gd")

const PHONETIC: Array[String] = [
	"ALFA", "BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT", "GOLF", "HOTEL", "INDIA", "JULIETT",
	"KILO", "LIMA", "MIKE", "NOVEMBER", "OSCAR", "PAPA", "QUEBEC", "ROMEO", "SIERRA", "TANGO",
	"UNIFORM", "VICTOR", "WHISKEY", "XRAY", "YANKEE", "ZULU",
]


## True QNH for a round: never within 4 hPa of standard, so a wrong setting is a real hazard.
static func random_qnh(rng: SimRng) -> int:
	while true:
		var q := rng.rand_int(996, 1030)
		if absi(q - 1013) >= 4:
			return q
	return 1013


## Fog over the field: CAT I conditions, light wind roughly down the runway.
## Returns the contract `atis` shape.
static func make_atis(w: SimWorld, qnh: int, rng: SimRng) -> Dictionary:
	var idx := rng.rand_int(0, 25)
	var letter := String.chr(65 + idx)
	var word := PHONETIC[idx]
	var wd := int(Geo.js_round((w.runway_heading + float(rng.rand_int(-40, 40))) / 10.0)) * 10
	var wind_dir := (wd + 360) % 360
	if wind_dir == 0:
		wind_dir = 360
	var wind_kt := rng.rand_int(3, 9)
	var visibility_m := rng.rand_int(6, 12) * 100
	var ceiling_ft := rng.rand_int(2, 4) * 100
	var temp := rng.rand_int(2, 9)
	var hh := rng.rand_int(0, 23)
	var mm := rng.rand_int(0, 5) * 10
	var time := "%02d%02d" % [hh, mm]
	var rwy := w.runway_name
	var text := " ".join(PackedStringArray([
		"%s INFORMATION %s, TIME %s ZULU." % [w.name.to_upper(), word, time],
		"EXPECT ILS APPROACH RUNWAY %s. RUNWAY IN USE %s." % [rwy, rwy],
		"WIND %03d DEGREES %d KNOTS." % [wind_dir, wind_kt],
		"VISIBILITY %d METRES, FOG. OVERCAST %d FEET." % [visibility_m, ceiling_ft],
		"TEMPERATURE %d, DEW POINT %d." % [temp, temp],
		"QNH %d." % qnh,
		"TRANSITION ALTITUDE %d." % w.transition_alt,
		"ACKNOWLEDGE RECEIPT OF INFORMATION %s AND ADVISE AIRCRAFT TYPE ON FIRST CONTACT." % word,
	]))
	return {
		"letter": letter,
		"runway": rwy,
		"qnh": qnh,
		"wind_dir": wind_dir,
		"wind_kt": wind_kt,
		"visibility_m": visibility_m,
		"ceiling_ft": ceiling_ft,
		"text": text,
	}
