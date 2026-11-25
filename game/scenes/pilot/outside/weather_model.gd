class_name PilotWeather
extends RefCounted
## Vertical extinction profile of the night: fog below the ceiling, a ramp into
## a thick stratus layer above it, thinner air above the tops. Everything the
## view fades (light points, depth fog, volumetric murk) is derived from here
## so they agree with each other and with the ATIS.

const FT := 0.3048
## Extinction in cloud (≈ 3 / 90 m visibility).
const CLOUD_SIGMA := 3.0 / 90.0
## Base of the layer is soft: density ramps up over this many feet.
const BASE_RAMP_FT := 180.0
const TOPS_AGL_FT := 7000.0
const ABOVE_SIGMA := 3.0 / 20000.0

var visibility_m := 900.0
var ceiling_ft := 300.0 ## above the field


func _init(vis_m: float = 900.0, ceil_ft: float = 300.0) -> void:
	visibility_m = maxf(vis_m, 100.0)
	ceiling_ft = maxf(ceil_ft, 50.0)


func fog_sigma() -> float:
	return 3.0 / visibility_m


## Extinction per metre at a height above the field (ft).
func sigma_at(h_ft: float) -> float:
	var f := fog_sigma()
	if h_ft <= ceiling_ft:
		return f
	if h_ft <= ceiling_ft + BASE_RAMP_FT:
		var k := (h_ft - ceiling_ft) / BASE_RAMP_FT
		return lerpf(f, CLOUD_SIGMA, k * k * (3.0 - 2.0 * k))
	if h_ft <= TOPS_AGL_FT:
		return CLOUD_SIGMA
	return ABOVE_SIGMA


## Mean extinction along a straight path between two heights (ft above field):
## the optical depth of a slant path of length L is L * mean_sigma(h1, h2).
func mean_sigma(h1: float, h2: float) -> float:
	var lo := minf(h1, h2)
	var hi := maxf(h1, h2)
	if hi - lo < 5.0:
		return sigma_at((lo + hi) * 0.5)
	var n := 24
	var acc := 0.0
	for i in n:
		acc += sigma_at(lerpf(lo, hi, (i + 0.5) / n))
	return acc / n


## 0 below the ceiling, 1 inside the cloud proper.
func cloudiness(h_ft: float) -> float:
	var f := fog_sigma()
	return clampf((sigma_at(h_ft) - f) / (CLOUD_SIGMA - f), 0.0, 1.0)
