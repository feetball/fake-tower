class_name FogBanks
extends FogVolume
## Patchy ground fog: a large, shallow FogVolume with 3D noise density that
## drifts slowly with the wind, so the volumetric fog has visible structure
## (needs Environment.volumetric_fog_enabled). Origin = centre of the layer.

@export var extent := Vector3(4000.0, 70.0, 4000.0)
@export var density := 0.028
## Drift speed in metres per second (world space). The drift slowly swings
## back and forth instead of wrapping, so the banks never jump.
@export var wind := Vector3(1.6, 0.0, 0.6)
@export var swing_period_s := 1200.0

var _origin := Vector3.ZERO
var _t := 0.0


func _ready() -> void:
	size = extent
	shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.22
	noise.fractal_octaves = 3
	var tex := NoiseTexture3D.new()
	tex.width = 48
	tex.height = 16
	tex.depth = 48
	tex.seamless = true
	tex.noise = noise
	var mat := FogMaterial.new()
	mat.density = density
	mat.albedo = Color(0.85, 0.87, 0.9)
	mat.height_falloff = 0.04
	mat.edge_fade = 0.2
	mat.density_texture = tex
	material = mat
	_origin = position


func _process(delta: float) -> void:
	# The texture is stretched over the box, so moving the box moves the banks.
	_t += delta
	var w := TAU / swing_period_s
	position = _origin + wind * sin(_t * w) / w
