class_name FogGlow
extends LightPoints
## Stand-in for the glow lights make in volumetric fog, for renderers without it
## (Mobile, Compatibility; see RenderCaps): one large, faint, soft additive sprite
## per fog-lighting lamp (the LightPoints "core" at glow size, no halo). On Forward+
## `create()` returns null and the real volumetric fog does the job.
## Usage: glow = FogGlow.create(parent); glow.add_light(...) per lamp; glow.commit().

## Glow brightness per unit of light energy × volumetric fog energy.
const GAIN := 0.0045
## Glow radius as a fraction of the light's range.
const RADIUS := 0.55


## A FogGlow added under `parent`, or null where volumetric fog exists.
static func create(parent: Node, glow_name: String = "FogGlow") -> FogGlow:
	if RenderCaps.has_volumetric_fog():
		return null
	var g := FogGlow.new()
	g.name = glow_name
	g.halo_gain = 0.0
	g.min_halo_angle = 0.0
	g.min_core_angle = 0.0
	parent.add_child(g)
	return g


## The glow of a light at `pos` (this node's space) with the given colour, energy,
## range (m) and light_volumetric_fog_energy.
func add_light(pos: Vector3, color: Color, energy: float, light_range: float, fog_energy: float) -> void:
	if energy * fog_energy <= 0.0:
		return
	add_point(pos, color, energy * fog_energy * GAIN * RenderCaps.glow_gain(), light_range * RADIUS)
