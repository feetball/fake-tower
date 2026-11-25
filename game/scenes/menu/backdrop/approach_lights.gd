class_name ApproachLights
extends Node3D
## ALSF-II approach lighting system, built procedurally.
## Runway frame: origin = runway threshold centre at surface level, landing
## direction = local −Z, so the system extends along local +Z (towards the
## approaching aircraft). Ground is assumed flat at y = 0.
## Contents: white centreline barrettes every 100 ft, 500 ft and 1000 ft
## crossbars, red side-row barrettes over the inner 1000 ft, sequenced flashers
## ("the rabbit", outer → inner, twice a second), steel stands, and a sparse set
## of OmniLights so the system lights the fog and the wet ground.

const FT := 0.3048

@export var length_m := 2400.0 * FT
@export var station_spacing_m := 100.0 * FT
@export var lamp_height_m := 0.9
@export var flasher_period_s := 0.5
@export var intensity := 5.0
@export var extinction_per_m := 0.0025
## One fog-lighting OmniLight every n centreline stations (0 = none).
@export var omni_every := 2
@export var omni_energy := 1.6

const WHITE := Color(1.0, 0.93, 0.82)
const RED := Color(1.0, 0.12, 0.06)
const STROBE := Color(0.85, 0.9, 1.0)

var whites: LightPoints
var reds: LightPoints
var flashers: LightPoints


func _ready() -> void:
	build()


func build() -> void:
	for c in get_children():
		c.queue_free()
	whites = _make_points("White", 2.0, 0.04)
	reds = _make_points("Red", 2.0, 0.04)
	flashers = _make_points("Flashers", 3.0, 0.02)
	var stands := PackedVector3Array()
	var n_stations := int(round(length_m / station_spacing_m))
	var n_flash := 0
	for i in range(1, n_stations + 1):
		if i * 100 >= 1100:
			n_flash += 1
	var flash_order := 0
	for i in range(n_stations, 0, -1):
		var z := i * station_spacing_m
		var ft := i * 100
		_barrette(whites, 0.0, z, 5, 1.0, WHITE)
		stands.append(Vector3(0.0, 0.0, z))
		if ft == 500:
			for side in [-1.0, 1.0]:
				_barrette(whites, side * 4.0, z, 4, 1.0, WHITE)
		if ft == 1000:
			for side in [-1.0, 1.0]:
				_barrette(whites, side * 9.0, z, 7, 1.0, WHITE)
				stands.append(Vector3(side * 9.0, 0.0, z))
		if ft < 1000:
			for side in [-1.0, 1.0]:
				_barrette(reds, side * 11.6, z, 3, 1.5, RED)
				stands.append(Vector3(side * 11.6, 0.0, z))
		if ft >= 1100:
			# Sequenced flasher: outermost fires first, each next one a bit later.
			var phase := -float(flash_order) / float(n_flash) * 0.62
			flashers.add_point(Vector3(0.0, lamp_height_m + 0.5, z), STROBE, intensity * 1.6, 0.45,
				flasher_period_s, phase)
			flash_order += 1
		if omni_every > 0 and i % omni_every == 0:
			_omni(Vector3(0.0, lamp_height_m + 1.2, z), WHITE, omni_energy, 26.0)
		if ft < 1000 and omni_every > 0 and i % (omni_every * 2) == 1:
			for side in [-1.0, 1.0]:
				_omni(Vector3(side * 11.6, lamp_height_m + 1.0, z), RED, omni_energy * 0.9, 16.0)
	whites.commit()
	reds.commit()
	flashers.commit()
	_build_stands(stands)


func _make_points(n: String, power: float, bmin: float) -> LightPoints:
	var lp := LightPoints.new()
	lp.name = n
	lp.beam_dir = Vector3(0.0, 0.08, 1.0)
	lp.beam_power = power
	lp.beam_min = bmin
	lp.extinction_per_m = extinction_per_m
	add_child(lp)
	return lp


func _barrette(lp: LightPoints, cx: float, z: float, count: int, spacing: float, col: Color) -> void:
	var half := (count - 1) * spacing * 0.5
	for k in count:
		lp.add_point(Vector3(cx - half + k * spacing, lamp_height_m, z), col, intensity, 0.28)


func _omni(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.light_volumetric_fog_energy = 40.0
	l.shadow_enabled = false
	add_child(l)


func _build_stands(bases: PackedVector3Array) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.09, 0.085)
	mat.metallic = 0.6
	mat.roughness = 0.45
	var pole := BoxMesh.new()
	pole.size = Vector3(0.1, lamp_height_m, 0.1)
	pole.material = mat
	var beam := BoxMesh.new()
	beam.size = Vector3(4.6, 0.08, 0.12)
	beam.material = mat
	for spec in [[pole, Vector3(0.0, lamp_height_m * 0.5, 0.0)], [beam, Vector3(0.0, lamp_height_m - 0.1, 0.0)]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = spec[0]
		mm.instance_count = bases.size()
		for i in bases.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, bases[i] + (spec[1] as Vector3)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
