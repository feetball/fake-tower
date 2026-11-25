extends Node3D
## The dark approach-control room around our position: carpet, acoustic wall
## panels, a dark ceiling with unlit fixtures, a row of other positions with
## live-looking scopes, equipment shelves, an exit sign and a UTC wall clock.
## Light comes almost entirely from displays; the environment adds subtle
## volumetric haze, bloom on emissive surfaces and filmic tonemapping.

const Kit := preload("res://scenes/controller/room/mesh_kit.gd")
const Console := preload("res://scenes/controller/room/console.gd")
const Look := preload("res://scenes/controller/scope/scope_theme.gd")
const IDLE_SHADER: Shader = preload("res://shaders/controller_idle_scope.gdshader")

const ROOM_MIN := Vector3(-8.0, 0.0, -1.55)
const ROOM_MAX := Vector3(8.0, 3.0, 4.6)
const NEIGHBOURS: Array[float] = [-4.7, -2.35, 2.55, 4.9]

var console: Console
var environment: Environment

var _clock: Label3D
var _clock_sec := -1


func _ready() -> void:
	_environment()
	_shell()
	console = Console.new()
	console.name = "Console"
	add_child(console)
	for i in NEIGHBOURS.size():
		_neighbour(NEIGHBOURS[i], i)
	_back_of_room()
	_wall_clock(Vector3(-1.3, 2.05, ROOM_MIN.z + 0.06))
	# A dimmed downlight at the back of the room so shapes separate from black.
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.55, 0.62, 0.75)
	fill.light_energy = 0.35
	fill.omni_range = 6.0
	fill.omni_attenuation = 1.5
	fill.light_specular = 0.1
	fill.light_volumetric_fog_energy = 0.3
	fill.position = Vector3(0.5, 2.8, 2.6)
	add_child(fill)
	# Dim cove wash on the acoustic wall behind the row of positions.
	var wash := SpotLight3D.new()
	wash.light_color = Color(0.5, 0.58, 0.72)
	wash.light_energy = 3.5
	wash.spot_range = 4.5
	wash.spot_angle = 62.0
	wash.spot_angle_attenuation = 1.5
	wash.light_specular = 0.05
	wash.light_volumetric_fog_energy = 0.2
	wash.position = Vector3(-0.6, 2.9, -0.3)
	add_child(wash)
	wash.look_at(Vector3(-0.6, 1.4, ROOM_MIN.z), Vector3.UP)


func _environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.05, 0.06, 0.07)
	environment.ambient_light_energy = 0.4
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 4.0
	environment.glow_enabled = true
	environment.glow_normalized = true
	environment.glow_intensity = 0.7
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.02
	environment.glow_hdr_threshold = 0.75
	environment.glow_hdr_scale = 1.6
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for lvl in 7:
		environment.set_glow_level(lvl, 0.0)
	environment.set_glow_level(1, 0.5)
	environment.set_glow_level(2, 0.8)
	environment.set_glow_level(3, 0.9)
	environment.set_glow_level(4, 0.7)
	environment.set_glow_level(5, 0.4)
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.018
	environment.volumetric_fog_albedo = Color(0.8, 0.82, 0.85)
	environment.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	environment.volumetric_fog_anisotropy = 0.4
	environment.volumetric_fog_length = 14.0
	environment.volumetric_fog_detail_spread = 1.5
	environment.volumetric_fog_ambient_inject = 0.0
	environment.volumetric_fog_temporal_reprojection_enabled = true
	environment.ssao_enabled = true
	environment.ssao_radius = 0.6
	environment.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)


func _shell() -> void:
	var size := ROOM_MAX - ROOM_MIN
	var centre := (ROOM_MAX + ROOM_MIN) * 0.5
	var carpet := Kit.pbr("carpet_dirty", 0.8, Color(0.22, 0.23, 0.26), 1.0)
	Kit.box(self, Vector3(size.x, 0.02, size.z), Vector3(centre.x, -0.01, centre.z), carpet, 0.0)
	var ceiling := Kit.mat(Color(0.05, 0.05, 0.055), 0.95)
	Kit.box(self, Vector3(size.x, 0.04, size.z), Vector3(centre.x, ROOM_MAX.y + 0.02, centre.z), ceiling, 0.0)
	var grid := Kit.mat(Color(0.09, 0.09, 0.1), 0.6, 0.3)
	for x in range(int(ROOM_MIN.x), int(ROOM_MAX.x) + 1, 1):
		Kit.box(self, Vector3(0.02, 0.01, size.z), Vector3(x, ROOM_MAX.y - 0.005, centre.z), grid, 0.0)
	for z in range(int(ROOM_MIN.z), int(ROOM_MAX.z) + 1, 1):
		Kit.box(self, Vector3(size.x, 0.01, 0.02), Vector3(centre.x, ROOM_MAX.y - 0.005, z), grid, 0.0)
	# Unlit fluorescent troffers.
	for fx: float in [-3.5, 0.0, 3.5]:
		for fz: float in [0.5, 3.0]:
			var lights := Kit.model(self, "mounted_fluorescent_lights", Vector3(fx, ROOM_MAX.y - 0.02, fz), 90.0)
			if lights != null:
				lights.rotation.x = PI
	var wall := Kit.mat(Color(0.06, 0.062, 0.068), 0.9)
	Kit.box(self, Vector3(size.x, size.y, 0.1), Vector3(centre.x, centre.y, ROOM_MIN.z - 0.05), wall, 0.0)
	Kit.box(self, Vector3(size.x, size.y, 0.1), Vector3(centre.x, centre.y, ROOM_MAX.z + 0.05), wall, 0.0)
	Kit.box(self, Vector3(0.1, size.y, size.z), Vector3(ROOM_MIN.x - 0.05, centre.y, centre.z), wall, 0.0)
	Kit.box(self, Vector3(0.1, size.y, size.z), Vector3(ROOM_MAX.x + 0.05, centre.y, centre.z), wall, 0.0)
	_acoustic_wall(ROOM_MIN.x + 0.3, ROOM_MAX.x - 0.3, ROOM_MIN.z + 0.035, 0.0)
	_acoustic_wall(ROOM_MIN.x + 0.3, ROOM_MAX.x - 0.3, ROOM_MAX.z - 0.035, PI)
	# Skirting
	var skirt := Kit.mat(Color(0.03, 0.03, 0.033), 0.5, 0.2)
	Kit.box(self, Vector3(size.x, 0.1, 0.02), Vector3(centre.x, 0.05, ROOM_MIN.z + 0.01), skirt, 0.0)


## Fabric-wrapped acoustic panels in a grid, slight tone variation.
func _acoustic_wall(x0: float, x1: float, z: float, rot_y: float) -> void:
	var w := 1.18
	var h := 0.58
	var tones: Array[Material] = []
	for i in 3:
		var c := Color(0.085, 0.09, 0.105).lerp(Color(0.07, 0.075, 0.085), i * 0.5)
		tones.append(Kit.pbr("carpet_dirty", 0.35, c * 5.0, 1.0))
	var x := x0 + w * 0.5
	var col := 0
	while x < x1:
		for row in 4:
			var y := 0.62 + row * (h + 0.03) + h * 0.5
			var mi := Kit.box(self, Vector3(w, h, 0.05), Vector3(x, y, z), tones[(col * 7 + row * 3) % 3], 0.012)
			mi.rotation.y = rot_y
		x += w + 0.03
		col += 1


## Another position along the row: desk, turret, a live-looking scope.
func _neighbour(x: float, idx: int) -> void:
	var n := Node3D.new()
	n.name = "Position%d" % idx
	n.position = Vector3(x, 0.0, 0.0)
	n.rotation.y = deg_to_rad(4.0 if x < 0.0 else -4.0)
	add_child(n)
	var shell := Kit.pbr("metal_plate_painted", 1.2, Color(0.16, 0.17, 0.19), 1.0)
	var top := Kit.mat(Color(0.07, 0.072, 0.078), 0.42)
	Kit.box(n, Vector3(1.9, 0.035, 0.82), Vector3(0.0, 0.7225, -0.6), top, 0.006)
	Kit.box(n, Vector3(1.7, 0.6, 0.03), Vector3(0.0, 0.38, -0.95), shell, 0.006)
	for sx: float in [-0.88, 0.88]:
		Kit.box(n, Vector3(0.12, 0.7, 0.78), Vector3(sx, 0.35, -0.6), shell, 0.008)
	var t := Node3D.new()
	t.position = Vector3(0.1, 1.13, -1.12)
	t.rotation.x = deg_to_rad(-9.0)
	n.add_child(t)
	Kit.box(t, Vector3(1.5, 0.78, 0.26), Vector3.ZERO, shell, 0.012)
	var screen := Node3D.new()
	screen.position = Vector3(0.0, 1.17, -0.86)
	screen.rotation.x = deg_to_rad(-9.0)
	n.add_child(screen)
	var bezel := Kit.mat(Color(0.045, 0.048, 0.052), 0.55, 0.15)
	Kit.box(screen, Vector3(0.71, 0.59, 0.05), Vector3(0.0, -0.009, -0.026), bezel, 0.007)
	var q := QuadMesh.new()
	q.size = Vector2(0.66, 0.528)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = IDLE_SHADER
	m.set_shader_parameter("seed", 3.7 + idx * 5.3)
	m.set_shader_parameter("energy", 1.1)
	mi.material_override = m
	screen.add_child(mi)
	var fdd := QuadMesh.new()
	fdd.size = Vector2(0.3, 0.528)
	var fm := MeshInstance3D.new()
	fm.mesh = fdd
	fm.material_override = Kit.mat(Color(0.01, 0.012, 0.014), 0.2, 0.0, Color(0.045, 0.055, 0.065), 1.0)
	fm.position = Vector3(0.55, 0.0, 0.0)
	screen.add_child(fm)
	Kit.box(screen, Vector3(0.34, 0.59, 0.05), Vector3(0.55, -0.009, -0.026), bezel, 0.007)
	if absf(x) < 3.0:
		var l := OmniLight3D.new()
		l.light_color = Color(0.5, 0.95, 0.68)
		l.light_energy = 0.5
		l.omni_range = 2.4
		l.light_specular = 0.0
		l.light_volumetric_fog_energy = 0.15
		l.position = Vector3(0.0, 1.1, -0.45)
		n.add_child(l)
	var chair := Kit.model(n, "modern_arm_chair_01", Vector3(0.15, 0.0, 0.25), 180.0 + (idx * 17.0 - 25.0))
	if chair != null:
		chair.name = "Chair"


func _back_of_room() -> void:
	for i in 3:
		var sx := -6.6 + i * 1.2
		# This model is authored in decimetres.
		Kit.model(self, "steel_frame_shelves_01", Vector3(sx, 0.0, ROOM_MAX.z - 0.3), 180.0, 0.1)
		Kit.model(self, "power_box_01", Vector3(sx, 0.25, ROOM_MAX.z - 0.3), 180.0)
	# Supervisor desk with a dim status monitor.
	var desk := Kit.model(self, "metal_office_desk", Vector3(3.4, 0.0, 3.4), 180.0)
	if desk != null:
		desk.name = "SupervisorDesk"
	Kit.model(self, "classic_laptop", Vector3(3.3, 0.79, 3.35), 160.0)
	Kit.model(self, "binoculars", Vector3(2.9, 0.79, 3.3), 40.0)
	# Exit sign over the door on the right wall.
	var exit_m := Kit.mat(Color(0.05, 0.3, 0.12), 0.4, 0.0, Color(0.2, 1.0, 0.45), 2.0)
	Kit.box(self, Vector3(0.05, 0.16, 0.36), Vector3(ROOM_MAX.x - 0.04, 2.35, 2.6), exit_m, 0.004)
	Kit.label(self, "EXIT", Vector3(ROOM_MAX.x - 0.075, 2.35, 2.6), 96, Color(0.02, 0.1, 0.04), 0.0011, Look.sans(800),
		Vector3(0.0, -PI * 0.5, 0.0))
	var door := Kit.mat(Color(0.08, 0.085, 0.09), 0.5, 0.3)
	Kit.box(self, Vector3(0.06, 2.1, 1.0), Vector3(ROOM_MAX.x - 0.02, 1.05, 2.6), door, 0.01)


func _wall_clock(p: Vector3) -> void:
	Kit.box(self, Vector3(0.62, 0.17, 0.05), p, Kit.mat(Color(0.02, 0.02, 0.022), 0.3, 0.1), 0.008)
	_clock = Kit.label(self, "", p + Vector3(0.0, 0.0, 0.0265), 120, Color(0.9, 0.12, 0.08), 0.0008,
		Look.mono(700), Vector3.ZERO, true)
	Kit.label(self, "UTC", p + Vector3(-0.24, 0.055, 0.0265), 40, Color(0.6, 0.12, 0.1), 0.0006, Look.sans(700),
		Vector3.ZERO, true)


func _process(_delta: float) -> void:
	var t := Time.get_datetime_dict_from_system(true)
	var sec := int(t["second"])
	if sec != _clock_sec:
		_clock_sec = sec
		_clock.text = "%02d:%02d:%02d" % [int(t["hour"]), int(t["minute"]), sec]
