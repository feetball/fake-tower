extends RefCounted
## Hand-made radar picture for screenshots (user arg --ctrl-debug-targets):
## a conflict pair, an MSAW target, one on final, one crashed, one landed and
## an outer arrival. sweeps() returns eleven consecutive 2 s sweeps so the
## history trails are populated.

const Fmt := preload("res://scenes/controller/scope/scope_format.gd")

const SWEEP_SEC := 2.0

## callsign, x, y, alt, gs, track, vs_trend, status, conflict, msaw
const TARGETS: Array[Array] = [
	["SKW412", 6.8, 0.15, 2600.0, 150.0, 270.0, -1, "flying", false, false],
	["ASA277", 24.5, 8.2, 3000.0, 240.0, 236.0, -1, "flying", false, true],
	["DAL1873", 20.6, -10.4, 4600.0, 250.0, 305.0, 0, "flying", true, false],
	["UAL905", 19.2, -8.2, 5100.0, 240.0, 205.0, -1, "flying", true, false],
	["JBU88", 31.5, 21.0, 9000.0, 250.0, 228.0, 0, "flying", false, false],
	["N12FT", 9.6, 8.1, 3900.0, 0.0, 0.0, 0, "crashed", false, false],
	["FFT61", -0.9, 0.0, 500.0, 0.0, 270.0, 0, "landed", false, false],
]

const EVENTS: Array[Dictionary] = [
	{"time": 192.0, "kind": "landed", "callsigns": ["FFT61"]},
	{"time": 281.0, "kind": "terrain", "callsigns": ["N12FT"]},
]


static func sweeps() -> Array[Array]:
	var out: Array[Array] = []
	for back in range(10, -1, -1):
		var sweep: Array = []
		for row in TARGETS:
			var t := _target(row)
			if String(t["status"]) == "flying" and back > 0:
				var p := Fmt.point_at(Vector2(t["x"], t["y"]), float(t["track"]) + 180.0,
					float(t["gs"]) * SWEEP_SEC * back / 3600.0)
				t["x"] = p.x
				t["y"] = p.y
				t["alt"] = float(t["alt"]) - int(t["vs_trend"]) * 60.0 * back
			sweep.append(t)
		out.append(sweep)
	return out


static func _target(row: Array) -> Dictionary:
	return {
		"callsign": row[0], "x": row[1], "y": row[2], "alt": row[3], "gs": row[4], "track": row[5],
		"vs_trend": row[6], "status": row[7], "conflict": row[8], "msaw": row[9],
	}
