class_name RunwayLights
extends Node3D
## Runway lighting in the runway frame (origin = threshold centre, landing
## direction −Z): white edge lights (amber over the last 2000 ft), green
## threshold bar with wing bars, red end bar, centreline lights with the
## standard red/white coding, touchdown zone barrettes and a 4-box PAPI on the
## left. A few OmniLights make the wet asphalt reflect.

const FT := 0.3048

@export var length_m := 1.4 * 1852.0
@export var width_m := 45.0
@export var intensity := 3.5
@export var extinction_per_m := 0.0025
@export var with_omni_lights := true

const WHITE := Color(1.0, 0.92, 0.78)
const AMBER := Color(1.0, 0.62, 0.18)
const GREEN := Color(0.2, 1.0, 0.45)
const RED := Color(1.0, 0.1, 0.05)
const TDZ := Color(1.0, 0.95, 0.86)


func _ready() -> void:
	build()


func build() -> void:
	for c in get_children():
		c.queue_free()
	var edges := _points("Edge", Vector3.ZERO, 1.0, 1.0)
	var inset := _points("Centreline", Vector3(0.0, 0.25, 1.0), 1.5, 0.15)
	var thr := _points("Threshold", Vector3(0.0, 0.1, 1.0), 2.0, 0.08)
	var papi := _points("PAPI", Vector3(0.0, 0.05, 1.0), 6.0, 0.0)
	var half := width_m * 0.5 + 1.5
	var amber_from := length_m - 2000.0 * FT
	var z := 0.0
	while z <= length_m:
		var col := AMBER if z >= amber_from else WHITE
		for side in [-1.0, 1.0]:
			edges.add_point(Vector3(side * half, 0.4, -z), col, intensity, 0.22)
		z += 200.0 * FT
	z = 0.0
	while z <= length_m - 7.5:
		var to_go := length_m - z
		var col := WHITE
		if to_go <= 1000.0 * FT:
			col = RED
		elif to_go <= 3000.0 * FT:
			col = RED if int(round(z / (50.0 * FT))) % 2 == 0 else WHITE
		inset.add_point(Vector3(0.6, 0.05, -z), col, intensity * 0.8, 0.18)
		z += 50.0 * FT
	z = 100.0 * FT
	while z <= 3000.0 * FT:
		for side in [-1.0, 1.0]:
			for k in 3:
				inset.add_point(Vector3(side * (11.0 + k * 1.5), 0.05, -z), TDZ, intensity * 0.7, 0.16)
		z += 100.0 * FT
	var x := -width_m * 0.5
	while x <= width_m * 0.5 + 0.01:
		thr.add_point(Vector3(x, 0.3, 1.0), GREEN, intensity * 1.2, 0.25)
		thr.add_point(Vector3(x, 0.3, -length_m - 1.0), RED, intensity, 0.25)
		x += 3.0
	for side in [-1.0, 1.0]:
		for k in 5:
			thr.add_point(Vector3(side * (width_m * 0.5 + 3.0 + k * 3.0), 0.4, 1.5), GREEN, intensity * 1.2, 0.25)
	# PAPI on glide path: the two units nearest the runway show red, the outer two white.
	for k in 4:
		papi.add_point(Vector3(-(width_m * 0.5 + 15.0 + k * 9.0), 0.8, -1000.0 * FT),
			RED if k < 2 else WHITE, intensity * 1.8, 0.4)
	for lp: LightPoints in [edges, inset, thr, papi]:
		lp.commit()
	if with_omni_lights:
		_omni(Vector3(0.0, 1.2, 1.5), GREEN, 1.4, 30.0)
		for zz in [120.0, 360.0, 600.0, 900.0]:
			for side in [-1.0, 1.0]:
				_omni(Vector3(side * half, 1.0, -zz), WHITE, 0.8, 26.0)


func _points(n: String, dir: Vector3, power: float, bmin: float) -> LightPoints:
	var lp := LightPoints.new()
	lp.name = n
	lp.beam_dir = dir
	lp.beam_power = power
	lp.beam_min = bmin
	lp.extinction_per_m = extinction_per_m
	lp.halo_size_m = 7.0
	add_child(lp)
	return lp


func _omni(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.light_volumetric_fog_energy = 2.0
	l.shadow_enabled = false
	add_child(l)
