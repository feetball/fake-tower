class_name CockpitShell
extends Node3D
## The flight-deck structure around the instruments: main instrument panel in
## three sections with panel breaks and screws, glareshield, windshield posts
## and header, side wall and window sill, roof lining, overhead panel with
## switch rows, side console with sidestick, knee panel and floor.
## Window glass is added by Windshield; instruments by their own builders.

const L := CockpitLayout
const K := PilotMeshKit
const M := CockpitMaterials

## Window openings (aircraft frame). Each = [bottom-outer, bottom-inner, top-inner, top-outer].
const C := CockpitLayout.CENTRE_X
static var FRONT_LEFT: Array[Vector3] = [
	Vector3(-0.43, -0.175, -0.96), Vector3(C - 0.035, -0.175, -1.17),
	Vector3(C - 0.035, 0.235, -0.83), Vector3(-0.43, 0.22, -0.67)]
static var SIDE_LEFT: Array[Vector3] = [
	Vector3(-0.475, -0.2, -0.88), Vector3(-0.575, -0.27, -0.36),
	Vector3(-0.575, 0.19, -0.36), Vector3(-0.49, 0.205, -0.62)]


static func mirror(pts: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in pts:
		out.append(Vector3(2.0 * C - p.x, p.y, p.z))
	return out


func _ready() -> void:
	_build_panel()
	_build_glareshield()
	_build_frames()
	_build_roof()
	_build_overhead()
	_build_side(1.0)
	_build_side(-1.0)
	_build_floor()


func _build_panel() -> void:
	var sections := [[-1.0, -0.2], [-0.19, 0.19], [0.2, 1.0]]
	var screws: Array[Transform3D] = []
	var h := L.PANEL_TOP_V - L.PANEL_BOTTOM_V
	var vc := (L.PANEL_TOP_V + L.PANEL_BOTTOM_V) * 0.5
	for s: Array in sections:
		var u0: float = s[0]
		var u1: float = s[1]
		var w := u1 - u0
		var xf := L.panel_xf((u0 + u1) * 0.5, vc, -0.03)
		K.add(self, K.rounded_box(Vector3(w, h, 0.06), 0.008), M.get_mat("panel"), xf, "PanelSection")
		for cu: float in [u0 + 0.012, u1 - 0.012]:
			for cv: float in [L.PANEL_BOTTOM_V + 0.012, L.PANEL_TOP_V - 0.012]:
				screws.append(L.panel_xf(cu, cv, 0.0) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	# Dark backing so the panel breaks read as gaps rather than see-through slits.
	K.add(self, K.rounded_box(Vector3(2.04, h + 0.02, 0.02), 0.004), M.get_mat("black"),
		L.panel_xf(0.0, vc, -0.065), "PanelBacking")
	# Knee panel: continues below, tilted further back towards the pilot.
	var knee_top := L.panel_xf(0.0, L.PANEL_BOTTOM_V, -0.03).origin
	var kb := Basis(Vector3.RIGHT, deg_to_rad(-48.0))
	var knee_xf := Transform3D(kb, knee_top + kb * Vector3(0.0, -0.13, 0.0))
	K.add(self, K.rounded_box(Vector3(2.0, 0.26, 0.05), 0.01), M.get_mat("panel_dark"), knee_xf, "KneePanel")
	K.multi(self, _screw_mesh(), M.get_mat("screw"), screws, "PanelScrews")
	# Small round knobs along the lower captain panel (lighting, chrono, loudspeaker).
	var knobs: Array[Transform3D] = []
	for u: float in [-0.9, -0.84, -0.45, -0.39, -0.33, 0.33, 0.39, 0.84, 0.9]:
		knobs.append(L.panel_xf(u, -0.29, 0.012) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	K.multi(self, K.cylinder(0.011, 0.024, 20, 0.0095), M.get_mat("knob"), knobs, "LowerKnobs")


func _screw_mesh() -> Mesh:
	var c := K.cylinder(0.0032, 0.003, 10, 0.0028)
	return c


func _build_glareshield() -> void:
	var p := PackedVector2Array()
	p.append(Vector2(-0.835, -0.365))
	p.append_array(K.bezier(Vector2(-0.72, -0.315), Vector2(-0.668, -0.3), Vector2(-0.67, -0.27), 5))
	p.append_array(K.bezier(Vector2(-0.668, -0.205), Vector2(-0.664, -0.172), Vector2(-0.7, -0.168), 5))
	p.append(Vector2(-1.0, -0.158))
	p.append(Vector2(-1.2, -0.16))
	p.append(Vector2(-1.2, -0.42))
	p.append(Vector2(-0.86, -0.42))
	var mesh := K.extrude_x(p, -0.5, 2.0 * C + 0.5, 30.0)
	K.add(self, mesh, M.get_mat("glareshield"), Transform3D.IDENTITY, "Glareshield")
	# Under-lip light strip housing (the flood lights sit behind it).
	K.add(self, K.rounded_box(Vector3(1.9, 0.012, 0.03), 0.004), M.get_mat("trim"),
		Transform3D(Basis.IDENTITY, Vector3(C, -0.318, -0.71)), "LipStrip")


func _build_frames() -> void:
	var frame := M.get_mat("frame")
	for side in 2:
		var fl := FRONT_LEFT if side == 0 else mirror(FRONT_LEFT)
		var sl := SIDE_LEFT if side == 0 else mirror(SIDE_LEFT)
		# Header over the front pane and the sill under it.
		_bar(fl[3], fl[2], 0.075, 0.09, frame)
		_bar(fl[0], fl[1], 0.04, 0.05, frame)
		# Side post between the front and side windows: the thick one.
		_bar(fl[0].lerp(sl[0], 0.5) + Vector3(0, -0.02, 0), fl[3].lerp(sl[3], 0.5) + Vector3(0, 0.02, 0), 0.095, 0.12, frame)
		# Side window frame.
		_bar(sl[3], sl[2], 0.06, 0.07, frame)
		_bar(sl[2], sl[1], 0.07, 0.08, frame)
		_bar(sl[0], sl[1], 0.06, 0.08, frame)
	# Centre post.
	_bar(Vector3(C, -0.2, -1.19), Vector3(C, 0.25, -0.82), 0.075, 0.1, frame)


## A rounded bar from a to b with cross-section w x d, depth axis roughly outward.
func _bar(a: Vector3, b: Vector3, w: float, d: float, mat: Material) -> void:
	var xf := K.between(a, b, (a + b) * 0.5 - Vector3(C, 0.0, -0.4))
	var len := a.distance_to(b) + w * 0.6
	K.add(self, K.rounded_box(Vector3(w, d, len), minf(w, d) * 0.3), mat, xf, "Frame")


func _build_roof() -> void:
	var lining := M.get_mat("lining")
	# Roof: from the windshield header back over the pilots' heads.
	var a := Vector3(-0.55, 0.26, -0.72)
	var b := Vector3(2.0 * C + 0.55, 0.26, -0.72)
	var c := Vector3(2.0 * C + 0.6, 0.48, 0.5)
	var d := Vector3(-0.6, 0.48, 0.5)
	K.add(self, K.slab(a, b, c, d, 0.04, Vector3.DOWN), lining, Transform3D.IDENTITY, "Roof")
	# Header lining above the front panes.
	var fl := FRONT_LEFT
	var fr := mirror(FRONT_LEFT)
	K.add(self, K.slab(fl[3] + Vector3(-0.05, 0.0, 0.0), fr[3] + Vector3(0.05, 0.0, 0.0),
		Vector3(fr[3].x + 0.1, 0.27, -0.6), Vector3(fl[3].x - 0.1, 0.27, -0.6), 0.03, Vector3.BACK + Vector3.DOWN),
		lining, Transform3D.IDENTITY, "HeaderLining")


func _build_overhead() -> void:
	# The overhead panel hangs below the roof between the pilots, sloping back.
	var front := Vector3(C, 0.3, -0.6)
	var back := Vector3(C, 0.43, 0.25)
	var xf := K.between(front, back, Vector3.DOWN)
	var length := front.distance_to(back)
	var ob := Node3D.new()
	ob.name = "Overhead"
	ob.transform = xf
	add_child(ob)
	# In ob space: local Z runs front→back, local -Y faces down to the pilots.
	K.add(ob, K.rounded_box(Vector3(0.78, 0.05, length), 0.012), M.get_mat("panel"), Transform3D.IDENTITY, "OverheadBody")
	var switches: Array[Transform3D] = []
	var guards: Array[Transform3D] = []
	var lights: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 2701
	var rows := 9
	for r in rows:
		var z := -length * 0.5 + 0.06 + r * (length - 0.1) / rows
		# Panel breaks between rows of sub-panels.
		K.add(ob, K.rounded_box(Vector3(0.74, 0.004, 0.003), 0.001), M.get_mat("black"),
			Transform3D(Basis.IDENTITY, Vector3(0.0, -0.026, z - 0.035)))
		for k in 12:
			var x := -0.33 + k * 0.06
			var roll := rng.randf()
			if roll < 0.45:
				switches.append(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(-25.0, 25.0))), Vector3(x, -0.035, z)))
			elif roll < 0.8:
				lights.append(Transform3D(Basis.IDENTITY, Vector3(x, -0.027, z)))
			elif roll < 0.88:
				guards.append(Transform3D(Basis.IDENTITY, Vector3(x, -0.03, z)))
	K.multi(ob, K.cylinder(0.0028, 0.022, 8), M.get_mat("switch"), switches, "Toggles")
	K.multi(ob, K.rounded_box(Vector3(0.026, 0.006, 0.02), 0.002), M.get_mat("bezel"), lights, "PushButtons")
	K.multi(ob, K.rounded_box(Vector3(0.03, 0.012, 0.03), 0.003), M.get_mat("knob"), guards, "Knobs")


func _build_side(side: float) -> void:
	var sx := -0.6 if side > 0.0 else 2.0 * C + 0.6
	var inward := 1.0 if side > 0.0 else -1.0
	var lining := M.get_mat("lining")
	var sl := SIDE_LEFT if side > 0.0 else mirror(SIDE_LEFT)
	# Wall below the side window down to the floor, and behind it.
	var w0 := Vector3(sl[0].x - inward * 0.02, sl[0].y - 0.02, sl[0].z - 0.05)
	var w1 := Vector3(sl[1].x - inward * 0.02, sl[1].y - 0.02, sl[1].z + 0.6)
	K.add(self, K.slab(w0, w1, Vector3(w1.x, -1.2, w1.z), Vector3(w0.x, -1.2, w0.z), 0.04, Vector3(inward, 0, 0)),
		lining, Transform3D.IDENTITY, "SideWall")
	# Rear wall section behind the side window.
	K.add(self, K.slab(Vector3(sx + inward * 0.02, 0.48, -0.36), Vector3(sx + inward * 0.02, 0.48, 0.6),
		Vector3(sx + inward * 0.02, -0.3, 0.6), Vector3(sx + inward * 0.02, -0.3, -0.36), 0.04, Vector3(inward, 0, 0)),
		lining, Transform3D.IDENTITY, "RearWall")
	# Window sill / armrest ledge.
	K.add(self, K.rounded_box(Vector3(0.1, 0.035, 0.6), 0.012), M.get_mat("trim"),
		Transform3D(Basis(Vector3.UP, deg_to_rad(-11.0 * inward)), Vector3(sl[0].x + inward * 0.03, -0.29, -0.6)), "Sill")
	# Side console with the sidestick (captain) / tiller.
	var cx := -0.47 if side > 0.0 else 2.0 * C + 0.47
	var console := Node3D.new()
	console.name = "SideConsole"
	console.position = Vector3(cx, -0.6, -0.15)
	add_child(console)
	K.add(console, K.rounded_box(Vector3(0.2, 0.36, 0.8), 0.02), M.get_mat("panel_dark"),
		Transform3D(Basis.IDENTITY, Vector3(0.0, -0.18, 0.0)))
	K.add(console, K.rounded_box(Vector3(0.19, 0.01, 0.78), 0.004), M.get_mat("panel"),
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.003, 0.0)))
	_sidestick(console, Vector3(0.0, 0.0, -0.12))
	# Tiller wheel further forward.
	var tiller := Node3D.new()
	tiller.position = Vector3(0.0, 0.02, -0.33)
	console.add_child(tiller)
	K.add(tiller, K.cylinder(0.035, 0.018, 24), M.get_mat("knob"), Transform3D.IDENTITY)
	K.add(tiller, K.cylinder(0.008, 0.03, 10), M.get_mat("knob"), Transform3D(Basis.IDENTITY, Vector3(0.022, 0.02, 0.0)))


func _sidestick(parent: Node3D, at: Vector3) -> void:
	var s := Node3D.new()
	s.name = "Sidestick"
	s.position = at
	parent.add_child(s)
	# Rubber boot, shaft and an ergonomic grip leaning forward/outboard.
	K.add(s, K.cylinder(0.038, 0.03, 20, 0.022), M.get_mat("trim"), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.015, 0.0)))
	var grip := Node3D.new()
	grip.position = Vector3(0.0, 0.03, 0.0)
	grip.rotation = Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(6.0))
	s.add_child(grip)
	K.add(grip, K.cylinder(0.012, 0.05, 12), M.get_mat("knob"), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.025, 0.0)))
	K.add(grip, K.rounded_box(Vector3(0.042, 0.13, 0.05), 0.018), M.get_mat("knob"),
		Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(0.0, 0.11, -0.005)))
	K.add(grip, K.rounded_box(Vector3(0.016, 0.012, 0.016), 0.005), M.get_mat("switch"),
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.178, -0.01)))


func _build_floor() -> void:
	K.add(self, K.rounded_box(Vector3(2.4, 0.05, 2.2), 0.01), M.get_mat("trim"),
		Transform3D(Basis.IDENTITY, Vector3(C, -1.22, -0.2)), "Floor")
