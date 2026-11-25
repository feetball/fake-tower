class_name CockpitLayout
extends RefCounted
## Flight-deck geometry shared by every cockpit part. Aircraft frame: origin =
## captain's design eye point, −Z forward, +X right, +Y up, metres. The
## aircraft centreline is CENTRE_X to the right of the eye.

const CENTRE_X := 0.53
const EYE_HEIGHT_ABOVE_WHEELS_M := 3.9 ## eye above the runway when on the ground

## Main instrument panel plane: origin, tilt (top leans away from the pilot).
const PANEL_ORIGIN := Vector3(CENTRE_X, -0.55, -0.79)
const PANEL_TILT_DEG := 12.0
const PANEL_TOP_V := 0.15
const PANEL_BOTTOM_V := -0.33
const PANEL_HALF_W := 1.0

## Display units on the panel: centre (u, v) in panel coordinates.
const DU_SIZE := 0.23 ## active screen, square (about 9 in)
const PFD_UV := Vector2(-0.6, 0.0)
const ND_UV := Vector2(-0.345, 0.0)
const EICAS_UV := Vector2(0.0, 0.0)
const FO_ND_UV := Vector2(0.345, 0.0)
const FO_PFD_UV := Vector2(0.6, 0.0)
const ISIS_UV := Vector2(-0.174, 0.045)
const ISIS_SIZE := 0.072
const GEAR_UV := Vector2(-0.31, -0.215)
const ANNUN_UV := Vector2(-0.805, 0.07)

## Glareshield front face, where the autopilot panel (MCP) sits.
const MCP_CENTRE := Vector3(CENTRE_X, -0.298, -0.662)
const MCP_TILT_DEG := 20.0
const MCP_SIZE := Vector2(0.64, 0.1)
const EFIS_CENTRE := Vector3(0.085, -0.298, -0.662)
const EFIS_SIZE := Vector2(0.24, 0.1)
const MASTER_CENTRE := Vector3(-0.1, -0.298, -0.662)

## Centre pedestal.
const PEDESTAL_FRONT_Z := -0.72
const PEDESTAL_BACK_Z := 0.32
const PEDESTAL_HALF_W := 0.2
const PEDESTAL_TOP_FRONT_Y := -0.74
const PEDESTAL_TOP_BACK_Y := -0.72


static func panel_basis() -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(-PANEL_TILT_DEG))


## Transform on the instrument panel: (u right, v up) from the panel origin,
## d towards the pilot along the panel normal.
static func panel_xf(u: float, v: float, d: float = 0.0) -> Transform3D:
	var b := panel_basis()
	return Transform3D(b, PANEL_ORIGIN + b * Vector3(u, v, d))


static func mcp_basis() -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(-MCP_TILT_DEG))


## Transform on the glareshield control strip (MCP plane), u right/v up from `centre`.
static func mcp_xf(centre: Vector3, u: float, v: float, d: float = 0.0) -> Transform3D:
	var b := mcp_basis()
	return Transform3D(b, centre + b * Vector3(u, v, d))


## Pedestal top surface transform at (x offset from centreline, z), facing up.
static func pedestal_top_xf(dx: float, z: float, d: float = 0.0) -> Transform3D:
	var t := inverse_lerp(PEDESTAL_FRONT_Z, PEDESTAL_BACK_Z, z)
	var y := lerpf(PEDESTAL_TOP_FRONT_Y, PEDESTAL_TOP_BACK_Y, t)
	var slope := atan2(PEDESTAL_TOP_FRONT_Y - PEDESTAL_TOP_BACK_Y, PEDESTAL_BACK_Z - PEDESTAL_FRONT_Z)
	# Local -Z = forward along the top, +Y = surface normal.
	var b := Basis(Vector3.RIGHT, slope)
	return Transform3D(b, Vector3(CENTRE_X + dx, y, z) + b * Vector3(0.0, d, 0.0))
