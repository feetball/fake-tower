extends RefCounted
## Visual attitude for the 3D view: bank from the turn rate, pitch from the
## flight path angle plus an angle-of-attack term. Not part of the TS sim and
## never feeds back into the flight model.

const BANK_MAX_DEG := 25.0
const ROLL_RATE_DEG_S := 5.0
const PITCH_RATE_DEG_S := 3.0
const NOSE_LOWER_RATE_DEG_S := 2.0
const G_MPS2 := 9.80665
const KT_TO_MPS := 0.514444
const KT_TO_FTPS := 1.68781
## AoA model: AOA_REF at 250 kt clean, growing with 1/V² (constant lift), less with flaps.
const AOA_REF_DEG := 3.0
const AOA_REF_KT := 250.0
const FLAP_AOA_RELIEF: Array[float] = [0.0, 1.5, 2.5, 4.0]

var pitch_deg := 0.0 ## positive = nose up
var bank_deg := 0.0 ## positive = right wing down (turning right)
var on_ground := false
var stopped := false


func reset(tas_kt: float, vs_fpm: float, ias_kt: float, flaps: int) -> void:
	bank_deg = 0.0
	pitch_deg = target_pitch(tas_kt, vs_fpm, ias_kt, flaps)


## Bank for a coordinated turn at this rate and true airspeed, capped.
static func target_bank(turn_rate_deg_s: float, tas_kt: float) -> float:
	var omega := deg_to_rad(turn_rate_deg_s)
	var b := rad_to_deg(atan(omega * tas_kt * KT_TO_MPS / G_MPS2))
	return clampf(b, -BANK_MAX_DEG, BANK_MAX_DEG)


static func flight_path_deg(vs_fpm: float, tas_kt: float) -> float:
	if tas_kt < 1.0:
		return 0.0
	return rad_to_deg(atan2(vs_fpm / 60.0, tas_kt * KT_TO_FTPS))


static func aoa_deg(ias_kt: float, flaps: int) -> float:
	var v := maxf(ias_kt, 60.0)
	var ratio := AOA_REF_KT / v
	return clampf(AOA_REF_DEG * ratio * ratio - FLAP_AOA_RELIEF[clampi(flaps, 0, 3)], 0.0, 12.0)


static func target_pitch(tas_kt: float, vs_fpm: float, ias_kt: float, flaps: int) -> float:
	return flight_path_deg(vs_fpm, tas_kt) + aoa_deg(ias_kt, flaps)


func update_airborne(dt: float, turn_rate_deg_s: float, tas_kt: float, vs_fpm: float, ias_kt: float, flaps: int) -> void:
	bank_deg = move_toward(bank_deg, target_bank(turn_rate_deg_s, tas_kt), ROLL_RATE_DEG_S * dt)
	pitch_deg = move_toward(pitch_deg, target_pitch(tas_kt, vs_fpm, ias_kt, flaps), PITCH_RATE_DEG_S * dt)


func update_ground(dt: float) -> void:
	bank_deg = move_toward(bank_deg, 0.0, ROLL_RATE_DEG_S * dt)
	pitch_deg = move_toward(pitch_deg, 0.0, NOSE_LOWER_RATE_DEG_S * dt)
