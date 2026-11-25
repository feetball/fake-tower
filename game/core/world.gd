class_name World
extends RefCounted
## The airport and airspace. Port of src/shared/world.ts — keep the numbers in
## sync. Fictional field, real-world procedure design: runway 27 with an ILS, a
## platform altitude, MSA sectors, terrain cylinders, a hold and a missed approach.
## Sim coordinates: x = nm east, y = nm north of the runway 27 threshold.

const NM_TO_M := 1852.0
const FT_TO_M := 0.3048
const FT_PER_NM := 6076.12

const GLIDE_DEG := 3.0
const FIELD_ELEV := 512.0
const TCH := 50.0
const PLATFORM := 3000.0

## Glideslope intercept distance from the threshold at the platform altitude, nm.
static func faf_dme() -> float:
	return (PLATFORM - FIELD_ELEV - TCH) / (tan(deg_to_rad(GLIDE_DEG)) * FT_PER_NM)

static var DATA: Dictionary = _build()

static func _build() -> Dictionary:
	var faf_x: float = round(faf_dme() * 10.0) / 10.0
	return {
		"icao": "KFTW",
		"name": "Fallow Ridge Regional",
		"field_elev_ft": FIELD_ELEV,
		"runway": {"name": "27", "heading_deg": 270.0, "length_nm": 1.4},
		"ils": {
			"course_deg": 270.0,
			"glide_deg": GLIDE_DEG,
			"tch_ft": TCH,
			"range_nm": 25.0,
			"platform_alt_ft": PLATFORM,
			"faf": {"name": "FALOW", "x": faf_x, "y": 0.0},
			"da_ft": FIELD_ELEV + 200.0,
		},
		"fixes": [
			{"name": "FALOW", "x": faf_x, "y": 0.0},
			{"name": "RIDGE", "x": 14.0, "y": 0.0},
			{"name": "NORBY", "x": 16.0, "y": 22.0},
			{"name": "SOLEY", "x": 14.0, "y": -24.0},
			{"name": "EASTO", "x": 30.0, "y": 2.0},
			{"name": "WHISK", "x": -20.0, "y": 18.0},
			{"name": "HOLDR", "x": 20.0, "y": 10.0},
		],
		"hold": {"fix": "HOLDR", "inbound_course_deg": 240.0, "turn": "R", "min_alt_ft": 6000.0},
		"missed_approach": "Climb straight ahead to 3000, then climbing right turn heading 060 to 6000 direct HOLDR and hold.",
		"terrain": [
			{"name": "Mt Carrow", "x": 9.0, "y": 9.0, "radius_nm": 3.5, "elev_ft": 4200.0},
			{"name": "Saddleback", "x": 3.0, "y": -11.0, "radius_nm": 3.0, "elev_ft": 3400.0},
			{"name": "West Ridge", "x": -14.0, "y": -3.0, "radius_nm": 4.5, "elev_ft": 4900.0},
			{"name": "Tower Hill", "x": 19.0, "y": -7.0, "radius_nm": 2.0, "elev_ft": 2300.0},
		],
		"msa": [
			{"from_deg": 0.0, "to_deg": 90.0, "alt_ft": 5200.0},
			{"from_deg": 90.0, "to_deg": 180.0, "alt_ft": 4400.0},
			{"from_deg": 180.0, "to_deg": 270.0, "alt_ft": 5900.0},
			{"from_deg": 270.0, "to_deg": 360.0, "alt_ft": 5900.0},
		],
		"transition_alt_ft": 6000.0,
		"scope_range_nm": 40.0,
		"separation": {"lateral_nm": 3.0, "vertical_ft": 1000.0},
	}

## Sim position (nm, nm, ft MSL) to Godot world space (metres, Y up, north = -Z).
static func to_3d(x_nm: float, y_nm: float, alt_ft: float) -> Vector3:
	return Vector3(x_nm * NM_TO_M, alt_ft * FT_TO_M, -y_nm * NM_TO_M)

## Heading in degrees true to a Godot Y rotation (0 = north = -Z).
static func heading_to_rot_y(hdg_deg: float) -> float:
	return -deg_to_rad(hdg_deg)
