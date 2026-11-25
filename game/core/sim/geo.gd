extends RefCounted
## Geometry and airspace lookups. Port of src/shared/sim/geo.ts.
## Coordinates: x = nm east, y = nm north of the runway 27 threshold.
## Headings/bearings are true degrees, 0 = north.

const SimWorld := preload("res://core/sim/sim_world.gd")

const FT_PER_NM := 6076.12
## Same expression as the TS `DEG` so trig results match bit for bit.
const DEG := PI / 180.0

const LOC_DEG_PER_DOT := 1.0
const GS_DEG_PER_DOT := 0.35
const FULL_SCALE := 2.5
## Inside this distance from the threshold the ±35° coverage cone is not applied.
const ILS_NEAR_NM := 0.5


## ILS needles. `valid` is false when there is no signal (both needles then read null).
class IlsDev:
	var valid := false
	var loc := 0.0 ## dots, positive = fly right
	var gs := 0.0 ## dots, positive = fly up


## JavaScript Math.round: halves round towards +infinity (GDScript round() goes away from zero).
static func js_round(v: float) -> float:
	return floor(v + 0.5)


static func norm360(deg: float) -> float:
	var d := fmod(deg, 360.0)
	return d + 360.0 if d < 0.0 else d


## Signed shortest angle from a to b, in (-180, 180].
static func angle_diff(a: float, b: float) -> float:
	var d := norm360(b - a)
	return d - 360.0 if d > 180.0 else d


static func clamp_f(v: float, lo: float, hi: float) -> float:
	return lo if v < lo else (hi if v > hi else v)


static func hypot(x: float, y: float) -> float:
	return sqrt(x * x + y * y)


static func dist(x1: float, y1: float, x2: float, y2: float) -> float:
	return hypot(x2 - x1, y2 - y1)


## True bearing from (x1,y1) to (x2,y2).
static func bearing(x1: float, y1: float, x2: float, y2: float) -> float:
	return norm360(atan2(x2 - x1, y2 - y1) / DEG)


## Unit displacement per nm along a heading (Vector2 is single precision, so two scalars).
static func heading_dx(hdg: float) -> float:
	return sin(hdg * DEG)


static func heading_dy(hdg: float) -> float:
	return cos(hdg * DEG)


## MSA for the sector containing the bearing FROM the station (threshold) to the point.
static func msa_at(w: SimWorld, x: float, y: float) -> float:
	var brg := bearing(0.0, 0.0, x, y)
	var best := -INF
	for i in w.msa_from.size():
		var lo := w.msa_from[i]
		var hi := w.msa_to[i]
		var inside := (brg >= lo and brg < hi) if lo <= hi else (brg >= lo or brg < hi)
		if inside:
			return w.msa_alt[i]
		best = maxf(best, w.msa_alt[i])
	return best


## Ground/obstacle elevation under a point: the highest obstacle top containing it, else field elevation.
static func terrain_elev_at(w: SimWorld, x: float, y: float) -> float:
	var elev := w.field_elev
	for i in w.terr_x.size():
		if w.terr_elev[i] > elev and dist(x, y, w.terr_x[i], w.terr_y[i]) < w.terr_r[i]:
			elev = w.terr_elev[i]
	return elev


## Highest obstacle top containing the point, or -INF (ignores the field elevation).
static func obstacle_elev_at(w: SimWorld, x: float, y: float) -> float:
	var elev := -INF
	for i in w.terr_x.size():
		if dist(x, y, w.terr_x[i], w.terr_y[i]) < w.terr_r[i] and w.terr_elev[i] > elev:
			elev = w.terr_elev[i]
	return elev


## Glidepath altitude ft MSL at distance d nm from the threshold.
static func glidepath_alt(w: SimWorld, d_nm: float) -> float:
	return w.field_elev + w.tch + d_nm * FT_PER_NM * tan(w.glide_deg * DEG)


## ILS needles for an aircraft at (x, y, alt). Antennas are modelled at the threshold.
static func ils_deviation(w: SimWorld, x: float, y: float, alt: float) -> IlsDev:
	var out := IlsDev.new()
	var d := hypot(x, y)
	var back_course := norm360(w.course_deg + 180.0)
	var off := angle_diff(back_course, bearing(0.0, 0.0, x, y))
	# Close in, only "behind the threshold" loses the signal (see geo.ts for why).
	if d > w.range_nm or d < 1e-6 or absf(off) > 90.0:
		return out
	if absf(off) > 35.0 and d > ILS_NEAR_NM:
		return out
	out.valid = true
	out.loc = clamp_f(off / LOC_DEG_PER_DOT, -FULL_SCALE, FULL_SCALE)
	var angle := atan2(alt - w.field_elev - w.tch, d * FT_PER_NM) / DEG
	out.gs = clamp_f((w.glide_deg - angle) / GS_DEG_PER_DOT, -FULL_SCALE, FULL_SCALE)
	return out
