class_name CockpitMaterials
extends RefCounted
## Shared PBR materials for the flight deck, built from the CC0 texture sets
## (painted metal, rubber trim, leather) with object-space triplanar mapping,
## so procedural meshes need no UV work. Falls back to flat colours when a set
## is missing. Cached: every part asks for materials by name.

const TEX_ROOT := "res://assets/textures/"

static var _cache: Dictionary = {}


static func get_mat(kind: String) -> Material:
	if not _cache.has(kind):
		_cache[kind] = _build(kind)
	return _cache[kind]


static func _build(kind: String) -> Material:
	match kind:
		"panel":
			# Airbus-ish blue-grey painted metal, satin.
			return _pbr("metal_plate_painted", Color(0.2, 0.225, 0.25), 2.5, 0.85, 0.35, 0.0)
		"panel_dark":
			return _pbr("metal_plate_painted", Color(0.085, 0.095, 0.105), 2.5, 0.9, 0.45, 0.0)
		"glareshield":
			return _pbr("leather_seat_02", Color(0.075, 0.075, 0.08), 6.0, 1.0, 0.75, 0.0)
		"trim":
			return _pbr("rubber_dark_trim", Color(0.32, 0.33, 0.34), 3.0, 1.0, 0.7, 0.0)
		"frame":
			# Window frames and lining: lighter grey padded/painted surfaces.
			return _pbr("metal_plate_painted", Color(0.3, 0.32, 0.34), 2.0, 0.9, 0.45, 0.0)
		"lining":
			return _pbr("leather_seat_brown", Color(0.24, 0.245, 0.25), 3.0, 1.0, 0.8, 0.0)
		"seat":
			return _pbr("leather_seat_brown", Color(0.22, 0.2, 0.19), 5.0, 1.0, 0.55, 0.0)
		"knob":
			return _flat(Color(0.025, 0.026, 0.028), 0.38, 0.0)
		"knob_metal":
			return _flat(Color(0.5, 0.5, 0.52), 0.3, 1.0)
		"bezel":
			return _flat(Color(0.03, 0.032, 0.035), 0.5, 0.0)
		"screw":
			return _flat(Color(0.32, 0.33, 0.35), 0.35, 0.9)
		"switch":
			return _flat(Color(0.55, 0.56, 0.58), 0.25, 1.0)
		"black":
			return _flat(Color(0.008, 0.008, 0.01), 0.6, 0.0)
		"lever_white":
			return _flat(Color(0.75, 0.74, 0.7), 0.35, 0.0)
		"window_lcd":
			var m := _flat(Color(0.01, 0.01, 0.012), 0.15, 0.0)
			m.emission_enabled = true
			m.emission = Color(0.03, 0.018, 0.005)
			return m
	push_warning("CockpitMaterials: unknown kind %s" % kind)
	return _flat(Color.MAGENTA, 0.5, 0.0)


static func _flat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


## Texture set tinted by `tint`, tiled every `tile_m`, object-space triplanar.
static func _pbr(set_name: String, tint: Color, tiles_per_m: float, rough_mul: float, rough_floor: float, metal: float) -> StandardMaterial3D:
	var base := TEX_ROOT + set_name + "/" + set_name
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = metal
	m.roughness = rough_mul
	if ResourceLoader.exists(base + "_albedo_2k.jpg"):
		m.albedo_texture = load(base + "_albedo_2k.jpg") as Texture2D
		# Most of the albedo's colour comes from the tint; keep only its variation.
		m.albedo_color = tint * 2.2
	else:
		m.roughness = rough_floor
	if ResourceLoader.exists(base + "_normal_gl_2k.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(base + "_normal_gl_2k.jpg") as Texture2D
		m.normal_scale = 0.5
	if ResourceLoader.exists(base + "_arm_2k.jpg"):
		var arm := load(base + "_arm_2k.jpg") as Texture2D
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.ao_light_affect = 0.4
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3(tiles_per_m, tiles_per_m, tiles_per_m)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
